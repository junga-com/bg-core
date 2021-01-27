#!/bin/bash


# Library bg_debugStack.sh
# This library adds value to the function scope stack that bash maintains in FUNCNAME, BASH_SOURCE, etc..
# The information bash maintains is relatied to the scopes that the bash maintains. That is similar to
# a call stack that is common in other languages but has key differences. This library translates the
# inormation bash provides into a traditional call stack that represents each invokacation that got
# bash to the current state. The way the bash informatin need to be  interpreted depends on how we got
# to that point -- is the code running because of a script invocation, script sourcing, or a previously
# sourced function being invoked? Is it stopped in a trap function or regular code?
# See Also:
#      bgStackMakeLogical : sets bgStack* arrays that are logical call stack version of FUNCNAME[] et. all.
#      bgStackPrint       : writes the logical call stack to stdout. (formats the bgStack* information)
#      bgStackGetFrame    : (core function) returns the logical call information for one stack frame
#      bgStackPrintFrame  : (core function) prints the logical call information for one stack frame to stdout


##################################################################################################################
### Bash Function Stack

# this tells bash to record function arguments in the stack data and source file and line number
# of functions. search for extdebug in man bash
shopt -s extdebug
set +o errtrace # extdebug turns this on but unit tests need it off

# usage: bgStackMakeLogical [--noSrcLookup] [--logicalStart+<n>]
# This makes a logical call stack that is intuitive to use. It initializes the $bgStatck* global vars. Whereas the item described
# in each bash function call stack frame is a function scope, each frame in this logical stack is a line of code being executed,
# possible inside a function but maybe not. Programmers think of a call stack as the later which is why this logical stack is more
# intuitive.
#
# We are insterested in using this function in two scenarios. First, is assertError and bgtraceStack which are meant to give the
# operator a view on what the script is doing at that point. Second is in the debugger which can stop via the DEBUG trap anywhere
# and gives the debugger operator a view on what the script is doing at that point.
#
# The Problem with the Bash FUNCNAME Stack:
# Bash maintains FUNCNAME, BASH_SOURCE, BASH_LINENO, LINENO, BASH_COMMAND, BASH_ARGC and BASH_ARGV but its complicated to interpret
# them correctly from different execution points in the script and, in fact, when trap handlers are being invoked, the information
# they provide is insufficient to fully understand the exceution stack.
#
# This function creates the logical call stack from that bash information that is easy to interpret but needs some additional
# information added by trap handlers in order to do it reliably.
#
# Trap Handlers:
# BASH does not provide enough information for us to tell that we are in a trap handler and where on the stack the trap ocrured.
# The logical source line of code for each stack frame which is gleaned from adjacent FUNCNAME, BASH_SOURCE, BASH_LINENO array
# entries but at the point a trap is called, that adjancency is discontinuous.
#
# There are two distinct cases -- the DEBUG trap vs all other (User level) traps. When in the DEBUG trap handler, this function
# adds an additional stack frame that represents the line of code that the debugger is stopped on and relies on the DEBUG trap
# handler to record the LINENO variable in the bgBASH_debugTrapLINENO to know what source line corresponds to BASH_COMMAND.
#
# Global Input Vars:
# These global variables are referenced by this function to create the logical stack.
#     bgBASH_funcDepthDEBUG      : set by the DEBUG trap handler to indicate the frame on the stack that represents the line being executed
#                                  this is only set by the DEBUG trap handler so if its set, it also indicates that the DEBUG handler is
#                                  on the stack beginning at that location.
#     bgBASH_trapStkFrm_funcDepth : set by trap handler entry and exit functions to indicate that a handler other than the DEBUG
#                                  handler is on the stack and where on the stack it begins. Both a non-DEBUG handler and a DEBUG handler
#                                  will be on the stack at the same time when the debugger is stepping through a handler.
#     bgBASH_debugTrapLINENO     : set by the DEBUG trap handler to indicate the source line number of the BASH_COMMAND that the
#                                  debugger is stopped on. This is not in the bash stack arrays and unlike BASH_COMMAND, it continues
#                                  to change while the DEBUG trap handler executes so the first this that the trap handler does is
#                                  make a copy of this value as it was the moment the handler was invoked when it still reflected
#                                  the BASH_COMMAND's source line.
# Global Logical Stack Vars:
# These global variables are set by this function for the caller to use.
#    bgStackSize                  : how many frames are in the stack.
#                                   example: for ((frameNo=0; frameNo<bgStackSize; frameNo++ ))...
#                                   Note that the indexes of the bash builtin vars will be different than the indexs of the
#                                   logical call stack.
#    bgStackLogicalFramesStart    : the first frame index that is part of the user's script as opposed to functions in the system
#                                   libraries. The plumbing functions of error handling and debugging are not logically part of the script.
#                                   example: for ((frameNo=bgStackLogicalFramesStart; frameNo<bgStackSize; frameNo++ ))...
#    bgStackSrcFile[$frameNo]     : the source file name that contains the line being exectued at that frame
#    bgStackSrcLineNo[$frameNo]   : the line number in the bgStackSrcFile
#    bgStackSrcLocation[$frameNo] : the baseFilename:(line number) together. Note the the path is removed
#    bgStackSimpleCmd[$frameNo]   : the simple command being exectuted or an approximation
#                                   for the first logical stack frame, this is exact b/c bash provides it.
#                                   for higher frames, the simple cmd must be a bash function and the function name
#                                   is always available but the arguments are only available with shopt -s extdebug
#    bgStackSrcCode[$frameNo]     : if the --noSrcLookup option is specified, this will be the source code line found at
#                                   bgStackSrcLocation[$frameNo], otherwise it is the same as bgStackSimpleCmd
#    bgStackFunction[$frameNo]    : the function that the src line is contained in.
#                                   its set to 'main' when the line is in the top level script being executed
#                                   its set to 'source' when the line is in the top level script being sourced
#    bgStackLine[$frameNo]        : a formatted line suitable for printing that represents the stack frame.
#    bgStackLineWithSimpleCmd[$frameNo] : a formatted line suitable for printing like bgStackLine, but whereas
#                                   bgStackLine contains the actual src code line, this contains the simple
#                                   command being executed which might be only part of the src code line and
#                                   has the actual values of the simple command argument
#    bgStackSrcLocationMaxLen bgStackFunctionMaxLen bgStackSrcCodeMaxLen : these are the max string lengths.
# Options:
#    --noSrcLookup : fill in the bgStackLine[$frameNo] array by reading the line at bgStackSrcLocation[$frameNo]. This is an option
#         because even though it is very quick to read these lines, its relatively heavy compared to the rest of the work this
#         function does. For most uses the time saved would not be significant
#    --logicalStart+<n> : this instructs the algorithm to skip the first <n> bash function scope frames because they
#         are not part of the logical code. For example if there are 3 nested assertFunctions on the stack when
#         this is called, passing +2 will cause two to be ignored and only the first assert that the applicaiton
#         code called would be included in the stack (as if that first assert called this function.
# See Also:
#     bg-lib/bashTests//bg-trapStrackTraces   : interactive test cases for various combinations of signals and logical stacks.
#     bgStackPrint  : format the logical frames that this function produces for output
function bgStackMakeLogical()
{
	# usage: _pushLogicalStackEntry <context> <srcFile> <function> <srcLineNo> <simpleCmd> [<cmd>]
	# internal function to add the next stack entry to our logical stack variables
	#     bgStackSize  : is how many frames are already on the stack. the new one goes into the index [$bgStackSize] and then bgStackSize is incremented
	# Params:
	#    <context>    : this is a short tag used for debugging this algorithm. Each call to _pushLogicalStackEntry uses a different
	#                   tag so in the debug output of the stack, we can see which part of this algorithm was responsible for adding
	#                   each logical frame
	#    <srcFile>    : the full path to the script command or library file containing the code for this frame
	#    <function>   : this is the function that code executing in this frame is located in. It is typically not part of the displayed
	#                   frame output. BASH's frame is literally associated with each function call so its focused on the functions
	#                   but our logical stack frames correspond to lines of code which are often a bash function but for the debugger
	#                   and for traps, there needs to be stack frames that are not associated with a bash function call.
	#    <srcLineNo>  : the line number in <srcFile> where the line being executed in this stack frame is located.
	#    <simpleCmd>  : This is the simple command being executed in this frame. Each source line can contain multiple bash statements
	#                   separated by ';'. Each bash statement can consist of multiple simple commands. For example [ "$foo" ] && grep foo && foo;
	#                   is one compound statement with three simple commands. The 'Simple Command' is bash's smallest unit of execution.
	#    <cmd>        : this is an instruction to the push algorithm to do some additional processing on this frame.
	#       lastFrameOfType:<frameType>
	#                   This marks that the logical stack frame is discontinuous at this point.
	#                   <frameType> is a signal name. Each signal that gets handled starts executing inbetween bash Simple Commands
	#                   and if it calls functions, they will append to the existing FUNCNAME stack but logically, the stack above and
	#                   below that point are unrelated. This is particularly important because common interpretation of the FUNCNAME
	#                   stack combines information  from two adjacent frames.
	function _pushLogicalStackEntry()
	{
		local context="$1"
		bgStackSrcFile[$bgStackSize]="$2"
		bgStackFunction[$bgStackSize]="$3"
		bgStackSrcLineNo[$bgStackSize]="$4"
		bgStackSimpleCmd[$bgStackSize]="$5"
		local cmd="$6"

		# the debugger can modify any sourced function to include calls to bgtraceBreak on the fly to implement non-persistent breakpoints.
		# however, when it does that, the sourceFile and line numbers associated with that modified function changes to the point in
		# bg_debugger.sh that overwrites the function. When it does that, the debugger adds an entry into bgBASH_debugBPInfo to indicate
		# the translation back to the original file. It adds the bgtraceBreak as an addtional compound clause to existing lines so that
		# the simple commands executed by bash will still match up with the original lines in the files
		declare -gA bgBASH_debugBPInfo
		local bpInfo="${bgBASH_debugBPInfo["${bgStackFunction[$bgStackSize]// /}"]}"
		if [ "$bpInfo" ]; then
			read -r origLineNo newLineNo origFile <<<"$bpInfo"
			bgStackSrcFile[$bgStackSize]="$origFile"
			bgStackSrcLineNo[$bgStackSize]="$((bgStackSrcLineNo[$bgStackSize] - newLineNo + origLineNo))"
		fi

		bgStackSrcLocation[$bgStackSize]="${bgStackSrcFile[$bgStackSize]##*/}:(${bgStackSrcLineNo[$bgStackSize]})"

		if [ ! "${bgStackSrcCode[$bgStackSize]}" ] && [ ! "$noSrcLookupFlag" ] && [ -r "${bgStackSrcFile[$bgStackSize]}" ] && ((${bgStackSrcLineNo[$bgStackSize]:-0} > 0 )); then
			bgStackSrcCode[$bgStackSize]="$(sed -n "${bgStackSrcLineNo[$bgStackSize]}"'{s/^[[:space:]]*//;p;q}' "${bgStackSrcFile[$bgStackSize]}" 2>/dev/null )"
			if [[ "${bgStackSrcCode[$bgStackSize]}" =~ ^[[:space:]]*[{][[:space:]]*$ ]] && [[ ! "${bgStackSimpleCmd[$bgStackSize]}" =~ ^[\<] ]]; then
				bgStackSimpleCmd[$bgStackSize]="{"
			fi
		elif [ ! "${bgStackSrcCode[$bgStackSize]}" ]; then
			bgStackSrcCode[$bgStackSize]="${bgStackSimpleCmd[$bgStackSize]}"
		fi
		if [ "${bgStackSimpleCmd[$bgStackSize]}" == "<unknown>" ] && [ "${bgStackSrcCode[$bgStackSize]}" ]; then
			bgStackSimpleCmd[$bgStackSize]="${bgStackSrcCode[$bgStackSize]}"
		fi

		(( bgStackSrcLocationMaxLen < ${#bgStackSrcLocation[$bgStackSize]} )) && bgStackSrcLocationMaxLen=${#bgStackSrcLocation[$bgStackSize]}
		(( bgStackFunctionMaxLen    < ${#bgStackFunction[$bgStackSize]} ))    && bgStackFunctionMaxLen=${#bgStackFunction[$bgStackSize]}
		(( bgStackSrcCodeMaxLen     < ${#bgStackSrcCode[$bgStackSize]} ))     && bgStackSrcCodeMaxLen=${#bgStackSrcCode[$bgStackSize]}

		bgStackBashStkFrm[$bgStackSize]="$context $bashStkFrmSummary"

		# its done, so increment bgStackSize to reflect the new entry
		((bgStackSize++))

		# cmd==lastFrameOfType:<SIG> is specified when ever we know we are on a trap handler transition. It sets the type of the
		# frame we just added but also sets the type of any unclaimed frames below it. E.G. when we cross the DEBUG trap border,
		# it claims everything up to that point as part of the DEBUG trap. Then later if we call it for a user trap, then it will claim anything between the DEBUG
		# border and that trap's border
		if [[ "$cmd" =~ ^lastFrameOfType:(.*)$ ]]; then
			local typeName="${BASH_REMATCH[1]:-UNK_TRAP}"
			local j; for ((j=0; j<bgStackSize; j++)); do
				[ ! "${bgStackFrameType[$j]}" ] && bgStackFrameType[$j]="$typeName"
			done
		fi

	}

	# internal function to construct the simple command from FUNCNAME, BASH_ARGV, and BASH_ARGC
	function _constructSimpleCommandFromBashStack()
	{
		local stackFrame="$(( $1 +1))"
		local _csc_simpleCommand="${FUNCNAME[$stackFrame]}"
		local n argcOffset=0; for ((n=0; n<=stackFrame; n++)); do ((argcOffset+=${BASH_ARGC[$n]:-0})); done
		local v; for (( v=1; v <=${BASH_ARGC[$stackFrame]:-0}; v++ )); do
			local quotes=""; [[ "${BASH_ARGV[$argcOffset-v]}" =~ [[:space:]]|(^$) ]] && quotes="'"
			_csc_simpleCommand+=" ${quotes}${BASH_ARGV[$argcOffset-v]}${quotes}"
		done
		returnValue "$_csc_simpleCommand" "$2"
	}

	# internal function to create the DEBUG handler frame special when its our debugger
	function _makeDEBUGTrapFrame()
	{
		local i=$((i+1)) # since this function call added a BASH stack frame, offest i internally
		# if the trap handler is invoking _debugEnterDebugger then we assume its our well know _debugSetTrap handler
		_constructSimpleCommandFromBashStack "$((i-1))" frmSimpleCmd
		if [[ "$frmSimpleCmd" =~ _debugEnterDebugger.*DEBUG-852 ]]; then
			import --getPath bg_debugger.sh frmSrcFile; assertNotEmpty frmSrcFile --critical
			frmFunc="DEBUGTrap"
			frmSrcLineNo="$(awk '/^[[:space:]]*_debugEnterDebugger[[:space:]][[:space:]]*.!DEBUG-852!./ {print NR}' "$frmSrcFile")"
			frmSimpleCmd='_debugEnterDebugger "!DEBUG-852!"'
		else
			frmSrcFile="<TRAP:DEBUG>"
			frmFunc="DEBUGTrap"
			frmSrcLineNo="0"
		fi
	}



	local noSrcLookupFlag logicalFrameStart=1 stackDebugFlag
	while [ $# -gt 0 ]; do case $1 in
		--noSrcLookup) noSrcLookupFlag="--noSrcLookup" ;;
		--logicalStart*) ((logicalFrameStart+=${1#--logicalStart?})) ;;
		--stackDebug)  stackDebugFlag="--stackDebug" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "$stackDebugFlag" ] && bgStackDump


	# in some cases, the BASH stack data can not be trusted. E.G. with core sourced in terminal, run '$Object.name::bgtrace' (which should assert an error)
	# The BASH_SOURCE was correct but BASH_LINENO was way off. The top BASH_LINENO was a cmd counter in the terminal. The rest were
	# wrong and I could not detect what they were
	# This flag is meant to create a mode where src is not read
	local bgCantTrustScrLocations; [ "$bgLibExecMode" != "script" ] && bgCantTrustScrLocations="1"
	[ "$bgCantTrustScrLocations" ] && noSrcLookupFlag="bgCantTrustScrLocations"

	# if we are in a DEBUG handler, frameIdxOfDEBUGTrap will point to the bash array index where the trap was invoked.
	# an empty value indicates that there is no DEBUG handler on the stack. 0 would be a problem but we know that it can not be zero
	# NOTE that a DEBUG trap can interrupt another trap so we could have  2 interupts on the stack with 2 dicontinuities in the BASH  function stack
	local frameIdxOfDEBUGTrap; [ "$bgBASH_funcDepthDEBUG" ] && frameIdxOfDEBUGTrap="$(( ${#BASH_SOURCE[@]} - bgBASH_funcDepthDEBUG ))"

	# logicalFrameStart determines the point in the stack where the plumbing code that is not interesting to the caller starts.
	# The logical stack that this function returns stops at the logicalFrameStart and suppresses the other frames which the user
	# does not want to see.  There are several use-cases for determining logicalFrameStart.
	#    1) when running in the DEBUG trap, the logicalFrameStart refers to the stack that was in progress when the DEBUG trap was
	#       signaled.  Even if there are other trap handlers on the stack, they must be part of the logical stack because that is
	#       the running code represented by BASH_COMMAND and the debugger step*/skip* commands are relative to that position.
	#    2) when called from assertError or other script code directly, the logicalFrameStart is determined by the function that calls
	#       us via the --logicalFrameStart option pattern. logicalFrameStart tells this function directly how many frames, starting
	#       with the one the represents this function should be ignored. Library functions that calls other library functions that
	#       eventually calls this function use the --logicalFrameStart pattern of incrementing an passing on to collect the total
	#       value of logicalFrameStart that should be ignored.


	# bgStackLogicalFramesStart is the same as logicalFrameStart, but translated into the index of the logical stack arrays
	# if frameIdxOfDEBUGTrap is valid (meaning we are in a DEBUG trap) bgStackLogicalFramesStart will be overwritten in the loop below
	declare -g bgStackLogicalFramesStart=$logicalFrameStart

	declare -g bgStackSize=0 bgStackSrcLocation=() bgStackSrcFile=() bgStackSrcLineNo=() bgStackFunction=() bgStackFrameType=()
	declare -g bgStackSrcCode=() bgStackSimpleCmd=() bgStackLine=() bgStackLineWithSimpleCmd=() bgStackBashStkFrm=()
	declare -g bgStackSrcLocationMaxLen=0 bgStackFunctionMaxLen=0 bgStackSrcCodeMaxLen=0

	# outside the loop, get the information about all the installed trap handlers so that we can use it in the trap detection code.
	# we only do trap detection when --noSrcLookup has not been specified
	local -A trapHandlers trapHandlersByLineNo
	if [ ! "$noSrcLookupFlag" ]; then
		bgTrapUtils getAll trapHandlers
		local sigTest; for sigTest in "${!trapHandlers[@]}"; do
			local lineno=1 line; while IFS="" read -r line; do
				trapHandlersByLineNo[$sigTest:$((lineno++))]="$line"
			done <<<"${trapHandlers[$sigTest]}"
		done
	fi

	# this indicates when we are in a trap handler other than a DEBUG handler. It is used by the debugger to optionally step over
	# traps. bg_untiTest.sh uses this feature to not step through ERR and EXIT traps that maintain the testcase run
	bgStackInUserTrap=""

	# iterate over the bash stack array (BASH_SOURCE, et all) and insert frames into our arrays (bgStack*)
	local i frmSrcFile frmFunc frmSrcLineNo frmSimpleCmd frmSrcLineText
	for ((i=0; i<${#BASH_SOURCE[@]}; i++)); do
		# the structure of this loop is that various conditions examine the current frame $i and determine if they should handle it.
		# if no conditions match, the default handler block at the end will add its corresponding logical stack frame.
		local doDefaultBlock="1"
		local frmSrcFile="" frmFunc="" frmSrcLineNo="" frmSimpleCmd="" frmSrcLineText=""

		# make a summary line of the bash stack vars to aid in debugging this algorithm
		local bashStkFrmSummary; printf -v bashStkFrmSummary "[%2s]%4s src:%s func:%s" "$i" "${BASH_LINENO[$i]}" "${BASH_SOURCE[$i]##*/}" "${FUNCNAME[$i]}"


		### determine if this frame was interupted by a trap handler. This block relies on the BGTRAPEntry/BGTRAPExit calls that
		#   bgtrap puts in the handlers
		local detectedTrapFrame=()

		# if we are in the range where BGTRAPEntry/BGTRAPExit has info pushed on the trapStk...
#		for j in "${!bgBASH_trapStkFrm_funcDepth[@]}"; do
		for ((j=0; j<${#bgBASH_trapStkFrm_funcDepth[@]}; j++)); do
			if ((i == (${#BASH_SOURCE[@]} - bgBASH_trapStkFrm_funcDepth[$j]) )); then
				#detectedTrapFrame="${bgBASH_trapStkFrm_signal[$j]:-$bgBASH_trapStkFrm_lastSignal}"
				detectedTrapFrame+=("$j")
			fi
		done

		# if the handler is in a call to BGTRAPEntry/BGTRAPExit, but outside the range where info is pushed on the trapStk
		if ((i>0)) && [ ! "$detectedTrapFrame" ] && [ "${FUNCNAME[i-1]}" == "BGTRAPEntry" ]; then
			local n argcOffset=0; for ((n=0; n<i-1; n++)); do ((argcOffset+=${BASH_ARGC[$n]:-0})); done
			detectedTrapFrame+=("${BASH_ARGV[argcOffset+3]}")
		elif ((i>0)) && [ ! "$detectedTrapFrame" ] && [ "${FUNCNAME[i-1]}" == "BGTRAPExit" ]; then
			detectedTrapFrame+=("$bgBASH_trapStkFrm_lastSignal")
		fi

		# if this is the debugger transition frame and the interrupted lineno is 1 its almost certain that the debugger interrupted
		# the first line of a TRAP (other than ERR b/c it preserves the interupted LINENO like DEBUG does). We should probably
		# add code to rule out this being a sourced file with code on line 1
		if ((i>0 && (frameIdxOfDEBUGTrap==i) && (bgBASH_debugTrapLINENO==1) )); then
			detectedTrapFrame+=("UNKTRAP")
		fi


		# CRITICALTODO: use declare -F (with lineno's) to fix trap handler boundry detection code.
		# OBSOLETE? Now that we alias trap to bgtrap, typical trap handlers will start with BGTRAPEntry and the above code works
		#           much better than this detection code. This code relies on examining the source to see if the frame matches but
		#           that is problematic -- notably code that executes a cmd inside a variable like $utFunc ...
		#           ERR traps have LINENO set to the interrupted LINENO (like DEBUG)
		#           non-ERR/DEBUG traps have LINENO set to 1 which is unlikely not to be a trap and handled above now
		# detect if this frame is the start of a TrapHandler.
		# NOTE: BASH does not record something like a FUNCNAME entry when a signal trap handler starts executing.
		# The trap handlers that bgtrap and debugger and Try:/Catch: manage gives us the required hints when they are executing.
		# This detection block handles the case when a trap handler is executing and does not give us the hint. This happens on the
		# fist line when we step into a trap call on the line that is about to call BGTRAPEntry (which records the hint information)
		# Also, we might want to turn off the way bgtrap does the hint when bgtraceing is not active and we still want to detect the
		# trap so that stack traces in asserts are not misleading when they try to get the lineno from the adjacent frame which is
		# not correct. When FUNCNAME[$i] is not interruped by a trap handler, the source line within FUNCNAME[$i] at
		# BASH_SOURCE[$1]:BASH_LINENO[$i-1] will include a reference to FUNCNAME[$i-1]. If not, we can glean that the FUNCNAME[$i-1]
		# is the result of a trap handler interruping FUNCNAME[$i]. If we find FUNCNAME[$i-1] in one of the active handlers, we can
		# assume that it is running and responsible for FUNCNAME[$i-1] being on the stack.
		if [ ! "$detectedTrapFrame" ] && ((i>0)) && [ ! "$noSrcLookupFlag" ] && [ "${BASH_SOURCE[$i]}" != "environment" ]; then
			# BASH BUG: for the first DEBUG trap hit in a new UserTrap handler, BASH_COMMAND will still have the last value before the UserTrap
			# if the DEBUGger interrupted top level trap code (before it calls a function) the frame no will be the same as frameIdxOfDEBUGTrap
			local referenceText="${FUNCNAME[$i-1]}"; ((frameIdxOfDEBUGTrap == i)) && referenceText="$BASH_COMMAND"

			# if the DEBUger is interrupting the trap  bgBASH_debugTrapLINENO is the lineno, otherwise the function stk that this trap
			# called has the lineno. The only way for trap code to be seen on the stack is if its being interupted or has it called
			# a function (either this function directly or a function that called this function like assert*
			frmSrcLineNo=$(( (frameIdxOfDEBUGTrap == i)?bgBASH_debugTrapLINENO:${BASH_LINENO[$i-1]} ))

			# CRITICALTODO: this code that gets the source line from the file needs to take into account \ line continuations.
			[ ${frmSrcLineNo:-0} -gt 0 ] && [ -r "${BASH_SOURCE[$i]}" ] && frmSrcLineText="$(sed -n "${frmSrcLineNo}"'{s/^[[:space:]]*//;p;q}' "${BASH_SOURCE[$i]}" 2>/dev/null )"
			# if the src line invokes the referenceText in a variable (like $utFunc ...) then it wont match. We could try to deref
			# but that var might not be in scope at the point we are running and its probably good enough to assume that its not a trap
			# if the source does not start the line with $cmd (like [ "$cmd" ] && $cmd) this will be a false positive. We could make a better REGEX but I dont want to do that now.
			if [[ ! "$frmSrcLineText" = *${referenceText}* ]] && [[ ! "$frmSrcLineText" =~ ^[[:space:]]*\"?[$] ]]; then
				local sigCandidates="" sigCandidatesCount=0 sigTest
				for sigTest in "${!trapHandlers[@]}"; do
					if [[ "${trapHandlersByLineNo[$sigTest:$frmSrcLineNo]}" =~ $referenceText ]]; then
						sigCandidates[$((sigCandidatesCount++))]="$sigTest"
					# when we enter a UserTrap while debugging, it stops on the first line before BGTRAPEntry is called. Also, a bash bug
					# makes it so that the BGTRAPEntry line is not in BASH_COMMAND. So this is a patch for that
					elif [[ "${trapHandlersByLineNo[$sigTest:$frmSrcLineNo]}" =~ $bgtrapHeaderRegEx ]]; then
						sigCandidates[$((sigCandidatesCount++))]="${BASH_REMATCH[2]}"
					fi
				done
				if [ "${sigCandidates[*]}" ]; then
					detectedTrapFrame+=("${sigCandidates[*]}")
					bgtraceVars -1 -l"bgStackMakeLogical:DETECTED INTR Frame " detectedTrapFrame frmSrcLineText referenceText
					bgAssertErrorTMPSIGNALTRIGGERED=1
				else
					# if we did not end up finding trap code, reset frmSrcLineNo before we move on
					frmSrcLineNo=""
				fi
			fi
		fi

		# Non-adjacent Frame -- First frame.
		# Add a logical frame for this code, right here.  FUNCNAME[0]==bgStackMakeLogical (this function) but there is no bash stack
		# frame below [0] to indicate where we are in that function. For completeness, we can hardcode a frame to represent this line.
		if ((i==0)); then
			# the bgStackSimpleCmd is the literal text of the this next line (we simplify it to exclude the parameters)
			_pushLogicalStackEntry FRM0 \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"$((LINENO))" \
				"_pushLogicalStackEntry FRM0"
			continue
		fi

		# Non-adjacent Frame -- DEBUGTrap transistion to a normal function that it interuptted.
		# This will only hit when we are in the debugger. We are at the frame where the DEBUG handler started.
		# In this case, the debugger did not interupt a top level UserTrap line so BASH[$i] is a normal frame (UserTrap or LogicalScript)
		# except for being interupted by the DEBUGTrap
		if ((i == frameIdxOfDEBUGTrap)) && [ ! "$detectedTrapFrame" ]; then
			# synthesize a frame to represent the DEBUG handler script
			_makeDEBUGTrapFrame
			_pushLogicalStackEntry T1_DBG \
				"$frmSrcFile" \
				"$frmFunc" \
				"$frmSrcLineNo" \
				"$frmSimpleCmd" \
				"lastFrameOfType:DEBUG"

			# record that this is the real logical start because in the debugger, this is where execution is stopped
			bgStackLogicalFramesStart=$((bgStackSize))

			# now add the logical frame for the line of code that the debugger is stopped on.
			_pushLogicalStackEntry T1_SCR \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${bgBASH_debugTrapLINENO}" \
				"${BASH_COMMAND}"

			doDefaultBlock=""
		fi


		# Non-adjacent Frame -- DEBUGTrap transistion to code directly in a UserTrap that it interuptted.
		# In this case, we are stepping through the UserTrap handler at the top level while that handler is not in a function call.
		# BASH[$i] is the function that was being executed when the UserTrap hapenned. The stack does not say which line in that function
		# BASH[$i-1] is the first function of the DEBUG trap that led to this code running.
		# bgBASH_debugTrapLINENO is LINENO at the moment DEBUG trap started and refers to the lineNo in the UserTrap handler that is running
		if ((i == frameIdxOfDEBUGTrap)) && [ "$detectedTrapFrame" ]; then
			bgStackInUserTrap="1"

			# synthesize a frame to represent the DEBUG handler script
			_makeDEBUGTrapFrame
			_pushLogicalStackEntry T3_DBG \
				"$frmSrcFile" \
				"$frmFunc" \
				"$frmSrcLineNo" \
				"$frmSimpleCmd" \
				"lastFrameOfType:DEBUG"

			# record that this is the real logical start because in the debugger, this is where execution is stopped
			bgStackLogicalFramesStart=$((bgStackSize))

			# now add the logical frame for the line of code that the debugger is stopped on which is a line in the UserTrap handler script.
			local detSig detLineno detLastCmd
			local j="${detectedTrapFrame[@]:0:1}";  detectedTrapFrame=("${detectedTrapFrame[@]:1}")
			if [[ "$j" =~ ^[0-9]+$ ]]; then
				detSig="${bgBASH_trapStkFrm_signal[j]}"
				detLineno="${bgBASH_trapStkFrm_LINENO[j]}"
				detLastCmd="${bgBASH_trapStkFrm_lastCMD[j]}"
			else
				detSig="$j"
				detLineno=""
				detLastCmd=""
			fi

			local modLineNo="$bgBASH_debugTrapLINENO"; [ "${detSig}" == "ERR" ] && modLineNo=$(( modLineNo - ${detLineno:-0} +1 ))
			local cmb2Cmd="${BASH_COMMAND}"; ((bgBASH_debugTrapLINENO==1)) && cmb2Cmd="<UNK>"
			_pushLogicalStackEntry T3_TRP \
				"<handler>" \
				"${detSig} handler" \
				"${modLineNo}" \
				"${cmb2Cmd}" \
				"lastFrameOfType:${detSig}"

			# if there are more than one trap, we dont know much about the others, except that the intrupted cmds should be valid
			local z; for ((z=0; z<${#detectedTrapFrame[@]}; z++)); do
				j=${detectedTrapFrame[z]}
				local thisCmd="$detLastCmd"
				if [[ "$j" =~ ^[0-9]+$ ]]; then
					detSig="${bgBASH_trapStkFrm_signal[j]}"
					detLineno="${bgBASH_trapStkFrm_LINENO[j]}"
					detLastCmd="${bgBASH_trapStkFrm_lastCMD[j]}"
				else
					detSig="$j"
					detLineno=""
					detLastCmd=""
				fi
				_pushLogicalStackEntry T3_TRPn \
					"<handler>" \
					"${detSig} handler" \
					"UNK" \
					"${thisCmd}" \
					"lastFrameOfType:${detSig}"
			done

			# now add the logical frame for the line of code that UserTrap interrupted. This is the first proper script line.
			bgStackGetFunctionLocation "${FUNCNAME[$i]}" frmSrcFile frmSrcLineNo
			_pushLogicalStackEntry T3_SCR \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${detLineno:-UNK}" \
				"${detLastCmd:-<${FUNCNAME[$i]}() interupted by ${detectedTrapFrame}>}"

			doDefaultBlock=""
		fi


		# Non-adjacent Frame -- UserTrap transistion to a normal function that it interuptted.
		# A UserTrap handler which is calling at least one function (b/c we are not also at the DEBUGTrap frame)
		if ((i != frameIdxOfDEBUGTrap)) && [ "$detectedTrapFrame" ]; then
			bgStackInUserTrap="1"

			# synthesize a frame to represent the handler script
			local detSig detLineno detLastCmd
			local j="${detectedTrapFrame[@]:0:1}";  detectedTrapFrame=("${detectedTrapFrame[@]:1}")
			if [[ "$j" =~ ^[0-9]+$ ]]; then
				detSig="${bgBASH_trapStkFrm_signal[j]}"
				detLineno="${bgBASH_trapStkFrm_LINENO[j]}"
				detLastCmd="${bgBASH_trapStkFrm_lastCMD[j]}"
			else
				detSig="$j"
				detLineno=""
				detLastCmd=""
			fi
			_constructSimpleCommandFromBashStack "$((i-1))" frmSimpleCmd
			local modLineNo="${BASH_LINENO[i-1]}"; [ "${detSig}" == "ERR" ] && modLineNo=$(( modLineNo - ${detLineno:-0} +1 ))
			_pushLogicalStackEntry T2_TRP \
				"<handler>" \
				"${detSig} handler" \
				"$modLineNo" \
				"$frmSimpleCmd" \
				"lastFrameOfType:${detSig}"

			# Note that our BGTRAPEntry records the information about the interupted src line in bgBASH_trapStkFrm_* variables.
			# but that data might not exist. We could be at the start or end of a trap handler outside the BGTRAPEntry/BGTRAPExit
			# or we could be in a non-ERR/DEBUG trap that does not have access to the interupted LINENO
			# TODO: use detLastCmd to calculate detLineno when detLineno==UNK
			_pushLogicalStackEntry T2_SCR2 \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${detLineno:-UNK}" \
				"${detLastCmd:-<${FUNCNAME[$i]}() interupted by ${detSig}>}"


			doDefaultBlock=""
		fi

		# Adjancent Frame -- Default case where we can get the line number and SimpleCmd from the frame below
		# When two bash functions are on the FUNCNAME stack within the same trap/script context, then we can glean all the information
		# for one logical frame from the two adjacent frames. FUNCNAME[$i] is the function that contains the line for this logical frame,
		# and FUNCNAME[$i-1] is a line within that function that is calling another function. The BASH_LINENO[$i-1] tells us where
		# in the  FUNCNAME[$i] function we are currently at and FUNCNAME[$i-]+BASH_ARGV.. is the SimpleCmd being executed at that
		# line
		if [ "$doDefaultBlock" ]; then
			_constructSimpleCommandFromBashStack "$(($i-1))" frmSimpleCmd
			_pushLogicalStackEntry DFLT \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${BASH_LINENO[$i-1]}" \
				"$frmSimpleCmd"
		fi
	done

	# Synthesize one last logical stack entry to represent how the script was invoked.
	# Each of our logical frames take some information from a given bash stack frame [i] and some information from the [i-1] frame
	# The last bash frame contains one last bit of information that we would normally access as [i-1] but i did not go that high.
	# This is that +1 frame that we are adding now that will use that part of the last bash frame.

	# the highest (last) frame on the BASH_ stack is one of
	#        'main'         : normal case. running a script in a non-interactive bash process
	#        'source'       : sourcing a script into an interactive bash process (aka a terminal emulator win)
	#        <functionName> : running a sourced function from an interactive bash process. This is typical of bash completion scripts and
	#                         functions in the bg-debugCntr system of development tools. The function is typically sourced from a
	#                         cmd earlier in a session (maybe in the .bashrc) and now its being invoked directly on the command line.

	local simpleCommand=""; lastFrame="$((${#BASH_SOURCE[@]}-1))"
	if [ "${#bgLibExecCmd[@]}" -gt 0 ]; then
		# bg_coreImport.sh global code and bg-debugCntr debug trap, records the cmd line being invoked in bgLibExecCmd
		local v; for (( v=0; v <=${#bgLibExecCmd[@]}; v++ )); do
			local quotes=""; [[ "${bgLibExecCmd[v]}" =~ [[:space:]] ]] && quotes="'"
			simpleCommand+=" ${quotes}${bgLibExecCmd[v]}${quotes}"
		done
	else
		# if the hint is not available, use the information available in the stack. This might be 'main' but it could be a sourced
		# function that is being called
		_constructSimpleCommandFromBashStack "$(($lastFrame))" simpleCommand
	fi
	# usage: _pushLogicalStackEntry <context> <srcFile> <function> <srcLineNo> <simpleCmd> [<cmd>]
	bgStackSrcCode[$bgStackSize]="$bgLibExecSrc"  # hack: setting bgStackSrcCode outside of _pushLogicalStackEntry instead of allowing it to be passed in
	_pushLogicalStackEntry TOPL \
		"<bash:$$>" \
		"${FUNCNAME[@]: -1}" \
		"<typed>" \
		"$simpleCommand"


	# now loop over the stack creating the composite data
	local frameNo; for ((frameNo=bgStackSize-1; frameNo>=0; frameNo--)); do
		local allButLast="1"; ((frameNo==bgStackSize-1)) && allButLast=""
		printf -v bgStackLine[$frameNo] "%-*s : %s" \
				"$((bgStackSrcLocationMaxLen+1))" "${bgStackSrcLocation[$frameNo]}:" \
				"${bgStackSrcCode[$frameNo]}"
		printf -v bgStackLineWithSimpleCmd[$frameNo] "%-*s : %s" \
				"$((bgStackSrcLocationMaxLen+1))" "${bgStackSrcLocation[$frameNo]}:" \
				"${bgStackSimpleCmd[$frameNo]}"

		# in addition to the individual arrays, make a composite stk array that has the other attributes tokenized into a string
		local vLine=""
		printf -v vLine "%s\b"  "${bgStackFrameType[$frameNo]:-SCRIPT}" "${bgStackSrcFile[$frameNo]}" "${bgStackSrcLineNo[$frameNo]}" "${bgStackSrcLocation[$frameNo]}" "${bgStackSimpleCmd[$frameNo]}" "${bgStackFunction[$frameNo]}"
		stringToBashToken vLine
		bgStack+=("${vLine//$'\b'/ }")
	done
}

# usage: bgStackPrint
# this prints a stack trace to stdout in the standard format.
# This was the original algorithm, written before the bgStackGetFrame and bgStackPrintFrame
# Options:
#    --allStack     : do not hide the first N stack frames that are considered part of the system code
#                     * when running in the debugger, the DEBUG trap handler frames are normally suppressed
#                     * when assertError is called by code, all the frames below the first assert* function are suppressed
#    --noSrcLookup  : normally, for each logical stack frame the source line is extracted from the script command or library file
#                     this suppresses that work. For the debugger and error handling the difference in work is not significant.
#    --oneline      : if the source code for a stack frame spans multiple lines, only show the first line followed by ...
#    --logicalStart : indicate where the logical start of the call stack is relative to this function call. Normally the call to
#                     bgStackPrint will be the last frame seen in the output. Adding --logicalStart+1 will supress the call to bgStackPrint.
#                     adding --logicalStart+2 will supress the function that called bgStackPrint also. If --allstack is specified
#                     all the frames will be shown but the --logicalStart point may be indicated in the output.
function bgStackPrint()
{
	local noSrcLookupFlag allStackFlag logicalFrameStart=1 onelineFlag argValuesFlag stackDebugFlag
	while [ $# -gt 0 ]; do case $1 in
		--allStack) allStackFlag="--allStack" ;;
		--noSrcLookup) noSrcLookupFlag="--noSrcLookup" ;;
		--oneline)     onelineFlag="oneline" ;;
		--argValues)   argValuesFlag="argValues" ;;
		--sourceAndArgs) argValuesFlag="both" ;;
		--stackDebug)  stackDebugFlag="--stackDebug" ;;
		--logicalStart*) ((logicalFrameStart+=${1#--logicalStart?})) ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
bgtraceVars argValuesFlag
	#bgStackDump
	bgStackMakeLogical $stackDebugFlag $noSrcLookupFlag --logicalStart+$logicalFrameStart

	local startFrame=0; [ ! "$allStackFlag" ] && startFrame="$bgStackLogicalFramesStart"

	echo "===============  BASH call stack trace P:$$/$BASHPID TTY:$(tty 2>/dev/null) ====================="
	local frameNo; for ((frameNo=$bgStackSize-1; frameNo>=startFrame; frameNo--)); do
		case $onelineFlag:$argValuesFlag in
			:both)             printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]}"
							   printf "%-*s    %s\n" "$((bgStackSrcLocationMaxLen+1))" "" "${bgStackSimpleCmd[$frameNo]}"
							   ;;
			:argValues)        printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLineWithSimpleCmd[$frameNo]}" ;;
			:)                 printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]}" ;;
			oneline::both)     printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]/$'\n'*/...}"
							   printf "%-*s    %s\n" "$((bgStackSrcLocationMaxLen+1))" "" "${bgStackSimpleCmd[$frameNo]/$'\n'*/...}"
							   ;;
			oneline:argValues) printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLineWithSimpleCmd[$frameNo]/$'\n'*/...}" ;;
			oneline:)          printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]/$'\n'*/...}" ;;
		esac
	done
	echo "=================  last line invoked the stack trace  =========================="
}


# OBSOLETE? bgStackMakeLogical now produces bgStack which is similar but does not include some duplicate formatted vars
#           in any case, even if we want a more complete version it should be made there and not here.
# usage: bgStackGet <retStack>
# create a stack trace of the current execution state and return it in an array where each array element is a tokenized string
# of stack frame attributes
# the last array element is a string of integers stackSize, logicalStart, and 3 max lengths for fields
function bgStackGet()
{
	local noSrcLookupFlag allStackFlag logicalFrameStart=1 onelineFlag
	while [ $# -gt 0 ]; do case $1 in
		--noSrcLookup) noSrcLookupFlag="--noSrcLookup" ;;
		--logicalStart*) ((logicalFrameStart+=${1#--logicalStart?})) ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local retVar="$1"
	local retVar2="$2"

	bgStackMakeLogical $noSrcLookupFlag --logicalStart+$logicalFrameStart

	varSetRef --array  $retVar
	varSetRef --array  $retVar2

	varSetRef --array -a $retVar "
		"${bgStackSize}"
		"${bgStackLogicalFramesStart}"
		"${bgStackSrcLocationMaxLen}"
		"${bgStackFunctionMaxLen}"
		"${bgStackSrcCodeMaxLen}"
	"
	local frameNo; for ((frameNo=$bgStackSize-1; frameNo>=startFrame; frameNo--)); do
		if ((frameNo > bgStackLogicalFramesStart )); then
			varSetRef --array -a $retVar2 "$(printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]/$'\n'*/...}")"
		fi

		varSetRef --array -a $retVar "$(cmdline \
			"${bgStackSrcFile[$frameNo]}" \
			"${bgStackSrcLineNo[$frameNo]}" \
			"${bgStackSrcLocation[$frameNo]}" \
			"${bgStackSimpleCmd[$frameNo]}" \
			"${bgStackFrameType[$frameNo]}" \
			"${bgStackSrcCode[$frameNo]}" \
			"${bgStackFunction[$frameNo]}" \
			"${bgStackLine[$frameNo]}" \
			"${bgStackLineWithSimpleCmd[$frameNo]}" \
			"${bgStackBashStkFrm[$frameNo]}"
		)"
	done
}


function bgGetPSTree()
{
	local label passThruOpts
	while [ $# -gt 0 ]; do case $1 in
		-l*|--label*) bgOptionGetOpt val: label "$@" && shift ;;
		-*) bgOptionGetOpt opt passThruOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local thePID="${1:-$$}"; shift
	local retVar="$1"

	[ "$label" ] && printf "%s: " "$label"
	if which pstree &>/dev/null; then
		returnValue "$(pstree -pl "${passThruOpts[@]}" "$thePID")" $retVar
	else
		returnValue "bgtracePSTree: error: pstree not installed. install it to get process tree information" $retVar
	fi
}


# usage: bgStackGetFunctionLocation <functionName> <srcFileVar> <srcLineVar>
function bgStackGetFunctionLocation()
{
	local isOn functionNameRead srcFileValue srcLineValue
	local functionName="$1"
	local srcFileVar="$2"
	local srcLineVar="$3"
	shopt -q extdebug && isOn="1"
	[ ! "$isOn" ] && shopt -sq extdebug
	read -r functionNameRead srcLineValue srcFileValue < <(declare -F "$functionName")
	[ ! "$isOn" ] && shopt -uq extdebug
	returnValue "$srcFileValue" "$srcFileVar"
	returnValue "$srcLineValue" "$srcLineVar"
}

# usage: bgStackPrintFrame [<functionName>+|-]<offset>
# prints a line describing the stack frame at the specified location on the stack.
# If <functionName> is not specified, this function will add 1 to offset so that the caller of this
# function will be the reference frame even though this function calls bgStackGetFrame where the
# offset is interpreted
# see man bgStackGetFrame for a description of [<functionName>][+|-]<offset>
# See Also:
#     bgStackGetFrame : bgStackPrintFrame uses bgStackGetFrame to get the information to print
#     bgStackTrace    : prints the whole formatted stack to the bgtrace destination
function bgStackPrintFrame()
{
	local formatFlag
	while [ $# -gt 0 ]; do case $1 in
		--oneline)  formatFlag="--oneline" ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _offsetTerm="$1"
	[[ "$_offsetTerm" =~ ^[+-]?[0-9]*$ ]] && ((_offsetTerm++))
	local -A stackFrame=(); bgStackGetFrame  "$_offsetTerm" stackFrame || return 1
	if [ "$formatFlag" == "--oneline" ]; then
		local colCount; cuiGetScreenDimension "" colCount
		echo "${stackFrame[printLine]:0:$colCount}"
	else
		echo "${stackFrame[printLine]}"
	fi
	return 0
}

#function bgStackGetFrame() moved to bg_libCore.sh

# usage: bgStackDump
# this is only used for debuggin bgStackMakeLogical.
# The typical way to use it is to uncomment the line in assertError that calls it
function bgStackDump()
{
	printf "%4s %-25s %14s %-25s %s %s\n" "frm#" "FUNCNAME#=$((${#FUNCNAME[@]}-1))"  "BASH_LINENO#=$((${#BASH_LINENO[@]}-1))"  "BASH_SOURCE#=$((${#BASH_SOURCE[@]}-1))"   "BASH_ARGC#=$((${#BASH_ARGC[@]}-1))" "BASH_ARGV#=$((${#BASH_ARGV[@]}))"
	#local frameNo; for frameNo in "${!FUNCNAME[@]}"; do
	local frameNo; for ((frameNo=${#FUNCNAME[@]}-1; frameNo>=0; frameNo--)); do
		local n argcOffset=0; for ((n=0; n<frameNo; n++)); do ((argcOffset+=${BASH_ARGC[$n]:-0})); done
		local argList="" j; for ((j=0; j<${BASH_ARGC[$frameNo]}; j++)); do  argList+=" '${BASH_ARGV[$((argcOffset++))]}'"; done
		((frameNo>0)) && printf "%4s %-25s %14s %-25s %2s %s\n" "$((frameNo-1))" "${FUNCNAME[$frameNo]}" "${BASH_LINENO[$frameNo]}" "${BASH_SOURCE[$frameNo]##*/}" "${BASH_ARGC[$frameNo]}" "$argList"
	done
#	printfVars bgBASH_funcDepthDEBUG bgBASH_debugTrapLINENO
#	printfVars ${!bgBASH_trapStkFrm_*}
}

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

# usage: bgStackMakeLogical [--noSrcLookup] [--logicalStart+<n>]
# This makes a logical call stack that is intuitive to use. It initializes the $bgStatck* global vars. Whereas the item described
# in each bash function call stack frame is a function scope, each frame in this logical stack is a line of code which is how most
# programmers think of a call stack.
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
# There are two distinct cases -- the DEBUG trap and all other (User level) traps. When in the DEBUG trap handler, this function
# adds an additional stack frame that represents the line of code that the debugger is stopped on and relies on the DEBUG trap
# handler to record the LINENO variable in the bgBASH_debugTrapLINENO to no what source line corresponds to BASH_COMMAND.
#
#
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
#                                   for the first logical stack frame during a trap, this is exact b/c bash provides it.
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
		# the translation bask to the original file. It adds the bgtraceBreak as an addtional compound clause to existing lines so that
		# the simple commands executed by bash will still match up with the original lines in the files
		declare -gA bgBASH_debugBPInfo
		local bpInfo="${bgBASH_debugBPInfo["${bgStackFunction[$bgStackSize]// /}"]}"
		if [ "$bpInfo" ]; then
			read -r origLineNo newLineNo origFile <<<"$bpInfo"
			bgStackSrcFile[$bgStackSize]="$origFile"
			bgStackSrcLineNo[$bgStackSize]="$((bgStackSrcLineNo[$bgStackSize] - newLineNo + origLineNo))"
		fi


		bgStackSrcLocation[$bgStackSize]="${bgStackSrcFile[$bgStackSize]##*/}:(${bgStackSrcLineNo[$bgStackSize]})"

		if [ ! "$noSrcLookupFlag" ] && [ -r "${bgStackSrcFile[$bgStackSize]}" ] && ((${bgStackSrcLineNo[$bgStackSize]:-0} > 0 )); then
			bgStackSrcCode[$bgStackSize]="$(sed -n "${bgStackSrcLineNo[$bgStackSize]}"'{s/^[[:space:]]*//;p;q}' "${bgStackSrcFile[$bgStackSize]}" 2>/dev/null )"
			if [[ "${bgStackSrcCode[$bgStackSize]}" =~ ^[[:space:]]*[{][[:space:]]*$ ]] && [[ ! "${bgStackSimpleCmd[$bgStackSize]}" =~ ^[\<] ]]; then
				bgStackSimpleCmd[$bgStackSize]="{"
			fi
		else
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

		# we call this when every we know we are on a trap handler transition. It sets the type of the frame we just added but also
		# sets the type of any unclaimed frames below it. E.G. when we cross the DEBUG trap border, it claims everything up to that
		# point as part of the DEBUG trap. Then later if we call it for a user trap, then it will claim anything between the DEBUG
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
		# if the trap handler is invoking _debugEnterDebugger then we assume its our well know debugSetTrap handler
		_constructSimpleCommandFromBashStack "$((i-1))" frmSimpleCmd
		if [[ "$frmSimpleCmd" =~ _debugEnterDebugger.*DEBUG-852 ]]; then
			findInclude bg_debugger.sh frmSrcFile; assertNotEmpty frmSrcFile --critical
			frmFunc="DEBUGTrap"
			frmSrcLineNo="$(awk '/^[[:space:]]*_debugEnterDebugger[[:space:]][[:space:]]*.!DEBUG-852!./ {print NR}' "$frmSrcFile")"
			frmSimpleCmd='_debugEnterDebugger "!DEBUG-852!"'
		else
			frmSrcFile="<TRAP:DEBUG>"
			frmFunc="DEBUGTrap"
			frmSrcLineNo="0"
		fi
	}



	local noSrcLookupFlag logicalFrameStart=1
	while [ $# -gt 0 ]; do case $1 in
		--noSrcLookup) noSrcLookupFlag="--noSrcLookup" ;;
		--logicalStart*) ((logicalFrameStart+=${1#--logicalStart?})) ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# if we are in a DEBUG handler, frameIdxOfDEBUGTrap will point to the bash array index where the trap was invoked.
	# an empty value indicates that there is no DEBUG handler on the stack. 0 would be a problem but we know that it can not be zero
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

	# iterate over the bash stack array (BASH_SOURCE, et all) and insert frames into our arrays (bgStack*)
	local i frmSrcFile frmFunc frmSrcLineNo frmSimpleCmd frmSrcLineText
	for ((i=0; i<${#BASH_SOURCE[@]}; i++)); do
		# the structure of this loop is that various conditions examine the current frame $i and determine if they should handle it.
		# if no conditions match, the default handler block at the end will add its corresponding logical stack frame.
		local doDefaultBlock="1"
		local frmSrcFile="" frmFunc="" frmSrcLineNo="" frmSimpleCmd="" frmSrcLineText=""

		# make a summary line of the bash stack vars to aid in debugging this algorithm
		local bashStkFrmSummary; printf -v bashStkFrmSummary "[%2s]%-20s : %4s : %s" "$i" "${BASH_SOURCE[$i]##*/}" "${BASH_LINENO[$i]}" "${FUNCNAME[$i]}"

		# if one of our trap handlers managed by bgtrap is hinting us that they are active, use that instead of the frame dicontinuity algorithm
		local detectedTrapFrame=""; ((i == (${#BASH_SOURCE[@]} - bgBASH_trapStkFrm_funcDepth) )) && detectedTrapFrame="$bgBASH_trapStkFrm_signal"

		# detect if this frame is the start of a TrapHandler.
		# NOTE: BASH does not record something like a FUNCNAME entry when a signal trap handler starts executing.
		# The trap handlers that bgtrap and debugger and Try:/Catch: manage gives us the required hints when they are executing.
		# This detection block handles the case when a trap handler is executing and does not give us the hint. This happens on the
		# fist line when we step into a trap call on the line that is about to call BGTRAPEntry (which records the hint information)
		# Also, we might want to turn off the way bgtrap does the hint when bgtraceing is not active and we still want to detect the
		# trap so that stack traces in asserts are not misleading when they try to get the lineno from the adjancent frame which is
		# not correct. When FUNCNAME[$i] is not interruped by a trap handler, the source line within FUNCNAME[$i] at
		# BASH_SOURCE[$1]:BASH_LINENO[$i-1] will include a reference to FUNCNAME[$i-1]. If not, we can glean that the FUNCNAME[$i-1]
		# is the result of a trap handler interruping FUNCNAME[$i]. If we find FUNCNAME[$i-1] in one of the active handlers, we can
		# assume that it is running and responsible for FUNCNAME[$i-1] being on the stack.
		if [ ! "$detectedTrapFrame" ] && ((i>0)) && [ ! "$noSrcLookupFlag" ] && [ "${BASH_SOURCE[$i]}" != "environment" ]; then
			# BASH BUG: for the first DEBUG trap hit in a new UserTrap handler, BASH_COMMAND will still have the last value before the UserTrap
			local referenceText="${FUNCNAME[$i-1]}"; ((frameIdxOfDEBUGTrap == i)) && referenceText="$BASH_COMMAND"
			frmSrcLineNo=$(( (frameIdxOfDEBUGTrap == i)?bgBASH_debugTrapLINENO:${BASH_LINENO[$i-1]} ))
			# CRITICALTODO: this code that gets the source line from the file needs to take into account \ line continuations.
			[ ${frmSrcLineNo:-0} -gt 0 ] && [ -r "${BASH_SOURCE[$i]}" ] && frmSrcLineText="$(sed -n "${frmSrcLineNo}"'{s/^[[:space:]]*//;p;q}' "${BASH_SOURCE[$i]}" 2>/dev/null )"
			if [[ ! "$frmSrcLineText" =~ $referenceText ]]; then
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
				detectedTrapFrame="${sigCandidates[*]}"
				if [ ! "$detectedTrapFrame" ]; then
					if ((frameIdxOfDEBUGTrap != i)); then
						detectedTrapFrame="UNKPOTTRAP"
					fi
				fi
			fi
		fi

		# Non-adjancent Frame -- First frame.
		# Add a logical frame for this code, right here.  FUNCNAME[0]==bgStackMakeLogical (this function) but there is no bash stack
		# frame below [0] to indicate where we are in that function. For completeness, we can hardcode a frame to represent this line.
		if ((i==0)); then
			# the bgStackSimpleCmd is the literal text of the this next line (we simplify it to exclude the parameters)
			_pushLogicalStackEntry FRM0 \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"$((LINENO-1))" \
				"_pushLogicalStackEntry FRM0"
			continue
		fi

		# Non-adjancent Frame -- DEBUGTrap transistion to a normal function that it interuptted.
		# This will only hit when we are in the debugger. We are at the frame where the DEBUG handler started.
		# In this case, the debugger did not interupt a top level UserTrap line so BASH[$i] is a normal frame (UserTrap or LogicalScript)
		# except for being interupted by the DEBUGTrap
		if ((i == frameIdxOfDEBUGTrap)) && [ ! "$detectedTrapFrame" ]; then
			# synthesize a frame to represent the DEBUG handler script
			_makeDEBUGTrapFrame
			_pushLogicalStackEntry DBG1 \
				"$frmSrcFile" \
				"$frmFunc" \
				"$frmSrcLineNo" \
				"$frmSimpleCmd" \
				"lastFrameOfType:DEBUG"

			# record that this is the real logical start because in the debugger, this is where execution is stopped
			bgStackLogicalFramesStart=$((bgStackSize))

			# now add the logical frame for the line of code that the debugger is stopped on.
			_pushLogicalStackEntry DBG2 \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${bgBASH_debugTrapLINENO}" \
				"${BASH_COMMAND}"

			doDefaultBlock=""
		fi


		# Non-adjancent Frame -- DEBUGTrap transistion to code directly in a UserTrap that it interuptted.
		# In this case, we are stepping through the UserTrap handler at the top level while that handler is not in a function call.
		# BASH[$i] is the function that was being executed when the UserTrap hapenned. The stack does not say which line in that function
		# BASH[$i-1] is the first function of the DEBUG trap that led to this code running.
		# bgBASH_debugTrapLINENO is LINENO at the moment DEBUG trap started and refers to the lineNo in the UserTrap handler that is running
		if ((i == frameIdxOfDEBUGTrap)) && [ "$detectedTrapFrame" ]; then
			# synthesize a frame to represent the DEBUG handler script
			_makeDEBUGTrapFrame
			_pushLogicalStackEntry CMB1 \
				"$frmSrcFile" \
				"$frmFunc" \
				"$frmSrcLineNo" \
				"$frmSimpleCmd" \
				"lastFrameOfType:DEBUG"

			# record that this is the real logical start because in the debugger, this is where execution is stopped
			bgStackLogicalFramesStart=$((bgStackSize))

			# now add the logical frame for the line of code that the debugger is stopped on
			# which is a line in the UserTrap handler script.
			_pushLogicalStackEntry CMB2 \
				"<TRAP:$detectedTrapFrame>" \
				"${detectedTrapFrame// /,}Trap" \
				"${bgBASH_debugTrapLINENO}" \
				"${BASH_COMMAND}" \
				"lastFrameOfType:${detectedTrapFrame/ */,...}"

			# now add the logical frame for the line of code that UserTrap interrupted. This is the first proper script line.
			bgStackGetFunctionLocation "${FUNCNAME[$i]}" frmSrcFile frmSrcLineNo
			_pushLogicalStackEntry CMB2 \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${frmSrcLineNo:-0}" \
				"${bgBASH_trapStkFrm_lastCMD:-<${FUNCNAME[$i]}() interupted by ${detectedTrapFrame// /,}>}"

			doDefaultBlock=""
		fi


		# Non-adjancent Frame -- UserTrap transistion to a normal function that it interuptted.
		# At UserTrap handler which is calling at least one function (b/c we are not alos at the DEBUGTrap frame)
		if ((i != frameIdxOfDEBUGTrap)) && [ "$detectedTrapFrame" ]; then
			# synthesize a frame to represent the handler script
			_constructSimpleCommandFromBashStack "$((i-1))" frmSimpleCmd
			_pushLogicalStackEntry UTR1 \
				"<TRAP:$detectedTrapFrame>" \
				"${detectedTrapFrame// /,}Trap" \
				"${BASH_LINENO[$i-1]}" \
				"$frmSimpleCmd" \
				"lastFrameOfType:${detectedTrapFrame/ */,...}"

			# now add the logical frame for the line of code that the UserTrap interupted
			# UserTraps always have LINENO set to 1 (not the interrupted value as with DEBUGTrap) so we can not know what line in the
			# function we interrupted.
			# Note that our BGTRAPEntry records the value of BASH_COMMAND when its entered which is the last command executed in
			# the interupted function represented by this frame. We can use that to detect the line number
			bgStackGetFunctionLocation "${FUNCNAME[$i]}" frmSrcFile frmSrcLineNo
			# TODO: use bgBASH_trapStkFrm_lastCMD to calculate frmSrcLineNo
			_pushLogicalStackEntry UTR2 \
				"${BASH_SOURCE[$i]}" \
				"${FUNCNAME[$i]}" \
				"${frmSrcLineNo:-0}" \
				"${bgBASH_trapStkFrm_lastCMD:-<${FUNCNAME[$i]}() interupted by ${detectedTrapFrame// /,}>}"

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
	# This is that +1 frame that we are added now that will use that part of the last bash frame.

	# the highest (last) frame on the BASH_ stack is one of
	#        'main'         : normal case. running a script in a non-interactive bash process
	#        'source'       : sourcing a script into an interactive bash process (aka a terminal emulator win)
	#        <functionName> : running a function from an interactive bash process. This is typical of bash completion scripts and
	#                         functions in the bg-debugCntr system of development tools. The function is typically sourced from a
	#                         earlier in a session (maybe in the .bashrc) and now its being invoked directly on the command line.

	local simpleCommand=""; lastFrame="$((${#BASH_SOURCE[@]}-1))"
	if [[ ${FUNCNAME[$lastFrame]} =~ ^(main|source)$ ]]; then
		# when bg_core.sh is sourced some top level, global code records the cmd line that invoked in bgLibExecCmd
		local v; for (( v=0; v <=${#bgLibExecCmd[@]}; v++ )); do
			local quotes=""; [[ "${bgLibExecCmd[v]}" =~ [[:space:]] ]] && quotes="'"
			simpleCommand+=" ${quotes}${bgLibExecCmd[v]}${quotes}"
		done
	else
		# when the highest (last) is a sourced function, then its just like any other function call
		_constructSimpleCommandFromBashStack "$(($lastFrame-1))" simpleCommand
	fi
	_pushLogicalStackEntry TOPL \
		"<bash:$$>" \
		"Script On Interative Bash" \
		"1" \
		"$simpleCommand"


	local frameNo; for ((frameNo=0; frameNo<bgStackSize; frameNo++)); do
		local allButLast="1"; ((frameNo==bgStackSize-1)) && allButLast=""
		printf -v bgStackLine[$frameNo] "%-*s : %s" \
				"$((bgStackSrcLocationMaxLen+1))" "${bgStackSrcLocation[$frameNo]}:" \
				"${bgStackSrcCode[$frameNo]}"
		printf -v bgStackLineWithSimpleCmd[$frameNo] "%-*s : %s" \
				"$((bgStackSrcLocationMaxLen+1))" "${bgStackSrcLocation[$frameNo]}:" \
				"${bgStackSimpleCmd[$frameNo]}"
		# printf -v bgStackLine[$frameNo] "%-*s %-*s: %s" \
		# 		"$((bgStackSrcLocationMaxLen+1))" "${bgStackSrcLocation[$frameNo]}:" \
		# 		"$((bgStackFunctionMaxLen+2))"  "${bgStackFunction[$frameNo]}${allButLast:+()}" \
		# 		"${bgStackSrcCode[$frameNo]}"
	done
	#bgStackDump >> $_bgtraceFile
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
	local noSrcLookupFlag allStackFlag logicalFrameStart=1 onelineFlag
	while [ $# -gt 0 ]; do case $1 in
		--allStack) allStackFlag="--allStack" ;;
		--noSrcLookup) noSrcLookupFlag="--noSrcLookup" ;;
		--oneline)  onelineFlag="--oneline" ;;
		--logicalStart*) ((logicalFrameStart+=${1#--logicalStart?})) ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	#bgStackDump
	bgStackMakeLogical $noSrcLookupFlag --logicalStart+$logicalFrameStart

	local startFrame=0; [ ! "$allStackFlag" ] && startFrame="$bgStackLogicalFramesStart"

	echo "===============  BASH call stack trace P:$$/$BASHPID TTY:$(tty 2>/dev/null) ====================="
	local frameNo; for ((frameNo=startFrame; frameNo<$bgStackSize; frameNo++)); do
		if [ "$onelineFlag" ]; then
			printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]/$'\n'*/...}"
		else
			printf "%s %s\n" "${bgStackFrameType[$frameNo]}" "${bgStackLine[$frameNo]}"
		fi
	done
	echo "=================  end of call stack trace  =========================="
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
# this is only used for debuggin stack trace functions. The bash stack vars are confusing so it can be helpful
# to see the raw data printed in a neat table
function bgStackDump()
{
	local argIdx=0
	printf "%4s %-25s %14s %-25s %s %s\n" "frm#" "FUNCNAME#=$((${#FUNCNAME[@]}-1))"  "BASH_LINENO#=$((${#BASH_LINENO[@]}-1))"  "BASH_SOURCE#=$((${#BASH_SOURCE[@]}-1))"   "BASH_ARGC#=$((${#BASH_ARGC[@]}-1))" "BASH_ARGC#=$((${#BASH_ARGV[@]}))"
	local frameNo; for frameNo in "${!FUNCNAME[@]}"; do
		local argList="" j; for ((j=0; j<${BASH_ARGC[$frameNo]}; j++)); do  argList+=" '${BASH_ARGV[$((argIdx++))]}'"; done
		((frameNo>0)) && printf "%4s %-25s %14s %-25s %2s %s\n" "$((frameNo-1))" "${FUNCNAME[$frameNo]}" "${BASH_LINENO[$frameNo]}" "${BASH_SOURCE[$frameNo]##*/}" "${BASH_ARGC[$frameNo]}" "$argList"
	done
	echo "BASH_COMMAND='$BASH_COMMAND' "
	printfVars frameIdxOfDEBUGTrap bgBASH_funcDepthDEBUG bgBASH_debugTrapLINENO
	printfVars ${!bgBASH_trapStkFrm_*}
}

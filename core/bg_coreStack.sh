
# Library bg_coreStack.sh
# This library provides features to work with the BASH native stack variables that keep track of the function execution stack.
# The native bash stack is incomplete or missleading in several ways which this library addresses.
#    * its difficult to interpret the native frame info
#    * trap handlers are not represented on the stack when they are invoked even though they share the stack which makes it discontinuous
#    * frames do not stand alone -- some attributes of the current frame are in the +1 frame above it
#    * when a trap handler is running, at that boundary, the +1 frame does not contain the right info for that frame
#    * the top frame is incomplete because logically it should describe the thing that invoked the script but does not.
#    * in a DEBUG trap, the interupted line is not represented
#
# Another issue that this library addresses is that the native stack continues to vary as functions are executed to examine it.
#
# The heart of this library is the bgStackFreeze function which does the following....
#     * copies the native BASH stack variables into new variables prefixed with 'bg'. i.e. FUNCNAME is copied into bgFUNCNAME
#     * new bgSTK_* variables are derived from the native variables
#     * missing trap handler frames are detected and inserted into the new variables.
#     * the top frame in the new vars is fixed up so that it represents and describes how the script was executed
#     * if the DEBUG trap is running, a bottom frame is added to the new vars to represent the interupted script line.
#     * each frame of the new vars stand alone so you do not need to reference adjacent frames to get info about that frame.
#
# bgStackFreeze is executed by assertError and the debugger DEBUG trap handler at their starts. Then bgStack* commands can be used
# to query the frozen stack.  bgStackUnFreeze is used to clear the variables created by freeze after it is not needed any more.
#
# bgStackMarshal/bgStackUnMarshal are used by assertError when it is throwing an exception in a subshell which is caught in a parent
# shell.
#
# In addition, to the bgStackFreeze/bgStackUnFreeze system of operating on the stack, there is the bgStackFrameGet function that
# stands alone. It logically operates on the same sythetic stack that bgStackFreeze creates but does minimal work to get the attributes
# of just one frame. Some features like bgmktemp() and Try() record the frame description of the thing that called them in order to
# provide context. This is different from the bgStackFreeze pattern because it is used in the non-error path of a script and needs
# to be more performant.
#
# In Summary, there are several principle ways to use this library.
#    bgStackFreeze   : typically used in error and development paths. After calling freeze, other functions in this library operate
#                       on the frozen stack
#    bgStackFrameGet : works on its own or on a frozen stack. typically used in non-error paths to provide information that may or
#                      may not be used at a latter time or for logging.
#    bgStackPrint    : works on its own or on a frozen stack.
#
# See Also:
#    man(3) assertError
#    man(3) Try
#    man(7) bg_debugger.sh



# usage: bgStackFreeze <ignoreFrames> [<interruptedSimpleCmd> <interuptedLineNo>]
# makes a copy of the BASH stack array variables (prepended with 'bg') so that other functions can operate on the copy without it
# changing as the real vars would as other functions are being pushed onto and popped off of the native bash stack. assertError
# freezes the stack at the top of its execution and the debugger freezes the stack just before entering the degger UI.
#
# It also produces a new set of stack variables (bgSTK_*) which fixup the native stack in various ways.
#
# Copies of the Native Stack Vars:
# The copies of builtins retain their original meaning and are untouched. The original vars are not changed so that anything that
# was built to use the native stack can still interpret these variables consistently and also for trouble shooting the stack
# processing, its valueable to be able to dump the untouched values. bgStackDump writes out the native and new vars for comparison.
#
#    bgFUNCNAME    : name of a bash function that is the simpleCmd being executed at this frame. (the top frame may be the literal 'main' or 'source')
#    bgBASH_SOURCE : scr file containing the bgFUNCNAME code. This is NOT where function is being invoked, but where it is defined.
#    bgBASH_LINENO : the line number where the bgFUNCNAME was invoked (this corresponds to the previous(+1) frame's bgBASH_SOURCE)
#    bgBASH_ARGC   : the number of arguments being passed to bgFUNCNAME in this invocation.
#    bgBASH_ARGV   : array of all arguments on the stack. You need to walk the stack from the bottom and add up bgBASH_ARGC to get
#                    offset of the args of this function. Also, the args are backwards so you access them like offset+argc-<argNum>
#                    where <argNum> corresponds to $1..$n
#
# New Stack Vars:
# These vars attempt to make the stack attributes more clear. Attributes are associated with two logical things in each frame.
#      simpleCmd : the main entity of a frame is a 'simple command' invocation. (see man bash for a definition of 'simple command')
#                  An invocation is is the `<cmdName> <arg1>..<argN>` and is located in <cmdFile> at <cmdLineNo>.
#                  In the native vars, FUNCNAME is always a bash function (except the top frame), but <cmdName> which is close to
#                  FUNCNAME may also be an external cmd or builtin, etc...
#      caller    : the entity that invoked the the simpleCmd invocation. Its usefull to know which function contains the invocation
#                  that the frame represents.
#
# There are four things that the new attributes do that the native attributes do not.
#    1) each frame stands alone. You dont need to get some information from an adjacent frame and check for boundary conditions
#       when doing so.
#    2) the top frame better represents how the script was invoked and has consistent information about that invocation.
#    3) In a DEBUG trap, the simple command that will run next is added to the bottom of the stack. Unlike all the native stack
#       frames this simple cmd does not have to be a bash function. Adding this frame is useful for the debugger but also when an
#       exception is thrown inside a DEBUG trap so that the stack makes sense.
#    4) non-DEBUG traps are detected and a frame is inserted to represent the interupted code and to resolve the misleading
#       discontinuity in the native stack. In the native stack, we have to match up the BASH_SOURCE from one frame with the
#       BASH_LINENO of an adjacent frame but when a trap handler invokes a bash funcction, the two adjacent frames do not correspond
#
#    bgSTK_caller     : name of the function/PID that contains the executing simple cmd. This is FUNCNAME attribute shifted by one
#                       and with the boundary conditions fixed up. <cmdLoc> describes a poisition inside <caller>
#    bgSTK_cmdName    : cmd name in simpleCmd being executed within caller (does not include args).
#                       This is a fixed up version of FUNCNAME
#    bgSTK_cmdLine    : the cmdline of the simpleCmd being executed (<cmdName> <arg1>..<argN>)
#                       This is derived from FUNCNAME, bgBASH_ARGC and BASH_ARGV
#    bgSTK_cmdFile    : src file containing the code that is invoking simpleCmd.
#                       This is BASH_SOURCE shifted down by one and fixed up.
#    bgSTK_cmdLineNo  : the line number where the simpleCmd being executed is at in <cmdFile>.
#                       This is the fixed up version of BASH_LINENO
#    bgSTK_argc       : same as the original but we modify it to fix a quirk with source <filename> and to add interupt frames
#    bgSTK_argv       : same as the original but we modify it to fix a quirk with source <filename> and to add interupt frames
#    bgSTK_argOff     : the offset into <argc> where this frame's arguments start. Note that they are backwards so $n is [<argOff>-n]
#    bgSTK_cmdLoc     : a one token expression made from <cmdFile> and <cmdLineNo> that describes where to find the source line of
#                       simpleCmd.
#    bgSTK_cmdSrc     : (optional) the line of code that contains simpleCmd read from <cmdLoc>. This is logically the
#                        same as cmdLine but it is literally what the author wrote and may contain whole or part of other simple
#                        commands that are written before and after it on the same text line. Also, <cmdLine> is normalized so
#                        <cmdSrc> may vary in whitespace and escaping method (i.e. quotes).
#                        The bgStackFreezeAddSourceCodeLines function creates this variable.
#    bgSTK_frmSummary : (optional) a one line summary that describes the frame suitable for a stack trace
#                        The bgStackRenderFormat function creates this variable.
#
# Params:
#    <ignoreFrames> : the number of stack frames to ignore on the bottom of the stack. The default is 1 which would ignore the
#                     call to this function so that the caller will be the bottom frame in the frozen stack.
#   <interruptedSimpleCmd> : when a DEBUG trap handler freezes the stack, it can pass the BASH_COMMAND and LINENO to add a stack
#                     frame to represent the simple command being interupted.
#   <interuptedLineNo> : if <interruptedSimpleCmd> is specified, this must be also. Note that in a DEBUG trap handler, LINENO starts
#                     out to be the interupted line number but it will continue to increment with each line of the trap handler so
#                     the handler must copy LINENO is its first line, before any carrage return in the handler string.
function bgStackFreeze() {
	local readCodeFlag="true" allFlag i
	while [ $# -gt 0 ]; do case $1 in
		-a|--all) allFlag="-f" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# what to do if we already have a frozen stack
	# TODO: circa 2021-02: Try/Catch never calls bgStackFreezeDone because the block after Catch needs to access it and so far, we
	#       dont have any function that gets called when the user's catch block finishes. So the default action is to overwrite
	#       the last stack. Time should tell if there are cases where we need to call bgStackFreeze without changing the frozen stack
	local dontOverwritePreviousFrozenStack # TODO: should this be an option?
	if varExists bgSTK_cmdName; then
		[ "$dontOverwritePreviousFrozenStack" ] && return 0
		bgStackFreezeDone
	fi

	local ignoreFrames="${1:-1}"; (( ignoreFrames=((ignoreFrames<(${#FUNCNAME[@]})) ? (ignoreFrames) : (${#FUNCNAME[@]}-1)) ))
	local interruptedSimpleCmd="$2"
	local interuptedLineNo="$3"

	### copy the builtin bash stack array vars. The only modification is that we optionally remove on or more frames from the bottom
	declare -ga bgFUNCNAME=("${FUNCNAME[@]:$ignoreFrames}")
	declare -ga bgBASH_SOURCE=("${BASH_SOURCE[@]:$ignoreFrames}")
	declare -ga bgBASH_LINENO=("${BASH_LINENO[@]:$ignoreFrames}")
	declare -ga bgBASH_ARGC=("${BASH_ARGC[@]:$ignoreFrames}")
	local i offset; for ((i=0; i<ignoreFrames; i++)) do ((offset+=${BASH_ARGC[i]:-0})); done
	declare -ga bgBASH_ARGV=("${BASH_ARGV[@]:$offset}")
	# from now on, we work with the copies. We dont change the original copies at all

	### add new synth vars

	local stackSize="${#bgFUNCNAME[@]}"

	# these are mostly the corresponding builtin var but later we will fixup the non-bash-function boundaries
	declare -ga bgSTK_cmdName=("${bgFUNCNAME[@]}")
	declare -ga bgSTK_cmdLineNo=("${bgBASH_LINENO[@]}")
	declare -ga bgSTK_argc=("${bgBASH_ARGC[@]}")
	declare -ga bgSTK_argv=("${bgBASH_ARGV[@]}")

	# these two are mostly the corresponding builtin var but shifted down one to separate the notion of caller and simpleCmd
	declare -ga bgSTK_caller=( "${bgFUNCNAME[@]:1}"    "")
	declare -ga bgSTK_cmdFile=("${bgBASH_SOURCE[@]:1}" "")

	# decorate bash functions in bgSTK_caller by appending () to distinguish from other types of commands
	# at this point, all the entries in bgSTK_caller are from BASH so all except the top one must be bash functions.
	# we shifted bgSTK_caller down one so the top entry is at $stackSize-2.
	for ((i=0; i<$stackSize-2; i++)); do
		bgSTK_caller[i]="${bgSTK_caller[i]}()"
	done

	declare -ga bgSTK_frmCtx=()
	for ((i=0; i<$stackSize; i++)); do
		bgSTK_frmCtx[i]="script"
	done

	# fixup the top frame which represents the line being executed in the top level script which may be a script (main), the gloabl
	# code of a lib being sourced into a terminal, or a sourced function
	# We keep a one-to-one correspondence to the original BASH stack as much as possible (we do add interupt frames below).
	# Each frame is really about the place that the simple command was exectucted so the top frame is about how the script itself
	# was executed.
	case ${bgFUNCNAME[@]: -1} in
		# typical case. running a script as an external command in a new bash session. The container process that invoked the script
		main)
			# replace 'main' with the name of the script. Its in two places bgSTK_cmdName[$stackSize-1], and bgSTK_caller[$stackSize-2]
			bgSTK_cmdName[$stackSize-1]="\$ ${0##*/}"
			((stackSize>1)) &&  bgSTK_caller[$stackSize-2]="${bgSTK_cmdName[$stackSize-1]}"

			local ppid ttyName; read -r ppid ttyName <<<"$(ps -o ppid=,tty= --pid $$)"
			local comm; read -r comm <<<"$(ps -o comm= --pid ${ppid:-$$})"
			bgSTK_caller[$stackSize-1]="${comm}(${ppid})"
			bgSTK_cmdFile[$stackSize-1]="${ttyName//\//-}"
			bgSTK_frmCtx[$stackSize-1]="top.main"
			;;
		# we are executing the global code from a library script being sourced into an interactive terminal. The container is the terminal
		source)
			local ttyName; read -r ttyName <<<"$(ps -o tty= --pid $$)"
			bgSTK_caller[$stackSize-1]="bash($$)"
			bgSTK_cmdFile[$stackSize-1]="${ttyName//\//-}"

			# there is a quirk in BASH that if there are no additional args sent to the sourced script, the <scriptName> is in the
			# BASH_ARGV array as the single argument to 'source'. However, if you pass args like 'source <scriptName> <arg1>..<argN>'
			# then <arg1>..<argN> are in BASH_ARGV but <scriptName> is not. This block attempts to detect when <scriptName> is
			# missing and add it back in.
			local scriptPath="${bgBASH_SOURCE[@]: -1}"   # <scriptName> is the first entry in the BASH_SOURCE array b/c that is what source executes
			local argc="${bgSTK_argc[@]: -1}"
			if [ ${argc:-0} -gt 1 ] || [[ ! "${bgSTK_argv[@]: -1}" =~ ${scriptPath##*/}$ ]]; then
				((stackSize>1)) &&  (( bgSTK_argc[${#bgSTK_argc[@]}-1]++ ))
				bgSTK_argv+=("$scriptPath")
			fi
			bgSTK_frmCtx[$stackSize-1]="top.source"
			;;
		# we are running a function that has been previously sourced into a terminal. The container is the sourced function.
		*)
			local ttyName; read -r ttyName <<<"$(ps -o tty= --pid $$)"
			bgSTK_caller[$stackSize-1]="bash($$)"
			bgSTK_cmdFile[$stackSize-1]="${ttyName//\//-}"
			bgSTK_frmCtx[$stackSize-1]="top.srcdFunc"
			;;
	esac

	# compose bgSTK_cmdLine by appending the args to bgSTK_cmdName
	declare -ga bgSTK_cmdLine=()
	declare -ga bgSTK_argOff=()
	if shopt -q extdebug; then
		local i j argcOffset=0
		for ((i=0; i<$stackSize; i++)); do
			bgSTK_argOff[i]="$argcOffset"
			# re-construct the simple command from the funcname and args
			bgSTK_cmdLine[i]="${bgSTK_cmdName[i]}"
			for ((j=${bgSTK_argc[i]}-1; j>=0; j--)); do
				local sq=""; [[ "${bgSTK_argv[argcOffset+j]}" =~ [[:space:]] ]] && sq="'"
				bgSTK_cmdLine[i]+=" ${sq}${bgSTK_argv[argcOffset+j]}${sq}"
			done
			((argcOffset+=${bgSTK_argc[i]:-0}))
		done
	else
		for ((i=0; i<$stackSize; i++)); do
			bgSTK_cmdLine[i]="${bgSTK_cmdName[i]} <extdebug off...>"
		done
	fi

	# This visualization represets inserting a frame at depth==6 to represent the line of code that a trap interupted.
	# a-f are normal script frames.
	# INT is the inserted frame.
	# g-h are the function stack of the intr handler. If the handler is not in a function call 'f' would be the bottom frame.
	# 'f' is a frame that represents a bash function that is executing when the intr ocurred. The bash stack does not tell
	# us where it is in that function's code because the stack only tells us that when it invokes another bash function. When the
	# intr ocurs, the BASH_COMMAND tells us which command in 'f' just completed before the intr handler started running. We get that
	# from the BGTRAPEntry call that bgtrap adds to all handlers. The lineno that we get from BGTRAPEntry does NOT tell us where in
	# 'f'  BASH_COMMAND is. Instead, we get the lineno of the start of the function which is the best we can do.
	# l=8              l=9
	# a 7 1          a   8 1
	# b 6 2          b   7 2
	# c 5 3          c   6 3
	# d 4 4          d   5 4
	# e 3 5          e   4 5
	# f 2 6 i=2 d=6  f   3 6    <-insertIdx=2   # this line represent where 'f' was invoked but we also known that 'f' is executing
	# g 1 7          INT 2 7                    # we add a line to reprent where in 'f' is executing. We have limitted info.
	# h 0 8          g   1 8                    # 'g' is the function that the trap handler is executing
	#                h   0

	### add frames for any trap handlers that we can detect are on the stack
	#     1) BGTRAPEntry/BGTRAPExit maintains a stack (bgBASH_trapStkFrm_*) of trap handlers that are executing
	#     2) if BGTRAPEntry or BGTRAPExit are on the stack but there is no (bgBASH_trapStkFrm_*) entry, the trap is executing but
	#        its outside the lines where BGTRAPEntry/BGTRAPExit have pushed the entry
	#     3) if lineno on the stack is 1, or a low number it might be a trap handler that does not use BGTRAPEntry/BGTRAPExit
	#        because many scripts dont have code on the first several lines and just by percentages, most code is not at low lineno
	local depth; for ((depth=stackSize; depth>0; depth--)); do
		local i=$(( ${#bgSTK_cmdName[@]} - depth ))

		# see if there is a bgBASH_trapStkFrm_* entry for this stack depth.
		local pushFound="" j; for ((j=0; j<${#bgBASH_trapStkFrm_funcDepth[@]}; j++)); do
			[ "${bgBASH_trapStkFrm_funcDepth[j]}" == "$depth" ] && pushFound="$j"
		done

		# bgBASH_trapStkFrm_* entry
		if [[ "$pushFound" ]]; then
			local signal="${bgBASH_trapStkFrm_signal[$pushFound]}"
			local trapPID="${bgBASH_trapStkFrm_setPID[$pushFound]}"
			local lastCmd="${bgBASH_trapStkFrm_lastCMD[$pushFound]}"
			local intrLineNo="${bgBASH_trapStkFrm_LINENO[$pushFound]}"

		# This is the frame that is calling BGTRAPEntry but the condition above did not detect a bgBASH_trapStkFrm_* entry
		elif ((i>0)) && [[ "${bgSTK_cmdName[i-1]}" =~ ^(BGTRAPEntry|BGTRAPExit)$ ]]; then
			local argStart=$((bgSTK_argOff[i-1]+bgSTK_argc[i-1]))
			local signal="${bgSTK_argv[argStart-2]}"
			local trapPID="${bgSTK_argv[argStart-1]}"
			local lastCmd intrLineNo
			if [ "${bgSTK_cmdName[i]}" == "BGTRAPEntry" ]; then
				lastCmd="${bgSTK_argv[argStart-3]}"
				intrLineNo="${bgSTK_argv[argStart-4]}"
			fi

		# no trap detected here. Nothing to see, move on.
		else
			continue
		fi

		# we detected that this is the last frame before a trap handler started executing.
		# insert one new frame ('ruptd') (aka 'interupted') to represent the line of code that the trap interupted.
		# unlike with the DEBUG trap (which is handled by passeing params to this function), BASH_COMMAND is the last completed
		# command that ran before the trap handler started run. i.e. its the last cmd instead of the next cmd.
		# Above insertIdx: everything is normal
		# Below insertIdx: the first frame needs to be fixed because it had been attributed to being called from the frame above it
		#                  but now we know it was invoked by the interupt handler (which will be the new frame above it)

		local origIdx=$(( ${#bgFUNCNAME[@]} - depth ))
		local insertIdx=$(( ${#bgSTK_cmdName[@]} - depth ))

		# now we know that the $insertIdx-1 is the first func called by the intr handler so fixup caller and cmdFile which had been
		# falsely attributed to the frame above it before now.
		if [ ${insertIdx:-0} -gt 0 ]; then
			bgSTK_caller[$insertIdx-1]="${signal}_HANDLER"
			bgSTK_cmdFile[$insertIdx-1]="${signal}-${trapPID}<handler>"
		fi

		# create our new frame data from these two sources
		#   1) the bottom element of the BASH stack has the FUNCNAME being interrupted and the BASH_SOURCE where that function is defined
		#   2) BGTRAPEntry/BGTRAPExit records BASH_COMMAND and LINENO when the handler starts.
		#            BASH_COMMAND will be the last command completed, unless trap is DEBUG where its the next cmd that will execute
		#            LINENO will only be available if trap is DEBUG (and maybe ERR?)
		local ruptdCaller="${bgFUNCNAME[$origIdx]}"
		local ruptdCmdFile="${bgBASH_SOURCE[$origIdx]}"
		local ruptdCmdName="${lastCmd%% *}(${signal}...)"
		local ruptdLineNo="${intrLineNo:-$(declare -F $ruptdCaller | awk '{print $2}')}"
		local ruptdCmdLine="${lastCmd}(${signal}...)"

		# insert it at insertIdx
		bgSTK_caller=(   "${bgSTK_caller[@]:0:$insertIdx}"     "$ruptdCaller"        "${bgSTK_caller[@]:$insertIdx}"    )
		bgSTK_cmdName=(  "${bgSTK_cmdName[@]:0:$insertIdx}"    "$ruptdCmdName"       "${bgSTK_cmdName[@]:$insertIdx}"   )
		bgSTK_cmdLineNo=("${bgSTK_cmdLineNo[@]:0:$insertIdx}"  "$ruptdLineNo"        "${bgSTK_cmdLineNo[@]:$insertIdx}" )
		bgSTK_argc=(     "${bgSTK_argc[@]:0:$insertIdx}"       "0"                   "${bgSTK_argc[@]:$insertIdx}"      )
		bgSTK_cmdLine=(  "${bgSTK_cmdLine[@]:0:$insertIdx}"    "$ruptdCmdLine"       "${bgSTK_cmdLine[@]:$insertIdx}"   )
		bgSTK_cmdFile=(  "${bgSTK_cmdFile[@]:0:$insertIdx}"    "$ruptdCmdFile"       "${bgSTK_cmdFile[@]:$insertIdx}"   )
		bgSTK_frmCtx=(   "${bgSTK_frmCtx[@]:0:$insertIdx}"     "lastBefore(${signal}-${trapPID})" "${bgSTK_frmCtx[@]:$insertIdx}"    )
		((stackSize++))
	done


	### add a frame at the bottom for the command interupted by the DEBUG or ERR trap if called for
	# The <interruptedSimpleCmd> and <interuptedLineNo> parameters are passed in only when we are called from the DEBUG trap where
	# those values are known
	if [ "$interruptedSimpleCmd" ]; then
		bgSTK_caller=(     "${bgFUNCNAME[0]}()"           "${bgSTK_caller[@]}"    )
		bgSTK_cmdName=(    "${interruptedSimpleCmd%% *}"  "${bgSTK_cmdName[@]}"   )
		bgSTK_cmdLineNo=(  "$interuptedLineNo"            "${bgSTK_cmdLineNo[@]}" )
		bgSTK_argc=(       "0"                            "${bgSTK_argc[@]}"      )
		bgSTK_cmdLine=(    "$interruptedSimpleCmd"        "${bgSTK_cmdLine[@]}"   )
		bgSTK_cmdFile=(    "${bgBASH_SOURCE[0]}"          "${bgSTK_cmdFile[@]}"   )
		bgSTK_frmCtx=(     "debugNext"                    "${bgSTK_frmCtx[@]}"    )
		((stackSize++))

		# detect cases where the DEBUG trap is interupting the top level lines of an interupt handler (not in a function it calls)
		# in this case, the new frame we just added represents the first frame of a trap non-DEBUG handler that we are stepping through
		# we need to fixup the frame to indicate that the caller is discontinuous from the frame before it.

		# this case is when the interupt handler is running betwen calls to BGTRAPEntry/BGTRAPExit.
		# the bgBASH_trapStkFrm_* mechanism results in the bottom stack frame being the last frame before the interuption so we know
		# the debugger is running the handler string code.
		if [[ "${bgSTK_frmCtx[1]}" =~ ^lastBefore[(]([^-]*)-(.*)[)] ]]; then
			local signal="${BASH_REMATCH[1]}"
			local trapPID="${BASH_REMATCH[2]}"
			bgSTK_caller[0]="${signal}_HANDLER"
			bgSTK_cmdFile[0]="${signal}-${trapPID}<handler>"

		# NOTE: When the debug trap fires before the first line the first line of a trap, BASH_COMMAND is the set for the other trap
		# and not the DEBUG trap.
		# this is the case of the first step into a handler when it is about to call the BGTRAPEntry function. The next step will
		# result in BGTRAPEntry setting the bgBASH_trapStkFrm_* mechanism, but until then, we need to manually detect this case
		elif [[ "$interruptedSimpleCmd" =~ ^BGTRAPEntry  ]]; then
			local signal="${bgSTK_argv[bgSTK_argc[0]-2]}"
			local trapPID="${bgSTK_argv[bgSTK_argc[0]-1]}"
			bgSTK_caller[0]="${signal}_HANDLER"
			bgSTK_cmdFile[0]="${signal}-${trapPID}<handler>"

		# we assume that if lineno is 1, its the start of an interupt handler. Unfortunately, because BASH_COMMAND is not set to the
		# next command in this rare case, we know nothing about the interupt that is starting.
		elif (( interuptedLineNo == 1 )); then
			local signal="<UNK>"
			local trapPID="<UNK>"
			bgSTK_caller[0]="${signal}_HANDLER"
			bgSTK_cmdFile[0]="${signal}-${trapPID}<handler>"
		fi
	fi



	### render the bgSTK_cmdLoc tokens
	declare -ga bgSTK_cmdLoc=()
	local i; for ((i=0; i<${#bgSTK_cmdFile[@]}; i++)); do

		# when our debugger inserts a breakpoint dynamically, BASH sees it as that script replacing the function so the source file
		# bash associates with the function will be the debugger script library instead of the original script that the function
		# came from. This tranaslates the cmdFile and cmdLineNo after the BP back to the originals that refer to the source file.
		declare -gA bgBASH_debugBPInfo
		local bpInfo="${bgBASH_debugBPInfo["${bgSTK_cmdName[i]// /}"]}"
		if [ "$bpInfo" ]; then
			local origLineNo newLineNo origFile; read -r origLineNo newLineNo origFile <<<"$bpInfo"
			bgSTK_cmdFile[i]="$origFile"
			bgSTK_cmdLineNo[i]="$((bgSTK_cmdLineNo[i] - newLineNo + origLineNo))"
		fi

		bgSTK_cmdLoc[i]="${bgSTK_cmdFile[i]##*/}(${bgSTK_cmdLineNo[i]}):"
	done

	# these are optional attributes filled in by other functions
	declare -ga bgSTK_frmSummary=()
	declare -ga bgSTK_cmdSrc=()

	if [ "$allFlag" ]; then
		bgStackFreezeAddSourceCodeLines
		bgStackRenderFormat
	fi
}








# usage: bgStackFreezeDone
# removes the global variables created by the bgStackFreeze function
function bgStackFreezeDone() {
	unset ${!bgSTK_*}
	unset bgFUNCNAME bgBASH_SOURCE bgBASH_LINENO bgBASH_ARGC bgBASH_ARGV
}


# usage: bgStackFreezeAddSourceCodeLines
# this adds the bgSTK_cmdSrc array to the set of stack variables created with bgStackFreeze. It loops over the stack and sets
# each element of the new array to the line of script code from bgSTK_cmdFile at bgSTK_cmdLineNo
function bgStackFreezeAddSourceCodeLines()
{
	local i; for ((i=0; i<${#bgSTK_cmdFile[@]}; i++)); do
		# read the actual source line if called for
		if [ -r "${bgSTK_cmdFile[i]}" ]; then
			bgSTK_cmdSrc[i]="$(sed -n "${bgSTK_cmdLineNo[i]}"'{s/^[[:space:]]*//;p;q}' "${bgSTK_cmdFile[i]}" 2>/dev/null)"
		else
			bgSTK_cmdSrc[i]="(norm) ${bgSTK_cmdLine[i]}"
		fi
	done
}

# usage: bgStackRenderFormat [--callerColumn|--no-callerColumn]
# this adds the bgSTK_frmSummary array to the set of stack variables created with bgStackFreeze. It loops over the stack and sets
# each element of the new array to a formatted line suitable for using in a stack trace
# Options:
#    --no-callerColumn : dont include the 'caller' column in the stack trace. The 'caller' the bash function (or process) that
#           contains the source line that caused the simple command in that stack frame to execute.
#    --callerColumn : (default) include the 'caller' column in the stack trace. The 'caller' the bash function (or process) that
#           contains the source line that caused the simple command in that stack frame to execute.
function bgStackRenderFormat()
{
	local callerColOpt="--callerColumn"
	while [ $# -gt 0 ]; do case $1 in
		--no-callerColumn)     callerColOpt="--no-callerColumn" ;;
		--callerColumn)        callerColOpt="--callerColumn" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local i maxSrcLoc maxFuncname
	for ((i=0; i<${#bgSTK_cmdFile[@]}; i++)); do
		((maxSrcLoc=   (maxSrcLoc>${#bgSTK_cmdLoc[i]}) ? maxSrcLoc   : ${#bgSTK_cmdLoc[i]} ))
		((maxFuncname= (maxFuncname>${#bgSTK_caller[i]})  ? maxFuncname : ${#bgSTK_caller[i]} ))
	done

	local i; for ((i=0; i<${#bgSTK_cmdFile[@]}; i++)); do
		if [ "$callerColOpt" == "--callerColumn" ]; then
			printf -v bgSTK_frmSummary[i] "%-*s : %-*s: %s" \
				"$maxSrcLoc"    "${bgSTK_cmdLoc[i]}" \
				"$((maxFuncname))"  "${bgSTK_caller[i]}" \
				"${bgSTK_cmdLine[i]}"
		else
			printf -v bgSTK_frmSummary[i] "%-*s : %s" \
				"$maxSrcLoc"    "${bgSTK_cmdLoc[i]}" \
				"${bgSTK_cmdLine[i]}"
		fi
	done
}





# usage: bgStackPrint
# Prints the existing frozen stack frames to stdout. If there is no existing frozen stack, it will freeze the stack so that the bottom
# of the stack is the caller to this function and unfreeze the stack before returning.
#
# This is used by assertError to print the stack trace to bgtrace destination. Script authors can also use it to print the current
# stack which is typically only done in development.
#
# bgtraceStack wraps this function and redirects its output to the bgtrace destination and suppresses its call if bgtrace is not
# active.
#
# Options:
#    --ignoreFramesCount=<n> : suppress printing the bottom <n> frames. If there is an existing frozen stack then its relative to
#           that, but if this function freezes the stack, the bottom of the stack will be the caller of this function so that
#           this function (bgStackPrint) will not be included in the stack print. 0 is the default. 1 would suppress the direct
#           caller of this function, and so on.
#           NOTE: that this option was more important with the older stack mechanism that did not freeze the stack. Now, typically
#                 the thing that calls bgStackFreeze will tell it where to make the bottom of the stack so that now we typically
#                 would always print the entire frozen stack.
#                 assertError uses this option to igore all but the first assert* function
#    --oneline : make the stack trace shorter by suprssesing all but the first line of the simple cmd shown in the frame.
#           A simple command could have multiple lines because the arguments contain line feeds. The simple cmd is normallize and
#           will show as one line even if the source code breaks it over multiple lines wiht the '\' line continuation character.
#    --source : for each frame show a second line below the summary line that contains the actual source code that produced the
#           simple command. The source line may include parts of other simple cmds.
#    --stackDebug : in addition to printing the stack, print the raw frozen stack vars too. This is used for troubleshooting the
#           stack library. Since this library provides a higher level meaning to the stack than BASH intended, there may be edge
#           cases popping up now and then that need trouble shooting. The 'bg-debugCntr errorStack debugStack/no-debugStack' command
#           allows turning this flag on and off easily.
#    --no-callerColumn : dont include the 'caller' column in the stack trace. The 'caller' the bash function (or process) that
#           contains the source line that caused the simple command in that stack frame to execute.
#    --callerColumn : (default) include the 'caller' column in the stack trace. The 'caller' the bash function (or process) that
#           contains the source line that caused the simple command in that stack frame to execute.
#
# see Also:
#    man(1) 'bg-debugCntr trace errorStack ...' to set options for stack traces produced by assertError
#    man(3) bgtraceStack : wrapper that redirects the function's output to bgtrace and supresses the call if bgtrace is not active.
function bgStackPrint()
{
	local noSrcLookupFlag onelineFlag stackDebugFlag useVarsFlag doUnFreezeFlag ignoreFramesCount showSourceFlag
	local callerColOpt="--callerColumn"
	while [ $# -gt 0 ]; do case $1 in
		--ignoreFramesCount*)  bgOptionGetOpt val: ignoreFramesCount "$@" && shift ;;
		--oneline)             onelineFlag="oneline" ;;
		--no-callerColumn)     callerColOpt="--no-callerColumn" ;;
		--callerColumn)        callerColOpt="--callerColumn" ;;
		--source)              showSourceFlag="--source" ;;
		--stackDebug)          stackDebugFlag="--stackDebug" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	if ! varExists bgSTK_cmdName; then
		bgStackFreeze 2
		doUnFreezeFlag=1
	fi

	[ "$showSourceFlag" ] && bgStackFreezeAddSourceCodeLines
	bgStackRenderFormat $callerColOpt

	[ "$stackDebugFlag" ] && bgStackDump

	echo "===============  BASH call stack trace P:$$/$BASHPID TTY:$(tty 2>/dev/null) ====================="
	local i
	for ((i=${#bgSTK_cmdFile[@]}-1; i>=${ignoreFramesCount:-0}; i--)); do
		if [[ "${bgSTK_cmdFile[i]}" =~ \<handler\>$ ]]; then
			echo "----- ${bgSTK_cmdFile[i]%<handler>} INTERUPT RECEIVED -------------------"
		fi
		if [ "$onelineFlag" ]; then
			echo "${bgSTK_frmSummary[i]/$'\n'*/ ...}"
		else
			echo "${bgSTK_frmSummary[i]}"
		fi
		[ "$showSourceFlag" ] && echo "${bgSTK_cmdSrc[i]}" | gawk -v onelineFlag="$onelineFlag" '
			onelineFlag && NR > 1 {exit(0)}
			NR==1 { printf("      %s\n", $0) }
			NR>1  { printf("    | %s\n", $0) }
		'
	done
	echo "=================  bottom of stack invoked the stack trace  =========================="
	bgGetPSTree

	[ "$doUnFreezeFlag" ] && bgStackFreezeDone
}




# usage: bgStackDump
# This prints all the frozen stack vars to stdout for troubleshooting the bgStackFreeze function.
# It can be called directly, but typically you turn it on for assertError stack traces written to the bgtrace destination with the
# 'bg-debugCntr trace errStack [debugStack|no-debugStack]' commands for a terminal session.
function bgStackDump()
{
	### first dump a table of the copied original vars.
	echo "BASH STACK:"
	printf "%4s %-25s %14s %-25s %s %s\n" "frm#" "bgFUNCNAME#=${#bgFUNCNAME[@]}"  "bgBASH_LINENO#=${#bgBASH_LINENO[@]}"  "bgBASH_SOURCE#=${#bgBASH_SOURCE[@]}"   "bgBASH_ARGC#=${#bgBASH_ARGC[@]}" "bgBASH_ARGV#=${#bgBASH_ARGV[@]}"
	#local frameNo; for frameNo in "${!bgFUNCNAME[@]}"; do
	local frameNo; for ((frameNo=${#bgFUNCNAME[@]}-1; frameNo>=0; frameNo--)); do
		local n argcOffset=0; for ((n=0; n<frameNo; n++)); do ((argcOffset+=${bgBASH_ARGC[$n]:-0})); done
		local argList="" j; for ((j=0; j<${bgBASH_ARGC[$frameNo]:-0}; j++)); do  argList+=" '[$argcOffset]=${bgBASH_ARGV[$argcOffset]}'"; ((argcOffset++)); done
		printf "%4s %-25s %14s %-25s %2s %s\n" "[$((frameNo))]" "${bgFUNCNAME[$frameNo]}" "${bgBASH_LINENO[$frameNo]}" "${bgBASH_SOURCE[$frameNo]##*/}" "${bgBASH_ARGC[$frameNo]}" "$argList"
	done


	### make a set that includes the stack variables
	local -A bgStackVarNames=()
	setAdd bgStackVarNames ${!bgSTK_*}


	### report if the sizes of the bgSTK_* arrays are all not the same size
	local sizes=()
	local varname; for varname in "${!bgStackVarNames[@]}"; do
		[ "$varname" == "bgSTK_argv" ] && continue # argv is expected to be different so ignore it.
		local size; arraySize "$varname" size
		sizes[$size]+="$varname "
	done
	[ ${#sizes[@]} -gt 1 ] && printfVars "-lSTACK VAR SIZES (not all the same):" sizes


	### now dump a table of the new vars
	setDelete bgStackVarNames bgSTK_frmSummary # dont display the summary in the table b/c its too long
	echo "SYNTH STACK:"
	local stackSize="${#bgSTK_cmdName[@]}"
	{
		local colList="bgSTK_frmCtx bgSTK_caller bgSTK_cmdName bgSTK_cmdLineNo bgSTK_cmdFile bgSTK_argc bgSTK_cmdLine bgSTK_cmdLoc"
		echo "frm#" "${colList}"
		#echo
		local i; for ((i=$stackSize-1; i>=0; i--)); do
			echo -n " [$i] "
			local varname; for varname in ${colList}; do
				local value; arrayGet "$varname" "$i" value
				varEscapeContents value
				[[ "$varname" =~ ^(bgBASH_SOURCE|bgSTK_cmdFile)$ ]] && value="${value##*/}"
				echo -n "$value "
			done
			echo
		done
	} | column -t -e


	### now dump the bgBASH_trapStkFrm_* stack
	echo "TRAP STACK:"
	printfVars --table="${!bgBASH_trapStkFrm_*}"
}



# usage: bgStackFrameFind <funcSpec>:[<offset>] <retVar>
#        bgStackFrameFind <targetFrameIndex> <retVar>
# return the index in the frozen stack that is identified by <funcSpec>:[<offset>] or <targetFrameIndex>.
# It is an error to call this when there is no frozen stack.
# Params:
#    <funcSpec>  : either an exact function name on the stack to use as the reference frame or a regex that matches.
#                  the top matching function of the lowest matching sequence becomes the reference frame. For example, if there
#                  are three recursive function calls of <funcSpec> in a row, the first one (highest) called will become the
#                  reference frame.
#                  For 'assert.*' called from the assertError function, the reference frame will be the first assert* function that
#                  lead to assertError being called.
#    <offset>    : an offest added to the reference frame to get the targetFrame. +1 will be the function that calls the function
#                  in the reference frame. -1 will be the function that the function in the reference frame calls.
#    <targetFrameIndex> : the exact index into the frozen stack arrays to use as the target frame. 0 is the bottom of the stack
#                  The top of the stack (stackSize-1) represnts how the script was exectued.
#    <retVar>    : the variable name to receive the index number of the targetFrame in the frozen stack identified by the paramters.
#                  If <targetFrameIndex> is passed in, it is clipped to the range [0,stackSize] and returned. If its clipped to
#                  stackSize, -1 is returned.
# See Also:
#    man(3) bgStackFrameGet
function bgStackFrameFind() {
	local targetFrameTerm="$1"
	local retVar="$2"

	# not using assertError because this is used by assertError (assertError will typically handle recursive calls but when
	# something goes wrong, this is less taxing and leads to better reporting.)
	if ! varExists bgSTK_cmdName; then
		bgExit --complete --msg="bgStackFrameFind: this function operates on the froozen stack but is being called when it does not exist. See bgStackFreeze"
	fi
	if [[ ! "$targetFrameTerm" =~ ^([^0-9+-][^:+-]*)?:?([-+]?[0-9]*)$ ]]; then
		bgExit --complete --msg="bgStackFrameFind: '$targetFrameTerm' is a bad value for [<funcSpec>][:][<offset>]"
	fi
	local referenceFuncSpec="${BASH_REMATCH[1]}"
	local referenceFuncOffset="${BASH_REMATCH[2]:-0}"

	# The refFrame is the function that called us, or the one that matches _functName
	local refFrame
	if [ "$referenceFuncSpec" ]; then
		# first try it using exact comparison
		local i; for ((i=0; i<${#bgSTK_cmdName[@]}; i++)); do
			[ "${bgSTK_cmdName[$i]}" == "$referenceFuncSpec" ] && { refFrame=$i; break; }
		done
		[ "$refFrame" ] && while ((refFrame+1<${#bgSTK_cmdName[@]})) && [ "${bgSTK_cmdName[$refFrame+1]}" == "$referenceFuncSpec" ]; do ((refFrame++)); done

		# if this function is recursive, go up to the first consequetive call of this function as the relative stack location
		while ((refFrame+1<${#bgSTK_cmdName[@]})) && [ "${bgSTK_cmdName[$refFrame+1]}" == "$referenceFuncSpec" ]; do ((refFrame++)); done

		# if not found, try it again using regex comparison
		if [ ! "$refFrame" ]; then
			for ((i=0; i<${#bgSTK_cmdName[@]}; i++)); do
				[[ "${bgSTK_cmdName[$i]}" =~ $referenceFuncSpec ]] && { refFrame=$i; break; }
			done
			# if more than one consequetive function matches the expression, go up to the first call as the relative stack location
			[ "$refFrame" ] && while ((refFrame+1<${#bgSTK_cmdName[@]})) && [[ "${bgSTK_cmdName[$refFrame+1]}" =~ $referenceFuncSpec ]]; do ((refFrame++)); done
		fi
		# if we did not find referenceFuncSpec on the stack, return 2
		if [ ! "$refFrame" ]; then
			bgStackDump >>$_bgtraceFile
			bgtrace "non exception error: bgStackFrameFind: '$functName' did not match any function on the stack"
			return -1
		fi
	else
		refFrame=0
	fi

	returnValue $((
		((refFrame+referenceFuncOffset < ${#bgSTK_cmdName[@]} ) ?
			((refFrame+referenceFuncOffset >= 0 ) ?
				refFrame+referenceFuncOffset
				: 0)
			: -1)
	)) "$retVar"
}


# usage: bgStackFrameGet <funcSpec>:[<offset>] <retArray>
#        bgStackFrameGet <targetFrameIndex> <retArray>
# Returns information about the stack frame identified by the parameters.
# This function operates on the froozen stack (see man(#) bgStackFreeze) if it exists.
# Initially, if there is no frozen stack, this function calls bgStackFreeze but it is anticipated that this function will eventually
# calculate the frames inforamtion independent from bgStackFreeze. The information returned should be the same in either case but
# this function is used by things like fsMakeTemp, Try:, and bgsudo in their non-error paths. Those things just need to get the
# one stack frame description and move on without using the rest of the stack. It is thought that we can make this more efficient
# and reserve the heavier bgStackFreeze for error paths (assertError) an in the debugger. Those things are not as sensitive to the
# performance of freezing the stack and actually use the whole stack.
#
# Return Values:
# See man(3) bgStackFreeze for more details on the attributes returned.
#    <retArray>[cmdName]    : name of simple command being executed without its arguments.
#    <retArray>[cmdLine]    : the whole simple command being executed. (with arguments)
#    <retArray>[cmdLoc]     : one token description of the file and lineno where the simple command invocation can be found.
#    <retArray>[cmdFile]    : the file where the simple command invocation can be found
#    <retArray>[cmdLineNo]  : the lineno where the simple command invocation can be found
#    <retArray>[cmdSrc]     : the text of the script read from <cmdLoc>
#    <retArray>[frmSummary] : a formatted one line representation of the stack frame. This is what appears in a stack trace.
#    <retArray>[arg<n>]     : the arguments to the simple command. <n> is in the range 1 to <cmdArgc> inclusive.
#
# Params:
#    <funcSpec>  : either an exact function name on the stack to use as the reference frame or a regex that matches.
#                  the top matching function of the lowest matching sequence becomes the reference frame. For example, if there
#                  are three recursive function calls of <funcSpec> in a row, the first one (highest) called will become the
#                  reference frame.
#                  For 'assert.*' called from the assertError function, the reference frame will be the first assert* function that
#                  lead to assertError being called.
#    <offset>    : an offest added to the reference frame to get the targetFrame. +1 will be the function that calls the function
#                  in the reference frame. -1 will be the function that the function in the reference frame calls.
#    <targetFrameIndex> : the exact index into the frozen stack arrays to use as the target frame. 0 is the bottom of the stack
#                  The top of the stack (stackSize-1) represnts how the script was exectued.
#    <retArray>  : the name of an associative array that will be filled in with the information on the targetFrame.
#
# See Also:
#    man(3) bgStackFreeze
#    man(3) bgStackFrameFind
function bgStackFrameGet() {
	local readCodeFlag=1
	local targetFrameTerm="$1"
	local retArray="$2"
	local -n frameData="$retArray"

	# TODO: rewrite this function to not use bgStackFreeze nor bgStackFrameFind.
	#       * identify the first trap boundary from the bottom if one exists. no need to fix up anything -- just identify where it starts
	#       * do the frame find algorithm (copied from bgStackFrameFind) but limit it not to go past the trap boundary
	#       * fill in the variables, only doing the trap boundary fixup if the identified frame it the top or second to top frame
	#       * if a trap was detected, decorate the frmSummary with that information so that its clear the execution is inside a trap

	# initially, this function uses freeze, but eventually, it will be re-written to get just one frame data quicker than freeze
	if ! varExists bgSTK_cmdName; then
		bgStackFreeze 2
		doUnFreezeFlag=1
	fi

	[ "${#bgSTK_cmdSrc[@]}" -eq "${#bgSTK_cmdName[@]}" ] || [ "$readCodeFlag" ] && bgStackFreezeAddSourceCodeLines
	[ "${#bgSTK_frmSummary[@]}" -eq "${#bgSTK_cmdName[@]}" ] || bgStackRenderFormat

	local targetFrame; bgStackFrameFind "$targetFrameTerm" targetFrame

	# clear the return array
	frameData=()

	frameData[caller]="${bgSTK_caller[$targetFrame]}"
	frameData[cmdName]="${bgSTK_cmdName[$targetFrame]}"
	frameData[cmdLine]="${bgSTK_cmdLine[$targetFrame]}"
	frameData[cmdFile]="${bgSTK_cmdFile[$targetFrame]}"
	frameData[cmdLineNo]="${bgSTK_cmdLineNo[$targetFrame]}"
	frameData[cmdArgc]="${bgSTK_argc[$targetFrame]}"
	frameData[cmdLoc]="${bgSTK_cmdLoc[$targetFrame]}"
	frameData[cmdSrc]="${bgSTK_cmdSrc[$targetFrame]}"
	frameData[frmSummary]="${bgSTK_frmSummary[$targetFrame]}"

	local i; for ((i=1; i<=${bgSTK_argc[$targetFrame]:-0}; i++)); do
		frameData["arg$i"]="${bgSTK_argv[bgSTK_argOff[$targetFrame] + bgSTK_argc[$targetFrame] - $i]}"
	done

	[ "$doUnFreezeFlag" ] && bgStackFreezeDone
	return 0
}




# usage: bgStackMarshal <mFile>
# save the bgStack variables (created by bgStackFreeze) into <mFile>. This and bgStackUnMarshal are used by Try/Catch when
# an exception is throw and caught in different sub shells.
# Each line is the ordered list of values of one array variable. Each value is escaped so that each will be one space separated token.
# This function and its companion bgStackUnMarshal each contain a list of variable names which needs to be kept in sync because the
# file does not identify which variable each line is the value for so it relies on each iterating the same list of var names.
# Params:
#    <mFile>  : a filename that will be filled in with the results.
# See Also:
#    man(3) bgStackUnMarshal
function bgStackMarshal()
{
	local mFile="$1"

	local varList="bgFUNCNAME bgBASH_SOURCE bgBASH_LINENO bgBASH_ARGC bgBASH_ARGV bgSTK_cmdName bgSTK_cmdLineNo bgSTK_argc bgSTK_argv bgSTK_caller bgSTK_cmdFile bgSTK_cmdLine bgSTK_frmSummary bgSTK_cmdSrc"

	echo -n  > "$mFile"
	local -n varname; for varname in $varList; do
		echo "$(cmdline "${varname[@]}" )" >> "$mFile"
	done
}

# usage: bgStackUnMarshal <mFile>
# restore the bgStack variables (previously saved by bgStackMarshal).
# Params:
#    <mFile>  : the filename that was previously filled in by bgStackMarshal
# See Also:
#    man(3) bgStackMarshal
function bgStackUnMarshal()
{
	local mFile="$1"

	local varList="bgFUNCNAME bgBASH_SOURCE bgBASH_LINENO bgBASH_ARGC bgBASH_ARGV bgSTK_cmdName bgSTK_cmdLineNo bgSTK_argc bgSTK_argv bgSTK_caller bgSTK_cmdFile bgSTK_cmdLine bgSTK_frmSummary bgSTK_cmdSrc"

	local varname; for varname in $varList; do
		local line; read -r line
		read -r -a "$varname" <<<"$line"
		arrayUnEscapeValues "$varname"
	done <"$mFile"
}



# usage: bgGetPSTree [<retVar>]
# This does not operate on the frozen stack vars but is related to the stack because it is interesting to know what subshells exist
# when the frame is created. A each subshell has its own stack that can diverge from its parent.
# Params:
#    <retVar> : name of variable to fill with the results. default writes to stdout
# See Also:
#    man(3) bgtracePSTree  : wrapper that redirects this function's output to bgtrace and suppresses the call if bgtrace is not active.
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
		local pstout=$(pstree -pl "${passThruOpts[@]}" "$thePID")
		if [[ "$pstout" =~ (-*pstree[(][0-9]*[)])$ ]]; then
			pstout="${pstout/%${BASH_REMATCH[1]}/*}"
		fi
		while [[ "$pstout" =~ -$ ]]; do pstout="${pstout%-}"; done
		returnValue "${pstout%}" $retVar
	else
		returnValue "bgtracePSTree: error: pstree not installed. install it to get process tree information" $retVar
	fi
}


# usage: bgStackGetFunctionLocation <functionName> <srcFileVar> <srcLineVar>
# this is a helper function to use the bash extdebug feature that declare -F provides the file and lineno where the function was
# sourced from.
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

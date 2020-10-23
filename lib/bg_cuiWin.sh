#!/bin/bash

#import bg_????.sh ;$L1;$L2

declare -g cuiWinCntrFilePrefix="/tmp/bgtrace."

# Library bg_cuiWin.sh
#######################################################################################################################################
### cuiWin is a library that implements the ability for a shell script to open additional terminal
# emulator windows to interact with the operator. This was created with the thought that its not for
# main stream scripts but rather unusual situations so caution should be used in popping up addition
# terminal windows when the user may not want that.
# The usecase that it was developed for is for the bg-debug.sh debugger functionality.


# usage: cuiWinCntr [--class <cuiWinClass>] [-R <retVar>] <cuiWinID> <cmd> [.. <args>]
# This is the main entry point and the only function most clients will call directly.
# This command implements an additional TTY window that scripts can use to interact with the operator.
# The open and gettty commands can be used to get the tty device that can be written to and read from
# by the script to interact with the user. The difference is that open will create or recreate the
# terminal emulator window if it does not already exist and gettty will return /dev/null as the tty
# and a non-zero exit code if it does not already exist.
# The tty can go away at any time if the operator closes the window so the script should call open or
# gettty often instead of caching tty or implement a thread that blocks on reading the tty and terminates
# automatically when that read fails, indicating that the user has closed the window.
# Commands:
#     open : Returns <tty> : creates the term emulator win and cntr pipe only if they do not yet exist
#        and return the <tty> device that the caller can use to write information and read input
#        entered by the operator. If it fails it assertError
#        --class=<cuiWinClass> : determines which cuiWinClass will be called in the new terminal process to run the window.
#        Exit codes:
#           0(true) : open (now). the window was already openned or was created and is good to go
#           assertError: the window was not open and could not be created so something is wrong.
#     gettty : Returns <tty> : same as open but in the case of the tty/window not existing, it returns
#        /dev/null as the tty and the exit code is non-zero instead of creating a new window.
#        Exit codes:
#           0(true) : open. the window is open and good to go.<retVar> contains the tty device
#           1(false): closed. the window does not exist. This is the typical/normal non-zero case.
#           assertError: the handler did not respond properly so something is wrong.
#     close : no return (asynchronous) : tell the window to terminate and delete the control pipe.
#        this can also be initiated by the operator at any time by closing the window.
#     ping : Returns pingTime(ms) : checks to see if the window is open. Returning 0(open) 1(closed)
#        are the typical, normal cases that the called should handle but 2(handler crashed) and
#        3(handler invalid) should not happen and represent a failure in the system.
#        Exit codes:
#           0(true) : open. the window is open and good to go.
#           1(false): closed. the window does not exist. This is the typical/normal non-zero case.
#           2(false): crashed. the cntr pipe exists but the handler is not responding so its crashed.
#           3(false): invaid. the handler did not respond properly so something is wrong.
#     <cmd> <args>... : the window class can implement other commands specific to it. If the <cmd> is synchornous, you must specify
#           the -R <retVar> options and if the <cmd> is async you must not. The -R options is how it knows  whether to wait for a reply
# Params:
#   <cuiWinID> : the ID of the window being operated on. Can be any string. Calls with the same string
#           operate on the same window. The logical namespace of these names are the control pipes
#           stored at ${cuiWinCntrFilePrefix}<cuiWinID>.cntr. Calling <cmd>='open' will make sure that the
#           corresponding cntr pipe and term emulator window exists and closing the window in any way
#           will result in the cntr pipe being removed (or else its an error condition for the either
#           to exist without the other)
#   <cmd> [.. <args>] : the command to send to the window. In general, new cmds must be supportted by
#           the window handler running in the window's proc. This command will know about some <cmds>
#           but does not need to know about new commands introduced by new window handlers because it
#           passes through any unknown commands.
#           if the <retVar> options was specified, it will invoke the synchronous <cmd> protocol to wait for a reply from the win.
# Options:
#     -R <retVal> : name of a variable to return the reply in. Note that the typical pattern for return
#           variables like this is that if they are empty or not specified the returned value is written
#           to stdout instead of set into the var name. That still applies to commands known to this
#           function. But if the <cmd> is not known to this function, whether or not the caller passed
#           in a non-empty <retVar> determines if the synchronous or asynchronous cmd protocol is used.
# See Also:
#    cuiWinCntr : normal entry point to all client level functions
#    cuiWinExec : implements the low level sync and async <cmd> protocol to the window handler
#    cuiWinOpen : helper function to cuiWinCntr that handles the open <cmd>
#    cuiWinProtocol: man(5) page to document the protocol
function cuiWinCntr()
{
	local retVar _cw_retValue cuiWinClass result=0 returnChannelFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R*) [ ${#1} -eq 2 ] && shift; retVar=${1#-R} ;;
		--class*) [ "$1" == "--class" ] && shift; cuiWinClass=${1#--class} ;;
		--returnChannel) returnChannelFlag="--returnChannel" ;;
	esac; shift; done

	# detect static commands vs commands that operate on a cuiWinID
	if strSetHas "list" "$1"; then
		local cuiWinID=""
		local cmd="$1"; shift
	else
		local cuiWinID="$1"; shift
		local cmd="$1"; shift
	fi

	# normalize cuiWinID which could be the whole control pipe, the associated bgtraceFile or just the simple name
	[[ "$cuiWinID" =~ ^${cuiWinCntrFilePrefix}(.*)([.]cntr)?$ ]] && cuiWinID="${BASH_REMATCH[1]}"

	case $cmd in
		list)
			bgfind -B ${cuiWinCntrFilePrefix} ${cuiWinCntrFilePrefix}* -type p | sed 's/[.]cntr\b//'
			;;
		isOpen)
			[ -e "${cuiWinCntrFilePrefix}$cuiWinID.cntr" ]; return
			;;
		open)
			cuiWinOpen $returnChannelFlag --class "${cuiWinClass:-Base}" -R _cw_retValue "$cuiWinID" "$@"; result=$?
			[ ${result:-0} -ge 2 ] && assertError -e "$result" -v _cw_retValue -v cuiWinID -v result "could not create the terminal emulator window"
			returnValue "$_cw_retValue" "$retVar"
			return $result
			;;
		gettty)
			cuiWinExec -R _cw_retValue "$cuiWinID" gettty; result=$?
			[ ${result:-0} -ge 2 ] && assertError -e "$result" -v _cw_retValue -v cuiWinID -v result "error in cummunicating with the window handler"
			[ ${result:-0} -ne 0 ] && _cw_retValue="/dev/null"
			returnValue "$_cw_retValue" "$retVar"
			return $result
			;;

		getCntrFile)
			returnValue "${cuiWinCntrFilePrefix}$cuiWinID.cntr" "$retVar"
			return $result
			;;
		ping)
			local pingTimer pingReply; bgtimerStart -T pingTimer
			cuiWinExec -R pingReply "$cuiWinID" youUp; result=$?
			bgtimerGet -R _cw_retValue -T pingTimer
			[ ${result:-0} -eq 0 ] && [ "$pingReply" != "youBet" ] && result=3
			[ ${result:-0} -ne 0 ] && _cw_retValue="unreachable"
			returnValue "$_cw_retValue" "$retVar"
			return $result
			;;
		close)    cuiWinExec "$cuiWinID" close ;;
		getClass) cuiWinExec -R _cw_retValue "$cuiWinID" getClass ;;

		# note that when we recognize the cmd in a case above, we specifically include or dont include
		# the -R <ret> to indicated to cuiWinExec our knowldge of whether the command is sync or
		# async. But for unknown commands we pass <retVar> through even though it
		# might be empty and cuiWinExec handles it as sync or async depending on if <retVar> is
		# empty. In that case the caller is implicitly declaring whether the cmd is sync or sync based
		# on whther they pass in a <retVar> to this function.
		*)        cuiWinExec -R "$retVar" "$cuiWinID" "$cmd" "$@" ;;
	esac
}


# usage: cuiWinExec [-R <retVar>] <cuiWinID> <cmd> [.. <args>]
# This is a lower lever function that implements the RPC synchronous and asynchronous <cmd> protocol
# between the script client and the window handler running in the terminalemulator's proc.
# This command sends an RPC command msg to the window identified by <cuiWinID> proc and optionally reads
# a reply returned in <retVal>. The window handler running in the window's process defines the set of
# valid <cmd> and determines whether each command is synchronous (aka sends a reply) or asynchronous
# (aka does not send a reply).
#
# The handler and the caller should agree whether cmds are sync or async but the protocol is tolerant
# to mistakes. Disagreements about the sync/async type of the command results in a small delay added
# to the commands. Typically commands process in a 5-10 milliseconds but disagrements result in <cmds>
# taking about 30 milliseconds longer.
#
# Protocol:
# See man(5) cuiWinProtocol
#
# Params:
#   <cuiWinID> : the ID of the window being operated on. Can be any string. Calls with the same string
#           operate on the same window. The logical namespace of these names are the control pipes
#           stored at ${cuiWinCntrFilePrefix}<cuiWinID>.cntr. Calling <cmd>='open' will make sure that the
#           corresponding cntr pipe and term emulator window exists and closing the window in any way
#           will result in the cntr pipe being removed (or else its an error condition for the either
#           to exist without the other)
#   <cmd> [.. <args>] : the command to send to the window. In general, new cmds must be supportted by
#           the window handler running in the window's proc. This command will know about some <cmds>
#           but does not need to know about new commands introduced by new window handlers because it
#           passes through any unknown commands and it the caller provides a <retVar>, it will invoke
#           the synchronous <cmd> protocol and return the reply to the caller.
# Options:
#     -R <retVal> : name of a variable to return the reply in. If retVal is empty or -R is not specified,
#           this function will send the <cmd> and return without trying to read a command. This is called
#           an asynchronous or one-way RPC message call
# See Also:
#    cuiWinCntr : normal entry point to all client level functions
#    cuiWinExec : implements the low level sync and async <cmd> protocol to the window handler
#    cuiWinOpen : helper function to cuiWinCntr that handles the open <cmd>
#    cuiWinProtocol: man(5) page to document the protocol
function cuiWinExec()
{
	local retVar msgType="async" result=0 cntrPipe
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R*) [ ${#1} -eq 2 ] && shift; retVar=${1#-R}; [ "$retVar" ] && msgType="sync" ;;
		--cntrPipe*) bgOptionGetOpt val: cntrPipe "$@" && shift ;;
	esac; shift; done
	if [ ! "$cntrPipe" ]; then
		cntrPipe=${cntrPipe:-"${cuiWinCntrFilePrefix}$1.cntr"}
		shift
	fi
	[ -e "$cntrPipe" ]   || return 1

	# if the create file exists but noone has it open, it must be left over from a crash
	if [ -e "$cntrPipe.createLock" ] && ! lsof -f -- "$cntrPipe.createLock" 2>/dev/null; then
		rm "$cntrPipe.createLock"
	fi

	# if the window does not exist. This low level function can not create the window so its an error
	# to get here. Note that the .createLock file indicates that its being created but its still not
	# ready for operation (only the creating proc should lock the pipe so we should not try)
	if [ ! -e "$cntrPipe" ] || [ -e "$cntrPipe.createLock" ]; then
		return 5
	fi

	local cuiWinExecLock; startLock -u cuiWinExecLock  -w 1 -q "$cntrPipe.lock"    || return 4
	echo "$*" | timeout 1 tee "$cntrPipe" >/dev/null || result=2
	if [ ${result:-0} -eq 0 ] && [ "$retVar" ]; then
		local _dwe_reply; read -r -t 500 _dwe_reply <"$cntrPipe" || result=3
		returnValue "$_dwe_reply" "$retVar"
	fi
	endLock -u cuiWinExecLock
	return $result
}

# usage: cuiWinOpen [--class <cuiWinClass>] [-R <retVar>] <cuiWinID>
# <cuiWinID> identifies the control pipe. The cntr pipe should be deleted by the window handler when
# the window closes.
# A main feature of this function is the synchronization that allows multiple procs to use a well known
# window name which will reliably get constructed on demand. If two procs need to create the win at the
# same time, one will create it and the other will block until its done. This blocking is outside the
# scope of the cuiWinProtocol which defines timouts that are too short to allow a GUI win to be created.
#
# This function is synchronous meaning that when this function returns succesfully, the caller knows that
# the window is open and ready to use. If the window fails the start this funtion asserts an error.
# See Also:
#    cuiWinCntr : normal entry point to all client level functions
#    cuiWinExec : implements the low level sync and async <cmd> protocol to the window handler
#    cuiWinOpen : helper function to cuiWinCntr that handles the open <cmd>
#    cuiWinProtocol: man(5) page to document the protocol
function cuiWinOpen()
{
	local retVar cuiWinClass="Base" returnChannelFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R*) [ ${#1} -eq 2 ] && shift; retVar=${1#-R} ;;
		--class*) [ "$1" == "--class" ] && shift; cuiWinClass=${1#--class} ;;
		--returnChannel) returnChannelFlag="--returnChannel" ;;
	esac; shift; done
	local cuiWinID="$1"; shift
	if [ ! "$cuiWinID" ]; then
		local genericBaseName="debugger.$$"
		local i; for ((i=0; i<10; i++)); do
			[ ! -e "${cuiWinCntrFilePrefix}$genericBaseName$i.cntr" ] && { cuiWinID="$genericBaseName$i"; break; }
		done
		[ ! "$cuiWinID" ] && assertError "no available generic debugger window communication pipes were found. looking for one of these that do not yet exist -- '${cuiWinCntrFilePrefix}$genericBaseName{0..9}.cntr'"
	fi

	local bgdCntrFile="${cuiWinCntrFilePrefix}$cuiWinID.cntr"

	# normally the flock pattern does not care if the proc that creates the file is the first one to
	# obtain the lock but we do because we use the existence of the lock to determine who should create
	# the window. We also want to create the file is a particulare way -- with mkfifo

	# 1) the first condition directs procs into the creation block not only if the pipe does not exist
	#    but also if the createLock file does exist. This gives lets us avoid the creator from having to
	#    race to lock the pipe after its created because the alternate branch goes directly into locking
	#    the pipe to send a gettty cmd.
	# 2) in the creation block, procs race to get the library lock and there is only one winner.
	# 3) winner creates the .createLock file thus ensuring that any new procs will go down the creation
	#    block path even after it creates the pipe
	# 4) it can now leisurely create the pipe and lock it without fear of another proc getting the pipe lock before it
	# 5) when the loosers blocking on the library lock get their turns, they see that the pipe exists
	#    and skip creation.
	# 6) after the winner deletes the .createLock file, any new procs take the optimum path, skipping
	#    the library lock
	if [ ! -e "$bgdCntrFile" ] || [ -e "$bgdCntrFile.createLock" ]; then
		# get the larger library lock for pipe + window creation as an atomic action.
		local libraryLock; startLock -u libraryLock -w 1 -q "$BASH_SOURCE"    || return 4

		# there will be only one winner of the above library lock that sees this condition as true.
		if [ ! -e "$bgdCntrFile" ]; then
			# at this point no procs are trying to wait on the pipe lock b/c it does not exist. They
			# either end up at the libary lock above or in the Exec function they fail because no window
			# exists. Here we turn on the other reason that prevents them from going after the pipe lock.
			local createLockFD; exec {createLockFD}<>"$bgdCntrFile.createLock"


			# now create the pipe and lock it even after the pipe exists, the things know not to use it
			# if the .createLock file exists, so we are not racing anyone to get the lock after pipe creation.
			mkfifo "$bgdCntrFile" || assertError "failed to mkfifo $bgdCntrFile"
			local cuiWinExecLock; startLock -u cuiWinExecLock -w 1 -q "$bgdCntrFile.lock"    || return 4
			[ "$returnChannelFlag" ] && mkfifo "$bgdCntrFile.ret"

			# create the environment for the new term win proc and launch the terminal emulator app
			(
				export winTitle="BGDebugger Viewer ${cuiWinID}"
				export PS1="\e]0;$winTitle\a [$winTitle]$ "
				export bgdCntrFile
				local decoratedWinClass="cuiWin${cuiWinClass}ClassHandler"
				if (! type -t ${cuiWinClass} && ! type -t $decoratedWinClass) >/dev/null; then
					assertError -v cuiWinID -v cuiWinClass "unknown cuiWin Class. Checked for function '${cuiWinClass}' or '$decoratedWinClass' but neither exists"
				fi
				type -t ${cuiWinClass} >/dev/null || cuiWinClass="$decoratedWinClass"
				export -f "${cuiWinClass}"
				gnome-terminal --geometry=100x24+0+0 --zoom=1.0   -- bash -c "$cuiWinClass" 2>$assertOut || assertError
			)

			# block waiting for the handler to signal that its started by sending its tty on the pipe.
			local _ttyVal="$(timeout 10 head -n1	 $bgdCntrFile)"
			[ -e "$_ttyVal" ] || assertError -v cuiWinID -v bgdCntrFile -v tty:_ttyVal "the new window did not return a valid tty"
			setReturnValue "$retVar" "$_ttyVal"

			# record some info on it
			declare -gA _debugWins
			local winObj="${_debugWins[$cuiWinID]}"
			if [ ! "$winObj" ]; then
				genRandomIDRef winObj
				declare -Ag $winObj='()'
				_debugWins[$cuiWinID]="$winObj"
				setRef $winObj[_OID] "$winObj"
			fi
			setRef $winObj[tty] "$_ttyVal"
			setRef $winObj[cuiWinID] "$cuiWinID"


			# deleting this file signifies that its ok to use the pipe as long as it exists.
			rm "$bgdCntrFile.createLock"
			exec {createLockFD}>&-
			endLock -u cuiWinExecLock
		fi
		endLock -u libraryLock
	fi

	# there are several paths for procs to get here when they did not create the window but either
	# saw that the window already existed, or was in progress of creating or did not exist but another
	# proc beat it to the lock. In any case, at this point it should exist so get the tty
	local __ttyValue; cuiWinCntr -R "__ttyValue" "$cuiWinID" gettty
	setReturnValue "$retVar" "$__ttyValue"
}


# usage: cuiWinCntr --class Base <cuiWinID> open
# usage: cuiWinCntr <cuiWinID> <cmd> [<arg1> .. <argN>]
# This is the default handler function for cuiWin windows.
# Scope Vars Provided by Caller:
#    bgdCntrFile : the path of the cntr pipe file
#    winTitle    : string that will be the title of the window
function cuiWinBaseClassHandler()
{
	echo "starting $bgdCntrFile"
	source /usr/lib/bg_core.sh --minimum
	import bg_cui.sh ;$L1;$L2
	trap -n cntrFileRm '
		rm -f "$bgdCntrFile" "$bgdCntrFile.lock" "$bgdCntrFile.ret" "$bgdCntrFile.ret.lock"
		[ "$tailPID" ] && kill "$tailPID"
		tailPID=""
	' EXIT
	# make sure that we dont inherit the bgtrace SIGINT handler. We should not in any case, but when we do trap -p we might see it otherwise
	builtin trap - SIGINT

	local tty="$(tty)"
	cuiSetTitle "$winTitle $tty"

	# the proc with the createLock lock is waiting on the tty msg to signal that we are started
	tty >$bgdCntrFile

	# do the msg loop
	while true; do
		local cmd="<error>"; read -r -a cmd <$bgdCntrFile
		local result=$?; (( result > 128)) && result=129
		case $result in
			0) 	;;
			129) ;;  # timeout (if we give read the -t <n> option)
			*)	bgtrace "CUIWIN($(tty)) read from bgdCntrFile exit code '$result'"
				echo "CUIWIN read from bgdCntrFile exit code '$result'"
				sleep 5
				;;
		esac
		# TODO: separate this case out into a <class>Dispatch function so that sub classes can delegate to superclasses
		case ${cmd[0]} in
			gettty) tty >$bgdCntrFile ;;
			close)  return ;;
			youUp)  echo "youBet" >$bgdCntrFile ;;
			testFail) trap -r -n cntrFileRm EXIT; return ;;
			ident)
				which pstree >/dev/null && pstree -p $$
				tty
				echo "pid='$$'  BASHPID='$BASHPID'   SHLVL='$SHLVL'  tailPID='$tailPID'"
				;;
			tailStatus)
				if [ "$tailPID" ] && pidIsDone "$tailPID"; then
					echo "tail process '$tailPID' on file '$file' has ended"
					tailPID=""
					file=""
				fi

				if [ "$tailPID" ]; then
					echo "tail file = '$file'"
				else
					echo "no tail in progress"
				fi
				;;
			tailFile)
				local file="${cmd[1]}"
				[ "$tailPID" ] && { bgkillTree "$tailPID"; tailPID=""; }
				[ ! -e "$file" ] && { touch "$file" || echo "warning: '$file' does not exist and can not be created"; }
				(
					builtin trap 'done=1' SIGINT
					while [ ! "$done" ]; do
						cuiSetTitle "$winTitle $tty tail -f '$file' $((count++))"
						echo "$$ $BASHPID starting tail -f $file"
						tail -f -n50 "$file"
						echo "!!!! woke and restarting tail $file (winID=$bgtraceLogFile)"
						which pstree >/dev/null && pstree -p -s $$
						sleep 10
					done
					# this line sends a message as a client would do. I think this is OK because its in a sub proc and not the main loop.
					echo "_onTailEnding" > $bgdCntrFile
				) &
				tailPID=$!
				disown "$tailPID"
				;;
			tailCancel)
				[ "$tailPID" ] && kill "$tailPID"
				tailPID=""
				;;
			_onTailEnding)
				tailPID=""
				file=""
				;;
			*) echo "'${cmd[0]}' is unknown"
		esac
	done
}

# MAN(5) cuiWinProtocol
# The cuiWin family of functions use a single linux pipe as a control channel for each additional GUI
# terminal emulator window that a script can create to interact with the operator. One end of the
# pipe is the window handler function that runs in a bash process in the terminal emulator window.
# The other end of the communication is the script that creates and uses that term emulator window.
# The script primarily operates with the TTY of the terminal but the control (cntr) pipe is used
# to manage the GUI window operations. This man page describes the protocol for how that pipe is
# used for cummunication.
#
# A single one-way linux pipe is used as the communication channel. This requires that the the communication
# is considered 'one way' from the client to the window handler. 'one way' means that the client initiates
# all commands (<cmd>) but it allows for some commands to have replies that are sent from the handler back
# to the client.
#
# The general protocol is that he handler is typically waiting for a client to send a <cmd> and clients
# initiate a <cmd> any time they want after getting a cooperative client side lock.
#
# Timeouts due to msg type disagrements are small (10's of ms). Timeouts due to the handler latency
# of processind a cmd should be on the order of 100ms. Timeouts to aquire the cooperative lock should
# be on the order of the time that it takes to create a new gui window which is on the order of 500ms
# to 1s.
#
# The handler should proces and finish commands immediately (as opposed to doing long lived operations
# that do arbitrary complex, blocking work) so that it returns to waiting for the next <cmd> in a
# predictable time. That maximum time is what clients should wait before considering the handler in
# a crashed state. That timeout shoould be on the order of 1s if the client does not know if the window
# is already open, or could be as low as 100ms if it knows that the window is not in the state of being
# created.
#
# Using a linux pipe means that communication only happens when a reader and writer exist at the same
# time. If both the client and window handler try to write at the same time or expect to read at the same
# time they will deadlock. This protocol results in both sides knowing when its time for them to either
# read or write as long as they agree about whether the <cmd> being processed is synchronous or
# asynchronous. Disagreements are bound to happen so the protocol requires both sides to agressively
# timeout the operations that are effected by disagreements and defines the recovery to a knowned state.
#
#  Message Format:
#    <msg>\n
# All msgs in both directions are line oriented. Newlines in data can be escaped in any way agreed by
# the higher level code as long as the ascii(10) character does not appear in the msg. This protocol does
# not inspect or care what is in the message.
#
#  <cmd> Types:
# Synchronous (aka two-way) and asynchronous (aka one-way) cmd types are supported.
#
# Asynchronous <cmd> type consists of a single msg sent from the client to the window handler. The client
# will block on the channel while sending this msg until the handler is available to receive the msg.
#
# Synchronous <cmd> type consists of the same initial <msg> as async type but also requires an additional
# msg sent from the handler back to the client in response to the first. In this cummunication,
# either the handler or the client will block on its pipe operation first and then when the other is
# ready the communication will complete.
#
# The two sides should agree on which <cmd> are sync and which are async but the protocol is tolerant
# to disagreements through the use of agressive timeouts and recovery to the known rest state
#
#  Client Collisions:
# Clients must obtain a cooperative lock on the pipe in order to initiate a msg so that they we know
# that there are at most two parties involve in a communication at a time. The handler is always one
# of the parties. Cooperative means in this case that the lock is not technically required to perform
# the operation. The handler needs to be able to read and write to the pipe while a client has the lock.
# All clients must agree that they will refrain from doing any operation on the pipe unless they have
# the lock.
# If not for this lock when a client reads the reply of a synchronous <cmd> it may read the initial
# msg written by another client. From the point of view of the second client, it thinks its sent a
# <msg> to the handler but it actually sent a <msg> to another client.
#
#  Rest State of the Pipe:
# In between cmd exchanged, the rest state is that the handler blocks on reading the pipe and no clients
# have any operation pending on the pipe.
#
#  Client Side Protocol:
# All cmds are initiated by the client. The client must obtain the shared cooperative lock before
# it performs a <cmd> of any type (sync or async) and release the lock when its done doing operations
# on the pipe for that <cmd>. It should timout of the lock aquisition after a timout that represents
# the max time that the cntr pipe exists but the handler is not ready to receive <cmds> which is typically
# the time it take to create a new gui window which is on the order of 500ms to 1s. The client should
# interpret this timout ocuring as there being a crashed or erroneous client in the system that did
# not release the lock or the system being so slow that its in an error condition.
# After obtaining the lock the client should perform the initial send operation with a relatively short
# timeout (10ms) because the handler should be in its rest state, waiting for a <cmd> to be initiated.
# The client should interpret this timeout ocuring as the handler being crashed or otherwise unhealthy.
# If the client believes that <cmd> is synchronous, it should next perform a read operation with a
# timout equal to the maximum handler latency (100ms). This gives the handler time to process the
# command and write the reply msg back to the pipe. This timeout ocuring should be interpreted as the
# handler being in disagreement with the client about whether its a synchronous <cmd>.
#
#  Window Handler Side Protocol:
# The handler is the responder to all commands. It waits indefinitely on the read pipe operation.
# When it wakes from read it should return to the rest state beore the maximum handler latency (100ms).
# This means that any long lived operation performed by the handler in response to a <cmd> should be
# performed in a separate thread of execution so that it can return to the rest state in time.
#
# When sending replies in response to synchronous <cmd>s the handler should implement a relatively
# short (10ms) time out because the client's sole responsibility after sending a synchronous <cmd>
# is to start reading the reply. The handler should interpret this timeout ocuring as the the client
# being in disagreement about this <cmd> being synchronous.
#
# The handler can not initiate a msgs to the client and should not try. If that is needed, the handler
# and client should agree on a different communication channel for that purpose. Typically, however,
# that is not needed because these window's purpose is to provide a terminal that the operator interacts
# with and the tty is the channel that the operator uses to initiate higher level application commands
# back to the running application (aka script).
#
#  Protocol Error Recovery:
# When a timeout ocrurs on either the client or window handler, the <cmd> being executed should be
# considered finished and it should return to its rest state where another command may be initiated.
# There are never retries as these may mess up subsequent <cmd>. The protocol describes the way to
# interpret each type of timeout. The client and handler informs the operater when appropriate. The
# handler can inform with mssages to its tty and the client can do the same with its tty.
#

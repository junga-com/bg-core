
# Library
# Oneline progressFeedback UI Driver.
# This library implements a destination for progress feedback data. It uses one line of the terminal to display the feedback,
# overwriting it each time there is new progress to report. If the script produces stdout output while the progress is active,
# the progress line will scroll
#
# The user can select which progress driver/destination will be used by setting the progressDisplayType environment variable in
# their profile or a specific terminal.
#
# The default driver is "statusline". A script could select a different default driver by calling "progressCntr setDefaultDriver"
#
# See Also:
#    man(3) progress
#    man(3) progressCntr
#    man(5) progressProtocol




# usage: progressTypeOnelineCntr start|stop|...  [parameters ...]
# this implements a progress feedback UI Driver class
# Its a Singleton object class implemented in this one function that is registered in the progressTypeRegistry
#
# The oneLine feedback UI works with the common terminal metaphore of a continuous scrolling page but
# progress updates always overwrite themseleves on the line in which they were first written.
# Each child process has separate status feedback so if a child process writes a progress message,
# the first time it writes on the next available line and from then on, that proccess will only overwrite
# that same line. This means that each new suproc that writes progress may cause the whole screen to
# scroll up and the previous status lines used by other subprocs will have moved up.
#
# stdout of the script is intercepted and inserted above the progress status line(s) so that the normal
# output only scrolls the text above it and the status lines stay at the bottom on the screen.
# When the UI is stopped (which typically happens when the script terminates, std output resumes after
# the status lines as normal and the last state of each status line will begin to scroll along with
# the other content.
function progressTypeOnelineCntr()
{
	local cmd="$1"; shift
	case $cmd in
		# end is a graceful shutdown that lets the UI proc finish its queue
		stop|end)
			#progressTypeOnelineCntr stopInputLoop

			### signal the stdou/stderr loop and the progress msg loop to stop

			# signal the user input loop to stop by sending a SIGINT. It traps SIGINT to set done=1
			kill -s SIGTERM ${progressPIDs[1]}

			# signal the stdout/stderr loop to stop by closing the pipe that its reading
			# stdout and stderr are redirected to pipeToStdStreamHandler. close pipeToStdStreamHandler and return stdout/err to original
			exec  >&- 2>&- >&4 2>&5

			# signal the progress msg loop to stop by closing its pipe. This will allow it to finish reading any buffered msgs
			[ "${_progressDriver["userFeedbackFD"]}" ] && exec {_progressDriver["userFeedbackFD"]}>&-
			_progressDriver["userFeedbackFD"]=""

			# now wait for the loops to end
			wait "${progressPIDs[2]}" "${progressPIDs[1]}" "${progressPIDs[0]}"
			unset progressPIDs
			rm "${ipcFile}*" 2>/dev/null
			ipcFile=""
			;;

		# @ cmds are sent to the UI process
		@*)   [ "${_progressDriver["PID"]}" ] && echo "$@" >&${_progressDriver["userFeedbackFD"]} ;;

		# the (stop|start)InputLoop messages are needed because scripts that need to read from stdin need to stop the driver
		# from reading from stdin so it does not fight over reading the input. I tried installing this loop as a filter
		# that replaces stdin with a pipe that it writes to but that does not work for things like sudo that bypass stdin
		# to read from the terminal pts device. Scripts should not be hardcoded to know about this driver so they send a message
		# the the actived driver like 'progressCntr "stopInputLoop"'. Any driver that needs to will respond to that
		# message and all others will ignore it.
		stopInputLoop)
			if [ "${progressPIDs[1]}" ]; then
				kill ${progressPIDs[1]}
				wait ${progressPIDs[1]}
				progressPIDs[1]=""
			fi
			;;

		startInputLoop)
			# is is a co-process to read user input from stdin and display a spinner.
			# As the user enters input, the screen can scroll so we intercept that so that we can keep the ipcFile uptodate.
			(_onelineUserInputLoop) >&4 <&0  &
			progressPIDs[1]=$!
			;;

		start)
			declare -ga progressPIDs

			local -x spinFlag="spinner"

			ipcFile=$(mktemp)
			echo "start" > "$ipcFile"
			echo  > "${ipcFile}.signal"
			# save stdout and stderr in fd 4 and 5
			exec 4>&1
			exec 5>&2

			# this is a co-process to pipe stdout/stderr through so that we can count lines to know where the progress lines have
			# scrolled to. This will be the normal output from the script or children
			pipeToStdStreamHandler=$(mktemp -u )
			mkfifo "$pipeToStdStreamHandler"
			(
				_onelineScriptOutputLoop
			) >&4 <$pipeToStdStreamHandler &
			progressPIDs[0]=$!
			exec &>$pipeToStdStreamHandler

			progressTypeOnelineCntr startInputLoop


			# this is a coproc to read the progress lines and display them
			local pipeToProgressHandler=$(mktemp -u /tmp/bgprogress-XXXXXXXXX)
			mkfifo -m 600 "$pipeToProgressHandler"
			(
				_onelineReadProgressLoop
			) >&4 <$pipeToProgressHandler &
			progressPIDs[2]=$!
			exec {_progressDriver["userFeedbackFD"]}>$pipeToProgressHandler
			_progressDriver["protocol"]="structured"
			;;

		hide)
			echo -n ""
			;;
	esac
}

# this function is executed in the background
# stdin is the pipe that the main script writes progress msgs to.
# stdout is the terminal
function _onelineReadProgressLoop()
{
	local lineOffset=1 msgType progressScope formattedStr label msg startTime lapTime curTime target current
	while read -r -a params; do
		arrayFromBashTokens params
		set -- "${params[@]}"
		local msgType="$1"; shift

		case $msgType in
			@end) break ;;

			# once both this copro and the calling process have redirected pipeToProgressHandler to make an open FD, we
			# do not need it in the filesystem anymore. The caller sends us this msg to say its ok to rm
			@rmPipe)
				rm -f "$pipeToProgressHandler" || assertError
				;;

			@1)	local progressScope="$1"
				local formattedStr="$2"
				local progCmd="$3"
				local parent="$4"
				local label="$5"
				local msg="$6"
				local startTime="$7"
				local lapTime="$8"
				local curTime="$9"
				local target="${10}"
				local current="${11}"

				startLock $ipcFile.lock

				local now=$(date +"%s%N")
				local delay=$((now - curTime))
				# if we get more than 0.2 seconds behind, start skipping up to 19 updates at a time
				if ((delay > 200100100)) && [ "$progCmd" == "-u" ] && (( skipCount++%20 !=0 )); then
					continue
				fi

				# get the terminal dimensions (do it in the loop in case the user resizes the terminal, but do it after throttling)
				cuiGetScreenDimension termHeight termWidth </dev/tty

				# dont let the progress line wrap to the next line
				formattedStr="${formattedStr:0:$termWidth}"

				# ipcFile mirrors the output to the terminal. Whenever we start a new progressScope we write a new line to ipcFile with its
				# name. This mirrors the fact that we wrte a new line to the terminal for that progressScope msgs. Then in other loops we
				# monitor the other things that can right to the terminal and when ever the cursor moves down a line (which may or may not
				# scroll the terminal), we mirror that by writing a newline to the ipcFile. In this way, the ipcFile always tells us how
				# many lines up from the current cursor each progressScope line is
				lineOffset="$(awk -v progressScope="$progressScope" '
					$0~"^"progressScope":" {line=NR}
					END {print (line)?(NR-line+1):"NOTFOUND"}
				' "$ipcFile" 2>/dev/null || echo "NOTFOUND")"

				# "NOTFOUND" means that the is the first time we are seeing this progressScope so we need to write it on a new line
				if [ "$lineOffset" == "NOTFOUND" ]; then
					echo "$progressScope:" >> "$ipcFile"
					printf "${csiSave}%s\n${csiRestore}" "$formattedStr"

				# this case, the ipcFile told us the lineOffset, so save the current cursor, move up to that line, overwrite it, and then
				# restore the cursor back to where it was
				else
					if [ ${termHeight:-0} -gt ${lineOffset:-0} ]; then
						printf "${csiSave}${csiToSOL}${CSI}$lineOffset${cUP}%s${csiClrToEOL}${csiRestore}" "$formattedStr"
					fi
				fi
				endLock $ipcFile.lock
				;;
		esac
	done;
	[ "$spinFlag" ] && printf "${csiToSOL}    ${csiToSOL}"
}


# this function is executed in the background
# stdin is a pipe in which we redirect both stdout and stderr to write to (because they both send output to the terminal)
# stdout is the terminal
# This purpose of this loop is to watch to see whenever the cursor moves down a line (chich may or may not scroll the terminal)
# and mirror it by writing a newline in the ipcFile. Since the _onelineReadProgressLoop writes the progressScope name as a new line
# whenever it adds a progress status line to the terminal, the ipcFile records how many lines above the current cursor each
# progressScope status line is (so that _onelineReadProgressLoop can move up, update it, and move back when its status changes)
function _onelineScriptOutputLoop()
{
	local readCode  done
	# the trap is the only way out of the loop b/c this loop reads from stdin which we dont want to close
	bgtrap 'done="1"' SIGTERM
	while [ ! "$done" ]; do
		line=""; IFS="" read -r -t 0.7 line; readCode=$?

		# pipe closed. end loop
		[ ${readCode:-0} -eq 1 ] && break

		# line is a completed line terminated with \n
		if [ $readCode -lt 128 ]; then
			startLock $ipcFile.lock
			cuiGetSpinner 100 spinner
			printf "${csiSave}${csiToSOL}    ${line}\n[${spinner}]: ${csiRestore}"
			echo >> "$ipcFile"
			endLock $ipcFile.lock

		# timeout. line might contain input that does not have a \n yet
		elif [ "$line" ]; then
			startLock $ipcFile.lock
			printf "${line}"
			endLock $ipcFile.lock
		fi
	done;

	[ "$spinFlag" ] && printf "${csiToSOL}    ${csiToSOL}"
}


# this function is executed in the background
# stdin is the terminal
# stdout is the terminal
# The purpose of this loop is to capture the user input to the terminal and update the ipcFile whenever the user enters a newline.
# It also writes the spinner if it is called for. The stdin read times out periodically and updates the spinner
function _onelineUserInputLoop()
{
	local spinner=( / - \\ \| )
	local spinCount=0

	# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
	stty -echo
	bgtrap '
		stty echo
		# clear spinner
		[ "$spinFlag" ] && printf "${csiToSOL}    ${csiToSOL}"
	' EXIT

	# display the spinner at the start of the current line and leave the cursor directly after it
	cuiGetSpinner 100 spinner
	[ "$spinFlag" ] && printf "${csiToSOL}[${spinner}]: "

	# the trap is the only way out of the loop b/c this loop reads from stdin which we dont want to close
	local done
	bgtrap 'done="1"' SIGTERM
	while [ ! "$done"  ]; do
		char=""
		IFS="" read -r -d '' -t 0.1  -n 1 char 2>/dev/null; readCode=$?
		[ ${readCode:-0} -eq 1 ] && break

		if [ ${readCode:-0} -eq 0 ]; then
			if [ "$char" == $'\n' ]; then
				startLock $ipcFile.lock
				echo >> "$ipcFile"
				# when user enters a carrage return, clear the spinner, go to the next line and then display the spinner again
				# the cursor will be right after the spinner which is where we want input to begin
				if [ "$spinFlag" ]; then
					cuiGetSpinner 100 spinner
					printf "${csiToSOL}    \n[${spinner}]: "
				else
					printf "\n"
				fi
				endLock $ipcFile.lock
			else
				# when the user enters any other character, just print it at the current cursor position
				printf "$char"
			fi
		fi

		# read timeout. update spinner
		if [ "$spinFlag" ] && [ $readCode -gt 128 ] && [ ! "$done" ]; then
			startLock $ipcFile.lock
			# save the cursor, write the new spinner, then restore the cursor
			cuiGetSpinner 100 spinner
			printf "${csiSave}${csiToSOL}[${spinner}]: ${csiRestore}"
			endLock $ipcFile.lock
		fi
	done;
	[ "$spinFlag" ] && printf "${csiToSOL}    ${csiToSOL}"
}


progressTypeRegistry[oneline]="progressTypeOnelineCntr"


# Library
# Oneline progressFeedback UI Driver.
# This library implements a destination for progress feedback data. It uses one line of the terminal to display the feedback,
# overwriting it each time there is new progress to report. If the script produces stdout output while the progress is active,
# the progress line will scroll




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
	local cmd="$1"; [ "$1" ] && shift
	case $cmd in
		stop)
			userFeedbackFD=""
			progressTypeOnelineCntr stopInputLoop
			exec >&4 2>&5           # set the stdout and stderr back
			procIsRunning "${progressPIDs[0]}" &&  { kill "${progressPIDs[0]}"; wait "${progressPIDs[0]}"; }
			procIsRunning "${progressPIDs[2]}" &&  { kill "${progressPIDs[2]}"; wait "${progressPIDs[2]}"; }
			unset progressPIDs
			export _progressCurrentType=""
			rm "${ipcFile}*" 2>/dev/null
			ipcFile=""
			stty echo
			;;

		# the (stop|start)InputLoop messages are needed because scripts that need to read from stdin need to stop the driver
		# from reading from stdin so it does not fight over reading the input. I tried installing this loop as a filter
		# that replaces stdin with a pipe that it writes to but that does not work for things like sudo that bypass stdin
		# to read from the terminal pts device. Scripts should not be hardcoded to know about this driver so they send a message
		# the the actived driver like 'progressFeedbackCntr "stopInputLoop"'. Any driver that needs to will respond to that
		# message and other will ignore it.
		stopInputLoop)
			if [ "${progressPIDs[1]}" ]; then
				kill ${progressPIDs[1]}
				wait ${progressPIDs[1]}
				progressPIDs[1]=""
			fi
			;;

		startInputLoop)
			local inputLoopType="${2:-}"

			# is is a co-process to read user input from stdin and display a spinner.
			# As the user enters input, the screen can scroll so we intercept that so that we can keep the ipcFile uptodate.
			(_onelineReadStdinLoop "$inputLoopType") >&4 <&0  &
			progressPIDs[1]=$!
			;;

		start)
			if [ ! -t 1 ]; then
				export userFeedbackFD="1"
				export _progressCurrentType="stdout"
				return
			fi

			export _progressCurrentType="$type"
			declare -ga progressPIDs

			# since we redirect input to a background task, we need to make sure that we clean up
			bgtrap '
				#myTestTrapHandler EXIT "'"$BASHPID"'" "START >>>>>>>>>>>>>>>>>>>>>>>>>"
				progressCntr off
				#myTestTrapHandler EXIT "'"$BASHPID"'" "STOP  >>>>>>>>>>>>>>>>>>>>>>>>>"
			' EXIT
			local termHeight=$(tput lines 2>/dev/tty)
			local termWidth=$(tput cols 2>/dev/tty)
			ipcFile=$(mktemp)
			echo "start" > "$ipcFile"
			echo  > "${ipcFile}.signal"
			# save stdout and stderr in fd 4 and 5
			exec 4>&1
			exec 5>&2

			# this is a co-process to pipe stdout/stderr though so that we can count lines and
			# what ever else we want. This will be output from the script or children that does not use 'progress'
			pipeToStdStreamHandler=$(mktemp -u )
			mkfifo "$pipeToStdStreamHandler"
			(_onelineReadStdoutStderrLoop) >&4 <$pipeToStdStreamHandler &
			progressPIDs[0]=$!
			exec &>$pipeToStdStreamHandler

			progressTypeOnelineCntr startInputLoop


			# this is a coproc to read the progress lines and display them
			local pipeToProgressHandler=$(mktemp -u )
			mkfifo "$pipeToProgressHandler"
			(_onelineReadProgressLoop) >&4 <$pipeToProgressHandler &
			progressPIDs[2]=$!
			exec {userFeedbackFD}>$pipeToProgressHandler
			export userFeedbackFD
			export userFeedbackProtocol="structured"
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
	# the trap is the only way out of the loop
	bgtrap 'exit' SIGTERM
	while IFS="" read -r line; do
		read -r msgType progressScope formattedStr parent label msg startTime lapTime curTime target current <<<$line
		[ "$msgType" == "@1" ] || assertError -v msgType "'oneline' cui progress driver expects structured progress messages with msgType=='@1'"
		unescapeTokens parent label msg target current formattedStr

		startLock $ipcFile.lock

		# dont let the progress line wrap to the next line
		formattedStr="${formattedStr:0:$termWidth}"

		# ipcFile mirrors the output to the terminal. Whenever we start a new progressScope we write a new line to ipcFile with its
		# name. This mirrors the fact that we wrte a new line to the terminal for that progressScope masgs. Then in other loops we
		# monitor the other things that can right to the terminal andwhen ever the cursor moves down a line (which may or may not
		# scroll the terminal), we mirror that by writing a newline to the ipcFile. In this way, the ipcFile always tells us how
		# many lines up from the current cursor each progressScope line is
		lineOffset="$(awk -v progressScope="$progressScope" '
			$0~"^"progressScope":" {line=NR}
			END {print (line)?(NR-line+1):"NOTFOUND"}
		' "$ipcFile" 2>/dev/null || echo "NOTFOUND")"

		# "NOTFOUND" means that the is the first time we are seeing this progressScope so we need to write it on a new line
		if [ "$lineOffset" == "NOTFOUND" ]; then
			echo "$progressScope:" >> "$ipcFile"
			printf "%s\n" "$formattedStr"

		# this case, the ipcFile told us the lineOffset, so save the current cursor, move up to that line, overwrite it, and then
		# restore the cursor back to where it was
		else
			if [ $termHeight -gt $lineOffset ]; then
				printf "${csiSave}${csiToSOL}${CSI}$lineOffset${cUP}%s${csiClrToEOL}${csiRestore}" "$formattedStr"
			fi
		fi
		endLock $ipcFile.lock
	done;
}


# this function is executed in the background
# stdin is a pipe in which we redirect both stdout and stderr to write to (because they both send output to the terminal)
# stdout is the terminal
# This purpose of this loop is to watch to see whenever the cursor moves down a line (chich may or may not scroll the terminal)
# and mirror it by writing a newline in the ipcFile. Since the _onelineReadProgressLoop writes the progressScope name as a new line
# whenever it adds a progress status line to the terminal, the ipcFile records how many lines above the current cursor each
# progressScope status line is (so that _onelineReadProgressLoop can move up, update it, and move back when its status changes)
function _onelineReadStdoutStderrLoop()
{
	local readCode lineEnd
	# the trap is the only way out of the loop
	bgtrap 'exit' SIGTERM
	while true; do
		line=""
		IFS="" read -r -t 0.7 line; readCode=$?
		if [ "$line" ]; then
			if [ $readCode -lt 128 ]; then
				startLock $ipcFile.lock
				printf "${csiSave}${csiToSOL}    ${line}\n${csiRestore}"
				echo >> "$ipcFile"
				endLock $ipcFile.lock
			elif [ "$line" ]; then
				startLock $ipcFile.lock
				printf "${line}"
				endLock $ipcFile.lock
			fi
		fi
	done;
}


# this function is executed in the background
# stdin is the terminal
# stdout is the terminal
# The purpose of this loop is to capture the user input to the terminal and update the ipcFile whenever the user enters a newline.
# It also writes the spinner if it is called for. The stdin read times out periodically and updates the spinner
function _onelineReadStdinLoop()
{
	local spinFlag="$1"

	# if the task is over quickly, dont draw the spinner
	sleep 1

	local spinner=( / - \\ \| )
	local spinCount=0

	# display the spinner at the start of the current line and leave the cursor directly after it
	[ "$spinFlag" ] && printf "${csiToSOL} ${spinner[spinCount%4]}]: "

	# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
	stty -echo
	bgtrap 'stty echo' EXIT

	bgtrap 'exit' SIGTERM
	while true; do
		sleep 0.2
		char=""
		IFS="" read -r -d '' -t 0.2  -n 1 char 2>/dev/null; readCode=$?
		[ ${readCode:-0} -eq 1 ] && break

		if [ ${readCode:-0} -eq 0 ]; then
			if [ "$char" == $'\n' ]; then
				startLock $ipcFile.lock
				echo >> "$ipcFile"
				# when user enters a carrage return, clear the spinner, go to the next line and then display the spinner again
				# the cursor will be right after the spinner which is where we want input to begin
				if [ "$spinFlag" ]; then
					printf "${csiToSOL}    ${csiRestore}\n ${spinner[spinCount%4]}]: "
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
		if [ "$spinFlag" ] && [ $readCode -gt 128 ]; then
			startLock $ipcFile.lock
			# save the cursor, write the new spinner, then restore the cursor
			printf "${csiSave}${csiToSOL} ${spinner[spinCount++%4]}]: ${csiRestore}"
			endLock $ipcFile.lock
		fi
	done;
	stty echo
}


progressTypeRegistry[oneline]="progressTypeOnelineCntr"

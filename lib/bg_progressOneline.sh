
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
			exec >&4 2>&5           # set the stdout and stderr back
			progressTypeOnelineCntr stopInputLoop
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
			local inputLoopType="${2:-spinner}"
			if [[ "$inputLoopType" == "spinner" ]]; then
				progressTypeOnelineCntr "startInputLoopWithSpinner"
			else
				progressTypeOnelineCntr "startInputLoopWithoutSpinner"
			fi
			;;

		startInputLoopWithoutSpinner)
			# we should only start the stdin read loop if the 'oneline' feedback UI driver is active
			[ "$_progressCurrentType" == "oneline" ] || return 1

			# is is a co-process to read user input and display a spinner. If the user hits enter, the term
			# scrolls the term directly (local echo) so we need to catch that. We turn off echo and we process the
			# user input oursleves so that we can scroll in sync with the other output
			(
				#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" INP LOOP' SIGTERM
				#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" INP LOOP' SIGINT
				#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" INP LOOP' EXIT
				# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
				stty -echo
				bgtrap 'stty echo' EXIT

				# the trap is the only way out of the loop SIGTERM is the default kill SIG
				bgtrap 'exit' SIGTERM
				while read -r buf; do
					startLock $ipcFile.lock
					echo >> "$ipcFile"
					printf "${csiToSOL}   ${csiToSOL}"
					echo
					endLock $ipcFile.lock
				done
				stty echo
			) >&4 <&6  &
			progressPIDs[1]=$!
			;;


		startInputLoopWithSpinner)
			# is is a co-process to read user input and display a spinner. If the user hits enter, the term
			# scrolls the term directly (local echo) so we need to catch that. We turn off echo and we process the
			# user input oursleves so that we can scroll in sync with the other output
			(
				#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" INP LOOP' EXIT
				#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" INP LOOP' SIGINT
				#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" INP LOOP' SIGTERM
				sleep 1
				local spinner=( / - \\ \| )
				local spinCount=0
				printf " /]: "

				# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
				# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
				stty -echo
				bgtrap 'stty echo' EXIT

				# the trap is the only way out of the loop SIGTERM is the default kill SIG
				bgtrap 'exit' SIGTERM
				while true; do
					sleep 0.2
					char=""
					IFS="" read -r -d '' -t 0.2  -n 1 char ; readCode=$?
bgtraceVars char readCode
					if [ "$char" == $'\n' ]; then
						startLock $ipcFile.lock
						echo >> "$ipcFile"
						printf "${csiSave}${csiToSOL}    ${csiRestore}"
						printf "$char"
						printf " /]: "
						endLock $ipcFile.lock
					else
						printf "$char"
					fi
					# read timeout. update spinner
					if [ $readCode -gt 128 ]; then
						startLock $ipcFile.lock
						printf "${csiSave}${csiToSOL} ${spinner[spinCount++%4]}]: ${csiRestore}"
						endLock $ipcFile.lock
					fi
				done;
				stty echo
			) >&4 <&0  &
			progressPIDs[1]=$!
			;;

		start)
			#bgtrap 'myTestTrapHandler EXIT   "'"$BASHPID"'" SCRIPT' EXIT
			#bgtrap 'myTestTrapHandler SIGINT "'"$BASHPID"'" SCRIPT' SIGINT
			#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" SCRIPT' SIGTERM
			# if we are not attached to a terminal, revert to plain stdout
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
			(
				#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" OUT LOOP' EXIT
				#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" OUT LOOP' SIGINT
				#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" OUT LOOP' SIGTERM
				local readCode lineEnd
				# the trap is the only way out of the loop
				bgtrap 'exit' SIGTERM
				while true; do
					line=""
					IFS="" read -r -t 0.7 line; readCode=$?
					if [ "$line" ]; then
						if [ $readCode -lt 128 ]; then
							startLock $ipcFile.lock
							printf "    ${line}\n"
							echo >> "$ipcFile"
							endLock $ipcFile.lock
						else
							printf "    ${line}"
						fi
					fi
				done;
			) >&4 <$pipeToStdStreamHandler &
			progressPIDs[0]=$!
			exec &>$pipeToStdStreamHandler

			progressTypeOnelineCntr startInputLoop

			# this is a coproc to read the progress lines and display them
			local pipeToProgressHandler=$(mktemp -u )
			mkfifo "$pipeToProgressHandler"
			(
				#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" PRO LOOP' EXIT
				#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" PRO LOOP' SIGINT
				#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" PRO LOOP' SIGTERM
				local lineOffset=1 progressScope
				# the trap is the only way out of the loop
				bgtrap 'exit' SIGTERM
				while IFS="" read -r line; do
					if [[ "$line" =~ ^@1\  ]]; then
						line="${line#@1 }"
						progressScope="${line%% *}"
						line="${line#* }"
						line="${line//%20/ }"
					fi
					startLock $ipcFile.lock
					line="${line:0:$termWidth}"
					if ! grep -q "^$progressScope:" "$ipcFile" 2>/dev/null; then
						echo "$progressScope:" >> "$ipcFile"
						printf "${csiToSOL}%s${csiClrToEOL}\n" "$line"
					else
						local lineNR="$(awk '
							$0~"^'"$progressScope"':" {printf("%s ", NR)}
						' "$ipcFile" 2>/dev/null || echo "err")"
						local totalNR="$(awk '
							END {print NR}
						' "$ipcFile" 2>/dev/null || echo "err")"


						lineOffset="$(awk '
							$0~"^'"$progressScope"':" {line=NR}
							END {print NR-line+1}
						' "$ipcFile" 2>/dev/null || echo "$lineOffset")"
						if [ $termHeight -gt $lineOffset ]; then
							printf "${csiToSOL}${CSI}$lineOffset${cUP}%s${csiClrToEOL}${csiToSOL}${CSI}$lineOffset${cDOWN}" "$line"
						fi
					fi
					endLock $ipcFile.lock
				done;
			) >&4 <$pipeToProgressHandler &
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
progressTypeRegistry[oneline]="progressTypeOnelineCntr"

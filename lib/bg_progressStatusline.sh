
# Library
# StatusLine progressFeedback UI Driver.
# This library implements a destination for progress feedback data. It turns the last line in the terminal into a status line
# that is outside the scroll region of the terminal. As the script produces stdout output, the rest of the terminal scrolls normally
# as last line displays the progress feedback




# usage: progressTypeStatusLineCntr start|stop|...  [parameters ...]
# this implements a progress feedback UI Driver class
# Its a Singleton object class implemented in this one function that is registered in the progressTypeRegistry
#
# this implements a progress feedback UI where progress lines are written in a 'status' line at the bottom of the screen.
# a new status line is allocated at the bottom of the screen for each new progressScope encountered
# at the end, the new shell prompt will be added at the bottom and all the status lines will scroll up like other output.
#
# This is a progressFeedbackUI driver control function. Its kind of like a Singleton object class. It is registered in the
# progressTypeRegistry map by its type name which is used in configuration to specify that it should be used.
function progressTypeStatusLineCntr()
{
	local cmd="$1"
	case $1 in
		stop)
			[ "$userFeedbackFD" ] && exec {userFeedbackFD}>&-
			wait "${progressPIDs[0]}"
			progressPIDs[0]=""
			userFeedbackFD=""
			;;
		start)
			declare -ga progressPIDs
			declare -g  progressTermFD=""

			# this driver needs to read and write the terminal
			cuiHasControllingTerminal || return 1

			local termHeight=$(tput lines 2>/dev/tty)
			local termWidth=$(tput cols 2>/dev/tty)

			# linesByScope has the offset from the bottom of each progressScope encountered
			local -A linesByScope

			# the block between ( and ) is a coproc to read the progress lines and display them in the status line
			local pipeToProgressHandler=$(mktemp -u /tmp/bgprogress-XXXXXXXXX); mkfifo -m 600 "$pipeToProgressHandler"; (
				local lineOffset=1 progressScope

				# init version of the $csi* vars in this coproc to reflect /dev/tty
				declare -g $(cuiRealizeFmtToTerm cuiColorTheme_sample1 </dev/tty)

				# this reserves a blank line at the bottom where the new prompt will go when the command ends
				# this makes it so the status line don't jump at the end
				# TODO:

				local fullScreen=$(( termHeight ))
				local partScreen=$(( termHeight ))

				builtin trap '
					printf "${CSI}0;$termHeight${cSetScrollRegion}${CSI}$((termHeight));0${cMoveAbs}${csiClrToEOL}" >/dev/tty
				' EXIT

				# when the calling process closes its FD to the pipe (and there are no other writers), read will exit with exit code 1
				while IFS="" read -r -u 3 line; do
					cmd=""
					if [[ "$line" =~ ^@1\  ]]; then
						line="${line#@1 }"
						progressScope="${line%% *}"
						line="${line#* }"
						line="${line//%20/ }"
					elif [[ "$line" =~ ^@2\  ]]; then
						cmd="hide"
					elif [[ "$line" =~ ^@end  ]]; then
						cmd="end"
					elif [[ "$line" =~ ^@rmPipe  ]]; then
						cmd="rmPipe"
					fi

					termHeight=$(tput lines 2>/dev/tty)
					termWidth=$(tput cols 2>/dev/tty)
					line="${line:0:$((termWidth-1))}"

					case $cmd in
						end) exit ;;

						# once both this copro and the calling process have redirected pipeToProgressHandler to make an open FD, we
						# do not need it in the filesystem anymore. The caller sends us this msg to say its ok to rm
						rmPipe)
							rm -f "$pipeToProgressHandler" || assertError
							;;

						hide)
							printf "${CSI}0;$termHeight${cSetScrollRegion}${CSI}$((termHeight));0${cMoveAbs}${csiClrToEOL}" >/dev/tty
							;;

						*)
							if  [ ! "${linesByScope[$progressScope]}" ]; then
								# offset the existing status line offsets to make room for the new one
								for i in ${!linesByScope[@]}; do
									(( linesByScope[$i]++ ))
								done
								linesByScope[$progressScope]="0"

								# set the scroll region to the whole screen and scroll everything up one line (including our status lines)
								# then set the scroll region to exclude our status lines and put the cursor at the end of the scroll region
								local fullScreen=$(( termHeight ))
								local partScreen=$(( termHeight - ${#linesByScope[@]} ))
								printf "${csiSave}${CSI}0;$fullScreen${cSetScrollRegion}${CSI}0;0${cMoveAbs}${CSI}1${cScrollUp}${CSI}0;$partScreen${cSetScrollRegion}${csiRestore}${csiUP}" >/dev/tty
							fi

							# we use the printf / CSI construct so that the entire sequence is one API call and (hopefully) one atomic write
							local statusLineNum=$(( termHeight - linesByScope[$progressScope] ))
							printf "${csiSave}${CSI}$statusLineNum;1${cMoveAbs}${csiBkMagenta}%s${csiClrToEOL}${csiDefBkColor}${CSI}${cRestore}" "$line" >/dev/tty
							;;
					esac
				done;
			) >>"$(bgtraceGetLogFile)" 2>&1 3<$pipeToProgressHandler &
			progressPIDs[0]=$!
			exec {userFeedbackFD}>$pipeToProgressHandler
			export userFeedbackFD
			export userFeedbackProtocol="structured"

			# let the loop know that we have finished with pipeToProgressHandler and it can delete it now from the file system
			echo "@rmPipe" >&$userFeedbackFD

			# since we change the scroll region, we need to make sure that we clean up
			bgtrap '
				progressCntr off
			' EXIT

			# the default SIGPIPE will silently exit the process so we trap it and do a bgtrace to aid in debugging. Typically this
			# happens when the driver loop endsprematurely or during shutdown if there is a race condition
			bgtrap 'bgtrace "progressTypeStatusLineCntr: PIPE write signal caught. This means that the driver coproc was not reading the pipe when progress() wrote to  it."' PIPE
			;;

		hide)
			if [ "${progressPIDs[0]}" ]; then
				echo "@2" >&$userFeedbackFD

			fi
			;;
	esac
}
progressTypeRegistry[statusline]="progressTypeStatusLineCntr"


# Library
# StatusLine progressFeedback UI Driver.
# This library implements a destination for progress feedback data. It turns the last line in the terminal into a status line
# that is outside the scroll region of the terminal. As the script produces stdout output, the rest of the terminal scrolls normally
# as last line displays the progress feedback
#
# If the script spawns asynchronous processes that generate progress messages, an additional line will be taken from the bottom
# for each one.
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
	case $cmd in
		stop|end)
			# close the pipe to signal that the background process should end
			[ "${_progressDriver["userFeedbackFD"]}" ] && exec {_progressDriver["userFeedbackFD"]}>&-
			wait "${_progressDriver["PID"]}"
			_progressDriver["PID"]=""
			_progressDriver["userFeedbackFD"]=""
			;;

		# aliases for @hide/@show withotu the @
		hide) [ "${_progressDriver["PID"]}" ] && echo "@hide" >&${_progressDriver["userFeedbackFD"]} ;;
		show) [ "${_progressDriver["PID"]}" ] && echo "@show" >&${_progressDriver["userFeedbackFD"]} ;;

		# @ cmds are sent to the UI process
		@*)   [ "${_progressDriver["PID"]}" ] && echo "$@" >&${_progressDriver["userFeedbackFD"]} ;;

		start)
			# this driver needs to read and write the terminal
			cuiHasControllingTerminal || return 1

			# linesByScope has the offset from the bottom of each progressScope encountered
			local -A linesByScope
			local -A dataByScope

			# the block between ( and ) is a coproc to read the progress lines and display them in the status line
			local pipeToProgressHandler=$(mktemp -u /tmp/bgprogress-XXXXXXXXX)
			mkfifo -m 600 "$pipeToProgressHandler"
			(
				_readProgressMsgLoop
			) >>"${_bgtraceFile:-/dev/null}" 2>&1 3<$pipeToProgressHandler &
			_progressDriver["PID"]=$!
			exec {_progressDriver["userFeedbackFD"]}>$pipeToProgressHandler
			_progressDriver["protocol"]="structured"

			# let the loop know that we have finished with pipeToProgressHandler and it can delete it now from the file system
			echo "@rmPipe" >&${_progressDriver["userFeedbackFD"]}

			# the default SIGPIPE will silently exit the process so we trap it and do a bgtrace to aid in debugging. Typically this
			# happens when the driver loop endsprematurely or during shutdown if there is a race condition
			bgtrap 'bgtrace "progressTypeStatusLineCntr: PIPE write signal caught. This means that the driver coproc was not reading the pipe when progress() wrote to  it."' PIPE
			;;
	esac
}

function _readProgressMsgLoop()
{
	# build the csi cmds that we use. They depend on termHeight and linesByScope so whenever they change, we must call this
	function renderCsiCmds() {
		cmdSetScrollAll="${CSI}0;${termHeight}${cSetScrollRegion}"
		cmdSetScrollPartial="${CSI}0;$(( termHeight - ${#linesByScope[@]} ))${cSetScrollRegion}"
		cmdGotoLowerLeft+="${CSI}$((termHeight));0${cMoveAbs}"
		cmdGotoUpperLeft+="${CSI}1;0${cMoveAbs}"
		cmdGotoHome+="${CSI}$(( termHeight - ${#linesByScope[@]} ));0${cMoveAbs}"
		cmdScrollUp1="${CSI}1${cScrollUp}"
		cmdScrollDn1="${CSI}1${cScrollDown}"
		cmdUPLineCnt="${CSI}${#linesByScope[@]}${cUP}"
		cmdScrollUpLineCnt="${CSI}${#linesByScope[@]}${cScrollUp}"
		cmdClearLines=""; for lineOffset in "${linesByScope[@]}"; do
			cmdClearLines+="${CSI}$((termHeight-$lineOffset));0${cMoveAbs}${csiClrToEOL}"
		done
	}

	local lineOffset=1 progressScope

	# init version of the $csi* vars in this coproc to reflect /dev/tty
	declare -g $(cuiRealizeFmtToTerm cuiColorTheme_sample1 </dev/tty)

	# remove the status lines when we exit
	builtin trap '
		printf "${csiSave}${cmdSetScrollAll}${cmdClearLines}${csiRestore}" >/dev/tty
	' EXIT

	# when the calling process closes its FD to the pipe (and there are no other writers), read will exit with exit code 1
	while read -r -u 3 -a params; do
		arrayFromBashTokens params
		set -- "${params[@]}"
		local msgType="$1"; shift

		# get the terminal dimensions and detect if they have changed
		cuiGetScreenDimension newTermHeight newTermWidth </dev/tty
		if [ "${newTermHeight}${newTermWidth}" != "${termHeight}${termWidth}" ]; then
			termHeight="$newTermHeight"
			termWidth="$newTermWidth"
			renderCsiCmds
		fi

		case $msgType in
			@end) break ;;

			# once both this copro and the calling process have redirected pipeToProgressHandler to make an open FD, we
			# do not need it in the filesystem anymore. The caller sends us this msg to say its ok to rm
			@rmPipe)
				rm -f "$pipeToProgressHandler" || assertError
				;;

			@hide|@2)
				hidden="1"
				printf "${csiSave}${cmdSetScrollAll}${cmdClearLines}${csiRestore}" >/dev/tty
				;;

			@show)
				printf "${csiSave}${cmdSetScrollAll}${cmdGotoUpperLeft}${cmdScrollUpLineCnt}${csiRestore}${cmdUPLineCnt}${cmdSetScrollPartial}${csiRestore}${cmdUPLineCnt}" >/dev/tty
				hidden=""
				;;

			@scopeEnd)
				local progressScope="$1"; shift
				if  [ "${linesByScope[$progressScope]}" ]; then
					local ourLineNo="${linesByScope[$progressScope]}"
					for i in ${!linesByScope[@]}; do
						if (( "${linesByScope[$i]}" > ourLineNo )); then
							(( linesByScope[$i]-- ))
						fi
					done
					unset linesByScope[$progressScope]
					renderCsiCmds

					# set the scroll region to the whole screen and scroll everything up one line (including our status lines)
					# then set the scroll region to exclude our status lines and put the cursor at the end of the scroll region
					printf "${csiSave}${CSI}0;$(( termHeight - ourLineNo ))${cSetScrollRegion}${cmdGotoUpperLeft}${cmdScrollDn1}${cmdSetScrollPartial}${csiRestore}${csiDOWN}" >/dev/tty
				fi
				;;

			@1)	local progressScope="$1"; shift
				local formattedStr="$1"; shift
				local progCmd="$1"; shift
				local parent="$1"; shift
				local label="$1"; shift
				local msg="$1"; shift
				local startTime="$1"; shift
				local lapTime="$1"; shift
				local curTime="$1"; shift
				local target="$1"; shift
				local current="$1"; shift

				[ "$hidden" ] && continue

				local now=$(date +"%s%N")
				local delay=$((now - curTime))
				# if we get more than 0.2 seconds behind, start skipping up to 19 updates at a time
				if ((delay > 100100100)) && [ "$progCmd" == "-u" ] && (( skipCount++%20 !=0 )); then
					continue
				fi


				if  [ ! "${linesByScope[$progressScope]}" ]; then
					# offset the existing status line offsets to make room for the new one
					for i in ${!linesByScope[@]}; do
						(( linesByScope[$i]++ ))
					done
					linesByScope[$progressScope]="0"
					renderCsiCmds

					# set the scroll region to the whole screen and scroll everything up one line (including our status lines)
					# then set the scroll region to exclude our status lines and put the cursor at the end of the scroll region
					printf "${csiSave}${cmdSetScrollAll}${cmdGotoUpperLeft}${cmdScrollUp1}${cmdSetScrollPartial}${csiRestore}${csiUP}" >/dev/tty
				fi

				# linesByScope has line numbers starting at 0 which is the offset from the bottom of the screen
				local cmdGotoStatusLine="${CSI}$(( termHeight - ${linesByScope[$progressScope]} ));1${cMoveAbs}"

				local statusStyle="${csiBkMagenta}"
				local termStyle="${csiDefBkColor}"

				# we use the printf / CSI construct so that the entire sequence is one API call and (hopefully) one atomic write
				# note that we dont have to change the scroll region to write outside of it but we have to be careful not
				# cause a scroll while we are outside of it b/c that resets the scroll region to the full terminal

				if [ "$target" ] && (( target != 0 )); then
					local divCol msgSection meter meterBarStart meterBarEnd meterDiv meterBar="" marker
					# divCol=$(( ${#formattedStr} +1 ))
					# divCol=$(( (divCol < termWidth*60/100) ? divCol : termWidth*60/100 ))
					divCol=$((termWidth*40/100))
					stringShorten -j left --pad -R formattedStr "$divCol"
					printf -v meter "[%2s of %-2s " "$current" "$target"
					stringShorten --pad --fill="-" -R meterBar $(( termWidth - divCol -${#meter} -1 ))
					meterDiv=$(( (${#meterBar} * current / target)-1 ))
					[ ${meterDiv} -lt 0 ] && meterDiv=0
					[ ${meterDiv} -ge ${#meterBar} ] && meterDiv=$((${#meterBar}))
					marker="#"; [ "$current" == "$target" ] && marker="-"
					meterBarStart="${meterBar:0: $meterDiv}$marker"
					meterBarEnd="${meterBar:${#meterBarStart}}"
					printf "${csiSave}${cmdGotoStatusLine}%s${meter}${statusStyle}${meterBarStart}${termStyle}${meterBarEnd}]${csiRestore}"  "$formattedStr" >/dev/tty
				else
					formattedStr="${formattedStr:0:$((termWidth-1))}"
					printf "${csiSave}${cmdGotoStatusLine}${statusStyle}%s${csiClrToEOL}${termStyle}${csiRestore}" "$formattedStr" >/dev/tty
				fi
				;;
		esac
	done;
}



progressTypeRegistry[statusline]="progressTypeStatusLineCntr"


# Library
# TermTitle progressFeedback UI Driver.
# This library implements a destination for progress feedback data. It changes the terminal windoe title to reflect the progress.
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




# usage: progressTypeTermTitleCntr start|stop|...  [parameters ...]
# this implements a progress feedback UI Driver class
function progressTypeTermTitleCntr()
{
	local cmd="$1"
	case $cmd in
		stop)
			# close the pipe to signal that the background process should end
			[ "${_progressDriver["userFeedbackFD"]}" ] && exec {_progressDriver["userFeedbackFD"]}>&-
			wait "${_progressDriver["PID"]}"
			_progressDriver["PID"]=""
			_progressDriver["userFeedbackFD"]=""
			;;

		@*)   [ "${_progressDriver["PID"]}" ] && echo "$@" >&${_progressDriver["userFeedbackFD"]} ;;

		start)
			# this driver needs to read and write the terminal
			cuiHasControllingTerminal || return 1

			_progressDriver["protocol"]="structured"

			# the block between ( and ) is a coproc to read the progress msgs
			local pipeToProgressHandler=$(mktemp -u /tmp/bgprogress-XXXXXXXXX)
			mkfifo -m 600 "$pipeToProgressHandler"
			(
				_termTitleReadProgressLoop
			) >>"$(bgtraceGetLogFile)" 2>&1 3<$pipeToProgressHandler &
			_progressDriver["PID"]=$!

			exec {_progressDriver["userFeedbackFD"]}>$pipeToProgressHandler

			# let the loop know that we have finished with pipeToProgressHandler and it can delete it now from the file system
			echo "@rmPipe" >&${_progressDriver["userFeedbackFD"]}
			;;
	esac
}

# this function is executed in the background
# stdin is the pipe that the main script writes progress msgs to.
# stdout is the terminal
function _termTitleReadProgressLoop()
{
	# build the csi cmds that we use. They depend on termHeight and dataByScope so whenever they change, we must call this
	function renderCsiCmds() {
		msgWidth=$((2*termWidth))
	}

	function makeOneBar() {
		local retVar="$1"; shift
		local width="$1"; shift
		local str="$1"; shift
		local current="$1"; shift
		local target="$1"; shift
		unescapeTokens str current target
		if [ "$target" ]; then
			local divCol msgSection meter meterBarStart meterBarEnd meterDiv meterBar="" marker
			divCol=$((width*20/100))
			stringShorten -j left --pad -R str "$divCol"
			printf -v meter "[%2s of %-2s " "$current" "$target"
			stringShorten --pad --fill="-" -R meterBar $(( width - divCol -${#meter} -1 ))
			meterDiv=$(( (${#meterBar} * current / target)-1 ))
			[ ${meterDiv} -lt 0 ] && meterDiv=0
			[ ${meterDiv} -ge ${#meterBar} ] && meterDiv=$((${#meterBar}))
			marker="#"; [ "$current" == "$target" ] && marker="-"
			meterBarStart="${meterBar:0: $meterDiv}$marker"
			meterBarEnd="${meterBar:${#meterBarStart}}"
			printf -v str "%s${meter}${meterBarStart}${meterBarEnd}]"  "$str"
		fi
		stringShorten --pad  -R str $width
		printf -v $retVar "%s" "$str"
	}

	local -A dataByScope

	local lineOffset=1 progressScope

	# init version of the $csi* vars in this coproc to reflect /dev/tty
	declare -g $(cuiRealizeFmtToTerm cuiColorTheme_sample1 </dev/tty)

	# remove the progress on exit
	builtin trap '
		cuiSetTitle "$0" >/dev/tty
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
				cuiSetTitle "$0" >/dev/tty
				;;

			@show)
				hidden=""
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
				if  [ ! "${dataByScope[$progressScope]}" ]; then
					renderCsiCmds
				fi
				marshalCmdline -v dataByScope[$progressScope]  "$formattedStr" "$current" "$target"

				local divWidth=$(( msgWidth / ${#dataByScope[@]} -5))

				local titleStr=""
				for data in "${dataByScope[@]}"; do
					local oneScope
					makeOneBar oneScope "$divWidth" ${dataByScope[$progressScope]}
					titleStr+="$oneScope     "
				done
				cuiSetTitle "$titleStr" >/dev/tty
				;;
		esac
	done;
}

progressTypeRegistry[termTitle]="progressTypeTermTitleCntr"

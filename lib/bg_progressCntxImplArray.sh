
# Library
# bg_cuiProgress.sh library context implementation plugin that uses an array variable to store the context
# This is a plugin to the bg_cuiProgress.sh library. It provides an implementation for the progress function subTask context stack.
# This implementation uses an bash array variable per asynchronous progressScope to store the context variables for each subTask.
#
# Because this implementation uses a bash array variable, its content is passed down to subshells within the bash script's process
# but subshells get a copy any the updates they make to the progress stack context will not be seen by the parent shell. This will
# not be a problem for many usecases but if it is, the TmpFile implementation do not have this limitation.
#
# Use "progressCntr loadCntxImpl Array|TmpFile" at the top of a script to specific one or the other implementation.
#
# See Also:
#    man(3) progressCntr



function _progressStackInit()
{
	progressScope=($BASHPID)
}


function _progressStackGet()
{
	local -n retArrayVar="$1"
	if [ ${#progressScope[@]} -gt 1 ]; then
		read -r -a retArrayVar <<< "${progressScope[@: -1]}"
		unescapeTokens retArrayVar[{0..2}]
	fi
}


function _progressStackPush()
{
	local -n retArrayVar="$1"
	escapeTokens retArrayVar[{0..2}]

	local fullName rest;
	[ ${#progressScope[@]} -gt 1 ] && read -r fullName rest <<<"${progressScope[@]: -1}"
	fullName+="${fullName:+/}${retArrayVar[1]}"

	retArrayVar[0]="$fullName"

	progressScope+=("${retArrayVar[*]}")

	unescapeTokens retArrayVar[{0..2}]
}

function _progressStackPop()
{
	local -n retArrayVar="$1"

	if [ ${#progressScope[@]} -gt 1 ]; then
		read -r -a retArrayVar <<<"${progressScope[@]: -1}"
		progressScope=("${progressScope[@]: 0 : ${#progressScope[@]}-1}")
		unescapeTokens retArrayVar[{0..2}]
	fi
}

function _progressStackUpdate()
{
	local -n retArrayVar="$1"; shift
	local msg="$1"; shift
	local current="$1"; shift

	if [ ${#progressScope[@]} -gt 1 ]; then
		read -r -a retArrayVar <<<"${progressScope[@]: -1}"
	fi

	escapeTokens msg

	retArrayVar[2]="$msg"
	retArrayVar[4]="${retArrayVar[5]}"  # lapTime=currentTime
	retArrayVar[5]="$(date +"%s%N")"    # currentTime=now
	retArrayVar[7]="$current"

	if [ ${#progressScope[@]} -gt 1 ]; then
		progressScope[${#progressScope[@]}-1]="${retArrayVar[*]}"
	fi

	unescapeTokens retArrayVar[{0..2}]
}

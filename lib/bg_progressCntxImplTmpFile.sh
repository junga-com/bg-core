
# Library
# bg_cuiProgress.sh library context implementation plugin that uses a tmp file to store the context
# This is a plugin to the bg_cuiProgress.sh library. It provides an implementation for the progress function subTask context stack.
# This implementation uses a tmp file per asynchronous progressScope to store the context variables for each subTask. This allows
# bash subshells to update the running status of a subTask started in a parent shell.
#
# For Example...
#    progress -s "foo" "starting" "10"
#    for ((i=0; i<10; i++)); do
#        echo $(getSomething; progress "hello" "+1")
#    progress -s "foo" "finished"
#
# In practice, its often not important to support a subshell updating the status of a parent shell and the Array implementation
# is significantly faster at the cost of not supporting it. For many usecases, the performance difference would not be significant.
#
# Use "progressCntr loadCntxImpl Array|TmpFile" at the top of a script to specific one or the other implementation.
#
# See Also:
#    man(3) progressCntr




# usage: _progressStackGet <retArrayVar>
# if progress is active for the current thread this will get the current progress message
# if not, it returns the empty string
# Output Format:
#    this function returns the progress in a structured one line string format
#    fields are separated by whitespace.
#    Fields are normalized with norm() so that they do not contain spaces and are not empty
#    field0 is a genereated parent field. This conveniently preserves the 1 based index positions used in awk
#    when its converted to a zero based base array so that the field indexes documented in the progress function
#
function _progressStackGet()
{
	local retArrayVar="$1"
	# if set, progressScope is the file that this thread is writing its progress messages to
	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(awk '
			{parent=parent sep $1; sep="/"}
			END {
				print parent" "$0
			}
		' "$progressScope")
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

function _progressStackInit()
{
	/bin/mkdir -p "/tmp/bg-progress-$USER"
	#2020-11 using declare -gx in the assignment statement caused the assignment not to work. why? It seems that when the var is an
	# ENV var coming into the process, the -g causes it to fail. The idiom is 'progressScope= someCommand &' # declare -gx progressScope
	progressScope="/tmp/bg-progress-$USER/$BASHPID"
	touch "$progressScope"
	bgtrap -n progress-$BASHPID 'rm $progressScope &>/dev/null' EXIT
}


function _progressStackPush()
{
	local retArrayVar="$1"
	local out
	local i; for ((i=1; i<=7; i++)); do
		local value; varDeRef $retArrayVar[$i] value
		escapeTokens value
		out+="$value "
	done

	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(
			bgawk -i -n -v record="$out" '
				{print $0}
				{parent=parent sep $1; sep="/"}
				END {
					print record
					print (parent? parent:"--")" "record >> "/dev/fd/3"
				}
			' "$progressScope"
		)
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

function _progressStackPop()
{
	local retArrayVar="$1"
	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(
			bgawk -i -n '
				on {print last}
				{last=$0; on="1"}
				{parent=parent sep $1; sep="/"}
				END {
					print parent" "$0 >> "/dev/fd/3"
				}
			' "$progressScope"
		)
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

function _progressStackUpdate()
{
	local retArrayVar="$1"; shift
	local msg="$1"; shift
	local current="$1"; shift
	escapeTokens msg current
	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(
			bgawk -i -n \
				-v msg="$msg" \
				-v current="$current" '
				on {print last}
				{last=$0; on="1"}
				{parent=parent sep $1; sep="/"}
				END {
					$2=msg
					$4=$5    # laptime
					$5="'"$(date +"%s%N")"'"
					$7=current

					print $0
					print parent" "$0 >> "/dev/fd/3"
				}
			' "$progressScope"
		)
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

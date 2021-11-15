
# usage: bgawk [-i] [-n] [-d] [-c] [-C] [-S] [-v <varName>=<value>] [-F <delim>] <awkScript> <file> [ ... <fileN>]
# this function combines some common behavior of sed and awk. The -i and -n options have the same
# semantics as in sed which means you can use awk syntax to do stream editting. By default, any line
# that your script does not modify will be passed through to the output unchanged. Any changed you make
# to $0, will be reflected in the output.
#
# outputOff variable:
#    if your script sets outputOff="1", the current line will not be outputed. It only effects the current
#    line so you need to set it on every line you what to suppress. {outputOff="1"} would suppress all the
#    lines so that your script will be solely responsible for the output. -n does the same.  If your code
#    prints a line that is meant to replace the current line, set this variable. The other way to change
#    the line outputed is to simply change the $0 variable and allow it to be automatically printed. i.e.
#    {$0="hello"} would replace the current line with "hello".
# insertLineBefore(newLine), insertLineAfter(newLine):
#    These functions are available in the awkScript to add lines to the output in addition to the current
#    input line.
# deleteLine()
#    cause the current line not to be included in the output. synonym for setting outputOff="1"
#
# <file>
#    the input file. If not specified, use stdin.
# Options:
# -q : quietFlag. don't assert an error if the script returns non zero. This does not apply when -i is specified.
#      When -i is not specified, you only need this if your script must return 1 and you want to process that result.
#      If your script returns codes >1, they will be passed back to you anyway. awk uses 1 to indicate a syntax error
# -i : Note that awk uses -i as the short form of --include. you must use the long form for that option. bgawk changes -i meaning.
#      behaves like sed's -i. It causes the file to be changed in place. It makes a temp file and then
#      overwrites the <file>. If the awk exits with a non-zero code, it will not overwrite the original file
#      The script needs to exit 0 for -i to be sucessful
#      Anything written to stdout will be become the file contents. See -n.
#      Anything written to "/dev/fd/3" will be redircted to the calling processe's stdout so that status
#      can be captured or progress can be displayed.
#      If multiple files are specified, each is read and written to separately
#      return true(0) if the file was modified or false(1) if it was not
# --checkOnly : when -i is specified, do not change file. return true(0) if the file would be modified
#       or false(1) if it would not be. no effect without -i
# -n : behaves like sed's -n. unlike plain awk, this command prints each line by default. -n suppresses that. you can suppress
#      just some lines by having your script call deleteLine() while on any line that you want to suppress
# -d : debug. When specified with the -i option, it will not overwrite the configFile and it will launch meld
#      to compare the confFile with the modified tempFile. Without the -i it will print the final script to
#      stderr instead of running it
# -c : treat the input file as an awkData file and allow referencing columns in the script as '$<colName>'
#      The input file must be specified as opposed to using stdin. The column names are in the header of the
#      file and '$<colName>' will be replaced with '$n' where n is the position of the named column.
# -C : similar to -c, enables referring to columns by name. But instead of reading cols from the a file and
#      using $<colName>, this expects the first input row to be the column names and in the script each col's
#      value  is available for each row as row["<clolName"]
# -B : strip all comment and blank lines leaving only content lines
# -S : strip comment and blank lines like -B but leave one blank line in the place of each run of comment and
#      blanks. This produces a compact output that retains the notion of grouped content
# -v <varName>=<value> : set the variable for the awk script to use
# -F <fs> : passthru option to awk
# --isAlreadySet            : See exit code section. (check mode, true if would be no change)
# --wouldChangeFile         : See exit code section. (check mode, true if file needs changing)
# --returnTrueIfAlreadySet  : See exit code section. (normal mode, true if file was not changed)
# --returnTrueIfChanged     : See exit code section. (normal mode, true if file changed)
# --returnTrueIfSuccessful  :  See exit code section. (normal mode. always true if function returns)
#
# Exit Codes:
#   in filter mode (without -i),
#     <n> : the exit code is the exit code that awk returned when invoked to run the <script>
#      1  : awk uses exit code 1 to indicate a script syntax error but it could also be that the script
#           called exit(1). Scripts written for use with bgawk should not exit(1) to avoid this confusion.
#           without -q, when awk return 1, assertError is call to end the process (or sub shell)
#           If your want to process the exit code 1 case, use -q
#
#   in inplace (-i) mode,
#     0 (true)   : the the file was modified or would be modified (in check mode)
#     1 (false)  : the file does not need to be changed as a result of this script
#     assertError: the awk script returned non-zero exit code. We assume that if the exit code was 1 its
#                  awk reporting a syntax error in the script but we can not distinguish between that and
#                  the script returning 1. A script used in -i mode must return 0 or an assertError will
#                  be thrown and the file will not be considered for change
# Note that these options explicitly state what condition will return true/false and whether the operation will be
# performed if needed or only checked. This overrides the default exit code meanings
#    --isAlreadySet            : check only (never change the file)  : true(0) means no change needed
#    --wouldChangeFile         : check only (never change the file)  : true(0) means file would change
#    --returnTrueIfAlreadySet  : change the file if needed           : true(0) means no change needed
#    --returnTrueIfChanged     : change the file if needed           : true(0) means file did change
#    --returnTrueIfSuccessful  :  change the file if needed : always return true unless there is an error.
#                                 this changes the meaning of the exit code so that it does not depend on
#                                 whether the file was or would be changed
function bgawk()
{
	local file awkScript inplace inplaceSort quietFlag debugFlag outOffFlag cols1Flag cols2Flag outputDefaultOff
	local useCols checkOnlyFlag stripCommentsFlag passThruOpts=("--re-interval") returnTrueIfChanged="1" returnTrueIfSuccessful
	while [ $# -gt 0 ]; do case $1 in
		-i)  inplace="-i" ;;
		--sort) inplaceSort="sort" ;;
		-q)  quietFlag="-q" ;;
		-d)  debugFlag="-d" ;;
		-n)  outOffFlag="-n"; outputDefaultOff="{outputOff="1"}" ;;
		-c)  cols1Flag="-c"; useCols="1" ;;
		-C)  cols2Flag="-C"; useCols="2" ;;
		-S)  stripCommentsFlag="-S" ;;
		-B)  stripCommentsFlag="-B" ;;
		-v*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		-F*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		--include*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		--checkOnly|--check)      checkOnlyFlag="--checkOnly"; returnTrueIfChanged="1" ;;
		--wouldChangeFile)        checkOnlyFlag="--checkOnly"; returnTrueIfChanged="1" ;;
		--isAlreadySet)           checkOnlyFlag="--checkOnly"; returnTrueIfChanged=""   ;;
		--returnTrueIfChanged)                                 returnTrueIfChanged="1" ;;
		--returnTrueIfAlreadySet)                              returnTrueIfChanged=""  ;;
		--returnTrueIfSuccessful) returnTrueIfSuccessful="1" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# it is useful sometimes to run this command without a script (like with -S) so if the user forgot to include '' we
	# make it ok
	if [ $# -ne 1 ] || [ ! -f "$1" ]; then
		awkScript="$1"; [ $# -gt 0 ] && shift
	fi


	# files may or may not contain the files list specified. if inplace is set it will because we have to process
	# each file separately, creating a new temp file, etc...  Otherwise, its set to '-' to indicate that we can invoke
	# awk once with what ever files were passed to us. This might be no files in which case awk will read from stdin.
	local files="<>#"; [ "$inplace$cols1Flag" ] && files=("$@")
	local inplaceExitCode=0
	for file in "${files[@]}"; do
		# this is the case where we want one pass using the 0, 1, or multiple files passed in on the command line
		[ "$file" == "<>#" ] && file=("$@")

		if [ "$useCols" == "1" ]; then
			assertNotEmpty file "an input file must be specified when the -c (use awkData colunms) option it specified"
			assertFileExists "$file"
			local cols="$(awkData_getColumns "$file")"
			assertNotEmpty cols "the input file '$file' does not have a awkData header with column names"
			local col colNum=1
			for col in $cols; do
				awkScript="$(echo "$awkScript" | sed 's/$'"$col"'\b/\$'"$colNum"'/g')"
				(( colNum++ ))
			done
		fi

		if [ "$inplace" ]; then
			assertNotEmpty file "an input file must be specified when the -i inplace option it specified"
			local tmpFile=$(mktemp --tmpdir "bgawk-${file##*/}.XXXXXXXXXX")
			if [ ! -s "$file" ]; then
				fsTouch "$file"
			fi
		fi

		local script='@include "bg_core.awk"'$'\n'
		[ "$useCols" == "2" ] && script="$script"'
			NR==1 {for (i=1; i<=NF; i++) colNames[i]=$i}
			NR>1 {for (i=1; i<=NF; i++) {if (colNames[i]) {row[colNames[i]]=$i; }}}
		'

		[ "$stripCommentsFlag" == "-S" ] && script="$script"'
			/^[[:space:]]*#/ {if (blankLineCount++ <= 0) print "" ; next}
			/^[[:space:]]*$/ {if (blankLineCount++ <= 0) print "" ; next}
			/^[[:space:]]*[^#[:space:]]/ {blankLineCount=0}
		'

		[ "$stripCommentsFlag" == "-B" ] && script="$script"'
			/^[[:space:]]*#/ {next}
			/^[[:space:]]*$/ {next}
		'

		script="$script"'
			function deleteLine() {
				outputOff="1"
			}
			function insertLineAfter(newLine) {
				print $0
				print newLine
				outputOff="1"
			}
			function insertLineBefore(newLine) {
				print newLine
			}
			'"$outputDefaultOff"'
			'"$awkScript"'

			! outputOff {print $0}
			{outputOff=""}
		'

		# if [ "$debugFlag" ] && [ ! "$inplace" ]; then echo "awk "${passThruOpts[@]}" \"$script\" ${file[@]}" >&2
		# elif [ "$file" ]    && [ "$inplace" ];   then      awk "${passThruOpts[@]}" "$script" "${file[@]}" 3>&1 > $tmpFile
		# elif [ "$file" ]    && [ ! "$inplace" ]; then      awk "${passThruOpts[@]}" "$script" "${file[@]}"
		# elif [ ! "$file" ]  && [ "$inplace" ];   then      awk "${passThruOpts[@]}" "$script" $tmpFile 3>&1
		# elif [ ! "$file" ]  && [ ! "$inplace" ]; then      awk "${passThruOpts[@]}" "$script"
		# fi

		# debugFlag when inplace(-i) is not specified means to print the awk command to stderr.
		# when inplace(-i) is specified, we handle debugFlag below in the tmpFile processing
		if [ "$debugFlag" ] && [ ! "$inplace" ]; then
			echo "awk "${passThruOpts[@]}" \"$script\" ${file[@]}" >&2
			return 1
		fi

		# determine if we need sudo to read or write an input/output file
		local sudoOpts
		[ ${#file[@]} -gt 0 ] && if [ "$inplace" ]; then
			bgsudo --makeOpts sudoOpts "${file[@]/#/-w}"
		else
			bgsudo --makeOpts sudoOpts "${file[@]/#/-r}"
		fi

		# if we need sudo and the script writes to /dev/fd/3 to return a status while stdout is being used to write to an in-place
		# file, fix it up b/c sudo will close all fd above 2
		local resultsFile
		if [[ ! "${sudoOpts[*]}" =~ skip ]] && [[ "$script" =~ /dev/fd/3 ]]; then
			resultsFile="$(mktemp -u)"
			bgsudo -O sudoOpts touch "$resultsFile"
			script="${script//\/dev\/fd\/3/$resultsFile}"
		fi

		# this case enumerates the 4 possible combinations of
		#    1) where the input comes from (stdin vs input file)
		#    2) where the output goes to (inplace vs stdout).
		# TODO: if the user does not have permission to read an input file, sudo is used to invoke awk, but the default sudo behavior
		#       is to close all file descriptors above 2 so if the script writes feedback on /dev/fd/3, (as iniParamSet does), it fails
		#       The 'sudo -C 4 ...' option would fix this but it requires that sudo be configured with the closefrom_override and I do
		#       not know what exploit that is meant to protect against.
		#       Another solution could be to replace "/dev/fd/3" in the script with "/tmp/<tempfile>" and then cat "/tmp/<tempfile>" >&3
		#       after awk runs.
		case ${file:+fileExists}:${inplace:+inplace} in
			fileExists:inplace) bgsudo -O sudoOpts gawk "${passThruOpts[@]}" "$script" "${file[@]}" 3>&1 | ${inplaceSort:-cat} > "$tmpFile" ;;
			fileExists:)        bgsudo -O sudoOpts gawk "${passThruOpts[@]}" "$script" "${file[@]}"                   ;;
			          :inplace) gawk "${passThruOpts[@]}" "$script"              3>&1 > "$tmpFile" ;;
			          :)        gawk "${passThruOpts[@]}" "$script"                                ;;
		esac; local exitCode=$?

		# if a temp resultsFile was created, process it now
		if [ "$resultsFile" ]; then
			cat "$resultsFile"
			bgsudo -O sudoOpts rm -f "$resultsFile"
		fi

		# if the awk command returns non-zero, we will not proceed with the inplace processing below
		# and we might assert an error depending on the -q option
		if [ $exitCode -gt 0 ] || [ ! "$inplace" ]; then
			local scriptFile="$(mktemp)"; echo "$script" > "$scriptFile"
			local output="$tmpFile"
			[ "$inplace" ] && assertError -e "$exitCode" -v file -v tmpFile -v scriptFile -v exitCode -f output "the awk script returned a non-zero exit code in inplace edit mode (-i). Exit code 1 may mean that the script had a syntax error "
			[ ! "$quietFlag" ] && [ $exitCode -eq 1 ] && assertError -e "$exitCode"  -v scriptFile -v exitCode "likely error in awk script"
			rm "$scriptFile"
			[ "$tmpFile" ] && rm "$tmpFile"
			return $exitCode
		fi

		# process the tmpFile that the inplace options caused to be created.
		if [ "$inplace" ]; then

			# compare the original and and new files (debug mode)
			if [ "$debugFlag" ]; then
				bgsudo -O sudoOpts $(getUserCmpApp) "$file"  "$tmpFile"
				echo "tmpFile= '$tmpFile'  (modified version of '$file')"

			# if files are different, overwrite/create the original with the new
			elif fsIsDifferent "$tmpFile" "$file"; then
				if [ ! "$checkOnlyFlag" ]; then
					cat "$tmpFile" | pipeToFile "$file" || assertError
				fi
				rm "$tmpFile"
				[ ! "$returnTrueIfSuccessful" ] && [ ! "$returnTrueIfChanged" ] && inplaceExitCode=1

			# do nothing. original and new file are the same.
			else
				rm "$tmpFile"
				[ ! "$returnTrueIfSuccessful" ] && [ "$returnTrueIfChanged" ] && inplaceExitCode=1
			fi
		fi
	done
	return $inplaceExitCode
}


# usage: bgsed [-p] [--prompt=<msg>] [<sedOptions>] [<file>]
# This is a wrapper over the linux utility sed. It adds several features mostly around how -i works. It strives to be completely
# backward compatible with sed. Initially, one incompatibility is that sed allows operating on multiple inplace files but bgsed does not.
#
# Enhancements to Inplace:
#   * it will use sudo if the user does not have permission to write to the file.
#   * it will create the inplace file if it does not exist and empty files are given one empty line (so that scripts have a line to operate on)
#   * able to inplace edit writable files in readonly folders without resorting to sudo. (e.g. adm can write to a file in /etc/)
#
# Enhancements to non-inplace:
#   * reading from a file that does not exist is same as reading an empty file
#   * if no files have any lines, an empty line is streamed because many sed scripts require at least one line to operate on.
#
#
# Params:
#     <file> : the file to operate on. default is to read input from stdin.
# Options:
#     -p   : parent folder. if the parent folder does not exist, create it.
#    --prompt=<msg>  : if sudo is required to perform the operation and the user is prompted to enter their password, <msg> provides
#                      context to what operation they are entering a password to complete.
#    -q : quiet. If sed exits with a non-zero code, an assertError will be thrown unless -q is specified in which case it will exit
#         with that code
#     <sedOptionsAndParameters> : any option that sed supports can be specified and will be passed through to sed.
function bgsed()
{
	local noDashI mkdirFlag sedOpts inplaceFlag bakupExt sudoPrompt quietFlag script scripts firstCanBeScript="1"
	while [ $# -gt 0 ]; do case $1 in
		-p|--makeParent) mkdirFlag="-p" ;;
		--prompt*)  bgOptionGetOpt opt: sudoPrompt "$@" && shift ;;
		-q) quietFlag="-q" ;;

		# we capture the -i option and pass it through
		# note special processing of -i|--in-place. If they appear alone, they have no argument, but they can have an arg in one token
		-i|--in-place)           sedOpts+=(-i); inplaceFlag="-i" ;;
		-i*|--in-place*)
			bgOptionGetOpt val: bakupExt "$@" && shift
			inplaceFlag="-i"
			sedOpts+=(-i${bakupExt})
			;;

		# the rest are sed pass through options
		-n|--quiet|--silent)     bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		--debug)                 bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		--follow-symlinks)       bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		--posix)                 bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		-E|-r|--regexp-extended) bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		-s|--separate)           bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		--sandbox)               bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		-u|--unbuffered)         bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		-z|--null-data)          bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		--help)                  bgOptionGetOpt opt  sedOpts "$@" && shift ;;
		--version)               bgOptionGetOpt opt  sedOpts "$@" && shift ;;

		# note that for sed, the short versions must have the argument in a separate token and the long version must have it in one token
		-e|--expression=*)
			bgOptionGetOpt val: script "$@" && shift
			sedOpts+=(-e "$script")
			scripts+=("$script")
			firstCanBeScript=""
			;;
		-f|--file=*)              bgOptionGetOpt opt: sedOpts "$@" && shift; firstCanBeScript="" ;;
		-l|--line-length=*)       bgOptionGetOpt opt: sedOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	if [ "$firstCanBeScript" ]; then
		sedOpts+=(-e "$1")
		scripts+=("$1")
		shift
	fi
	local inputFiles=("$@")

	local sudoOpts; bgsudo --makeOpts sudoOpts "${sudoPrompt[@]}"

	# if a file is to be operated on, we need at least read access
	local inputFile; for inputFile in "${inputFiles[@]}"; do
		[ "$inputFile" ] && bgsudo --makeOpts sudoOpts  -r "$inputFile"
	done

	if [ "$inplaceFlag" ]; then
		# TODO: sed allows operating on multiple inplace files. the current implementation of bgsed does not. we would have to iterate
		#       the files and either invoke sed separately or (better) sort the files into groups that could be done in the same sed run
		[  ${#inputFiles[@]} -ne 1 ] && assertError -v inputFiles "exactly one filename must be provided when the inplace option (-i) is specified to sed"
		inputFile="${inputFiles[0]}"

		# since we are changing it in-place, we need write access to the file
		bgsudo --makeOpts sudoOpts -w "$inputFile"

		# create the file if needed, if mkdirFlag was not specified, this might throw an assertError
		if [ ! -e "$inputFile" ]; then
			fsTouch $mkdirFlag "${sudoPrompt[@]}" "$inputFile"
			# # adjust group ownership?
			# [ ! -f "$inputFile" ] && grep -q "adm:" /etc/group &>/dev/null && which fsTouch &>/dev/null && fsTouch -u adm --perm="... rw. ..." "$inputFile"
		fi

		# we need to be able to write to the parent folder as well to use "sed -i ..."
		bgsudo -OsudoOpts test -w "${inputFile%/*}" || noDashI="noDashI"

		# make sure the file has at least one line because sed scripts often do not work unless there is at least one line
		bgsudo -OsudoOpts test -s "${inputFile}" || echo | bgsudo -OsudoOpts tee "$inputFile" >/dev/null
	fi

	#bgtraceVars sedOpts inputFiles sudoOpts

	# this case is when inplace is set and we have permission to write to the file, but not the parent
	if [ "$noDashI" ]; then
		#bgtrace "path1"
		local tmpFile; fsMakeTemp tmpFile
		bgsudo -OsudoOpts cat "$inputFile" > "$tmpFile"
		sed "${sedOpts[@]}" "$tmpFile"; local result=$?
		cat "$tmpFile" | bgsudo -OsudoOpts tee "$inputFile" >/dev/null
		fsMakeTemp --release tmpFile
		# TODO: if a backup was made and the backup file exists next to <inifile> and we have permission to write to it, cp it into place.
		# TODO: if backup ext was specified but we cant write to it, throw an error before changing the <inifile>

	# if inplace, we know at this point that there is exactly one inputFile and its ok to use the -i option
	elif [ "$inplaceFlag" ]; then
		#bgtrace "path2  $(cmdline -q bgsudo -OsudoOpts sed "${sedOpts[@]}" "${inputFiles[@]}")"
		bgsudo -OsudoOpts sed "${sedOpts[@]}" "${inputFiles[@]}"; local result=$?

	# running as a stdin/out filter
	elif [  ${#inputFiles[@]} -eq 0 ]; then
		#bgtrace "path3"
		sed "${sedOpts[@]}"; local result=$?

	# reading from one or more files
	else
		#bgtrace "path4"
		# we dont consider it an error to read from an non-existent file -- same as an empty file
		local i; for i in "${!inputFiles[@]}"; do
			bgsudo -OsudoOpts test -s "${inputFiles[i]}" || unset inputFiles[$i]
		done

		# if no files had any lines, stream an empty line instead
		if [ ${#inputFiles[@]} -eq 0 ]; then
			echo | sed "${sedOpts[@]}"; local result=$?
		else
			bgsudo -OsudoOpts sed "${sedOpts[@]}" "${inputFiles[@]}"; local result=$?
		fi
	fi

	[ ! "$quietFlag" ] && [ ${result:-0} -gt 0 ] && assertError -v scripts "sed exitted with a non-zero code"

	return $result
}

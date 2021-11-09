
# Library bg_coreFiles.sh
#######################################################################################################################################
### File and File System Library

#######################################################################################################################################
### File Functions

# usage: fsIsEmpty <fileOrFolder>
# returns 0(true) if a file is 0 length or a folder contains no entries or if the path does not exist
# Params:
#   <fileOrFolder> : any filesystem path
function fsIsEmpty()
{
	local fileOrFolder="$1"
	[ ! -e "$fileOrFolder" ] || [ "$(find "$fileOrFolder" -maxdepth 0 -empty)" ]
}

# usage: fsMakeTemp [-d] [-u] [-k] [--will-not-release] <fileNameVar> [<nameTemplate>]
# usage: fsMakeTemp --release <fileNameVar>
# This is a wrapper over mktemp that provided additional features
#      * Atomatic Remove of Temp Files.
#      * the default <nameTemplate> is bgmktemp.XXXXXXXXXX
#      * BGMKTEMP_TRACE_FILE Feature to help identify what is creating temp files
#      * future feature: this function can automatically set the template and tpdir based on security
#         context and script class.
# Automatic Removal of Temp Files:
#    This function relies on bgtrap so that it can reliably set multiple EXIT trap handlers that coexist
#    with other library functions or script authors who might also set EXIT trap handlers. See bgtrap.
#
#    /bin.mktemp enforces that templates have to be random so this function can not be tricked into
#    removing other files. All file with the generated root will be removed not just the base file or
#    folder. Any folders with this root will be completely removed.
#
#    As a conservative measure, tmp files will only be removed if they are in the /tmp/
#    folder or a folder that contains .bglocal/ which is a common pattern for transient storage at
#    different scope by bg-lib library features.
#
#    -k (--keep) is meant to be a debugging tool so that a script author can examine the contents of
#    the temp file(s) after the script runs. The name is written at the end of the script in an EXIT
#    handler.
#
#    --realease is optional but good coding practice to reduce resource usage to its minum scope and
#    to reduce the expose of the temp file data to prying eyes. Typically --release should be called
#    in the same function that creates the tempfile while <fileNameVar> is still in scope.
#    If BGMKTEMP_ERROR_UNRELEASED is set or bgtraceIsActive, if any bgmktemp EXIT handlers are left
#    an error will be asserted to remind the script author to call --release.
# BGENV: BGMKTEMP_ERROR_UNRELEASED: when set to non-empty, bgmktemp/fsMakeTemp assert an error if any temp files are not released
#
# BGMKTEMP_TRACE_FILE Feature:
#    When this ENV var is set or bgtraceIsActive, a log file is written to in /tmp/bgmktemp.log
#    This is meant to help identify what is creating specific temp files. It should be less likely that
#    temp files created with this function do not get removed but its possible. Another common issue
#    with temp files is that a pentester determines that a script is writing inappropriate sensitive
#    information. This can help the pentester determine the source.
# BGENV: BGMKTEMP_TRACE_FILE: when set to non-empty, bgmktemp/fsMakeTemp will log the script lines that make tmp files in /tmp/bgmktemp.log
#
# Params:
#    <fileNameVar>  : the name of a variable in the callers scope that will be set with the value of
#          the generated temp filename.
#    <nameTemplate> : the template for the tmp file name. default is bgmktemp.XXXXXXXXXX. See man mktemp
# Options:
#   Posix options
#   -d|--directory : make a directory
#   -u|--dry-run   : dont make any fs object, just return the name
#   -q|--quiet     : quiet. its already pretty quiet.
#   --suffix <suffix>    : a suffix that is added to <nameTemplate> if <nameTemplate> does not end in X
#   -p|--tmpdir <tmpdir> : the folder to make <nameTemplate> relative to unless <nameTemplate> is absolute
#   Extensions to posix mktemp
#   -k|--keep : keep the tmp file/folder. Instead of deleting the file its name is written to the tty
#   --release : remove the tempfile and trap. default is that a trap is set to remove the file but
#         if its called with this and the same <fileNameVar> it will perform the cleanup before EXIT
#         and remove the trap. If -k was specified in the original call, --release will be ignored.
#  --will-not-release|--auto : this informs the function that is is expected that the code will rely on the
#         exit trap to remove the file instead of calling --release. Without this, the exit trap will
#         print a warning about the code not calling --release
# See Also:
#    mktemp
#    bgtrap
function bgmktemp() { fsMakeTemp --bumpCallerStackFrame "$@"; }
function fsMakeTemp()
{
	local keepFlag mode="create" suffix tmpdir="/tmp" passThruOpts willNotReleaseFlag fileNameVar callerStackFrame=1
	while [ $# -gt 0 ]; do case $1 in
		--bumpCallerStackFrame) ((callerStackFrame++)) ;;
		-d|--directory) bgOptionGetOpt opt passThruOpts "$@" && shift ;;
		-u|--dry-run)   bgOptionGetOpt opt passThruOpts "$@" && shift ;;
		--suffix*)      bgOptionGetOpt val: suffix "$@" && shift ;;
		-p*|--tmpdir*)  bgOptionGetOpt val: tmpdir "$@" && shift ;;
		-k) keepFlag="-k" ;;
		--release) mode="release" ;;
		--releaseInternal) mode="releaseInternal" ;;
		--will-not-release|--auto) willNotReleaseFlag="--will-not-release" ;;
		*)  bgOptionsEndLoop --firstParam fileNameVar "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateValue="${1:-bgmktemp.XXXXXXXXXX}"

	[ "$suffix" ] && passThruOpts+=("--suffix=$suffix")
	[ "$tmpdir" ] && passThruOpts+=("--tmpdir=$tmpdir")

	if [ "$mode" == "create" ]; then
		local fileNameValue="$(command mktemp "${passThruOpts[@]}" $templateValue)"
		local caller trapHandler
		if [ "$keepFlag" ] || [ "${BGMKTEMP_TRACE_FILE+exists}" ] || [ "$BGMKTEMP_ERROR_UNRELEASED+exists" ] || bgtraceIsActive; then
			local -A stackFrame=(); bgStackFrameGet "${callerStackFrame:-1}" stackFrame
			caller="${stackFrame[frmSummary]}"
			trapHandler='
				# bgmktemp '"${keepFlag}"' '"${passThruOpts[@]}"' '"${fileNameVar}"'
				# created at: '"$caller"''
		fi

		if [ ! "$keepFlag" ]; then
			trapHandler+='
				fsMakeTemp --releaseInternal '"$willNotReleaseFlag"' "'$fileNameValue'"
			'
		else
			trapHandler+='
				[ -e "'"$fileNameValue"'" ] && echo "'"${caller} fsMakeTemp -k left $fileNameValue to be examined"'"
			'
		fi

		bgtrap -n "$fileNameValue" "$trapHandler" EXIT

		if [ "${BGMKTEMP_TRACE_FILE+exists}" ] || bgtraceIsActive ; then
			touch /tmp/bgmktemp.log
			chmod 666 /tmp/bgmktemp.log
			printf "%-20s : script=%-28s  varname=%-15s caller=%s\n" "$fileNameValue" "${0##*/} ($$)" "$fileNameVar" "$caller" >> /tmp/bgmktemp.log
		fi

		returnValue "$fileNameValue" "$fileNameVar"

	# the following code block is executed later when the user or trap handler calls us again with --release*
	else
		# if the user calls --release, we need to deref the fileNameVar but the trap call uses the temp
		# filename directly since it might be invoked after the caller's fileNameVar has gone out of scope
		if [ "$mode" == "releaseInternal" ] || bgtrap -e -n "$fileNameVar" EXIT; then
			local fileNameValue="$fileNameVar"
		else
			local fileNameValue="${!fileNameVar}"
		fi

		local prevKeepFlag
		local trapHandler="$(bgtrap -g -n "$fileNameValue"  EXIT 2>/dev/null)"
		[[ "$trapHandler" =~ bgmktemp.*-k  ]] && prevKeepFlag="1"

		if [ ! "$prevKeepFlag" ]; then
			# remove the trap
			bgtrap -r -n "$fileNameValue"  EXIT || assertError -c -v fileNameVar -v fileNameValue -V "$(trap -p EXIT)" "the trap previously set to remove the temp filecould not be removed."

			# validate the fileNameValue before we start deleting things..
			[[ "$fileNameValue" =~ (^/tmp/...)|([.]bglocal/) ]] || assertError -v fileNameVar -v fileNameValue "refusing to delete temp filename that does not comply with naming policy"

			# and clean up the temp files...
			# TODO: decide if its safe to add an * to the end of this rm -rf or what we would have to do to safely rm
			#       other temp files created by adding extensions to the base name. Some bg-lib code already does that
			#       but maybe they should be refactored to create a temp directory to put multiple files
			[ ! "$keepFlag" ] && rm -rf "$fileNameValue"

			if [ ! "$assertError_EndingScript" ] && [ "$mode" == "releaseInternal" ] && [ ! "$willNotReleaseFlag" ] && { [ "$BGMKTEMP_ERROR_UNRELEASED+exists" ] || bgtraceIsActive; } && [ "$bgBASH_tryStackAction" != "exitOneShell" ]; then
				(assertError --continue -v fileNameValue -v trapHandler "a temp file created with bgmktemp was not released before the end of the script." &>>$_bgtraceFile)
			fi
		fi
	fi
}


# usage: fsIsNewer <filename1> <filename2>
# this is a wrapper over the [ <filename1> -nt <filename2> ] syntax.
# Either file can be non-existent or an empty filename. Returns 0(true) only if <filename1> exists and either has a newer timestamp
# than <filename2> or <filename2> does not exist.
function fsIsNewer()
{
	[ "$1" -nt "$2" ]
}

# usage: fsGetNewerDeps [-A|--array=<varName>] <referenceFilename> <depFilename1> [.. <depFilenameN>]
#        if fsGetNewerDeps <referenceFilename> <depFilename1> [.. <depFilenameN>] >/dev/null; ...
# Determine if any of the dependent files of <referenceFilename> are newer than <referenceFilename>.
# This function returns true/false in its exit code and the list of newer files on stdout or in <varName>. If you just want to test
# the exit code, redirect stdout to null
# Options:
#    -A|--retArray=<varName> : return the list of <depFilenameN> that are newer than <referenceFilename> in this array var name
# Exit Code:
#    0(true)  : yes, at least one <depFilenameN> is newer
#    1(false) : no, <referenceFilename> is newer than any of the <depFilenameN>
function fsGetNewerDeps()
{
	local retArrayOpt
	while [ $# -gt 0 ]; do case $1 in
		-R|--string*) bgOptionGetOpt opt: retArrayOpt "$@" && shift ;;
		-A|--array*)  bgOptionGetOpt opt: retArrayOpt "$@" && shift ;;
		-S|--set*)    bgOptionGetOpt opt: retArrayOpt "$@" && shift ;;
		-a|--append)  bgOptionGetOpt opt: retArrayOpt "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local refFile="$1"; shift
	if [ ! -e "$refFile" ]; then
		varOutput "${retArrayOpt[@]}" "$@"
		return 0
	fi
	bgfind "${retArrayOpt[@]}" "${@:-NOTHING}" -newer "$refFile"
}

# usage: fsIsDifferent [<diffIgnoreOpt>] <file1> <file2>
# returns true(0) if <file1> <file2> do not have the same contents and false(1) if they do
# Options:
#   These options are passed through to diff. see man diff for details
#	-i, --ignore-case
#	-E, --ignore-tab-expansion
#	-Z, --ignore-trailing-space
#	-b, --ignore-space-change
#	-w, --ignore-all-space
#	-B, --ignore-blank-lines
#	-I, --ignore-matching-lines=RE
function fsIsDifferent()
{
	local diffOpts
	while [[ "$1" =~ ^- ]]; do case $1 in
		-i|-E|-Z|-b|-w|-B)
			diffOpts+=($1)
			;;
		-I) diffOpts+=($1); shift
			diffOpts+=($1)
			;;
	esac; shift; done
	local file1="$1"
	local file2="$2"


	# both do not exist is being the same
	[ ! -f "$file1" ] && [ ! -f "$file2" ] && return 1

	# if not both exist, they can not be the same
	[ -f "$file1" ] && [ -f "$file2" ] || return 0

	# both exist so use diff to tell
	! bgsudo -r "$file1" -r "$file2" diff -q "${diffOpts[@]}" "$file1" "$file2" >/dev/null
}


# usage: fsGetAge [-S|-M|-H|-D|-L<p>] [-d <fromTime>] <path>
# usage: if [ $(fsGetAge "./filename") -gt 300 ; then ...
# return the number of time period since the file was last modified.
# The default timeperiod units is seconds but that can be changed with an option
# If the file does not exist, it returns the age as if the file had been created at the epoch.
# This allows consistent terse testing to see if a file needs to be updated -- either creating
# the file or modifying it with new data.
# Params:
#    <path> : the path to a file or folder. If the path does not exist, the modification time is
#             taken as (1970-01-01:00:00:00)
# Options:
#    -S  : (default) return the result in seconds
#    -M  : return the result in minutes, rounded down
#    -H  : return the result in hours, rounded down
#    -D  : return the result in days, rounded down
#    -L<p> : return the result in long format with precision <p>. <p> can be 1,2,3,4
#          Long format is like "1d:2m:43m:12s". Leading terms that are 0 are not included
#          <p> specifies the maximum number of terms to include.
#    -d <fromTime> : (default is 'now') The timestamp in seconds from the epoch that the age will
#          be computed from. For example if you specify a timestamp from another file, this function
#          will return how much older <path> is than that file. If the file is younger(newer) the
#          returned value will be negative.
function fsGetAge()
{
	local units="seconds" seconds precision fromTime
	while [[ "$1" =~ ^- ]]; do case $1 in
		-S) units="seconds" ;;
		-M) units="minutes" ;;
		-H) units="hours" ;;
		-D) units="days" ;;
		-L*) units="long"
			precision="$(bgetopt "$@")" && shift
			;;
		-d) fromTime="$(bgetopt "$@")" && shift ;;
	esac; shift; done
	local path="$1"

	fromTime="${fromTime:-$(date +"%s")}"

	if [ ! -e "$path" ]; then
		seconds=$(( fromTime ))
	else
		seconds=$(( fromTime - $(stat -c"%Y" "$path") ))
	fi

	case $units in
		seconds) echo "$seconds" ;;
		minutes) echo $(( seconds /    60 )) ;;
		hours)   echo $(( seconds /  3600 )) ;;
		days)    echo $(( seconds / 86400 )) ;;
		long)    bgTimePeriodToLabel -p "$precision" "$seconds" ;;
	esac
}

# usage: fsGetUserCacheFile <relFilePath> [<retVar>]
# returns a usable file path that the caller can read and write to as the current loguser (see aaaGetUser)
# The file may or may not be shared with other users (but for now it is not)
# User Cache Folder:
#   This initial (current code circa 2016-07) this folder is $HOME/.bglocal/cache
#   This may change in the future but code that uses this function should not care. the worst that
#   could happen is the the cache files would be lost and they will be re-created
# Params:
#   <relFilePath> : the filename of the cache file relative to the system's user cache folder. If its
#                   empty, the base folder is returned. If it ends in a /, it will be a folder, if not
#                   it will be a file. If the same path is called as both a file and a folder, the first
#                   call will determine if its a file or folder.
#   <retVar> : if specified, the result will be set in this variable name instead of returned on stdout
function fsGetUserCacheFile()
{
	# make sure the aaaTouch function is available
	import bg_authUGO.sh ;$L1;$L2

	local relFilePath="$1"

	# if running a script with sudo, $USER will be root, but really the script is running as the loguser (login user)
	# but just with elevated permissions. If someone is really logged in a root, then we would use root's home
	local fsguc_aaaUser; aaaGetUser fsguc_aaaUser
	local fsguc_userCacheFolder="$(getent passwd | awk -F: '$1=="'"$fsguc_aaaUser"'"{print $6}')"

	# fall back on the $HOME variable if something went wrond with getting the real user's home folder
	[ ! "$fsguc_userCacheFolder" ] || [ ! -d "$fsguc_userCacheFolder" ] && fsguc_userCacheFolder="$HOME"

	# it should be very reliable to get the folder so this assert should never fail
	assertFolderExists "$fsguc_userCacheFolder"

	fsguc_userCacheFolder="${fsguc_userCacheFolder%/}/.bglocal/cache"
	local fsguc_cachFile="${fsguc_userCacheFolder}/${relFilePath#/}"

	# make sure that the file exists with the typical home folder permissions
	aaaTouch -p -d "" "$fsguc_cachFile" "owner:$fsguc_aaaUser:writable,group::writable,world:readable"

	returnValue "$fsguc_cachFile" "$2"
}



# usage: fsMakeSymLink <targetPath> <symLinkPath>
# Make the symlink. This is a wrapper over ln -s that does a few nice things.
#    1) it will make an optimal relative link regardless of how <targetPath> is specified.
#       if either path does not start with a / or ~, it will be taken as a relative path from the PWD
#       and not relative to the symlink. So you just specify two file paths and it will calculate how
#       to get tothe target from the link
#    2) it will not touch the symlink if it is already set as specified.
# Params:
#    <targetPath>   : the path to the target file system object that the link should refer to
#    <symLinkPath>  : the path to the symlink object that will point to the <targetPath>
# Options:
#    -f : force. if a file or folder exists at the <symLinkPath> -f will make it replace that file system object. without -f an
#        it would be an error
function fsMakeSymLink()
{
	local forceFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-f) forceFlag="-f" ;;
	esac; shift; done
	local targetPath="$1"
	local symLinkPath="${2%/}"
	local linkContents="$(pathGetRelativeLinkContents "${symLinkPath%/}" "$targetPath")"

	# if its not a symlink or if its content is not what we are setting, then create/update the symlink
	local sudoOpts; bgsudo --makeOpts sudoOpts -r "${symLinkPath}"
	if [ ! -h "${symLinkPath%/}" ] || [ "$linkContents" != $(bgsudo -O sudoOpts readlink "${symLinkPath%/}") ]; then
		# its ok if the symLinkPath does not exist or is already a symlink but it its another type of FS object
		# its an error instaead of overwriting what ever object is there. But if forceFlag is specified, go ahead
		# and replace what ever is there with the new symlink (ln -sfn will do that automatically)
		[ ! "$forceFlag" ] && [ -e "$symLinkPath" ] && [ ! -h "${symLinkPath%/}" ] && assertError -v targetPath -v symLinkPath -v linkContents "could not make symlink. A file or folder is in the way"

		bgsudo --makeOpts sudoOpts -w "${symLinkPath}"
		local linkParent="${symLinkPath%/*}"
		[ ! -d "$linkParent" ] && { bgsudo -O sudoOpts /bin/mkdir -p "$linkParent" || assertError -v targetPath -v symLinkPath -v linkContents "could not make the parent folder for symlink"; }
		bgsudo -O sudoOpts ln -sfn "$linkContents" "${symLinkPath%/}" || assertError -v targetPath -v symLinkPath -v linkContents "could not make symlink"
	fi
}


# function fsExists()        moved to bg_libCore.sh
# function bgfind()          moved to bg_libCore.sh
# function fsExpandFiles()   moved to bg_libCore.sh

# usage: fsMergeFoldersRecursively <srcFolder> <dstFolder>
# this is like calling /bin/mv with options that make it do a logical recursive merge. Those options do not exist.
# It uses mv to rename directory entries and never copies content so its just as fast with very large files (unlike rysnc).
# It also does not modify the timestamps and persmissions except to choose the later timestamp for conflicts so there is
# no issue of "preserving" them (like with cp and rsync)
# Differences From /bin/mv:
#    -R behaivior : /bin/mv does not descend into folders that exist in both src and dst. This function calls it self to merge
#         those folders recursively
#    -n and -S behaivior : /bin/mv can either make backups of the dstination file (that would have been overwritten) or it can
#         not clobber the destination by leaving the src file in place. It treats these as mutually exclusive. This function
#         behaives as if -n reverses the -S so that is does not clobber the destination and it moves the src next the destination
#         adding the -S suffix.
#    hidden files behaivior : /bin/mv uses only globbing which ignores hidden files by default. This function operates on all
#         srcFolder contents, both hidden and non-hidden. Both parameters must be folders.
function fsMergeFoldersRecursively()
{
	local srcFolder="${1%/}"; assertFolderExists "$srcFolder"
	local dstFolder="${2%/}"; assertFolderExists "$dstFolder"

	# if they refer to the same folder, its a no op.
	if [ "$(readlink -f "$srcFolder")" == "$(readlink -f "$dstFolder")" ]; then
		return
	fi

	local fileList=()
	fsExpandFiles -E -A fileList "$srcFolder"/* "$srcFolder"/.[^]*
	[ ${#fileList[@]} -eq 0 ] && return

	# first, let /bin/mv move everything using the backup/conflict suffix, so that files and folders that would be overwritten
	# will be renamed
	/bin/mv -S".mergeConflict.dst" "${fileList[@]}" "$dstFolder" 2>/dev/null

	# make the dst the later of the two timestamps and then remove srcFolder
	[ "$srcFolder" -nt "$dstFolder" ] && touch -r "$srcFolder" "$dstFolder"
	rmdir "$srcFolder"

	# fixup any folders that have the .mergeConflict.dst extension
	fileList=(); fsExpandFiles -D -A fileList "$dstFolder"/*.mergeConflict.dst/
	local conflictFolderDst; for conflictFolderDst in "${fileList[@]}"; do
		local conflictFolder="${conflictFolderDst%.mergeConflict.dst/}"
		local conflictFolderSrc="${conflictFolder}.mergeConflict.src"

		# swap the conflict names b/c we want to preserve the dst content and mv can only make backups of the dst content
		# the --backup="numbered" makes a unique backup names in case we somehow (incorrectly) have a conflictFolderSrc
		/bin/mv -T --backup="numbered" "$conflictFolder" "$conflictFolderSrc" || assertError "/bin/mv failed unexpectidly"
		/bin/mv -T "$conflictFolderDst" "$conflictFolder" || assertError "/bin/mv failed unexpectidly"

		# if source is expected to be a folder but there can be inconsistencies so account for that case (which is a noop)
		if [ -d "$conflictFolderSrc" ]; then
			fsMergeFoldersRecursively "$conflictFolderSrc" "$conflictFolder"
		fi
	done

	# fixup any files that have the .mergeConflict.dst extension
	fileList=(); fsExpandFiles -F -A fileList "$dstFolder"/*.mergeConflict.dst
	local conflictFileDst; for conflictFileDst in "${fileList[@]}"; do
		local conflictFile="${conflictFileDst%.mergeConflict.dst}"
		local conflictFileSrc="${conflictFile}.mergeConflict.src"

		# swap the conflict names b/c we want to preserve the dst content and mv can only make backups of the dst content
		# the --backup="numbered" makes a unique backup names in case we somehow (incorrectly) have a conflictFileSrc
		mv --backup="numbered" "$conflictFile" "$conflictFileSrc" || assertError "/bin/mv failed unexpectidly"
		mv "$conflictFileDst" "$conflictFile" || assertError "/bin/mv failed unexpectidly"

		[ "$conflictFileSrc" -nt "$conflictFile" ] && touch -r "$conflictFileSrc" "$conflictFile"

		# if the content is the same, there is no conflict so just delete the .mergeConflict.dst file that mv nievely made
		# diff -q is true when the files are the same
		if diff -q "$conflictFileSrc" "$conflictFile" >/dev/null; then
			rm "$conflictFileSrc" || assertError "rm failed unexpectidly"
		fi
	done
}


# usage: fsMove <src> <dst>
# This will move the contents of <src> into <dst>, creating <dst> if needed.
# Params:
#    <src> : path to a folder whose content will be moved int <dst>
#            It is not an error if it does not exist. In that case, there is simply no content to move
#            It is not an error if <src> and <dst> are the same path. In that case, there is simply no (new) content to move
#            if <src> is a symlink it logically operates on the target of the sysmlink. i.e. if the target does not exist then
#            <src> does not exist and there will be no content to move.
#    <dst> : path to a folder that will exist at the end of the function regardless of whether src provided any
#            content to move into it. If content in <dst> existed before, it will not be changed.
# Options:
#    -p : make parent folder if needed. this function will create the <dst> folder if required. Like mkdir, without -p
#         it will fail if the parent folder does not already exist. With -p it will create all the parent hierarchy as needed
# Goals:
#    1) <dst> will exist or it will assert an error.
#    2) any existing content in <dst> will remain, unchanged, with its original name
#    3) any existing content from <src> will exist in <dst> either as the original relative path name or with the mergeConflict.src extension
#    4) No (unique) content will exist in <src>. If <src> is not a symlink, it will be removed. The 'unique' qualification means that
#       if <scr> is the same path as <dst> (maybe via a symlink), its content will still exist because it is the <dst> content
# Merge Conflicts:
#    TODO: invoke content merge handlers based on extension or content inspection.
#    Any files that exist in both folder and their contents are the same, the <src> copy will be removed because it is already respresented
#    in <dst>.
#    If the content is different, the conflict will be handled like this.
#       1) the src file version will be written with the <filename>.mergeConflict.src extension
#       2) the dst file version will remain, untouched, with its original name.
# Exit Code: reflects the method used
#    0 : nothing.   dst already existed and src did not or src refered to dst (maybe as a symlink)
#    1 : created.   neither dst nor src existed, so an empty dst folder was created
#    2 : moved.     only src existed so it was mv'd to dst
#    3 : merged.    both dst and src existed, so the contents of src were moved into dst (see "Merge Conflicts" section.
#                   search for files matching "*.mergeConflict.src" to see if there were any merge conflicts
function fsMove()
{
	local passThruOpts
	while [ $# -gt 0 ]; do case $1 in
		-m*|--context) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		-*)            bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	 done

	local src="${1%/}"
	local dst="${2%/}"
	[ -e "$src" ] && [ ! -d "$src" ] && assertError -v src "src is not a folder."
	[ -e "$dst" ] && [ ! -d "$dst" ] && assertError -v dst "dst is not a folder."

	# srcFull and dstFull are just used to see if they refer to teh same path. readlink -f will return empty str if the path does not
	# exist on the file system but that is ok for this purpose b/c if either does not exist, the algorithm does not care if they are the same
	# src and/or dst can have symlinks in their path so that they may look different even when they refer to the same folder
	# readlink -f returns the canonical path whether or not it contains symlinks.
	local srcFull="$(readlink -f "$src")"
	local dstFull="$(readlink -f "$dst")"

	# make the label of whether src exists. if it exists and refers to dst, we don't consider that existing as a distinc entity
	local srcContentExists="src$( [ -e "$src" ] && echo "Exists" || echo "DoesNot")"

	# make the label of whether dst exists. if it exists and refers to src, we don't consider that existing as a distinc entity
	local dstContentExists="dst$( [ -e "$dst" ] && echo "Exists" || echo "DoesNot")"

	# if they refer to the same path, we still might need to handle the case where dst is a sym link
	if [ "$srcFull" == "$dstFull" ]; then
		if [ -h "$dst" ]; then
			dstContentExists="dstDoesNot"
			[ -h "$src" ] && rm "$src"
			src="$srcFull"
		else
			srcContentExists="srcDoesNot"
			dstContentExists="dstExists"
		fi
	fi

	### we have 4 different cases for the combinations of src and dst existing or not.
	local result
	case $srcContentExists:$dstContentExists in
		srcDoesNot:dstExists)
			result=0
			;;
		srcDoesNot:dstDoesNot)
			/bin/mkdir "${passThruOpts[@]}" "$dst" || assertError "could not create '$dst'"
			result=1
			;;
		srcExists:dstDoesNot)
			[ -h "$dst" ] && rm "$dst"
			[ -d "${dst%/*}" ] || /bin/mkdir "${passThruOpts[@]}" "${dst%/*}" || assertError "could not create parent folder for '$dst'"
			/bin/mv "$src" "$dst" || assertError "could not 'mv $scr $dst'"
			result=2
			;;
		srcExists:dstExists)
			fsMergeFoldersRecursively "$src/" "$dst/"
			result=3
			;;
	esac
	assertFolderExists "$dst" "the desination folder ($dst) does not exist after fsMove from source ($src)"
	return $result
}

# usage: fsCopyAttributes  <srcFile>  <dstFileSpec>
# copy the attributes from the <srcFile> to the <dstFile>.
# Params:
#    <srcFile>     : get the attributes from this file
#    <dstFileSpec> : set those attributes on this file
function fsCopyAttributes()
{
	local srcFile="$1" ; assertFileExists "$srcFile"
	local dstFile="$2" ; assertFileExists "$dstFile"
	local octalStr fuser; read -r octalStr fuser <<<"$(stat -c "%a %U" "$srcFile")"
	if [ "$USER" != "$fuser" ]; then
		sudo -p "changing file permissions '$dstFile' [sudo] " chmod $octalStr "$dstFile"
	else
		chmod $octalStr "$dstFile"
	fi
}


# usage: fsPipeToFile [--channelID <channelID>] [-p|--tmpdir <tmpdir>] <destFile>
# usage: fsPipeToFile --didChange --channelID <channelID>
# usage: <someCommand> | pipeToFile <destFile>
# This is a filter that redirects a command's output to a file similar to using "<someCommand> > <destFile>"
# but with the following features that a simple redirect does not have.
#  * <destFile> can be used in <someCommand>. e.g. "grep -v badToken myFile | pipeToFile myFile"
#  * it will only touch the <destFile> if the content is different than what is already in <destFile>
#  * you can call it again after the pipeline to find out whether the <destFile>was changed.
#  * if the USER does not have permission to write to <destFile>, sudo will be attempted.
#  * if <destFile> exists, it will be overwritten, if not, it will be created
#  * if the parent folder does not exist, it will be created
# Note that this command is similar to collectContents but is more generic
# Params:
#     <destFile> : the file that the contents will be written to (if needed).
# Options:
#    --channelID <channelID> : (default is the sanitized filename) If you are updating multiple files in a group and only need to
#            know that at least one file in the group was updated, set the --channelID of all those calls to the same group name
#            and then call with --getResult once for the whole group.
#    --didChange : After the pipe is done, call this function a second time with either the same <destFile> or channelID and its
#            exit value will indicate if the content was changed.
#    -p|--tmpdir <tmpdir> : provides an existing location to write its tmp file. Otherwise mktmp will be used
# See Also:
#    collectContents
function pipeToFile() { fsPipeToFile "$@"; }
function fsPipeToFile()
{
	local channelID mode tmpdir
	while [ $# -gt 0 ]; do case $1 in
		--channelID*)  bgOptionGetOpt  val: channelID         "$@" && shift ;;
		--didChange)   mode="--didChange" ;;
		-p*|--tmpdir*) bgOptionGetOpt  val: tmpdir           "$@" && shift ;;
	*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local destFile="$1"; assertNotEmpty destFile

	[ ! "$channelID" ] && channelID="${destFile//\//_}"

	# because this function is typically called in a pipe's subshell, it can not return whether the destination file was changed.
	# so instead if it changed the destination file, it creates the file "$assertOut.$channelID". The caller then calls it again,
	# (not in a pipe) with the --didChange and the same --channelID value and this block tests if that file exists, removes the
	# file if needed and returns the result
	if [ "$mode" == "--didChange" ]; then
		local result
		if [ -e "$assertOut.$channelID" ]; then
			result="1"
			rm "$assertOut.$channelID"
		fi
		[ "$result" ]
		return
	fi

	if [ "$tmpdir" ]; then
		local relDestFile="${destFile#/}"
		mkdir -p "${tmpdir}/${relDestFile%/*}"
		local tmpFile="${tmpdir}/${relDestFile}"
	else
		local tmpFile="$(mktemp)"
	fi

	cat - > "$tmpFile"

	# we only need read permissions to test to see if the file is different
	local sudoOpts; bgsudo --makeOpts sudoOpts -r "$destFile" -p "reading '${destFile##*/}' [sudo] "

	if [ ! -e "$destFile" ] || ! bgsudo -O sudoOpts diff -q "$tmpFile" "$destFile" &>/dev/null; then
		# now we need write perission
		sudoOpts=(); bgsudo --makeOpts=sudoOpts -w "$destFile" -p "writing to '${destFile##*/}' [sudo] "
		if [[ "$destFile" =~ / ]]; then
			local destFolder="${destFile%/*}"
			[ ! -d "$destFolder" ] && bgsudo -O sudoOpts mkdir -p "${destFolder}"
		fi
		cat "$tmpFile" | bgsudo -O sudoOpts tee "$destFile" >/dev/null #|| assertError
		[ "$channelID" ] && touch "$assertOut.$channelID"
	fi
	rm "$tmpFile"
	return 0
}

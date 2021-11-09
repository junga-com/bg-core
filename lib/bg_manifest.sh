
# Library
# The manifest file is a concept from the bg-core package. Any package that complies with its specification will install a
# hostmanifest file in the system folder "/var/lib/bg-core/<pkgName>/hostmanifest" listing the assets that that package provides.
# The file at "/var/lib/bg-core/manifest" is the aggregation of all the package hostmanifest files.
#
# the purpose of the manifest file is to allow the efficient discovery of assets of various types provided by arbitrary pacakges.
#
# Format:
# The manifest file has four columns. Each row is a single asset.
#    <pkgName>        <assetType>      <assetName>     <assetPath>
#
# The <assetType> consists of the base type optionally followed by qualifications separated by '.'. Each qualification is a subclass
# of the preeding type. For example, all assets that start with "cmd*" are linux commands, both binary and script based but those
# starting with "cmd.script*" are text based scripts, and "cmd.script.bash" are written to the bash script standard.
#
# The <assetName> is typically the base filename with no path an dno extension but does not have to be.
#
# the <assetPath> is the location of the asset on the local host. It can be any filesystem object -- file, folder, etc...
#
# See Also:
#    man(1) bg-dev-manifest  : from the bg-dev package which supports creating and distributing projects that contain assets.

# these are moved to bg_coreLibsMisc.sh
#declare -gx manifestInstalledPath="/var/lib/bg-core/manifest"
#declare -gx pluginManifestInstalledPath="/var/lib/bg-core/pluginManifest"


# moved to bg_coreLibsMisc.sh function manifestGet() {
# moved to bg_coreLibsMisc.sh function manifestGetHostManifest() {


# usage: manifestSummary
# print to stdout a summary of what is in the manifest
function manifestSummary()
{
	local manifestFile; manifestGetHostManifest manifestFile
	while [ $# -gt 0 ]; do case $1 in
		-f*|--file*) bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	cat "$manifestFile" | awk '
		{
			pkg=$1; type=$2
			types[pkg][type]++
		}
		END {
			for (pkg in types) {
				printf("%s contains:\n", pkg)
				for (type in types[pkg]) {
					printf("   %4s %s\n", types[pkg][type], type)
				}
			}
		}
	'
}


# usage: manifestReadTypes [-f|--file=<manifestFile>] [<typesRetVar>]
# get the list of asset types present in the project's manifest file
# Params:
#    <typesRetVar>  : the variable name of an array to return the asset type names in
# Options:
#    -f|--file=<manifestFile> : the default manifest file is $manifestInstalledPath
function manifestReadTypes()
{
	local manifestFile; manifestGetHostManifest manifestFile
	while [ $# -gt 0 ]; do case $1 in
		-f*|--file*) bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local typesVar="$1"
	local type count
	while read -r type count; do
		[ "$type" == "<error>" ] && assertError -v manifestFile -v pkgName "The manifest file does not exist."
		mapSet $typesVar "$type" "$count"
	done < <(awk '
		{types[$2]++}
		END {
			for (type in types)
				printf("%s %s\n", type, types[type])
		}
	' "$manifestFile" || echo '<error>')
}

# usage: manifestReadOneType [-f|--file=<manifestFile>] <filesRetVar> <assetType>
# get the list of files and folders that match the given <assetType> from the manifset
# Params:
#    <filesRetVar>  : the variable name of an array to return the file and folder names in
#    <assetType>    : the type of asset to return
# Options:
#    -f|--file=<manifestFile> : the default manifest file is $manifestInstalledPath
function manifestReadOneType()
{
	local manifestFile; manifestGetHostManifest manifestFile
	while [ $# -gt 0 ]; do case $1 in
		-f*|--file*) bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local filesVar="$1"
	local type="$2"

	local file
	while read -r file; do
		varSet "$filesVar[$((i++))]" "$file"
	done < <(awk -v type="$type" '
		$2==type {print $4}
	' "$manifestFile")
}


# usage: manifestUpdateInstalledManifest [all]
# usage: manifestUpdateInstalledManifest remove <pkgName>
# usage: manifestUpdateInstalledManifest add <pkgName>
# This function is called when ever the set of installed packages changes on a host to update the manifest and pluginManifest to
# reflect the new state of installed packages.
#
# Based on the arguments passed, it can either create the manifest from scratch or remove one pkg's data or update/add one pkg's
# data. The add operation works as an update operation if an older version of the package is already installed.
#
# This function only handles the real, installed manifest files. There is another version of this function  in the bg_manifestScanner.sh
# library from the bg-dev package that is used to create and maintain the vinstalled sandbox's manifest files.
function manifestUpdateInstalledManifest() {
	local action="$1"
	local pkgName="$2"

	# make backups of the current manifest files for debugging by diffing to see what changed
	[ -f "$manifestInstalledPath" ]       && cat "$manifestInstalledPath"       | fsPipeToFile "${manifestInstalledPath}.prev"
	[ -f "$pluginManifestInstalledPath" ] && cat "$pluginManifestInstalledPath" | fsPipeToFile "${pluginManifestInstalledPath}.prev"

	case ${action:-all} in
		all)
			local rebuildInstalled dirtyDeps
			if fsGetNewerDeps --array=dirtyDeps "$manifestInstalledPath" /var/lib/bg-core/*/hostmanifest; then
				cat $(fsExpandFiles -f /var/lib/bg-core/*/hostmanifest) | sort | fsPipeToFile "$manifestInstalledPath"
			fi

			import bg_plugins.sh  ;$L1;$L2
			$Plugin::buildAwkDataTable --manifest="$manifestInstalledPath" | fsPipeToFile "$pluginManifestInstalledPath"
			;;

		remove)
			assertNotEmpty pkgName
			[ ! -f "$manifestInstalledPath" ] && [ ! -f "$pluginManifestInstalledPath" ] && return 0
			bgawk -i  \
			   -v pkgName="$pkgName" \ '
				$1==pkgName {deleteLine()}
			' $(fsExpandFiles "$manifestInstalledPath" "$pluginManifestInstalledPath")
			;;

		add)
			assertNotEmpty pkgName
			bgawk -i \
			   -v pkgName="$pkgName" \ '
				function insertNewPkgData() {
					if (!didIt) {
						didIt="1"
						while (getline < "/var/lib/bg-core/"pkgName"/hostmanifest" >0)
							printf("%s\n", $0)
					}
				}

				# suppress printing of any pkgName data already in the file
				$1==pkgName {deleteLine()}

				# if we have not yet written the new data and we see a pkgName that sorts after it, its time to write the data
				!didIt && ($1 > pkgName) {
					insertNewPkgData()
				}

				END {
					# if we did not find an insertion point while scanning the file, we write it at the end
					if (!didIt)
						insertNewPkgData()
				}
			' "$manifestInstalledPath"

			{
				import bg_plugins.sh  ;$L1;$L2
				[ -f "$pluginManifestInstalledPath" ] && bgawk -n  \
				   -v pkgName="$pkgName" \ '
					@include "bg_core.awk"
					NR==1 {
						for (i=1; i<=NF; i++)
							cols[i]=$i
					}
					NR==2 {next;}
					{
						if ($1!=pkgName) {
							for (i=1; i<=length(cols); i++)
								printf("%s %s %s %s\n", pkgName, norm($2), cols[i], norm($i))
						}
					}
				' "$pluginManifestInstalledPath"

				static::Plugin::_dumpAttributes --manifest="$manifestInstalledPath" --pkgName="$pkgName"

			} | static::Plugin::_assembleAttributesForAwktable | column -t -e | fsPipeToFile "$pluginManifestInstalledPath"
			;;
	esac
}

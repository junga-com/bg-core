
declare -g manifestInstalledPath="/var/lib/bg-core/manifest"

# usage: manifestGetHostManifest
# returns the file path to the prevailing host manifest file. In production this would be "$manifestInstalledPath"
# but vinstalling a sandbox overrides it
function manifestGetHostManifest() {
	returnValue "${bgVinstalledManifest:-$manifestInstalledPath}" $1
}

# usage: manifestSummary
# print to stdout a summary of what is in the manifest
function manifestSummary()
{
	local manifestFile; manifestGetHostManifest manifestInstalledPath
	while [ $# -gt 0 ]; do case $1 in
		-f*|--file*) bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	cat "$manifestFile" | awk '
		{
			pkg=$1; type=$2; file=$3
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
#    -f|--file=<manifestFile> : by default the manifest file in <projectRoot>/.bglocal/manifest is used
function manifestReadTypes()
{
	local manifestFile; manifestGetHostManifest manifestInstalledPath
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
#    -f|--file=<manifestFile> : by default the manifest file in <projectRoot>/.bglocal/manifest is used
function manifestReadOneType()
{
	local manifestFile; manifestGetHostManifest manifestInstalledPath
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
		$2==type {print $3}
	' "$manifestFile")
}


# usage: manifestUpdateInstalledManifest
function manifestUpdateInstalledManifest() {
	local rebuildInstalled dirtyDeps
	if fsGetNewerDeps --array=dirtyDeps "$manifestInstalledPath" /var/lib/bg-core/*/hostmanifest; then
		cat /var/lib/bg-core/*/hostmanifest | sort | fsPipeToFile "$manifestInstalledPath"
	fi
}

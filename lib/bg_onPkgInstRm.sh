
# Library:
# This bash script library implements the package installation and removal hooks for both deb and rpm package managers
# There are four hooks. pre and post package install, and pre and post package remove. There may be some differences in the order
# called between deb and rpm managers but over time, this package will provide abstrations to perform common tasks correctly for
# both systems.
# See Also:
# https://www.debian.org/doc/debian-policy/ap-flowcharts.html
# https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html
# https://wiki.debian.org/MaintainerScripts


onPkgTrace=""

# The package will not yet be unpacked, so the preinst script cannot rely on any files included in its package. Only essential
# packages and pre-dependencies (Pre-Depends) may be assumed to be available. Pre-dependencies will have been configured at least
# once, but at the time the preinst is called they may only be in an “Unpacked” or “Half-Configured” state if a previous version
# of the pre-dependency was completely configured and has not been removed since then.
function onPreinst()
{
	[ "$onPkgTrace" ] && echo "$packageName - $FUNCNAME $*" >> "/tmp/bgtrace.out"
	local action="$1";  shift  # install|upgrade|abort-upgrade
	if [ "$action" != "abort-upgrade" ]; then
		local oldVersion="$1"; shift

	else # "$action" == "abort-upgrade"
		# This case is called on the older version that was being updgraded. The upgrade failed after the old version was disrupted
		# so it it 'reinstalling' the old version to get it into a god state again
		# The unpacked files may be partly from the new version or partly missing, so the script cannot rely on files
		# included in the package.
		local newVersion="$1"; shift
	fi
	return 0
}

# The files contained in the package will be unpacked. All package dependencies will at least be “Unpacked”. If there are no
# circular dependencies involved, all package dependencies will be configured.
function onPostinst()
{
	[ "$onPkgTrace" ] && echo "$packageName - $FUNCNAME $*" >> "/tmp/bgtrace.out"
	local action="$1"; shift    # configure|abort-upgrade|abort-remove|abort-deconfigure

	if [ "$action" == "configure" ]; then
		local oldVersion="$1"; shift

	else # "$action" == "abort-upgrade"|"abort-remove"|"abort-deconfigure"
		# these rollback cases are when prerm fails so we are being called to see if we need to, for example, restart a service
		# that prerm has stopped.
		# local newVersion="$1"; shift # see doc links above. version is pass in different locations but maybe its not so important
		:
	fi

	import bg_manifest.sh  ;$L1;$L2
	manifestUpdateInstalledManifest "${packageName:+add}" "${packageName}"

	local file
	for file in $(fsExpandFiles "$pkgDataFolder/bash_completion.d/"*); do
		cp "$file" /etc/bash_completion.d/ || assertError
	done
	return 0
}


# The package whose prerm is being called will be at least “Half-Installed”. All package dependencies will at least be
# “Half-Installed” and will have previously been configured and not removed. If there was no error, all dependencies will at least
# be “Unpacked”, but these actions may be called in various error states where dependencies are only “Half-Installed” due to a
# partial upgrade.
function onPrerm()
{
	[ "$onPkgTrace" ] && echo "$packageName - $FUNCNAME $*" >> "/tmp/bgtrace.out"
	local action="$1"; shift   # remove|upgrade|deconfigure|failed-upgrade

	local file
	for file in $(fsExpandFiles "$pkgDataFolder/bash_completion.d/"*); do
		rm -f "/etc/bash_completion.d/$file"
	done
	return 0
}

function onPostrm()
{
	[ "$onPkgTrace" ] && echo "$packageName - $FUNCNAME $*" >> "/tmp/bgtrace.out"
	local action="$1"; shift    # remove|purge|upgrade|disappear |failed-upgrade |abort-install|abort-upgrade
	case $action in
		# The postrm script is called after the package’s files have been removed or replaced. The package whose postrm is being
		# called may have previously been deconfigured and only be “Unpacked”, at which point subsequent package changes do not
		# consider its dependencies. Therefore, all postrm actions must only rely on essential packages and must gracefully skip
		# any actions that require the package’s dependencies if those dependencies are unavailable.
		remove|purge|upgrade|disappear)
			:
			;;

		# Called when the old postrm upgrade action fails. The new package will be unpacked, but only essential packages and
		# pre-dependencies can be relied on. Pre-dependencies will either be configured or will be “Unpacked” or “Half-Configured”
		# but previously had been configured and was never removed.
		failed-upgrade)
			:
			;;

		# Called before unpacking the new package as part of the error handling of preinst failures. May assume the same state as
		# preinst can assume.
		abort-install|abort-upgrade)
			:
			;;
	esac

	import bg_manifest.sh  ;$L1;$L2
	manifestUpdateInstalledManifest  "${packageName:+remove}" "${packageName}"

	return 0
}

# process the command line and invoke the specified hook
hookFn="$1"; shift
packageName="$1"; shift
case $hookFn in
	--preinst)   onPreinst   "$@" ;;
	--postinst)  onPostinst  "$@" ;;
	--prerm)     onPrerm     "$@" ;;
	--postrm)    onPostrm    "$@" ;;
esac

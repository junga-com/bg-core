
import bg_objects.sh ;$L1;$L2

DeclareClass AwkData

AwkData::__construct() {
	while [ $# -gt 0 ]; do case $1 in
		--schema*) bgOptionGetOpt val: this[schemaName] "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	this[filename]="$1"

	if [ "${this[schemaName]}" ]; then
		$_this.loadSchema
	fi
}

AwkData::loadSchema() {
	this[columns]="$(awk -F= '$1=="columns" {print $2}')"
}

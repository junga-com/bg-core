#@include "bg_core.awk"
# Library
# Added this library 2022-03 so that bash and awk programs can use the same algorithm to lookup the path of scriptNames.
# The intention will be to migrate all manifest operations to this file over time but I wont take the time now to do those other operations.
# Params:
#    -v mode=importLookup|   : selects a function that this library script can do
#    -v scriptName=<scriptName> : implies mode="importLookup"
#    -v outStr="$4..."  : change the normal output to this string




BEGIN {
	if (!outStr) outStr="$4"

	if (scriptName) {
		mode = "importLookup"
		baseName = gensub(/[.]sh$/, "", "g", scriptName)

		pluginTypeName = ""

		if (scriptName ~ /^PluginType[.:]/) {
			mode = "PluginTypeLookup"
			pluginTypeName = gensub(/^PluginType[.:](.*)$/, "\\1", "g", scriptName)
		} else if (scriptName ~ /[.:]PluginType$/) {
			mode = "PluginTypeLookup"
			pluginTypeName = gensub(/^(.*)[.:]PluginType$/, "\\1", "g", scriptName)
		}

		# bgtrace("bg_manifest.awk: scriptName=" scriptName " baseName=" baseName " pluginTypeName=" pluginTypeName)
	}
}

mode=="importLookup" && $2=="lib.script.bash" && ($3==baseName || $4 ~ "(^|/)" scriptName "$") { output(); exit 0 }
mode=="importLookup" && $2=="plugin"          && ($3==baseName || $4 ~ "(^|/)" scriptName "$") { output(); exit 0 }
mode=="importLookup" && $2=="unitTest"        && ($3==baseName || $4 ~ "(^|/)" scriptName "$") { output(); exit 0 }

mode=="PluginTypeLookup" && $2=="PluginType" && ( \
	$3 == "PluginType:" pluginTypeName || \
	$3 == "PluginType." pluginTypeName || \
	$3 == pluginTypeName ":PluginType" || \
	$3 == pluginTypeName ".PluginType" || \
	$4 ~ "(^|/)" pluginTypeName "[.]PluginType$" \
) {
	output()
	exit 0
}

function output(            s) {
	s = outStr
	gsub(/[$]1/, $1, s)
	gsub(/[$]2/, $2, s)
	gsub(/[$]3/, $3, s)
	gsub(/[$]4/, $4, s)
	gsub(/[$]5/, $5, s)
	print(s)
}

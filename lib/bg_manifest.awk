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
		mode="importLookup"
		baseName=gensub(/([.]sh)$/,"","g",scriptName)
	}
}

mode=="importLookup" && $2 == "lib.script.bash" && ($3 == baseName || $4~"(^|/)"scriptName"$") {output(); exit 0;}
mode=="importLookup" && $2 == "plugin"          && $4~"(^|/)"scriptName"$"                     {output(); exit 0;}
mode=="importLookup" && $2 == "unitTest"        && $4~"(^|/)"scriptName"$"                     {output(); exit 0;}

function output(            s) {
	s=outStr
	gsub(/[$]1/,$1,s)
	gsub(/[$]2/,$2,s)
	gsub(/[$]3/,$3,s)
	gsub(/[$]4/,$4,s)
	gsub(/[$]5/,$5,s) # in case we add a fifth
	print(s)
}

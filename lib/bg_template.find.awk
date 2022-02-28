
#pkg assetType assetName path
# $1    $2        $3      $4


function getOrd(pkg) {
	if (!pkg)
		return(0)
	if (!(pkg in ords))
		return(1)
	else
		return(ords[pkg])
}

BEGIN {
	# Order:
	#   4 domainadmin
	#   3 localadmin
	#   2 <packageName>
	#   1 (unknown packages)
	#   0 ""
	ords["domainadmin"]=4
	ords["localadmin"]=3
	if (packageName)
		ords[packageName]=2
}

$2~/^template(.folder)?$/ && $3==templateName {
	#print("hit "$1"   "getOrd($1)" > "getOrd(curPkg)"    curPkg="curPkg)
	if (getOrd($1) > getOrd(curPkg) ) {
		curPkg=$1
		filename=$4
		if (!filename)
			filename="!!error!!"
	}
}

END {
	if (filename)
		printf("%s\n", filename)
	else
		exit(1)
}


#pkg assetType assetName path
# $1    $2        $3      $4


BEGIN {
}

$2~/^template(.folder)?$/ && $3~"^"templateSpec {
	names[$3]=$1
	if (outFormat=="getSubtypes") {
		match($3,"^"templateSpec"[^.]*")
		matchedPart=substr($3,RSTART,RLENGTH)
		if (matchedPart == templateSpec) {
			suffix=gensub("^"templateSpec"[.]","","g",$3)
			suffix="."gensub("[.].*$","","g",suffix)
			matchSuffix[suffix]=matchedPart
		}
	}
}

END {
	if (outFormat=="getSubtypes") {
		for (name in matchSuffix)
			printf("%s\n", name)
	} else {
		for (name in names)
			printf("%s\n", name)
	}
}

@include "bg_core.awk"

#pkg assetType assetName path
# $1    $2        $3      $4

function treeAdd(node, parts                             ,partName) {
	if (length(parts)==0)
		return
	partName=arrayShift(parts);
	if (!(partName in node))
		arrayCreate2(node,partName)
	treeAdd(node[partName], parts)
}

function treePrint(name, node, depth                    ,subname,theDot) {
	if (depth>0)
		theDot="."
	printf("%*s%s\n", depth*3,"", theDot""name)
	if (isarray(node))
		for (subname in node)
			treePrint(subname, node[subname], depth+1)
}

BEGIN {
	arrayCreate(treeRoots)
}

$2~/^template(.folder)?$/ && $3~"^"templateSpec {
	split($3, parts, ".");
	if (length(parts)>0)
		treeAdd(treeRoots,parts)
}

END {
	for (name in treeRoots)
		treePrint(name, treeRoots[name], 0)
}

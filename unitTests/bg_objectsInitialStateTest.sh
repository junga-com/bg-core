#!/usr/bin/env bash

source /usr/lib/bg_core.sh

import bg_objects.sh  ;$L1;$L2


function showClass() {
	local class="$1"
	printf "#\n#\n#------------------ $class --------------------\n"
	eval local globalArrayVars='"${!'"$class"'*}"'
	echo "global array vars: $globalArrayVars"
	printfVars --noObjects $class -l"#" ${class}_vmt "$(strSetSubtract "$globalArrayVars" "$class  ${class}_vmt")"
}

echo Object ${Object[subClasses]}
for class in Object ${Object[subClasses]}; do
	showClass "$class"
done

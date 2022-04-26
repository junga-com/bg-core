#!/usr/bin/env bash

source /usr/lib/bg_core.sh
import bg_objects.sh  ;$L1;$L2

bgtrace 1
type _bgclassCallSetup
bgtrace 2

declare -n obj; ConstructObject Object obj
obj[color]="red"
$obj.toString

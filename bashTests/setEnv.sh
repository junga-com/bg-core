#!/usr/bin/env bash

# 2022-03 bobg:
# I wrote this because I was about to change the global code to set ENV vars at bg_coreImport.sh(lines ~300 to ~400)
# Turns out the original code was better than what I was about to do.
# This script shows why.
# This is the comment for the change that I ended up not making
#                changed this algorithm. The previous version was working pretty well for a long time. It was overly complicated however because
#               it based its decision on only on FUNCNAME instead of considering BASH_SOURCE and therefore had to query FUNCNAME inside a dummy function
#               I now understand that ${BASH_SOURCE[@]: -1} can only be ...
#                     '' when running at 1) typed at the cmdline and 2) global code being sourced.
#                     'main' when running in a function sourced into the terminal ('main' is considered the source file name of sourced functions )
#                     anything else when running in a script (note that 'main' can never be a script name b/c it have no path like ./main)
#                ${FUNCNAME[@]: -1} can only be ...
#                     '' when running global code in a script and also in scripts being source from global script code
#                     '<functionName>' when running inside a function


if [[ "$1" =~ ^(-h|--h) ]]; then
	echo "
Its best to cd into the folder that contains this script (to make the source file name short to fit in the table column)
This script is a test for the code in bg_coreImport.sh that set the bgLibExecMode, bgLibExecCmd, and bgLibExecSrc vars
Run it in various ways to compare the output of  entry of FUNCNAME and BASH_SOURCE and BASH_SUBSHELL vars
   * from cmdline
   * source from cmdline
   * ?
After sourcing it, run the sourced functions bar1,bar2,and foo
	"
	exit
fi


libfile=$(mktemp --tmpdir foo.XXX)
cat <<<'
fileName="lib file"
where="global"

printf "%-16s:%-12s:%-14s:%-7s  %s: %s code: \n"  "${BASH_SOURCE[*]: -1}" "${FUNCNAME[*]: -1}" "$BASH_SUBSHELL"  ""$(getit)""  "$fileName" "$where"

function foo()
{
	local fileName="lib file"
	local where="func"
	printf "%-16s:%-12s:%-14s:%-7s  %s: %s code: \n"  "${BASH_SOURCE[*]: -1}" "${FUNCNAME[*]: -1}" "$BASH_SUBSHELL"  ""$(getit)""  "$fileName" "$where"
}
foo
' > "$libfile"


fileName="cmd file"
where="global"

function getit() { echo "${FUNCNAME[*]: -1}"; }

echo "(BASH_SOURCE[-1],FUNCNAME[-1],BASH_SUBSHELL,getit()"

printf "%-16s:%-12s:%-14s:%-7s  %s: %s code: \n"  "${BASH_SOURCE[*]: -1}" "${FUNCNAME[*]: -1}" "$BASH_SUBSHELL"  ""$(getit)""  "$fileName" "$where"

function bar1()
{
	local fileName="cmd file"
	local where="func"
	printf "%-16s:%-12s:%-14s:%-7s  %s: %s code: \n"  "${BASH_SOURCE[*]: -1}" "${FUNCNAME[*]: -1}" "$BASH_SUBSHELL"  ""$(getit)""  "$fileName" "$where"
}
bar1

echo "global sourcing "
source "$libfile"


function bar2()
{
	local where="func"
	echo "func sourcing "
	source "$libfile"
}
bar2


#  ./bar
# (BASH_SOURCE[-1],FUNCNAME[-1],BASH_SUBSHELL,getit()
# ./bar.sh        :            :0             :main     bar: global code:
# ./bar.sh        :main        :0             :main     bar: func code:
# global sourcing
# ./bar.sh        :            :0             :main     bar: global code:
# ./bar.sh        :main        :0             :main     bar: func code:
# func sourcing
# ./bar.sh        :main        :0             :main     bar: global code:
# ./bar.sh        :main        :0             :main     bar: func code:


#  source bar.sh
# (BASH_SOURCE[-1],FUNCNAME[-1],BASH_SUBSHELL,getit()
# bar.sh          :            :0             :source   bar: global code:
# bar.sh          :source      :0             :source   bar: func code:
# global sourcing
# bar.sh          :            :0             :source   bar: global code:
# bar.sh          :source      :0             :source   bar: func code:
# func sourcing
# bar.sh          :source      :0             :source   bar: global code:
# bar.sh          :source      :0             :source   bar: func code:

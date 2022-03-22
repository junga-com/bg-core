This ./core folder contains script libraries that are unconditionally loaded by sourcing bg_core.sh

The load/import/source order of unconditional code is this...
	1) bg_core.sh
	2)  '-- bg_coreImport.sh
	3)        |-- bg_coreBashVars.sh     (working with bash vars)
	4)        '-- bg_coreStrings.sh          (legacy? maybe merge into bg_coreBashVars.sh?)
	5)        '-- bg_coreLibsMisc.sh     (required functions from non-core libs and critical functions from core libs that need early definition)
	6)        '-- <other core libs in any order>

Some functions in bg_coreLibsMisc.sh are stubs that, when called, load a lib from the ./coreOnDemand/ folder.

libs from ./lib/ must be explicitly sourced by a script that wants to use them.

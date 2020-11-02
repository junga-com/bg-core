
* bug to fix: BC bg-debugCntr trace of<tab> -> off: gets a trailing : even those its suggestion does not have one -- tweak the $(nextBreakChar :) directive
* unitTest: support ut_<func> without parameters. it ut_<func>: would run it without any params
* unitTest: finish test runner in "bg-dev tests"
* unitTests: consider #!bashTests shebangs instead of calling untiTestCntr at the end of the file
* add funcman unit tests to document syntax -- add more markdown support -- try to factor out formatter to allow separate unit testing
* add try/catch unit tests
* assertError: add "Throw: assertError" and "Rethrow:" syntax function
* assertError: support catching specific exceptions
* import: make L2 optional with function pass() { return $?; }   
* bring over bg_plugins.sh
* (done) implement on demand bash completion scripts
* (done) update funcman
*


* make funcman scan for iniParamGet/Set and document the config settings referenced by the function or script
* add # FUNCMAN_ALIAS bg_bashCompletion support
* test putting a bgtraceBreak in a sourced function to debug it. will it end the terminal in some cases? Try in conjuction with the feature to hotpatch sourced function code with breakpoints
* bug: funcman: Catch.3 and Catch:.3 are different
* make _bgbc_... resuse to send bgtrace to stderr or stdout so that BC does not get messed up
* add a bg-db() function to bg-debugCntr so that `bg-db <myscript>` invokes the debugger
* add bg-debugCntr debugger stopOnAssert:(on|off)
* reverse the driection of bgtraceStack traces to match the that of the debugger. Should be script at the top
* bgtraceBreak stops inside system code instead of a the the line after bgtraceBreak
* make funcman collect Environment: sections and BGENV: tags and create an agregate documentation
* fix bg-debugCntr listCodeFiles
* add progress reporting to unitTest Runner
* add multithreading to unitTest Runner
* bug to fix: BC bg-debugCntr trace of<tab> -> off: gets a trailing : even those its suggestion does not have one -- tweak the $(nextBreakChar :) directive
* unitTests: consider #!bashTests shebangs instead of calling untiTestCntr at the end of the file
* add funcman unit tests to document syntax -- add more markdown support -- try to factor out formatter to allow separate unit testing
* add try/catch unit tests
* assertError: add "Throw: assertError" and "Rethrow:" syntax function
* assertError: support catching specific exceptions
* bring over bg_plugins.sh
(done)* make unitTestCntr an on-demand core function
(done) * break out progress from cui.sh to separate library script
(done) * unitTest: support ut_<func> without parameters. it ut_<func>: would run it without any params
(done) * unitTest: finish test runner in "bg-dev tests"
(done) * import: make L2 optional with function pass() { return $?; }   
(done) * implement on demand bash completion scripts
(done) * update funcman
*

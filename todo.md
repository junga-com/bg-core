
* configGet: support a syntax (maybe +=) that combines values from scopes instead of just taking the value of the most specific scope. Something like the awkData column algorithm
* create a custom text diff that supports a language of sections that can match regex. The language may be a superset of the bash template language. Use it in 1) fsTouch and 2) unit test plato comparisons.
* add a system user assetType to make a package add a system user account to the target host
* add a configUser, collectUser, standardsUser system accounts and make the *Cntr commands execute as them   
* add support to turn on/off the automatic running of collect, standards, and configs
* make funcman scan for iniParamGet/Set and document the config settings referenced by the function or script
* add # FUNCMAN_ALIAS <name> support for man pages
* test putting a bgtraceBreak in a sourced function to debug it. why are line numbers so off in the stack trace? will it end the terminal in some cases? Try in conjuction with the feature to hotpatch sourced function code with breakpoints
* bug: funcman: Catch.3 and Catch:.3 are different
* make _bgbc_... refuse to send bgtrace to stderr or stdout so that BC does not get messed up
* make funcman collect Environment: sections and BGENV: tags and create an agregate documentation
* fix bg-debugCntr listCodeFiles
* add multithreading to unitTest Runner
* add funcman unit tests to document syntax -- add more markdown support -- try to factor out formatter to allow separate unit testing
* add try/catch unit tests
* assertError: add "Throw: assertError" and "Rethrow:" syntax function
* assertError: support catching specific exceptions
(done) * add an activationState to Config plugins. activeConfig is the selected plugin, activationState is enforcing,checking, or paused
(done) * bring over bg_plugins.sh
(done) * unitTests: consider #!bashTests shebangs instead of calling untiTestCntr at the end of the file
(done) * bug to fix: BC bg-debugCntr trace of<tab> -> off: gets a trailing : even those its suggestion does not have one -- tweak the $(nextBreakChar :) directive
(done) * add progress reporting to unitTest Runner
(done) * bgtraceBreak stops inside system code instead of a the the line after bgtraceBreak
(done) * reverse the direction of bgtraceStack traces to match the that of the debugger. Should be script at the top
(done) * add bg-debugCntr debugger stopOnAssert:(on|off)
(done) * (its called bgdb) add a bg-db() function to bg-debugCntr so that `bg-db <myscript>` invokes the debugger
(done) * make unitTestCntr an on-demand core function
(done) * break out progress from cui.sh to separate library script
(done) * unitTest: support ut_<func> without parameters. it ut_<func>: would run it without any params
(done) * unitTest: finish test runner in "bg-dev tests"
(done) * import: make L2 optional with function pass() { return $?; }   
(done) * implement on demand bash completion scripts
(done) * update funcman
*

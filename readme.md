# bg-core

This is a library for writing secure bash scripts. It supports many features that make it easier to write and maintain
good scripts that participates in the operating system's host environment.

Learn more in the package's man(7) bg-corePkg.

## Key features include...

 * import: system for importing (aka sourcing) bash libraries.
   See man(3) import  (you need to specify the section like man -s3 import)
 * options processing: easy, idiomatic options processing syntax that supports short and long options both with and without arguments and short option concatenation.
 * in-place cmdline argument completion: your script provides the completion data to bash so that the syntax is maintained in one place
   See man(3) _bgbc-complete-viaCmdDelegation, man(3) oob_printBashCompletion, and man(3) oob_invokeOutOfBandSystem
 * simple text template expansion against the linux environment variables
 * full featured bash debugger (the debugger UI's are in the bg-dev package)
 * easy to use error handling patterns with some exception throw / catch semantics and stack traces for script exits
   See man(3) assertError
 * tracing: system for putting trace statements in scripts that can be turned on/off and redirected to various destinations
   See man(1) bg-debugCntr
 * progress feedback: scripts can 'broadcast' their progress and the environment that the script runs and user preferences can determine if and how the progress is displayed
 * bash idioms: various idiomatic functions are provided to make passing parameters to functions and working with bash variables easier
 * cuiWin : when running on a desktop host, a script can open additional terminal windows to provide UI
 * object oriented: optionally organize your script with classes and objects
 * RBAC permission system (using sudo)
 * Daemon scripts: easily write a script which can be deployed as a full featured, manageable daemon
 * configuration files: read and write configuration files in a variety of formats

## Script Modularity

To build good scripts you need a good way to package reusable components.  Scripts that source /usr/lib/bg_core.sh can include library
scripts easily. A library script is any bash script that contains functions.

```bash
$ cat - >/tmp/mylib.sh
function myCoolFunction() {
    if [ ${1:-0} -eq 42 ]; then
        echo "its the answer to life and everything"
        return 42
    fi
    echo "p1 is '$1' and p2 is '$2'"
}
<cntr-d>
```
Then to use the library, import it into a script.
```bash
$ cat - >/tmp/test3.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh

import bg_ini.sh  ;$L1
import mylib.sh   ;$L1

myCoolFunction  "hello. we are running on" "$(iniParamGet /etc/os-release . ID "<unknownDistro>")"

<cntr-d>
$ chmod a+x /tmp/test3.sh
```
```bash
$ /tmp/test3.sh
p1 is 'hello. we are running on' and p2 is 'ubuntu'
```
The import syntax is a wrapper over the bash `source bg_ini.sh` command that adds idempotency (you can call it more than once with no ill effect), secure location finding, and other features. This means a library script can import its dependencies without regard to whether the script its being used in has imported it or not. The script also does not need to know where the library script is located which may be different on different OS and between production and development environments.  

The ` ;$L1` is an an idiomatic thing. Bash is not a modern language but its ubiquitous. Sometimes we need to adopt some idiom that might not be clear in itself but its simple and just works. To work efficiently, the import statement needs us to follow that syntax. IDE's can help make it easy to know what idioms are available and to follow them.

See:
* man(3) import
* man(3) importCntr

## Testing

To build good scripts and especially good script libraries, you need to define the expected behavior and automate the testing of each new change to see if the expected behavior is still achieved.

Unit tests scripts are simple bash scripts that follow a minimal pattern.
```bash
$ cat - >/tmp/test4.sh.ut
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
import mylib.sh ;$L1

declare -A ut_myCoolFunction=(
   ["testA"]="$(cmdline  0 "this is something else")"
   ["test42"]="$(cmdline 42 "this is something")"
)
function ut_myCoolFunction() {
    # expect: output of myCoolFunction be different if the first argument is 42
    myCoolFunction "$@"
}

# this should be the last line of any ut script
unitTestCntr "$@"

<cntr-d>
$ chmod a+x /tmp/test4.sh
```
```bash
$ /tmp/test4.sh.ut <tab><tab>
debug   list    run
$ /tmp/test4.sh.ut run myCoolFunction:test<tab><tab>
>        test42   testA    
$ /tmp/test4.sh.ut run myCoolFunction:test42
***** bg-debugCntr: Tracing='/tmp/bgtrace.out'. Vinstall='ON:bg-core:'

###############################################################################################################################
## test4.sh:myCoolFunction:test42 start
## expect: output of myCoolFunction to be what we want it to be
cmd> myCoolFunction "$@"
its the answer to life and everything
['ut onCmdErrCode "$?" "$BASH_COMMAND"' exitted 0]

## test4.sh:myCoolFunction:test42 finished
###############################################################################################################################
```

> Note that the .ut script gets command line completion automatically even without being installed on the host.

Its really no harder to write a .ut script as it would be to write the simplest of test scripts to exercise some new functionality you are creating so it encourages writing test scripts this way during development.

It allows direct running of the tests while you are authoring your library or command and it also works with the `bg-dev test` tools in a project to run and track the results in a project integrated with a continuous build system.

The output of the test just records what happens on stdout, stderr and exit codes that are not 0. In the `bg-dev test` system a testcase passes if the output matches the output previously committed to the project. This makes it easy to test error paths as well as success paths and the testcase data becomes documentation of the expected behavior and how and when that behavior changes over the life of a project.

> Note that testcases can document and test the effects of any command, not just those written in bash.

See:
* man(7) bg_unitTest.sh
* man(1) bg-dev-test

## Debugging

To be productive in writing scripts we need to be able to debug them during the initial development and also later if an issue is reported.

A testcase can be invoked in the debugger like this.
```bash
$ /tmp/test4.sh.ut debug myCoolFunction:test42
```
A new terminal will open running a debugger stopped on the line after the bgtraceBreak. The default UI is a terminal window running a debugger written in BASH so the requirements are minimal.

You can also configure the terminal to connect to a stand alone JS GUI debugger or an Atom IDE debugger. The debugger protocol is documented so other IDEs can be supported.

Any script that sources /usr/lib/bg_core.sh can be ran in the debugger. There are a number of ways to invoke the debugger such as inserting a bgtraceBreak call at the place in your script that you want to examine.

The debugger is part of a larger system of development that includes a tracing system and virtual in-place installation of project source folders.

The `bg-debugCntr` command from the bg-dev package is the interface to many debugging and development time features.

```bash
$ source bg-debugCntr
$ bg-debugCntr trace on:
BGTracing status     : desination='/tmp/bgtrace.out' (bgTracingOn='on:')
```
in another terminal enter ...
```bash
$ tail -f /tmp/bgtrace.out
```

now in the first terminal enter ...
```bash
$ bg-debugCntr vinstall  sourceCore
$ declare -A foo=([hat]="head" [shirt]="body" [shoe]="foot")
$ bar="hello world"
$ bgtraceVars foo bar
$
```
and observe in the second terminal window...
```bash
$ tail -f /tmp/bgtrace.out
foo[]
   [shirt]='body'
   [shoe ]='foot'
   [hat  ]='head'
bar='hello world'
```

This illustrates two things. First when you run the sourceCore command it sources bg_core.sh into the terminal so that the terminal behaves like the inside of a script. This allows you to interactively test things out. While I write a new function, I often paste the commands into a terminal periodically to check that they work. BASH is a weird, quirky language so it really helps to confirm what you write as you go.

And second, the bgtraceVars function is a powerful debugging aid that allows you to inspect variables inside your script. There are many bgtrace* functions and the output can be suppressed or sent to a variety of places. The output of bgtraceVars can be copy and pasted into a terminal to set the variable state to test out commands interactively that reference those variables.

See:
* man(1) bg-debugCntr
* man(7) bg_debugTrace.sh
* man(1) bg-dev
* man(3) bgtrace
* man(3) bgtrace*

## Error Handling

Good software of any kind needs to be robust and transparent so if it does not succeed, it provides information about why and how to proceed.

Scripts that source /usr/lib/bg_core.sh can use a family of assert* functions to make sure the script fails well when a error is encountered.

```bash
$ cat - >/tmp/test5.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
function bar() {
    local p1="$*"
    ls "$p1" --FOO 2>$assertOut || assertError
}
function foo() { bar "hello" "$@"; }
function myFunc() { foo  "$@"; }
myFunc "hoopla" "$@"
<cntr-d>
$ chmod a+x /tmp/test5.sh
```

```bash
$ /tmp/test5.sh hey

error: bar: ls "$p1" --FOO 2>$assertOut || assertError
    exitCode='2'
    p1='hello hey'
    : ls: unrecognized option '--FOO'
    : Try 'ls --help' for more information.
```
Notice how the default error report shows us the source line of the command that failed and even the values of the variables used in that line. assertError can be passed many options to affect how the error is displayed and with what context.

Lets run it again with bgtrace enabled to get a full stack trace.
```bash
$ /tmp/test5.sh blue
ls: unrecognized option '--FOO'
Try 'ls --help' for more information.

error: bar: ls "$p1" --FOO || assertError
    exitCode='2'
    p1='hello hoopla'

: bash(1151822)───bash(1151837)───pstree(1151883)
===============  BASH call stack trace P:1151822/1151837 TTY:/dev/pts/7 =====================
 <bash:1151822>:(1):        :  test5.sh blue
 test5.sh:(9):              : myFunc "hoopla"
 test5.sh:(8):              : function myFunc() { foo  "$@"; }
 test5.sh:(7):              : function foo() { bar "hello" "$@"; }
 test5.sh:(5):              : ls "$p1" --FOO || assertError
=================  bottom of call stack trace  ==========================
$
```
We can also use `bg-debugCntr debugger stopOnAssert` to invoke the debugger if an uncaught assert happens.

When writing reusable library code, you don't really know how the script that uses your code will want to deal with the errors it might produce. The assert* family of functions allows you to declare that the function can not complete its task but not necessarily that the script needs to exits.

Calling an assert is similar to throwing an exception in other languages. Modify the test5.sh script to put Try: / Catch: statements around the call to myFunc
```bash
Try:
    myFunc "$@"
Catch: && {
    echo "caught and ignoring this exception"
    printfVars "${!catch_*}"
}
```

```bash
$ /tmp/test5.sh hey
caught and ignoring this exception
catch_errorClass='assertError'
catch_errorCode='36'
catch_errorDescription='
                        error: bar: ls "$p1" --FOO 2>$assertOut || assertError
                            exitCode='2'
                            p1='hello hey'
                            stderr output=
                              : ls: unrecognized option '--FOO'
                              : Try 'ls --help' for more information.'
catch_psTree=': bash(1205874)---bash(1205980)---pstree(1205982)'
catch_stkArray[]
              [0]=' <bash:1205874>:(1):        :  test5.sh hey '
              [1]=' test5.sh:(13):             : myFunc "$@"'
              [2]=' test5.sh:(10):             : function myFunc() { foo  "$@"; }'
              [3]=' test5.sh:(9):              : function foo() { bar "hello" "$@"; }'
              [4]=' test5.sh:(7):              : ls "$p1" --FOO 2>$assertOut || assertError'

```
Now the script continues to completion instead of ending prematurely. We printed out all the catch_* variables so that you can see the context the Catch block has at its disposal to determine what happened and decide how to proceed.

See
* man(1) bg-debugCntr
* man(7) bg_debugger.sh
* man(3) assertError
* man(3) Try:
* man(3) Catch:


## Documentation

When you spend time and effort to build script commands and libraries you want them to be understood and used so this system provides two important mechanisms to document your work as you write it.

`bg-dev funcman` scans scripts and produces documentation from the the comments and other information that it gleans. This can produce man(1) pages for each script command, man(3) pages for public script functions in libraries and man(7) pages for each script library.
The bg-core uses this to provide man pages for each command, library, protocol, and public function. While writing a script, the bash
completion on man pages lets you lookup a bash function name and then see how to use it.

See
* man(1) bg-dev-funcman
* man(7) bg_funcman.sh

The second mechanism is the "out of band" script mechanism. When a script includes a call to  `oob_invokeOutOfBandSystem`, the command will inherit certain functionality. The -h option will open the command's man page and bash completion will be supported.

Command line completion is an important form of documentation. The BC (bash completion) support adds a convention that comment strings
can be added to the suggested words to give the user context about what they are entering. Comments are surrounded by '<>' which makes
then unselectable.

```bash
$ cat - >/tmp/test6.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
function oob_printBashCompletion() {
    bgBCParse "vqf:" "$@"; set -- "${posWords[@]:1}"
    cmd="${posWords[1]}"
    case $cmd:$posCwords in
        *:1) echo "get set increment <chooseASubCmd>" ;;
        get:2|set:2) echo "\$(doFilesAndDirs) <chooseATestFile>" ;;
        set:3) echo "one two three" ;;
    esac
}
oob_invokeOutOfBandSystem "$@"
# ... the 'real' script follows...
<cntr-d>
$ chmod a+x /tmp/test6.sh
```

```bash
$ /tmp/test6.sh
<chooseASubCmd>  get         set         increment
```

By having the bash completion algorithm inside the script, it encourages it to be developed and maintained along with the script. I find that I build the command line syntax first for each new feature I write so that I dont have to type the whole command line out while testing a new script. BC becomes a sort of UI for the command line that gives the user feedback while they complete the cmdline.

There is emerging support for gleaning the command line syntax from the usage comments in the file so that we would not even have to write the completion routine at all. If we define the oob_printBashCompletion function, we can have complete control over the syntax but if we leave it out, the syntax would be gleaned.

See
* man(3) _bgbc-complete-viaCmdDelegation
* man(3) oob_invokeOutOfBandSystem


## Command Structure

Every language has a function call protocol that defines the mechanism that passes arguments provided by the caller to the parameters expected by the function. This is the principle thing that makes any shell language like BASH different from other languages. Its a blessing and a curse. The blessing is that it makes the language mimic typing commands at a terminal and bash functions are called just like any external command installed on the host.  The curse is that compared to modern languages, the syntax can be quirky and cryptic.

Supporting the traditional command line syntax with long and short options with and without arguments, entered with and without separating spaces and optionally combining multiple short options has been very hard until now. The bgOpt* family of functions allow a syntax that is easy to reproduce in scripts and functions to support all conventions with a minimum of overhead.

```
$ cat - >/tmp/test8.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
oob_invokeOutOfBandSystem "$@"
while [ $# -gt 0 ]; do case $1 in
	-a|--all)  allFlag="-a" ;;
	-b|--my-bFlag) myBFlag="-b" ;;
	-c*|--catBread*) bgOptionGetOpt val: catBread "$@" && shift ;;
	*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
done
p1="$1"; shift
p2="${1:-"defaultP2Value"}"; shift
printfVars allFlag myBFlag catBread p1 p2
<cntr-d>
$ chmod a+x /tmp/test8.sh
```
Ok, at first glance this is not simple. But its another idiomatic thing. The first and last two lines of the while loop are constant. You dont need to think about them. Copy and paste them or rely on an editor snipit to add them to your script or function. What you do care about are the lines starting with -a, -b, and -c. Each of those lines introduce a supported option. Option -c requires an argument.
After a while, you get conditioned to recognizing the options loop at the start of a function or script body and it becomes simple to understand.

The glean feature in the bgBCParse function understands this idiom so it automatically provides completion help for the user to know that options are available, what they are, and which require arguments. This script does not implement a oob_printBashCompletion callback so it will use the default BC algorithm using only the glean feature.

```
$ /tmp/test8.sh<tab><tab>
<optionsAvailable>  >                   
$ /tmp/test8.sh -<tab><tab>
<options>    -a           --all        -b           --my-bFlag   -c           --catBread=  
$ /tmp/test8.sh --catBread=calico one
allFlag=''
myBFlag=''
catBread='calico'
p1='one'
p2='defaultP2Value'
```




## Daemons

Some commands are meant to be invoked by a user and others are meant to run in the background to provide some long running feature. Still others are meant to be invoked in response to some system event. Scripts that are run by the host init system  are daemons.

Writing a good unix/linux daemon has traditionally been difficult. Scripts that source /usr/lib/bg_core.sh can declare that they are a daemon and the oob_printBashCompletion system will provide many common features that a good daemon should support. For testing, the daemon can be started and stopped manually without installing it into the host and then when packaged and installed on a host, it
will controlled by systemd, sysV, or what ever init system the host supports.

```bash
$ cat - >/tmp/test7.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
daemonDeclare "$@"
oob_invokeOutOfBandSystem "$@"
while ! daemonCheckForSignal INT TERM; do
    echo "hi for the $((count++))th time"
    bgsleep 5
done
daemonOut
<cntr-d>
$ chmod a+x /tmp/test7.sh
```

```terminal
$ sudo /tmp/test7.sh -F
[sudo] password for bobg:
hi for the 0 time
hi for the 1 time
^C
```

```terminal
$ /tmp/test7.sh start
test7.sh has started
$ /tmp/test7.sh status -v
test7.sh is running (1531347)
no auto start configuration is installed
log file            (-vv): /var/log/test7.sh
PID file                 : /var/run/test7.sh.pid
last 3 log lines:
   > hi for the 10 time
   > hi for the 11 time
   > hi for the 12 time
$ /tmp/test7.sh stop
test7.sh is stopped
```
Note that sudo is required to run the daemon so that it can write to the pid and log files in the system folders. You can configure
The daemon to drop privilege to a different user and it will manage the ownership and permissions on those files accordingly.

The loop of this daemon wakes up every 5 seconds to do something. It could alternatively block on reading a pipe to receive messages.
The daemonCheckForSignal API allows the daemon to respond to signals synchronously with respect to the task that it performs. For
example, when it receives SIGTERM, it will finish the current loop and then drop out to the exit code so that it shuts down gracefully.


## Configuration Files

Devops and sysops coding involves


## Project Folder structure and naming

This project is managed by the bg-dev project tools. It initially contains only bash script libraries but it may grow to include some commands or other assets over time.

Typically bash libraries are placed in the lib/ subfolder but this project places them in several subfolders for organization.

### Root level

The root level of this project contains the bg_core.sh script library. That is the entry point for sourcing any of the libraries. bg_core.sh is sourced from its well known /usr/lib/bg_core.sh location. All other libraries are sourced via the import <libFile> ;$L1;$L2 syntax.

The only responsibility of bg_core.sh is to setup the host security environment and sourcing the bg_coreImport.sh library which introduces the import system and imports the unconditional core libraries.

### core/

The core/ subfolder contains the core libraries that are imported unconditionally when a script sources /usr/lib/bg_core.sh

### coreOnDemand/

The coreOnDemand/ subfolder contains libraries that are not imported initially when a script sources /usr/lib/bg_core.sh but will be automatically imported if certain features are used by the script. For example, if the script declares the daemonDefaultStartLevels variable and uses the daemonDeclare API to become a daemon script, the bg_coreDaemon.sh library will be imported.

### lib/

The lib/ subfolder contains libraries that are available for a script to use if they import them.

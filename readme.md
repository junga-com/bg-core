# bg-core

| :warning: WARNING          |
|:---------------------------|
| This library is in a pre-release state. The readme file is full of mini tutorials that demonstrate most of the features. If you try any out, I would love to here about your experience.<br/><br/>circa 2022-09 all test cases are passing in the environments listed using FreshVMs and virtually installing the projects. It will build into a deb and rpm package but I am not yet testing the installation via packages yet but plan to soon.|

## Tested Environments
I have tested this library on
 * Ubuntu 20.04 (focal)
 * Ubuntu 22.04 (jammy)
 * Centos Stream 9.

It should work in other distributions and versions without major change.

## Installing
I will start uploading deb and rpm packages soon (circa 2022-09). If there is a package for the OS you use, downloading and installing it is probably the easiest way to try out this library.

Alternatively, you can follow these steps to clone the required projects and 'virtually' install them which allows only the terminal where you run the commands to act as if the projects where
installed on your host.
```bash
  ~/github$ git clone https://github.com/junga-com/bg-coreSandbox.git
  ~/github$ cd bg-coreSandbox
  ~/github/bg-coreSandbox$ git submodule init
  ~/github/bg-coreSandbox$ git submodule update
  ~/github/bg-coreSandbox$ source bg-dev/bg-debugCntr
```

## Overview

This is a library for writing secure bash scripts. It provides many features that make it easier to write and maintain good scripts that participates in the operating system's host environment.

The motivation of this package is a philosophy that developing software at all levels should be linearly independent. Instead of developing platforms that can be hosted on an OS, the OS is the platform and components coexist and compliment each other.

This is a form of integrating DevOps into application development.

This package is part of a larger ecosystem that I have developed consisting of first, a productive shell scripting environment, second a modern high performance scripting language (javascript), and third, high performance native code (C/C++/WebAsm). Components written in any of these environments are available in the others.


## Key features include...
Click on each item to scroll down to its mini-tutorial.

 * [Script Modularity](#Script-Modularity): An Import System for importing (aka sourcing) bash libraries.
   See man(3) import  (you need to specify the section like man -s3 import)
 * [Testing](#Testing): A system for maintaining unit tests alongside scripts and other resources.
 * [Debugging](#Debugging): Features to debug BASH scripts using a debugger or tracing.
 * [Error Handling](#Error-Handling): Make robust scripts that print relevant diagnostics when they do not succeed.
 * [Documentation](#Documentation): Produce man pages and web sites automatically from scripts content.
 * [Command Structure](#Command-Structure): Supports a simple pattern for defining the options and positional parameters that a command script or script function accepts. Automatically supports short and long form options with and without arguments. Automatically supports command line completion to document the optional and required parameters.
 * [Daemons](#Daemons): Create a script application that is controlled on the target host as a daemon.
 * [Configuration Files](#Configuration-Files): Read and set configuration settings in various file formats.
 * [Object Oriented Bash](#Object-Oriented-Bash): Use object oriented techniques to organize BASH script code.
 * [Plugins](#Plugins): Plugins provide a way to build features that can be extended by third party scripts delivered in different packages.
 * [RBACPermission Plugins](#RBACPermission-Plugins): Define permissions that can be granted to users that results in the user being able to perform only a specific function.
 * [Collect Plugins](#Collect-Plugins): Activating a Collect plugin on a host causes it to record some information periodically. This is typically used to collect information on hosts into a central management system.
 * [Declarative Configuration Part 1 -- Creqs](#declarative-configuration-part-1----creqs): A declarative configuration statement describes how something on a host should be and then can be used to either test to see if the host complies with the description or modify the host so that it does.
 * [Declarative Configuration Part 2 -- Standards and Config Plugins](#Declarative-Configuration-Part 2----Standards-and-Config-Plugins): These plugin types provide a script written with creqs that represent a unit of configuration that can be applied or checked.
 * [Simple Text Database](#Simple-Text-Database): awkData is a lightly coupled, low barrier to entry database system.


This is a list of some noteable discrete features...
 * printfVars: powerful and compact way to format shell variables of various types for output
 * templates: simple text template expansion against the linux environment variables
 * debugger: full featured bash debugger (the debugger UI's are in the bg-dev package)
 * assertError: easy to use error handling patterns with some exception throw / catch semantics and stack traces for script exits
 * bgtrace: tracing: system for putting trace statements in scripts that can be turned on/off and redirected to various destinations
 * progress feedback: scripts can 'broadcast' their progress and the environment that the script runs and user preferences can determine if and how the progress is displayed
 * bash idioms: various idiomatic functions are provided to make passing parameters to functions and working with bash variables easier
 * cuiWin : when running on a desktop host, a script can open additional terminal windows to provide UI
 * object oriented: optionally organize your script with classes and objects
 * RBAC permission system (using sudo)
 * Daemon scripts: easily write a script which can be deployed as a full featured, manageable daemon
 * configuration files: read and write configuration files in a variety of formats
 * awkData: a lightly coupled text file database system.


## Script Modularity

To build good scripts you need a good way to package reusable components.  Scripts that source /usr/lib/bg_core.sh can include library scripts easily. A library script is any bash script that contains functions.

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

import mylib.sh   ;$L1;$L2

myCoolFunction  "hello. we are running on" "$(iniParamGet /etc/os-release . ID "<unknownDistro>")"

<cntr-d>
$ chmod a+x /tmp/test3.sh
```
```bash
$ /tmp/test3.sh
p1 is 'hello. we are running on' and p2 is 'ubuntu'
```
This import syntax is a wrapper over the bash `source` builtin that makes it easier and convenient to use.

It adds idempotency which means you can call it more than once with no ill effect so that you do not have to be concerned if something else in the script has already sourced the library.

It adds a secure search path so that you can import the name of the library script without being concerned with where the library is. A library script can be included in a package that can be installed as needed.

The ` ;$L1;$L2` part of the syntax is an an idiomatic thing. Bash is not a modern language but its ubiquitous. Sometimes we need to adopt some idiom that might not be clear in itself but its simple and just works. To work efficiently, the import statement needs us to follow that syntax. IDE's can help make it easy to know what idioms are available and to follow them.

See:
* man(3) import
* man(3) importCntr

## Testing

To build good scripts and especially good script libraries, you need to define the expected behavior and automate the testing of that behavior each time a change is made.

Unit tests scripts are simple bash scripts that follow a minimal pattern.
```bash
$ cat - >/tmp/test4.sh.ut
#!/usr/bin/env bg-utRunner
import mylib.sh ;$L1;$L2

declare -A ut_myCoolFunction=(
   ["testA"]="$(cmdline  0 "this is something else")"
   ["test42"]="$(cmdline 42 "this is something")"
)
function ut_myCoolFunction() {
    # expect: output of myCoolFunction be different if the first argument is 42
    myCoolFunction "$@"
}
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
By default, if the terminal environment has the DISPLAY var set, a new terminal window will open running a debugger stopped on the line after the bgtraceBreak. If DISPLAY is not set, it will use the page feature of the terminal to switch to and from the debugger UI. You can specify the debugger destination explicitly with the `bg-debugCntr debugger ...` command. That command also controls whether the debugger will be invoked if you enter cntr-c or if the script encounters an uncaught exception.

You can also configure the debugger to connect to an Atom IDE debugger. If you use a different IDEs it should be pretty straight forward to add support for debugging from that environment.

Any script that sources /usr/lib/bg_core.sh can be ran in the debugger. There are a number of ways to invoke the debugger such as inserting a bgtraceBreak call at the place in your script that you want to examine. When bg-debugCntr is sourced you can use `bgdb <script> <arguments...>`. bgdb works with foreign scripts that do not source bg_core.sh (at least for simple scripts).

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

Good software of any kind needs to be robust and transparent when it it encounters a problem. Scripts that source /usr/lib/bg_core.sh can use a family of assert* functions to make sure the script fails well when a error is encountered.

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
$ bg-debugCntr trace off
$ /tmp/test5.sh hey

error: bar: ls "$p1" --FOO 2>$assertOut || assertError
    exitCode='2'
    p1='hello hey'
    : ls: unrecognized option '--FOO'
    : Try 'ls --help' for more information.
```
Because bgtrace is off, this is the message a normal user would see when encountering an un-caught exception in a script. Notice how the default error report shows us the source line of the command that failed and even the values of the variables used in that line. This gives the user some information that might help them work around the problem. assertError can be passed many options to affect how the error is displayed and with what context.

Lets run it again with bgtrace enabled to get a full stack trace. This is what the developer typically sees when an exception is encountered while testing the script.
```bash
$ bg-debugCntr trace on:
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
The stack trace lets the developer understand the context that the exceptions happened in.

We can also use `bg-debugCntr debugger stopOnAssert` to invoke the debugger if an uncaught assert happens.

Calling an assert is similar to throwing an exception in other languages. When writing reusable library code, you don't really know how the script that uses your code will want to deal with the errors it might produce. The assert* family of functions allows you to declare that the function can not complete its task but not necessarily that the script needs to exit because the calling script can catch and handle the exception.

Modify the test5.sh script to put Try: / Catch: statements around the call to myFunc
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
Now the script continues to completion instead of ending prematurely. We printed out all the catch_* variables so that you can see the context the Catch block has at its disposal to determine what happened and to decide how to proceed. A real script might do some cleanup and rethrow the exception or log the error and proceed.

See
* man(1) bg-debugCntr
* man(7) bg_debugger.sh
* man(3) assertError
* man(3) Try:
* man(3) Catch:


## Documentation

When you spend time and effort to build script commands and libraries you want them to be understood and used so this system provides two important mechanisms to document your work as you write it.

`bg-dev funcman` scans scripts and produces documentation from the the comments and other information that it gleans. This can produce man(1) pages for each script command, man(3) pages for public script functions in libraries and man(7) pages for each script library.
While writing a script, the bash completion on man pages lets you lookup a bash function name and then see how to use it.

See
* man(1) bg-dev-funcman
* man(7) bg_funcman.sh

The second mechanism for documentation is Command line completion support. When a script includes a call to  `oob_invokeOutOfBandSystem`, the command will inherit certain functionality. It will recognize when the script is invoked with an option that starts with "-h". The -h option will open the command's man page and other out of band options like -hb allow a generic bash completion stub to query the script for information about that command line syntax it requires.

This allows the script itself to provide the bash completion routine so that the bash completion can be developed as a first class feature of the script.

Command line completion is an important form of documentation so that users can get information about the command as they attempt to use it. This mechanism adds a notion to bash completion that in addition to suggested words, the command can also display non-selectable comment words that gives the user context about the command line parameter being entered.

```bash
$ cat - >/tmp/test6.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
cmdSyntax="[-v] [-q] [-f|--file=<foo>] <name> <species>|dog|cat|human"
function oob_printBashCompletion() {
    bgBCParse -RclInput "$cmdSyntax" "$@"
    case $completingArgName in
        '<name>') getent passwd | awk -F: '$3>=1000{print $1}' ;;
        '<foo>')  echo "\$(doFilesAndDirs)" ;;
    esac
}
oob_invokeOutOfBandSystem "$@"
# ... the rest of the script would follow...
bgCmdlineParse -RclInput "$cmdSyntax" "$@"
echo "your name is '${clInput[name]}'"
printfVars clInput
<cntr-d>
$ chmod a+x /tmp/test6.sh
```

```bash
$ /tmp/test6.sh <tab><tab>
<optionsAvailable>  <name>              -                   nobody              bobg                libvirt-qemu        nobody
$ /tmp/test6.sh -<tab><tab>
<options>  -v         -q         -f         --file=    
$ /tmp/test6.sh --file=<tab><tab>
<foo>                       bg-dom/                     bg-atom-utils/              tags                     bgit
$ /tmp/test6.sh --file=tags <tab><tab>
<optionsAvailable>  <name>              -                   nobody              bobg                libvirt-qemu        nobody
$ /tmp/test6.sh --file=tags bobg <tab><tab>
<species>  dog        cat        human      
$ /tmp/test6.sh --file=tags bobg cat
***** bg-debugCntr: Tracing='/tmp/bgtrace.out'. Vinstall='ON:bg-core:'
```

By having the bash completion algorithm inside the script, it encourages its development and maintenance along with the script. I find that I build the command line syntax first for each new feature I write so that I can select files and other parameters from lists instead of finding the values and typing them in. BC becomes a sort of UI for the command line that gives the user lists of choices. Also, by providing the BC code inside the script, the functions that the script uses are available so that it can be very dynamic, filtering the list to exactly the values that are possible given the arguments already completed. Check out the bg-awkData command for a great example of that.

There are many ways to write an oob_printBashCompletion function. This example passes a syntax string to bgBCParse that allow it to do most of the work. Then it adds to the results by providing suggestions for <name> and <foo> type arguments.

See
* man(3) _bgbc-complete-viaCmdDelegation
* man(3) oob_invokeOutOfBandSystem


## Command Structure

Every language has a function call protocol that defines the mechanism that passes arguments provided by the caller to the parameters expected by the function. The call mechanism used by shell language like BASH is the principle thing that makes them different from other languages. The call mechanism they use is both a blessing and a curse. The blessing is that it makes the language mimic commands typed at a terminal and bash functions are called just like any external command installed on the host.  The curse is that compared to modern languages, the syntax can be quirky and cryptic.

A convention has formed around the syntax of passing arguments to commands. Arguments can be optional or positional. Optional arguments can be specified on the command line in different ways -- short and long options, with and without an argument, options and their arguments can sometimes be combined into one token or can be specified in multiple tokens.

Supporting this syntax convention completely has been so hard that it is common that simple or quickly written scripts do not attempt to fully support it. This makes commands less uniform. The bgOpt* family of functions makes it so that the easiest way to add support for an option will fully support the convention fully.

Check out this example script.
```
$ cat - >/tmp/test8.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
oob_invokeOutOfBandSystem "$@"
while [ $# -gt 0 ]; do case $1 in
	-a|--all)  allFlag="-a" ;;
	-b|--my-bFlag) myBFlag="-b" ;;
	-c*|--catBreed*) bgOptionGetOpt val: catBreed "$@" && shift ;;
	*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
done
p1="$1"; shift
p2="${1:-"defaultP2Value"}"; shift
printfVars allFlag myBFlag catBreed p1 p2
<cntr-d>
$ chmod a+x /tmp/test8.sh
```
Ok, at first glance this is not simple. But its an idiomatic thing. The first and last two lines of the while loop are constant. You dont need to think about them. Copy and paste them or rely on an editor snipit to add them to your script or function. What you do care about are the lines starting with -a, -b, and -c. Each of those lines introduce a supported option. Can you tell that option -c requires an argument and options -a and -b do not?

After a while, you get conditioned to recognizing the options loop at the start of a function or script body and it becomes simple to understand.

This script uses the default BC behavior which will glean the option syntax from the standard options block to let the user know that optional arguments are available, what they are, and if any require an argument.  You could define the oob_printBashCompletion callback function in your script to add bespoke option processing if needed. Note that the words surrounded in &lt&gt are comments that give the user context and can not be selected.

```
$ /tmp/test8.sh<tab><tab>
<optionsAvailable>  >                   
$ /tmp/test8.sh -<tab><tab>
<options>    -a           --all        -b           --my-bFlag   -c           --catBreed=  
$ /tmp/test8.sh --catBreed=calico one
allFlag=''
myBFlag=''
catBreed='calico'
p1='one'
p2='defaultP2Value'
```




## Daemons

Some commands are meant to be invoked by a user and others are meant to run in the background to provide some long running feature. Still others are meant to be invoked in response to some system event. Commands that are run by the host system as opposed to a user are daemons.

Writing a good linux daemon has traditionally been difficult, especially as a script.  bg-core provides a way to easily create a script file that runs as a well behaved daemon.

For testing, the daemon can be started and stopped manually without installing it into the host and then when packaged and installed on a host, it will controlled by the host's init system whether its systemd, sysV, or upstart.

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
Note that sudo is required to run the daemon so that it can write to the pid and log files in the system folders. You can configure the daemon to drop privilege to a different user and it will manage the ownership and permissions on those files accordingly.

The loop of this daemon wakes up every 5 seconds to do something. It could alternatively block on reading a pipe to receive messages. The daemonCheckForSignal API allows the daemon to respond to signals synchronously with respect to the task that it performs. For example, when it receives SIGTERM, it will finish the current loop and then drop out to the code after the loop so that it shuts down gracefully.


## Configuration Files

Devops and sysops coding involves a lot of configuration file manipulation. The bg_ini.sh library provides commands to read and write to different kinds of configuration files (not just just ini formatted files) while the bg_template library provides a way to manage
and expand a library of template files.

#### Reading and writing config file settings

```bash
$ bg-debugCntr vinstall sourceCore  
$ import bg_ini.sh ;$L1;$L2
$
$ iniParamSet /tmp/data9 . name bobg
$ iniParamSet /tmp/data9 home state "Ca"
$ iniParamSet /tmp/data9 work state "NY"
$ cat /tmp/data9
name=bobg

[ home ]
state=Ca

[ work ]
state=NY
$
$ iniParamGet /tmp/data9 home state
Ca
$ iniParamGet /tmp/data9 webserver template

$ # there is no webserver template setting. We can provide a default
$ iniParamGet /tmp/data9 webserver template mytemplate
mytemplate
$ iniParamSet /tmp/data9 webserver template yourTemplate
$ iniParamGet /tmp/data9 webserver template mytemplate
yourTemplate
```
There are many features of the ini* and config* functions from bg_ini.sh so this example only illustrates a few. When these functions make a change to files, they preserve the existing order and comments where ever possible. They try to make the change as close as possible to how a human would make the change, preserving work done by other humans to organize and comment the file.

Note that the [webserver]template setting inside /tmp/data9 did not initially exist. A common idiom is that when making a script we decide that it needs some information like a file path. We dont want to hard code it but we also want the script to work in a reasonable way with zero configuration. So we can retrieve the value from a config file and provide a reasonable default value. If the config file does not exist or the setting is missing, the default value is returned but the host admin or end user can configure the file to change the script's behavior. The script author can mention the setting in the comments of the script that will become the man page.

#### Domain Configuration

The `domDataConfig ...` function from bg_domData.sh library is similar to the iniParam function but uses a concept of a virtual config file for the operating domain. We do not pass the configuration filename to the function call since it uses the well known global file.  That file is 'virtual' because it is actually the combination of multiple files that produce the end result.  This makes it so that a domain admin can change the default value for a set of hosts and a local host admin could override that default.  The most specific value will be used. When changing a value, the default is to change it only on the host but if the user has sufficient privilege, they can specify that it be changed at a different scope level.


#### Templates

There are many different template languages but what separates the template system in bg_core is that it is native to the OS environment. These templates are expanded against the bash shell variables which include the OS ENVIROMENT variables.

```bash
$ bg-debugCntr vinstall sourceCore  
$ import bg_template.sh ;$L1;$L2
$ templateExpandStr "Hello %USER%. My favorite color is %color:blue%"
Hello bobg. My favorite color is blue
$ color=red
$ templateExpandStr "Hello %USER%. My favorite color is %color:blue%"
Hello bobg. My favorite color is red
```
Here for brevity I expanded a string literal template but I could have done the same by putting the content in a file.

The template functions use a notion of 'system templates'. System templates are specified by their simple filename without a path. System templates require privilege to install on a host -- either by installing a package that provides template assets or by a sysadmin using privilege to copy or create one in the /etc/bgtemplates/ folder. The findTemplate function will only return system templates so that the caller can trust that any found template comes from a privileged source. As always, during developement of a package security is reduced so that templates can be developed in-place in a virtually installed package.

The security around system templates is important because templates can be used to configure daemons and other system processes that could be compromised if untrusted content made its way into the configuration.  

## Object Oriented Bash

When writing a full featured script, one comes up against a limitation of bash's concept of data scope. There is no native concept of data structures that can be passed around to functions and nested inside each other so its hard to write all but the most simple data structures and functions that work with them.

The reason for the bg_objects.sh library is to alleviate this data structure shortcoming. The OO syntax is just a nice side affect.

```bash
$ cat - >/tmp/test7.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
import bg_objects.sh ;$L1;$L2

DeclareClass MyData
function MyData::__construct() {
    this[filename]="$1"
    $this.data=new Array
}
function MyData::read() {
    mapfile -t data < "$filename"
}

function process() {
    local -n dataFile="$1"
    echo "processing $($dataFile.data[2])"
    $dataFile.data[2]="done"
}

ConstructObject MyData d1 /tmp/data
$d1.read
printfVars d1

process d1
printfVars d1

<cntr-d>
$ chmod a+x /tmp/test7.sh
```

```bash
$ /tmp/test7.sh
d1 : MyData
   filename: /tmp/data
   data    : <instance> of Array
      [0]: one fish
      [1]: two fish
      [2]: red fish
      [3]: blue fish
processing red fish
d1 : MyData
   filename: /tmp/data
   data    : <instance> of Array
      [0]: one fish
      [1]: two fish
      [2]: done
      [3]: blue fish
$
```

The most important thing is that we can now easily create bash arrays within arrays.

Initially I considered the object syntax a novelty because the object syntax was so much slower that native bash syntax that all but the most carefully crafted scripts that used it heavily would be uncomfortably slow. However, with the introduction of the bgCore bash loadable builtin, the object syntax is in the same magnitude of performance as native bash function calls.

The bg-dev project uses bash object syntax extensively to create a hierarchy of project types.

See
* man(7) bg_objects.sh
* man(3) DeclareClass
* man(3) ConstructObject
* project bg-core-bash-builtins


## Plugins

The plugin system formalizes the process of building features in packages that can be extended by other packages.

A pluginType is a particular type library file named like `<MyNewPluingTypeName>.PluginType` which follows the protocol described in `man(3) DeclarePluginType`. It is convenient to write these in bash but the protocol allows them to be written in any language including complied languages.

Features in that package that provides <MyNewPluingTypeName>.PluginType can then query the host for available plugins of the <MyNewPluingTypeName> type and invoke them.

Another package can then include a plugin of that <MyNewPluingTypeName> type by creating a library written in bash or another language named like `<myPluginName>.<MyNewPluingTypeName>`. Now when that package is installed, <myPluginName> will be available to the features written in the first library.

Boy, that a mouth full. I think an example will make it more clear.

The bg-core package includes the Collect.PluginType library which introduces the 'Collect' plugin type. The bg-collectCntr command is a 'feature' that will list all the available Collect plugins installed on the host and allows running now or enabling them to be ran on a schedule.

The purpose of Collect plugins is to gather information about the host that will be collected into a central administration system.

The bg-core library provides osBase.Collect and a few other Collect plugins that collect information that is universal to any linux host.

Other packages can provide a Collect plugin that gathers the information specific to its provisioning and configuration so that it will be visible to the central administration system in use.

The bg-collectCntr is a feature in bg-core that can be extended by packages providing Collect plugins to collect information specific to them.

## Distributed System Administration

In the Plugins section I use bg-core's Collect plugin type as an example of how plugins work. That plugin type is one of several that provide secure distributed command and control of a set of hosts in a domain.

* RBACPermission  : a way to configure sudo to provide RBAC access control for linux commands
* Collect : Collect plugins retrieve some information about the host and put it in a shared repository for domain administration
* Standards : Standards plugins check some aspect of the host configuration state to see if it complies with a standard.
* Config : Config plugins provide some discrete unit of configuration that can be turned on or off

#### RBACPermission Plugins

When an RBACPermission Plugin is activated on a host, it makes it so that a user that is in the group with the same name of the plugin can use sudo to execute the commands named in the plugin.

```bash
$ cat /usr/lib/upgradeSoftware.RBACPermission
#!/bin/bash

DeclarePlugin RBACPermission upgradeSoftware "
	auth: NOPASSWD
	runAsUser: root
	cmd: apt-get upgrade
	 apt-get update
	 apt upgrade
	 apt update
	goal: allows upgrading software but not installing new software
"
$ bg-rbacPermissionCntr activate upgradeSoftware
[sudo] password for bobg:
$ bg-rbacPermissionCntr report
Name                 Enabled    
upgradeSoftware      activated  
```
This is particularly powerful when a central user directory is used to administer users and group membership. If a user is put in the `upgradeSoftware` group, they would be able to run `sudo apt upgrade` on any host where this plugin is activated. The plugin actually introduces a family of group names like `upgradeSoftware-<hostGroup>` where `<hostGroup>` is either a specific hostname or a tagname that is included in the /etc/tags file on one or more hosts. This allows us to grant this permission to a single host or an group of hosts.

Privilege is required to change the RBACPermission plugins or to change the hostname or the /etc/tags file so unprivileged users are bound by this system.

#### Access Control

The RBACPermission plugin is part of a comprehensive access control system for linux administration. bgsudo and oob_getRequiredUserAndGroup are other parts of that system.

Inside a script you can use bgsudo on a particular command. It is a wrapper over sudo which adds the capability to decide what privilege is required to run the command and use `sudo -u<user>` to run the command with least privileges possible.

At the top level script you can define a function oob_getRequiredUserAndGroup() which will cause the entire script to be re-invoked if necessary with `sudo -u<user>` to make sure its running at the intended privilege level.

These two mechanisms both result in the script being able to execute privileged commands but they do it in ways that are profoundly different in terms of how you administer the rights of users.

The bgsudo method results in a script that has no privilege but is only for convenience because the user executing it must be authorized to use sudo for the privileged actions that the script performs. That means that the user could accomplish a similar outcome by running the same commands (or slightly modified commands) as the script would have ran.

The oob_getRequiredUserAndGroup() method, on the other hand, authorizes the script to do things that the user executing it would not otherwise be able to do. Say a script named 'foo' modifies a system file. If a user has sudo privilege to run 'foo' as root or another privileged user, they are able to perform the action that 'foo' performs but they must use 'foo' to do it because if they try to execute the same commands that 'foo' does, they will find that they do not have the required privilege to modify that system file.

A software package can provide commands using the oob_getRequiredUserAndGroup() method and RBACPermission plugins that allow those commands to be run with privilege. Then a central user administration system such as an LDAP server can assign fine grained permissions to users.

#### Collect Plugins

```bash
$ cat plugins/osBase.Collect
#!/bin/bash
DeclarePlugin Collect osBase "
	cmd_collect: collect_osBase
	runSchedule: 4/10min
	description: collect the basic linux OS host information
	 * osBase/lsb_release
	 * osBase/uname
	 * /etc/passwd
	 * /etc/group
	 * /etc/hostname
	 * /etc/cron.d/*
	 * /etc/apt/sources.list.d/*
	 * /etc/ssh/*.pub
	 ...
"

function collect_osBase()
{
	collectPreamble || return

	lsb_release -a  2>/dev/null | collectContents osBase/lsb_release
	uname -a       | collectContents osBase/uname
	dpkg -l | sort | collectContents osBase/dpkg

	collectFiles "/etc/passwd"
	collectFiles "/etc/group"
	collectFiles "/etc/hostname"
	collectFiles "/etc/cron.d/*"
	collectFiles "/etc/apt/sources.list"
	collectFiles "/etc/apt/sources.list.d/*"
	collectFiles "/etc/ssh/*.pub"
	collectFiles "/etc/bg-*"
	collectFiles "/etc/at-*"
}
$ bg-collectCntr
Name                 Enabled     RunSchedule  LastResult   When        
hardware             off         1day         <notYetRan>  ''          
network              off         3/10min      <notYetRan>  ''          
osBase               activated   4/10min      success      'over 2 minutes ago'
```
Each time a collect plugin runs it copies any of the configuration that it is responsible for into a designated folder hierarchy. That folder would typically be on a mounted shared drive from the domain in which that the host participates. The domData system provides distributed shared folders that can be used for this purpose.

The purpose of collect plugins is to collect up-to-date information about the hosts in a domain without having to grant permission to a remote user to access the host with enough privilege to copy the information.

This is an important distinction with other remote administration system because the remote authority is able to turn on and off any installed Collect plugins even though that remote authority does not have sufficient privilege to access the information being collected. Often if an authority has permission to access privileged information on a host it would also have permission to perform arbitrary other actions which could be exploited by an attacker.


#### Declarative Configuration Part 1 -- Creqs

When a human makes a configuration change to a host, they look to see what the current configuration state is and then make only the changes required to get to where they want it to be. Declarative configuration makes our automation configuration scripts work a little bit more like that. Instead of a configuration script containing the steps to get from A to B, it contains more of a description of B so that whether we start at A or B or a different, unanticipated starting point, the script with result in just the steps needed to get to B.

When I maintained a server farm for an enterprise cloud company I learned that scripts are much more robust if they first check to see that an action is necessary before doing the action. The downside is that the script got more verbose, harder to write, harder to read and maintain.

The creq system automates the process of checking to make sure that the action is needed before performing it. Creq stands for 'configuration required'. A creq class is similar to a command or function name. It takes command line arguments just like a command and the creq class combined with its arguments is called a creq statement.

bg-creqApply is an external command that lets you run a creq statement on its own, executing the apply operation only if it is required. The creq statement in the following command is `cr_fileExists /tmp/foo`
```bash
$ bg-creqApply -v cr_fileExists /tmp/foo
APPLIED : fileExists /tmp/foo
$ bg-creqApply -v cr_fileExists /tmp/foo
PASSED  : fileExists /tmp/foo
```  
The first time we invoked the statement, it saw that /tmp/foo did not exist, so it created it. the second time the same command ran, it saw that it already existed so it did nothing.

The bg-core package comes with lots of creq classes to make statements with. They all start with cr_ by convention so you can find them by looking up their man pages with `man cr_<tab><tab>`. The manpage will tell you what arguments the creq class expects.

You can also make your own creq classes. An external command, created in any language can be a creq class by complying with the protocol described in man(5) creqClassProtocal. Its also really easy to create one in a bash script.

```bash
$ cat - >/tmp/test9.sh
#!/usr/bin/env bash
source /usr/lib/bg_core.sh
import bg_creqs.sh ;$L1;$L2

DeclareCreqClass cr_myConfFile
function cr_myConfFile::check() { [ -e "/tmp/myConfig.conf" ]; }
function cr_myConfFile::apply() { echo "hello word" > "$/tmp/myConfig.conf"; }

creqApply cr_myConfFile

<cntr-d>
$ chmod a+x /tmp/test9.sh
$ /tmp/test9.sh
APPLIED : myConfFile
$ /tmp/test9.sh
$
```
Notice that because we did not use the verbose switch to the creqApply command, the second time we ran test9.sh it did not print anything because at the default verbosity it only prints a line when it does something.

You can also access the check operation of a creq statement directly with the bg-creqCheck command. Its exit code will reflect whether the host complies with the configuration described by the statement.

The reason that this simple idea is so powerful is that often, performing the earlier steps in a configuration algorithm would mess up the target state if it is already in a later, possibly customized state of configuration. This allows writing the algorithm with the quality of idempotency which means you can call it multiple times without adverse affect.


#### State Database

A host computer's state is made up of base state from the operating system and additional state from all the applications installed on the host.  We can think of the host as an object instance of a computer class. The provisioning and configuration data can be thought of as state variables of the computer.

The problem is that the provisioning and configuration data is spread out over non-uniform commands and files.

Awkdata is a text database system that can help access the disparate configuration and provisioning information in a uniform way. Think of it as a compatibility layer on top of the native configuration files on a server. Awkdata builder plugins are responsible for translating the data.

The native configuration files and commands remain the system of record for the data but there is a uniform cache layer that allows the data to be inspected and queried.

(Tutorial to come.... write a plugin for the ip data and then query it. show other data in the schema)


#### Declarative Configuration Part 2 -- Standards and Config Plugins

You can write scripts that invoke individual creq statements like we saw in the Part 1 of Declarative Configuration section but you can also create groups of creq statements that work in a larger system to perform system administration.

A group of creq statements is called a creq profile and there are two types -- Standards and Config.

In a creq profile, we use the generic `creq` runner command which does not specify whether the statement will run in check or apply mode.

Since they are plugins, you can provide Standards and Config creq profiles in packages that can be installed to add capabilities to the hosts. Running a Standards plugin produces a report about what on the host complies with the standard and what does not.  When a host admin activates a Standards plugin it will run on a schedule and report the host's compliance using the same shared folder system used by the Collect plugin system.

Config plugins can be used just like Standards but can additionally be ran in apply mode to affect a change in the host configuration to make it comply.

Standards, Config, Collect and RBACPermission plugins along with AwkData sources are the heart of a system of distributed system administration that provides central command and control without requiring that any remote user have unrestricted privilege on a host. This is an important new firewall that limits risk in an organization by allowing compartmentalization to an extent not achieved by other means.

## Commandline User Interface
TODO: write this section on bg_cui.sh and bg_cuiWin.sh
Example: open a new terminal with "bg-core cuiWin myWin open" then sourceCore and wrtie to it with various csi codes. Then tailFile
and feed it data. etc...



## bg-core Project Folder Description

The bg-core project is managed by the bg-dev project tools. The asset scanners and installers built into the bg-dev package and other packages that extend bg-dev define how files in various folders in the project are treated. When you install an asset scanner and installer plugin, it will generally identify assets of its type in a project folder by the file path, extension and type.

Note that typically, bg-dev projects place all bash library scripts in the <projectFolder>lib/ subfolder but the bg-core  project places them in several subfolders to reflect the bootstrapping nature of bg-core.

### Root level

The root level contains any command files that will be installed on the target system.

The root level of this project also contains one script library ( bg_core.sh ) which is the entry point for sourcing any libraries in the bg-core package or any package that conform to its protocols. bg_core.sh is sourced from its well known /usr/lib/bg_core.sh location. All other libraries are sourced via the `import <libFile> ;$L1;$L2` syntax.

The only responsibility of bg_core.sh is to setup the host security environment and sourcing the bg_coreImport.sh library which introduces the import system and imports the unconditional core libraries of the bg-core project.

#### core/

The core/ subfolder contains the core libraries that are imported unconditionally when a script sources /usr/lib/bg_core.sh.

You never have to import these libraries. All functions defined in any file in this folder will be available to use in a script after sourcing /usr/lib/bg_core.sh

In addition to being located in the core/ folder, these libraries also typically start with bg_core*.

Of notable mention is the bg_coreLibsMisc.sh bash library. The idea is that sometimes there are functions that logically belong to another library in terms of its functionality but only only a few functions from that functional library need to be available all the time without importing the whole library. The 'core' functions in a functional library can be included in bg_coreLibsMisc.sh while the other other related but less 'core' functions can reside in the functional library where they are only available if that library is imported.

#### coreOnDemand/

The coreOnDemand/ subfolder contains libraries that are not imported initially when a script sources /usr/lib/bg_core.sh but will be automatically imported if certain features are used by the script. For example, if the script calls the daemonDeclare function to become a daemon script, the bg_coreDaemon.sh library will be imported and its features enabled.

You never have to import these libraries but some functions defined in these files will only be available after an entrypoint function typically located in the bg_coreLibsMisc.sh library is called.

Often the entrypoint function in bg_coreLibsMisc.sh will be a stub function that only imports the library and call itself again. When the library is imported it will overwrite the stub with the real implementation so that subsequent calls will call the real implementation directly.  

#### lib/

The lib/ subfolder is a standard folder for any bg-dev pacakgeProject.

Your script needs to import one of these libraries in order to use its features.

#### unitTests/

The unitTests/ subfolder is a standard folder for any bg-dev pacakgeProject. It contains unit test scripts containing testcases that can be executed directly for development work or via `bg-dev test` as part of the package's SDLC.

Unit tests are not included in the deb or rpm package this project produces.

See man(1) bg-dev-tests

#### data/

The data/ subfolder is a standard folder for any bg-dev pacakgeProject. It contains file assets that will be copied to the target system when the package is installed. On debian systems these files will be in /usr/share/bg-core/. Scripts use the $pkgDataFolder variable to refer to this folder which may be in a different location on other OS.

#### templates/

The templates/ subfolder is a standard folder for any bg-dev pacakgeProject. Files in this folder will be considered template files regardless of their extension.

Template functions from bg_templates.sh will find these templates when just their names (no path) are used.  

You can use the `bg-core templates ...` command to manage templates on a host from this and other packages. Templates can be overridden by a host administrator but requires privilege on the host to do so, therefore templates can be trusted to contain approved content.

#### plugins/

The plugins/ subfolder is a standard folder for any bg-dev pacakgeProject. bg-core introduces several plugin types which are typically placed in the lib/ folder. It also provides a number of instances of those plugin types that reside in this folder.


#### doc/

The doc/ folder contains the changelog and copywrite files for the project and miscellaneous documentation such as diagrams.

#### man[0-7]/

The man[0-7]/ subfolders are standard folders for any bg-dev pacakgeProject. They contain manually written man pages.

Most man pages are written as comment blocks in the source code and generated into manpages when the package is built but some man pages do not fit that pattern well and can be written manually.

#### .bglocal/

The .bglocal/ hidden subfolder is a standard folder for any bg-dev project. It is a local cache folder for things that do not get committed to git. For example, a staging folder to build deb and rpm packages and the funcman generated documentation build.

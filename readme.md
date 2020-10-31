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
 * simple text template expansion against the linux environment variabels
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

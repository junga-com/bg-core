
# Library bg_coreDebug.sh
# sourcing /usr/lib/bg-core.sh provides several debugging facilities for scripts that will be optionally activated depending on
# the environment that the script is ran in.
#
# This library is unconditionally sourced by bg_coreImport.sh. When debug features are not allowed or not asked for by the
# user's environment (controlled by bg-debugCntr), only noop stub funcitons will be provided for all the fetaure entrypoints.
# If the a feature is called for and allowed, bg_debugTrace.sh will be imported and further, if the interactive debugger is called
# for, bg_debugger.sh will be imported.
#          bg_coreDebug.sh  : always sourced
#          bg_debugTrace.sh      : sourced only if bgtracing is called for and allowed
#          bg_debugger.sh        : sourced only if the debugger is called for and allowed
#
# Security:
# These mechanisms are designed for development time and when any of these features are available to a user, we assume that they have
# complete controll of the script execution and are not bound by any security policy enforced by the script.
#
# We make a distinction between scripts that the authenticated user has file permissions to write to and those that they do not.
# If the script is not writable by the user, these mechanisms will refuse to activate.
#
# If the user's linux account can not change the script or any libraries that the script sources, we assume that they can
# not defeat this protection.
#
# When a host implements a policy that only root can write to system folders and packages install scripts only to system folders,
# any non-root user will be able to debug a copy of a script in there home folder but not any script in a system folder. Sudo
# configuration uses the complete path to identify a command so a script with that requires sudo permisison can not be debugged
# unless the user has write permission to the system folder in which case they could modify the script directly and not need a
# debug feature to violate security policy in the script
#
#
# bgtrace Debug Mechanism:
# bgtrace is a system for debugging bash scripts by placing bgtrace* calls in key places to see if they are reached and expose the
# values of variables, call stack, function parameters and other state at those places. Typically bgtrace* statements are added
# during a debugging session and then removed but they can also be left in scripts in certain circumstances. The convention is that
# temporary bgtrace* statements are not indented with the code so that the regex "^bgtrace" matches all temporary statements so that
# they can be removed at the end of the session.
#
# The script operator controls whether bgtracing is active and if so, where the output is sent. The "bg-debugCntr trace ..."
# command is used to configure the bgtracing environment. Durring a development session, the operator can termpoarily turn off bgtracing
# so that the script runs as it would in production without removing the bgtrace* statements added for that session.
#
# The bgtraceBreak statement is an entrypoint into the interactive debugger decribed in the next section.
#
# Note that the  arguments to inactive bgtrace* statements will still be processed so they should not contain side effects that affect
# the scripts function.
#
# Interactive Debugger Debug Mechanism:
# An interactive debugger can be used to step through a script to observe its code path and state. The debugger can only be activated
# when bgtracing is active.
# The debugger is activated in one of two ways.
#     * bgtraceBreak statement added in one or more places in the script. When encountered, this will open the debugger window
#       with the script stopped on the following line
#     * "bg-debugCntr debugger on:[<dbgID>]" : when the terminal is configured with this command, any script lanched from that
#       terminal that includes /usr/lib/bg_core.sh will immediately stop in the debugger.
#     * pressing cntr-c while a stript is running. This is usefull if the script is in an infinite loop.
#
# See Also:
#    man(3) bgtraceBreak
#    man(1) bg-debugCntr debugger on:[<dbgID>]
#


##################################################################################################################
### Init bgtracing to be on or off.
# If bgtracing is not enabled, we provide stubs to make bgtrace* statements into noops.
# Note that bgtraceIsActive is a core function in bg_libCore.sh and if bgtracing is enabled, it will load bg_debugTrace.sh and provide
# the real versions of these commands.
if ! bgtraceIsActive; then
	function bgtraceTurnOff()    { :; }
	function bgtraceCntr()       { :; }
	function bgtrace()           { :; }
	function bgtracef()          { :; }
	function bgtraceLine()       { :; }
	function bgtraceVars()       { :; }
	function bgtraceParams()     { :; }
	function Object::bgtrace()   { :; }
	function bgtraceStack()      { :; }
	function bgtraceBreak()      { :; }
	function bgtraceXTrace()     { :; }
	function bgtraceRun()        { :; }
	function bgtimerStartTrace() { :; }
	function bgtimerTrace()      { :; }
	function bgtimerLapTrace()   { :; }
	function debuggerTriggerIfNeeded()   { :; }
else
	# this case is logically part of the bg_debugTrace.sh library but it is global init code that is important and have to happen
	# after the functions in bg_debugTrace.sh are available so if we put this in that library, we would have to put it at the end
	# where its kind of hidden from sight.

	# install a cntr-c signal handler to invoke the debugger.
	[ ! "$bgDebuggerInhibitCntrC" ] && [ "$bgDevModeUnsecureAllowed" ] && [ "$bgLibExecMode" == "script" ] && bgtrap -n debugger '
		if debuggerIsInBreak; then
			# if we are already stopped in the debugger, interpret cntr-c normally and end the script
			bgtrace "cntr-c caught in bgtrace mode. Already stopped in debugger so interrupting script."
			builtin trap - SIGINT
			kill -SIGINT $BASHPID
		else
			bgtrace "cntr-c caught in bgtrace mode. Invoking the debugger. Hitting cntr-c again will stop the script"
			bgtraceBreak || {
				bgtrace "Invoking the debugger failed. Stopping the script with a unhandled cntr-c"
				builtin trap - SIGINT
				kill -SIGINT $BASHPID
			}
		fi
	' SIGINT


	##################################################################################################################
	### recognize debugger environment var maintianed by bg-debugCntr to activate the debugger when a script runs
	function debuggerTriggerIfNeeded() {
		if [ "$bgDevModeUnsecureAllowed" ] &&  [ "$bgLibExecMode" == "script" ] && [ "${bgDebuggerOn}" ]; then
			[ ! "$(import --getPath bg_debugger.sh)" ] && assertError "the debugger is not installed. Try installing the bg-dev package"
			import bg_debugger.sh ;$L1;$L2
			bgtrace "bgDebuggerOn is on : ${bgDebuggerOn}"
			case ${bgDebuggerOn#on:} in
				stopOnLibInit)           debuggerOn stepOver ;;
				*|stopOnFirstScriptLine) debuggerOn stepToLevel 1 ;;
			esac
		fi
	}
fi



# usage: debugShowBanner
# This prints a banner msg if any bg_coreDebug.sh features are activated in the terminal environment so that the user is aware.
# It then turns off the banner feature so that if the script invokes any child scripts, only the script invoked from the terminal
# directly by the user will display the banner. Also the banner will not display if invoked from a bash completion function.
function debugShowBanner()
{
	local traceState="off" tColor
	if bgtraceIsActive; then

		traceState="$_bgtraceFile"; [ "$traceState" == "/dev/null" ] && traceState="off"
		tColor="${csiYellow}"
	fi

	local vinstallState="none" vColor
	if [ "${bgInstalledPkgNames}" ]; then
		vinstallState="ON:"
		local bestFolder="${bgVinstalledPaths%/bg-lib*}"
		local bestFolder="${bestFolder##*/}"
		vinstallState+="$bestFolder"
		vColor="${csiYellow}"
	fi

	if [ "${bgTracingOn}${bgInstalledPkgNames}" ] && [ "$bgTracingBanner" ] && [ ! "$bgtraceShowBanner_IKnowAlready" ]; then
		printf "***** ${csiYellow}bg-debugCntr${csiNorm}: Tracing='${tColor}$traceState${csiNorm}'. Vinstall='${vColor}$vinstallState${csiNorm}'\n" >&2
		declare -gx bgtraceShowBanner_IKnowAlready="1"
	fi
}

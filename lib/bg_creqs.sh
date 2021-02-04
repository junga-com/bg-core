#!/bin/bash

creqApplyLog="/var/log/creqs.log"


# usage: creq cr_<type> [ p1 [ p2 ... pN ] ]  
# this is used to create configuration items using a declarative syntax. 
# cr_type is the name of a function written in a particular way that behaves 
# like a Object Class of type ConfReqs so that one function can define several
# methods (actions) and this creq function decides which actions should be invoked
# creq implements the main algorithm for running the declarative statements
# It can be called explicitly like "creq cr_<type> [ p1 [ p2 ... pN ] ]"
# or it can be called implicitly like "cr_<type> [ p1 [ p2 ... pN ] ] "
# see cr_boilerplate for writing cr_ type functions
function creq()
{
	local fullOrigCmdLine="creq $*"
	
	function testAndProcTestLog()
	{
		# creqTestLog is a tmp filename used to capture the stdout and stderr of each small command. Its content is consumed and reset to empty
		# creqLogfile is the persistent log file that lasts the entire current run session

		if [ -s ${creqTestLog}.out ]; then
			awk '{printf("     %-5s: %s\n","'"$crSection"'", $0)}' ${creqTestLog}.out | tee -a $creqLogfile  >>$creqStdout
			echo -n > ${creqTestLog}.out
		fi

		if [ -s ${creqTestLog}.err ]; then
			awk '{printf("   %-5s(ERR): %s\n","'"$crSection"'", $0)}' ${creqTestLog}.err | tee -a $creqLogfile  >>$creqStderr
			echo -n > ${creqTestLog}.err
			return 1
		fi
		return 0
	}

	local exitTrapAction='
		(
			awk '\''{print "      (stderr): "$0}'\'' '"${creqTestLog}.err"'
			_creqEcho -v1 "ERROR: creq run ended prematurely in $classFn::$objectMethod"
			local -A stackFrame=(); bgStackGetFrame creq-1 stackFrame 
			assertError "
				      $classFn::$objectMethod called exit/assert and has ended the creq run prematurely.
				      this function should use return instead of exit. The equivalent to exit in creq class 
				      methods is to write an error message to stderr and return n. This error can be fixed by 
				      enclosing any function call in $classFn::$objectMethod that might call exit 
				      (or assert*) in (). For example: use '\''(assertNotEmpty myRequiredVar) || return'\'' 
				      to assert an error condition. Make sure that any class variable assignments are not
				      inside any (). The offending line is...
				         ${stackFrame[printLine]}
			"
		) >&3 2>&3
	'


	### initialize the creq execution environment
	if [[ ! "$creqAction" =~ (check)|(apply) ]]; then
		assertError "creq system not initialized. see creqInit "
	fi

	# 2016-07 bobg: not sure if sync is needed. do we still use coprocs to capture output anywhere? It would be faster without sync probably
	sync
	crSection="init "
	echo -n > ${creqTestLog}.out
	echo -n > ${creqTestLog}.err
	_creqLogMarker "creq start: $*"
	local _creqUID
	while [[ "$1" =~ ^- ]]; do
		case $1 in
			-p)  _creqUID="$2"; shift ;;
			-p*) _creqUID="${1#-u}" ;;
			*) echo "unknown optional parameter to creq: '$1': params: $@" >>${creqTestLog}.err
		esac
		shift
	done
	if ! testAndProcTestLog $creqTestLog; then
		(( creqCountCtorError++ ))
		_creqEcho -v1 "ERROR in statement: unknown optional parameter to creq: '$1': params: $@"
		crSection=""
		_creqLogStmtResult ERROR inStmtParams
		return 100
	fi

	# typically creqConfig do not provide a GUID for the _creqUID so we create a transient (TRANS) one
	# that will be unique within a particular version of the creq profile. 
	if [ ! "$_creqUID" ]; then
		printf -v _creqUID "TRANS%04d" "$creqCountTotal"
	fi


	### construct the cr_ object
	crSection="ctor "
	local classFn="$1" ; shift
	if ! type -t "$classFn" >/dev/null; then
		_creqEcho -v1 "ERROR in init: '$classFn' not found' "
		crSection=""
		_creqLogStmtResult ERROR inStmtCtor
		return 103
	fi

	(( creqCountTotal++ ))
	creqCompleteness="$((creqCountPass+creqCountApplyPass))/${creqCountTotal}..."
	creqCompletenessPercent="$(((creqCountPass+creqCountApplyPass)*100/((creqCountTotal>0)?creqCountTotal:1) -1))%..."

	# declare these class vars for the ut_ class to set if needed
	local this="_creqThisSyntaxHandler "
	local displayName=""
	local creqMsg=""
	local passMsg=""
	local noPassMsg=""
	local appliedMsg=""
	local failedMsg=""

	# declare the variable names local at this scope so that they will be 
	# shared among all the calls to classFn
	bgtrap '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
	local classVars="$(objectMethod=objectVars $classFn 3>&2  2>>${creqTestLog}.err)"
	for classVar in $classVars; do
		eval local -x $classVar >>${creqTestLog}.out 2>>${creqTestLog}.err
	done
	bgtrap -r '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
	if ! testAndProcTestLog $creqTestLog; then
		(( creqCountCtorError++ ))
		_creqEcho -v1 "ERROR in objectVars: '$classFn $@' "
		crSection=""
		_creqLogStmtResult ERROR inStmtObjVars
		return 101
	fi

	# call the construct 'method'
	bgtrap '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
	objectMethod=construct $classFn "$@" 3>&2 >>${creqTestLog}.out 2>>${creqTestLog}.err
	local result=$?
	bgtrap -r '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
	if ! testAndProcTestLog $creqTestLog || [ $result -ne 0 ]; then
		(( creqCountCtorError++ ))
		_creqEcho -v1 "ERROR in construct: '$classFn $@' returned '$result'"
		crSection=""
		_creqLogStmtResult ERROR inStmtCtor
		return 102
	fi

	# check to see if the constructor assigned the class variables
	# This catches the easy to make mistake of declaring the variables 'local' in the cr_statement ctor.
	local unassignedVarList
	for classVar in $classVars; do
		classVar="${classVar%%=*}"
		[ ! "${!classVar+wasAssigned}" ] && unassignedVarList+=($classVar)
	done
	[ "$unassignedVarList" ] && assertError -v fullOrigCmdLine -v classFn -v displayName -v unassignedVarList "The 'constructor' case of a cr_statement must assign a value (it can be empty) to every variable it declares in the 'objectVars' section. A common mistake is to declare them 'local' in the construct section instead of just assinging them without the 'local'"

	displayName="${displayName:-$(creqMakeDisplayName "$classFn" "$@")}"



	### call the check 'method'
	crSection="check"
	# set a trap for the duration of the check call to trap exit. check functions should never exit the process.
	# we do not wrap it in () to catch exit, because that would prohibit the check function from setting the creqMsg 
	# variable or any 'class' variable used by us or the ::apply method
	bgtrap '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
	objectMethod=check $classFn 3>&2 >>${creqTestLog}.out 2>>${creqTestLog}.err
	local checkResult=$?
	bgtrap -r '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
	if ! testAndProcTestLog $creqTestLog; then
		(( creqCountCheckError++ ))
		creqMsg="${creqMsg:-${msg:-$displayName}}"
		_creqEcho -v1 "ERROR in check: $creqMsg"
		crSection=""; creqMsg=""
		_creqLogStmtResult ERROR check
		return 103
	fi



	### check PASSED case
	local applyResult=0
	if [ $checkResult -eq 0 ]; then
		# the check passed
		(( creqCountPass++ ))
		creqCompleteness="$((creqCountPass+creqCountApplyPass))/${creqCountTotal}..."
		creqCompletenessPercent="$(((creqCountPass+creqCountApplyPass)*100/creqCountTotal -1))%..."
		creqMsg="${passMsg:-${creqMsg:-${msg:-$displayName}}}"
		_creqEcho -v2 "PASS: $creqMsg"
		_creqLogStmtResult PASS



	### check FAILED case
	else
		# the check did not pass
		creqMsg="${noPassMsg:-${creqMsg:-${msg:-$displayName}}}"
		_creqEcho -v1 "FAIL: $creqMsg"
		(( creqCountNoPass++ ))
		_creqLogState


		### APPLY the change if we are in apply mode
		if creqIsApply; then

			# to protect against accidental changes we require an env variable to
			# be set also before we proceed to make any changes
			if [ ! "$creqWriteModeEnabled" ]; then
				_creqEcho -v0 "ERROR: readonly mode refusing to make changes to configuration"
				_creqLogStmtResult ERROR applyInROmode
				exit 59
			fi

			# call the apply method and report differently based on its exit code 
			crSection="apply"
			_creqEcho -v1 -o "APPLYING...: $creqMsg"

			# this case statement can be removed eventually. the 'new' case seems to work well and will be all we need but until
			# it withstands the test of time, the case shows the alternative and allows easy testing. 'simple' is meant for debugging
			# we could select different methods based on verbosity if needed but I don't think that will be needed. 
			creqMsg=""
			case new in
				orig)
					objectMethod=apply $classFn  \
						>  >(awk '{printf("     %-5s: %s\n","'"$crSection"'", $0);fflush()}' | tee -a $creqLogfile >>$creqStdout) \
						2> >(awk '{printf("   %-5s(ERR): %s\n","'"$crSection"'", $0);fflush()}' | tee -a $creqLogfile >>$creqStderr)
					applyResult=$?
					;;

				new)
					# the problem with this style of running the ::apply method in the sub process is that we are loosing
					# 
					while IFS="" read -r line; do
						if [ "$line" == "---M(exit)M---" ]; then
							# this manual termination check was implemented 2015-10-21 b/c packageInstalled_mysql in siemServer_on would 
							# hang after the apply was done and all output written to $creqLogfile 
							break
						elif [[ "$line" =~ ^---M\(classMember\)M--- ]]; then
							_creqThisSyntaxHandler "${line#---M(classMember)M---}"
						else
							printf "     %s\n" "$line" | tee -a $creqLogfile >>$creqStdout
						fi
					done < <(
						this="echo ---M(classMember)M---"
						(objectMethod=apply $classFn 2>&1)
						local res=$?
						$this.applyResult="$res"
						echo "---M(exit)M---"
					)
					;;

				simple)
					objectMethod=apply $classFn
					applyResult=$?
					;;
			esac

			crSection="dtor "
			if [ $applyResult -eq 0 ]; then
				(( creqCountApplyPass++ ))
				creqMsg="${appliedMsg:-${creqMsg:-${msg:-$displayName}}}"
				_creqEcho -v1 -o "APPLIED: $creqMsg"
				checkResult=0
				local iz; for iz in ${!creqsChangetrackersActive[@]}; do creqsChangetrackersActive[$iz]="1"; done
				_creqLogStmtResult PASS APPLIED
			else
				creqMsg="${failedMsg:-${creqMsg:-${msg:-$displayName}}}"
				_creqEcho -v1 -o "ERROR($applyResult) in apply: $creqMsg"
				(( creqCountApplyError++ ))
				[ "$creqStopOnApplyError" ] && assertError "stop on apply error requested"
				_creqLogStmtResult FAIL errorInApply
				_creqLogState
			fi
			(( creqCountChange++ ))
		else
			_creqLogStmtResult FAIL
		fi
	fi
	crSection=""
	return $(( $checkResult + $applyResult ))
}



# usage: _creqLogState
# This internal creq helper function that logs information about creq statement when it failes, based
# on the verbosity
function _creqLogState()
{
	if [ ${creqVerbosity:-0} -ge 4 ]; then
		creqLog0 "   creq state:"
		local classVar; for classVar in $classVars; do
			local __creqTmpVal
			printf -v __creqTmpVal "      > this.%-16s : '%s'"  "$classVar" "${!classVar}"
			creqLog0 "$__creqTmpVal"
		done
	fi
}


# usage: $this.<varname>=<value
# This internal creq helper function supports using member variable assignment syntax in creq class member functions 
# like construct, check, and apply. creq defines the variable local this="_creqThisSyntaxHandler " before invoking the
# member functions. Inside those functions a script line like...
#      $this.msg="hello world"
# will expand to the following line after variable substitution, word splitting and quote removal
#      _creqThisSyntaxHandler '.msg=hello world'
# which will call this function
function _creqThisSyntaxHandler()
{
	local line="$*" local sq="'"
	local _mnameShort="${1#.}";  [ $# -gt 0 ] && shift
	if [[ "$_mnameShort" =~ ^[a-zA-Z0-9_]*= ]]; then
		eval "${_mnameShort/=/=$sq}'"

	else
		assertError "unknown 'this' syntax '\$this.$line'"
	fi
}


# This is meant to be copied to make other cr_* functions/classes
# usage: cr_boilerplate p1 p2
# see man creq
# declares that <TODO: description of what it declares>
function cr_boilerplate()
{
	case $objectMethod in
		objectVars) echo "p1 p2=5 localVar1" ;;
		construct)
			# TODO: replace these sample variables with the real ones
			p1="$1"
			p2="$2"
			localVar1="$p1 + $p2"
			displayName="<TODO: terse description that will show on outputs>"
			;;

		check)
			# TODO: replace with a real check.
			[ "$localVar1" == "this + that" ]
			;;

		apply)
			# TODO: replace with code to make a config change
			echo "change something here using $p1, $p2, $localVar1, etc..."
			;;

		*) cr_baseClass "$@" ;;
	esac
}


##############################################################################################
### lifecycle functions to initialize the environment to run cr_ statements and to report 
#   on what happened afterward.
#
# typically:
#     creqInit check verbosity:1
#
#     cr_fileExists foo
#     cr_iniParamExists foo . myName myValue
#     ...
#     creqReport

declare -A creqsChangetrackers
declare -A creqsChangetrackersActive
declare -A creqsTrackedServices
declare -A creqsTrackedServicesActions


# usage: creqInit action verbosity
# this function sets the environment for using subsequent calls to creq
# in a certain way. 
#	action: can be "check" or "apply"
#			check: will cause subsequent creq calls to only report compliance
#			apply: will cause subsequent creq calls to apply changes if needed
#				to use 'apply' the env var 'creqWriteModeEnabled' must be
# 				non-empty 
#	verbosity: control how much information will be written to standard out
#			0: terse.   only display a summary at the end
#			1: default. also display a msg at the start, line for each item that fails the check
#			2: verbose. also display a line for every item checked
#			3: debug1.  also display all stderr output produced by creq items
#			4: debug2.  also display all stderr and stdout output produced by creq items plus log entering each method.
# TODO: rewrite. there are now better techniques to implement this. the creqs was implemented as the very first OO organized bash feature 
function creqInit()
{
	declare -gx creqCollectFlag="" creqRunLog="" creqProfileID="transientStatements"
	while [[ "$1" =~ ^- ]]; do case $1 in
		--profileID) creqProfileID="$2"; shift ;;
		--collect)   collectPreamble && creqCollectFlag="1" ;;
		--runLog)    creqRunLog="$2"; shift ;;
	esac; shift; done
	declare -gx  creqAction="${1:-check}"
	declare -gx  creqVerbosity="${2#*:}" # support 'N' and 'verbosity:N'
	creqVerbosity="${creqVerbosity:-2}"

	if [[ ! "$creqAction" =~ (check)|(apply) ]]; then
		assertError "creqInit called with unknown action '$creqAction'"
	fi

	declare -gA creqRunningPluginType=""
	declare -gA creqRunningProfileName="$creqProfileID"
	[[ "$creqProfileID" =~ : ]] && splitString -d":" "$creqProfileID" creqRunningPluginType creqRunningProfileName


	# init the vars using in the change tracking mechanism. creqsChangetrackers holds all 
	# varNames that we are tracking and creqsChangetrackersActive holds just the ones that 
	# are currently tracking. When a apply block is done, all active varNames are set to "1"
	declare -gA creqsChangetrackers=()
	declare -gA creqsChangetrackersActive=()

	declare -gx creqStderr="/dev/null"; [ ${creqVerbosity:-0} -ge 3 ] && creqStderr="/dev/stderr"
	declare -gx creqStdout="/dev/null"; [ ${creqVerbosity:-0} -ge 4 ] && creqStdout="/dev/stdout"

	declare -gx creqCountTotal=0             # +count every creq statment
	declare -gx creqCountCtorError=0         #    An error ocured outside of check and apply methods
		                                     #    + (uncounted)
	declare -gx creqCountCheckError=0        #       the ones the have a error in check method so we don't know the pass state -- assumed noPass
	declare -gx creqCountPass=0              #       the ones that pass cleanly (no errors)
	declare -gx creqCountNoPass=0            #       +the ones the do not pass cleanly (no errors)
	declare -gx creqCountChange=0            #           +any that apply was called
	declare -gx creqCountApplyPass=0         #              apply was called and exited cleanly
	declare -gx creqCountApplyError=0        #              apply was called but had errors
	declare -gx creqCompleteness="0/1"
	declare -gx creqCompletenessPercent="0%..."

	declare -gx crSection=""
	declare -gx creqStopOnApplyError=""; [ "$creqVerbosity" -gt 3 ] && creqStopOnApplyError="1"

	declare -gx _creqProfileLog
	if [ "$creqProfileID" ] && [ "$creqCollectFlag" ]; then
		_creqProfileLog="${scopeFolder%/}/collect/creqs/$creqProfileID"
		domTouch "${_creqProfileLog}.statements"
		domTouch "${_creqProfileLog}.results"
		domTouch "${_creqProfileLog}.applyLog"
		# truncate and write header (-H) to the profle's statement log
		_creqLogStmtResult -H
	else
		_creqProfileLog="$(mktemp)"
	fi

	declare -gx creqTestLog=$(mktemp)
	declare -gx creqLogfile
	#bgtraceIsActive && creqLogfile="$(bgtraceGetLogFile)"
	if creqIsApply && [ "$creqApplyLog" ] && touch "$creqApplyLog" 2>/dev/null; then
		creqLogfile="$creqApplyLog"
	fi
	if [ ! "$creqLogfile" ]; then
		creqLogfile="$(mktemp)"
		declare -gx creqLogfileIsTmp="1"
	fi

	declare -gx creqStartTimeFile=""
	if creqIsApply; then
		creqStartTimeFile=$(mktemp)
		touch "$creqStartTimeFile"
	fi

	[ ${creqVerbosity:-1} -ge 1 ] && printf "%s: (%s)\n"  "$creqProfileID" "$creqAction";
	creqLog0 "start '$creqProfileID'"

	echo "" >> "$creqLogfile"
	echo "" >> "$creqLogfile"
	echo "#################################################################################################" >> "$creqLogfile"
	echo "### creqInit $*" >> "$creqLogfile"
	echo "### creqProfileID=$creqProfileID" >> "$creqLogfile"
	echo "### run by '$USER' at $(date)" >> "$creqLogfile"
}


# usage: creqReport
# End the run of cr_ statements. report the stats of what happened. 
# this is typically called only by bg-creqCntr and bg-standards.
function creqReport()
{
	creqLog0 "finish '$creqProfileID'"

	local resultCode=0
	if [ "$creqStartTimeFile" ]; then
		rm "$creqStartTimeFile"
	fi

	local profIDLabel
	if [ ${creqVerbosity:-1} -lt 1 ]; then
		printf -v profIDLabel "%-30s: " "$creqProfileID"
	fi

	for service in "${!creqsTrackedServices[@]}"; do
		creqServiceAction "$service" "${creqsTrackedServicesActions[$service]}" "${creqsTrackedServices[$service]}"
	done

	creqCompleteness="$((creqCountPass+creqCountApplyPass))/${creqCountTotal}"
	creqCompletenessPercent="$(((creqCountPass+creqCountApplyPass)*100/((creqCountTotal) ? creqCountTotal : 1)))%"
	if [ ${creqCountTotal:-0} -gt 0 ]; then
		if ! creqIsApply; then
			if [  $creqCountPass -eq $creqCountTotal ]; then
				echo "   ${profIDLabel}pass: all $creqCountTotal statements comply with configuration goals"
			elif [ $((creqCountPass+creqCountNoPass)) -eq $creqCountTotal ]; then
				echo "   ${profIDLabel}fail: $creqCountNoPass out of $creqCountTotal statements do not comply with configuration goals" 
			else
				echo "   ${profIDLabel}fail:"
				[ $creqCountNoPass -gt 0 ] && echo "      $creqCountNoPass statements do not comply with configuration goals"
			fi

		else
			if [ $creqCountPass -eq $creqCountTotal ]; then
				echo "   ${profIDLabel}pass: all $creqCountTotal statements already complied with configuration goals"
			elif [ $((creqCountPass+creqCountApplyPass)) -eq $creqCountTotal ]; then
				echo "   ${profIDLabel}pass: $creqCountChange configuration statements were applied and now all $creqCountTotal statements comply"
			else
				echo "   ${profIDLabel}fail:"
				[ $creqCountApplyError -gt 0 ] && echo "      $creqCountApplyError statements failed while applying changes and may not comply with configuration goals"
			fi
		fi
	else
		echo "   ${profIDLabel}pass: no configuration statements are required in this configuration"
	fi
	[ ${creqCountCheckError:-0} -gt 0 ] && echo "      $creqCountCheckError statements had errors while performing checks"
	[ ${creqCountCtorError:-0} -gt 0 ]  && echo "      $creqCountCtorError statements had errors while consctructing the creq object"
	resultCode=$(( creqCountApplyError + creqCountCheckError + creqCountCtorError ))

	if [ $((creqVerbosity + ((resultCode>0)?1:0) )) -ge 3 ]; then
		echo "   details of this run logged in '$creqLogfile'"
	else
		[ "$creqLogfileIsTmp" ] && rm $creqLogfile
	fi

	rm ${creqTestLog}.out ${creqTestLog}.err ${creqTestLog} &>/dev/null

	local cols="server    pluginType profileName       total passPercent             pass  applyPass  fail   applyError checkError  statementError"
	#           scopeName creqRunningPluginType creqRunningProfileName  Total creqCompletenessPercent Pass  ApplyPass  NoPass ApplyError CheckError  CtorError
	local fmtStr="%-18s %13s %-20s %5s  %11s  %4s  %9s  %4s  %10s  %10s  %14s\n" 
	printf "$fmtStr" $cols > "${_creqProfileLog}.results"
	printf "\n"  >> "${_creqProfileLog}.results"
	printf "$fmtStr" "${scopeName:--}" "${creqRunningPluginType:---}" "${creqRunningProfileName:---}" "$creqCountTotal" "$creqCompletenessPercent" "$((0+creqCountPass+creqCountApplyPass))"  "$((0+creqCountNoPass-creqCountApplyPass))" "$creqCountApplyError" "$creqCountCheckError"  "$creqCountCtorError" >> "${_creqProfileLog}.results"

	return $resultCode
}

##############################################################################################
### functions to use in cr_* sections / lists to augment and add features
#   For example to keep track of what has changed to know if a daemon needs to be restarted


# usage: if creqGetState; then ...
# returns "check", "apply", or empty string to indication whether the creq system is running and in what state
function creqGetState() { echo "$creqAction"; }

# usage: if creqIsCheck; then ...
# test if the configuration required system is in the 'check' mode
function creqIsCheck() { [ "$creqAction" == "check" ]; }

# usage: if creqIsApply; then ...
# test if the configuration required system is in the 'apply' mode
function creqIsApply() { [ "$creqAction" == "apply" ]; }

# usage: creqLog0 ...
# write to the log file even if the level is 0 (typically when the user specifies -q)
function creqLog0()
{
	if [ "$crSection" ]; then
		echo "$*"
	elif [ "$creqStdout" ]; then
		echo "$*" | awk '{printf("--- %s\n", $0)}' | tee -a $creqLogfile  >>$creqStdout
	fi
	true
}

# usage: creqLog1 ...
# write to the log file if verbosity is level 1 or more (default is level 1)
function creqLog1() { [ ${creqVerbosity:-0} -ge 1 ] && creqLog0 "$*"; true; }

# usage: creqLog2 ...
# write to the log file if verbosity is level 2 (typically when user specifies -v)
function creqLog2() { [ ${creqVerbosity:-0} -ge 2 ] && creqLog0 "$*"; true; }

# usage: creqLog3 ...
# write to the log file if verbosity is level 3 (typically when user specifies -vv)
function creqLog3() { [ ${creqVerbosity:-0} -ge 3 ] && creqLog0 "$*"; true; }

# usage: creqLog4 ...
# write to the log file if verbosity is level 4 (typically when user specifies -vvv)
function creqLog4() { [ ${creqVerbosity:-0} -ge 4 ] && creqLog0 "$*"; true; }



# usage: creqsDelayedServiceAction [-s] <serviceName>[:<action>] [<varName>]
# declare that the specified servive should have an action performed at the end of the creq profile run
# this is typically used in creqConfigs. The more typical pattern is to wrap some creq statements in
# creqsTrackChangesStart and creqsTrackChangesStop calls so that the service will be flagged for an action
# only if some creq statements result in configuration changes being applied. This function unconditionally
# flags the service/action to happen. 
function creqsDelayedServiceAction()
{
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s) nothing="-s" ;;
	esac; shift; done
	local serviceName serviceAction varName
	serviceName="$1"
	[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
	local varName="${2:-$serviceName}"
	creqsTrackedServices["$serviceName"]="$varName"
	creqsTrackedServicesActions["$serviceName"]="${serviceAction:-restart}"
	creqsChangetrackers[$varName]="1"
}

# usage: creqsTrackChangesStart -s <serviceName>[:<action>] [<varName>]
# usage: creqsTrackChangesStart <varName>
# start tracking changes with varName. If a cr_ is applied while varName is tracking changes,
# it will be set to a non empty string (true). This facilitates surrounding a set of cr_ statements
# with a start/stop pair and if any of those statements resulted in a change(apply), then varName
# will be true. This -s form records serviceName so that at the end it will be restarted if its coresponding
# varName has be set to true. The default varName is serviceName if the second param is not specified 
# a varName can be stopped and restarted multiple times. 
function creqsTrackChangesStart()
{
	local serviceName serviceAction varName
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s*) serviceName="$(bgetopt "$@")" && shift
			[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
			varName="${2:-$serviceName}"
			creqsTrackedServices["$serviceName"]="$varName"
			creqsTrackedServicesActions["$serviceName"]="${serviceAction:-restart}"
			;;
	esac; shift; done
	varName="${varName:-$1}"

	# this ensures that there is a $varName index in the creqsChangetrackersActive map. the value at the index
	# is "" unless its been set to 1 when a cr_ runs. Since we can start and stop the tracked varname multiple
	# times, we preserve the previous value which will be "" if this is the first start.
	creqsChangetrackersActive[$varName]="${creqsChangetrackers[$varName]}${creqsChangetrackersActive[$varName]}"
}

# usage: creqsTrackChangesStop -s <serviceName>[:<action>] [<varName>]
# usage: creqsTrackChangesStop <varName>
# stop tracking varName. This means that if a cr_ results in an applied and makes a change,
# varName will not be set to true.
# this also returns the value of varName so that the caller can stop tracking changes and
# check to see if any changes had been made while it was tracking in one operation.
# if creqsTrackChangesStop apacheRestartNeeded; then ...
function creqsTrackChangesStop()
{
	local serviceName varName
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s*) serviceName="$(bgetopt "$@")" && shift
			[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
			varName="${2:-$serviceName}"
			;;
	esac; shift; done
	varName="${varName:-$1}"

	creqsChangetrackers[$varName]="${creqsChangetrackers[$varName]}${creqsChangetrackersActive[$varName]}"
	unset creqsChangetrackersActive[$varName]
	[ "${creqsChangetrackers[$varName]}" ]
}

# usage: creqsTrackChangesCheck <varName>
# check the tracking varName value. see creqsTrackChangesStart for a description.
# typical: if creqsTrackChangesCheck apacheRestartNeeded; then ...
function creqsTrackChangesCheck()
{
	local varName="$1"
	[ "$varName" ] || return 1
	creqsChangetrackers[$varName]="${creqsChangetrackers[$varName]}${creqsChangetrackersActive[$varName]}"
	[ "${creqsChangetrackers[$varName]}" ]
}

# usage: creqServiceAction <serviceName> <action> [<varName>]
# Perform an action (ie. restart,reload, etc..) on a service daemon only if varName has been set and the mode is 'apply'
# This is typically only called by creqReport at the end of a creq run on any service/actions that have been registered
# during the creq run with creqsTrackChangesStart/Stop or creqsDelayedServiceAction. 
# It only does the action in apply mode so check mode can be sure not to change anything on the host.
# Typically, varName is the service name and if any creq changes are applied between creqsTrackChangesStart/Stop statements
# for varName, it will be set and the service action will be performed at the end of the run
function creqServiceAction()
{
	local serviceName="$1"
	local action="$2"
	local varName="${3:-$serviceName}"
	assertNotEmpty varName
	if creqIsApply; then
		if creqsTrackChangesCheck $varName; then
			_creqEcho -v1 "${action^^}ing... : service '$serviceName' because its configuration has changed USER='$USER'"
			# note: 2015-09 the sudo prefix to service is needed even if you are already root. related to User Sessions for upstart services
			local line temp; while IFS="" read -r temp; do
				line="${temp/+-M-+/$line}"
				_creqEcho -v1 -o "${action^^}ing... : $line"
			done < <(sudo service $serviceName $action || echo "FAILED($?) +-M-+")
			_creqEcho -v1 -o "${action^^}ed '$serviceName' : $line"
		fi
	fi
}

# usage: creqWasChanged file1 [ file2 [ .. fileN] ]
# test the files to see if any have a modification time stamp newer than the start of the
# creqInit run. This can be called any time before the creqReport call 
# returns 0 (true) if any of the files have been changed
# returns 1 (false) if none have been changed 
function creqWasChanged()
{
	while [ "$creqStartTimeFile" ] && [ "$1" ]; do
		if [ "$1" -nt "$creqStartTimeFile" ]; then
			return 0
		fi 
		shift
	done
	return 1
}




##############################################################################################
### internal functions

# usage: _creqEcho [-o] [-v <level>] ... text ...
# internal function used to display progress of a creqs execution. 
# Options:
#    -o : overwrite. move cursor back to the previous line. If you use -o with single line output
#         each call will replace the last line
#    -v<level> : verbosity threshold. the level at which this message should be displed. 
#         e.g. a msg sent with -v3 will only be output when verbosity is 3 or higher
function _creqEcho()
{
	local overWriteFlag=""
	local vLevel=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		-o) overWriteFlag="1" ;;
		-v) vLevel="$2"; shift ;;
		-v*) vLevel="${1#-v}" ;;
	esac; shift; done

	# if the verbosity is 3 or more or if we are not writing to a terminal, turn off overwrite even if it was asked for
	[ ! -t 1 ] && overWriteFlag=""
	[ ${creqVerbosity:-1} -ge 3 ] && overWriteFlag=""

	# 2015-09 bg: not sure why this line check for "^/dev". Why wouldn't this be like the rest?
	[[ ! "$creqLogfile" =~ ^/dev ]] && echo "$*" > >(awk '{print "  # : "$0}' >>$creqLogfile)

	if [ ${creqVerbosity:-1} -ge ${vLevel:-0} ]; then
		[ "$overWriteFlag" ] && echo -en "\033[1A"  # move cursor back up one line to overwrite the last message
		echo -en "${@}"  | wrapLines "   " "      "
		[ "$overWriteFlag" ] && echo -en "\033[K"  # clear to eol
		echo
	fi
}


# usage: _creqTrapExitingCrStmts
# internal function used in trap .. EXIT by creqs()
function _creqTrapExitingCrStmts()
{
	sync
	(
		awk '{print "      (stderr): "$0}' "${creqTestLog}.err"
		_creqEcho -v1 "ERROR: creq run ended prematurely in $classFn::$objectMethod"
		local -A stackFrame=(); bgStackGetFrame creq-1 stackFrame 
		assertError -v classFn -v objectMethod -v file -v lineno -v function -v scriptLine "
			       $classFn::$objectMethod called exit/assert and has ended the creq run prematurely.
			       this function should use return instead of exit. The equivalent to exit in creq class 
			       methods is to write an error message to stderr and return n. This error can be fixed by 
			       enclosing the exit with (). Typically that means putting assert calls in (). 
			       For example: use '(assertNotEmpty myRequiredVar) || return' 
			       to assert an error condition. Make sure that any class variable assignments are not
			       inside any (). The offending line is...
			          ${stackFrame[printLine]}
		"
	) 
}



# usage: _creqLogStmtResult <result> <resultDetail>
# usage: _creqLogStmtResult -H
# TODO: refactor this whole module.
# this is a temp measure. Its used in similar places to _creqEcho but only the places where creq statement ends.
# so this is called exactly once per statement
function _creqLogStmtResult()
{
	# TODO: record parameters too in a separate file keyed on (creqProfileID,_creqUID) 
	if [ "$_creqProfileLog" ]; then
		local fmtStr="%-18s %13s %-20s %-18s %-7s %12s %-18s \n"
		if [ "$1" == "-H" ]; then
			printf "${fmtStr}\n" "server" "pluginType" "profileName" "stmtID" "result" "resultDetail" "stmtType"  > "${_creqProfileLog}.statements"
		else
			local result="$1"
			local resultDetail="$2"

			# if it passes because we just applied the statement, record the timestamp in a log that grows
			if [ "$result:$resultDetail" == "PASS:APPLIED" ]; then
				# we don't record the APPLIED in the state file because on the next run, it will change again to PASS:-- and we want to avoid double commits like that 
				# the growing apply log file will change just once per APPLY 
				resultDetail=""

				local fmtStr2="%-19s %-10s %-18s %13s %-20s %-18s %-18s \n"
				if [ ! -s "${_creqProfileLog}.applyLog" ]; then
					printf "${fmtStr2}\n" "time" "timeEpoch" "server" "pluginType" "profileName" "stmtID" "stmtType"  > "${_creqProfileLog}.applyLog"
				fi
				local nowTS="$(date +"%s")"
				local nowStr="$(date +"%Y-%m-%d:%H:%M:%S")"
				printf "$fmtStr2" "${nowStr:--}" "${nowTS:--}" "${scopeName:--}"  "${creqRunningPluginType:---}" "${creqRunningProfileName:---}" "${_creqUID:---}" "${classFn:---}"  >> "${_creqProfileLog}.applyLog"
			fi

			printf "$fmtStr" "${scopeName:--}" "${creqRunningPluginType:---}" "${creqRunningProfileName:---}" "${_creqUID:---}" "${result:---}" "${resultDetail:---}" "${classFn:---}"  >>"${_creqProfileLog}.statements"
		fi
	fi
}


# usage: _creqLogMarker ...
# Writes the content passed on the command line to the log file decorated as a marker section to indicate 
function _creqLogMarker()
{
	sync
	echo "$*" > >(awk '
		NR==1{printf("\n### : %s\n", $0)}
		NR>1 {printf(  "  # : %s\n", $0)}
	' | tee -a $creqLogfile >>$creqStdout)
	sync
}

# usage: dn="$(creqMakeDisplayName "cr_funcName" "$@" )"
# the creq function uses this to create a default display name when the cr_* function
# does not define one
function creqMakeDisplayName()
{
	stringShorten -j fuzzy 90 "$@"
}


# usage: cr_baseClass
# this provides the default implementation for cr_ function classes
# most cr_* type functions call this from their default (*) case statement
# if the caller does not set the objectMethod var, this function knows that
# it was not invoked by the creq fucntion so it reinvokes with the creq function
function cr_baseClass()
{
	#bgtrace "entering cr_baseClass $@  objectMethod='$objectMethod'"
	if [ ! "$objectMethod" ]; then
		local i
		for i in ${!FUNCNAME[@]}; do
			#bgtrace "fun[$i] = ${FUNCNAME[$i]}"
			if [ "${FUNCNAME[$i]}" == "creq" ]; then
				assertError "cr_baseClass bad recursion"
			fi
		done
		creq ${FUNCNAME[1]} "$@"
	fi
}

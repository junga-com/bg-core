# usage: confirm [-dy|-dn|-de] <prompt>
# prompts the user for y/n and returns 0 (yes,true) or 1 (no,false) other keys are ignored until
# [nNyY] is pressed and the function returns immediately without requiring the user does to press enter.
# If the user presses cntr-c at the prompt it asserts an error. That is usefull for getting a stack
# trace of where the confirm is be called from when bg-debugCntr tracing is turned on.
#
# The caller can not suppress this prompt via redirection but can by setting the 'confirmAnswer' env
# variable to 'y', 'n', 'e'. e stands for error and is the action that the user cancels the operation
# by press cntr-c.
# BGENV: confirmAnswer: specify the answer to any 'confirm' prompts that the command might make
#
# Controlling Terminal:
# This function uses /dev/tty directly to communicate with the user running the command. If there is
# no controlling terminal we can not communicate with the user so it performs the default action.
# The default action is set with the -d* options and the default default action is 'no'
#
# common cases which do not have a controlling terminal
#    * invoked from a command via ssh without the -t options
#    * invoked from from cron
#    * invoked from from a daemon
#
# Params:
#    <prompt>  : the text that will prompt the user for a y/n response. The text " (y/n)" will be
#          appended to the prompt to let the user know that y or n must be entered.
# Options:
#    -dy : defaultAction='yes'.   return 'yes'(true) if there is no controlling terminal
#    -dn : defaultAction='no'.    return 'no'(false) if there is no controlling terminal
#    -de : defaultAction='error'. assert an error if there is no controlling terminal
# Exit Code:
#    0 (true)  : confirmation granted
#    1 (false) : confirmation denied
function confirm()
{
	local defaultAction="n"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-dy*) defaultAction="y" ;;
		-dn*) defaultAction="n" ;;
		-de*) defaultAction="e" ;;
	esac; shift; done
	local prompt="$*"

	# observe the confirmAnswer ENV var if set
	case ${confirmAnswer,,} in
		y*) return 0 ;;
		n*) return 1 ;;
	 	e*) assertError "confirm prompt canceled by user via the confirmAnswer='e' ENV var" ;;
		*) [ "$confirmAnswer" ] && assertError -v confirmAnswer "unknown value set in confirmAnswer ENV var"
	esac

	# handle the case that there is no controlling terminal to interact with the user
	if ! cuiHasControllingTerminal; then case $defaultAction in
		y) return 0 ;;
		n) return 1 ;;
	 	e) assertError "can not confirm with the user because there is no interactive terminal" ;;
	esac; fi

	bgtrap -n confirm 'stty echo; assertError --errorFn="confirm" "confirm prompt canceled by user"' SIGINT

	printf "$prompt (y/n)" >/dev/tty
	while [[ ! "$result" =~ ^[yYnN] ]]; do read -s -n1 result </dev/tty; done
	printf "$result\n" >/dev/tty

	bgtrap -r -n confirm SIGINT

	[[ "$result" =~ ^[yY] ]]
}

# usage: isShellFromSSH
# returns true if the script has been invoked by a ssh term (or child of one)
# this should not be used to determin permissions. the user could get this to
# report falsely. Use this for niceties like deciding whether to launch a getUserCmpApp
# version of a program or a text based one.
function isShellFromSSH()
{
	[ "$SSH_TTY" ] || [ "$(who | grep "([0-9.]*)" )" ]
}

# usage: isGUIViable
# returns true if the script has been invoked by a ssh term (or child of one)
# this should not be used to determin permissions. the user could get this to
# report falsely. Use this for niceties like deciding whether to launch a GUI
# version of a rpogram or a text based one.
function isGUIViable()
{
	[ ! "$SSH_TTY" ] && [ ! "$(who | grep "([0-9.]*)")" ]
}

# usage: wheresTheUserAt userOverridePlace "placesInPrefOrder"
# usage: wheresTheUserAt -t placeToTest
# First Form returns a token that indicates the best place for a script to interact with
# the user.
# Example:
# 	case $(wheresTheUserAt "$userOverride") in
# 		gui)	zenity --question --text="Do you wanna?" ;; 	# invoke a GUI app for the user to interact with
# 		tuiOn1)	confirm "Do you wanna?" ;;						# invoke a text interact program in stdout
# 		tuiOn2)	confirm "Do you wanna?" >&2 ;;					# invoke a text interact program on stderr
# 		none)	echo "Do you wanna? I am going to assume yes" ;;# can't interact, must assume
# 	esac
#
# Second Form tests one place and returns true if that place is available
# Example:
# 	wheresTheUserAt "gui" && gedit
#
# It should not be thought of as an absolute. It might be wrong. Its a best guess
# A good practice is to support an optional parameter that the user can specify
# to the script and pass that in to this function. That value will take precendence
function wheresTheUserAt()
{
	# if the -t (test) form is specified this block will handle it and return
	if [ "$1" == "-t" ]; then
		case $2 in
			gui)	! isShellFromSSH; return ;;
			tuiOn1)	[ -t 1 ] && [ -t 0 ]; return ;;
			tuiOn2)	[ -t 2 ] && [ -t 0 ]; return ;;
			none)	return 0 ;;
		esac
		return
	fi
	local userOverride="$1"
	local placesInPrefOrder="${2:-gui tuiOn1 tuiOn2}"

	# this the user specified what they wanted and its a valid option,
	# return that
	if [[ " gui tuiOn1 tuiOn2 " =~ \ $userOverride\  ]]; then
		echo "$userOverride"
		return
	fi

	# test the UI places in order of preference and return the first that matches
	for i in $placesInPrefOrder; do
		if wheresTheUserAt -t $i; then
			echo "$i"
			return
		fi
	done

	# if nothing else, return none.
	echo "none"
}

function __testAndReturnApp() {
	if [ "$1" ] && which "$1" &>/dev/null; then
		echo "$@";
		return 0;
	fi
	return 1
}


# usage: $(getUserCmpApp) <file1> <file2>
# this inspects the environment and finds the command that the user prefers
# to compare two text files. If not specified, it will select meld if its
# installed or sdiff or diff as a last resort
#    BGENV: EDITOR_DIFF : diff|sdiff|<programName> : specify the prefered diff program. Invoked with two filenames to compare
#    BGENV: VISUAL_DIFF : meld|<programName> : takes precendence over EDITOR_DIFF when invoked on a GUI workstation
function getUserCmpApp()
{
	if wheresTheUserAt -t "gui"; then
		__testAndReturnApp "${VISUAL_DIFF}" && return
		__testAndReturnApp "meld" && return
	fi

	__testAndReturnApp "${EDITOR_DIFF}" && return
	__testAndReturnApp "${AT_COMPARE_APP}" && return
	__testAndReturnApp "diff" && return

	echo "diff"
}

# usage: $(getUserTerminalApp)
# this inspects the environment and finds the command that the user prefers
# to open a new terminal emulator window. 'gnome-terminal' is the default
#    BGENV: VISUAL_TERM : gnome-terminal|<programName> : the user's prefered terminal emulator program
function getUserTerminalApp()
{
	__testAndReturnApp "${VISUAL_TERM}" && return
	__testAndReturnApp "gnome-terminal" && return

	assertError "
		could not find an installed terminal emulator.
		See man(3) getUserTerminalApp
	"
}

# usage: $(getUserFileManagerApp) <file1> <file2>
# this inspects the environment and finds the command that the user prefers
# to view/edit a file system folder. (aka file manager)
# It will select 'atom' 'subl' or 'mc' if installed. The user can set EDITOR_IDE and VISUAL_IDE
#    BGENV: EDITOR_IDE : mc|<programName> : IDE application. used to open a folder for user to interact with. Invoked with one folder name
#    BGENV: VISUAL_IDE : atom|subl|<programName> : gui equivalent to EDITOR_IDE. takes precendence when invoked on a GUI workstation
function getUserFileManagerApp()
{
	if wheresTheUserAt -t "gui"; then
		__testAndReturnApp "${VISUAL_IDE}" && return
		__testAndReturnApp "atom" $@ && return
		__testAndReturnApp "subl" && return
	fi

	__testAndReturnApp "${EDITOR_IDE}" && return
	__testAndReturnApp "mc" && return

	echo  "echo -e no IDE (aka file manager) application configured.\nsee man getUserFileManagerApp\n\t<ideApp>"
}

# usage: $(getUserEditor) <file>
# this inspects the environment and finds the command that the user prefers
# to edit a text file. If not specified, it will select 'editor'
#    BGENV: EDITOR : nano|vi|<programName> : specify the prefered editor program. Invoked with one filename
#    BGENV: VISUAL : gedit|<programName> : takes precendence over EDITOR when invoked on a GUI workstation
function getUserEditor()
{
	if wheresTheUserAt -t "gui"; then
		__testAndReturnApp "${VISUAL}" && return
	fi

	__testAndReturnApp "${EDITOR}" && return

	echo "editor"
}


# usage: $(getUserPager) <file>
# this inspects the environment and finds the command that the user prefers to view files on the command line. This is typically
# more or less.
#    BGENV: PAGER : less|more|<programName> : specify the prefered program to view a text file on the command line. Invoked with one filename
function getUserPager()
{
	local quietMode
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q) quietMode="-q" ;;
	esac; shift; done

	__testAndReturnApp "${PAGER}" && return

	echo "less"
}


# usage: $(getUserBrowser) <file>
# this inspects the environment and finds the command that will open a url in the user's browser
# if desktop is avaiable
#    BGENV: BROWSER : <programName> : specify the prefered browser program. Invoked with one filename
function getUserBrowser()
{
	local quietMode
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q) quietMode="-q" ;;
	esac; shift; done

	__testAndReturnApp "$BROWSER" && return
	if wheresTheUserAt -t "gui"; then
		__testAndReturnApp "xdg-open" && return
		__testAndReturnApp "gnome-open" && return
	fi

	[ "$quietMode" ] || assertError "no GUI available to open URL"
}


# usage: notifyUser <message to display>
# sends a notification message to the  user
# tries to use an unobtrusive system like notify-send if available
function notifyUser()
{
	if which notify-send &>/dev/null; then
		notify-send "$@"
	fi
}


# Library
# CSI refers to a standard for escape sequences for terminals. A terminal is something that can be on the other end of a file
# descriptor. You can open a terminal for reading from the keyboard (and special query like cursor position) or writing charcaters
# to the terminal's screen display.
#
# If a script is ran from a desktop from within a GUI terminal emulator (e.g. gnome_terminal) or from one of the fixed tty (e.g.
# cntr-alt-[345...]) its stdin(0), stdout(1) and stderr(2) will be set to the tty device by default.
#
# When the output of a command goes to a FD that is a terminal, you can send it escape sequences which are out-of-band messages
# that instruct the terminal to change its internal state which affects how the in-band data is rendered. Most notable are cursor
# commands that allow drawing at a specific location and font commands that change the color of the text.
#
# This library defines a bunch of bash string variables that make it easier to use the escape sequences. To send CSI commands to a
# terminal you can use echo with the -e option or printf in the format string. printf is the prefered way b/c it separates
# presentaion and data. CSI sequences in the format string are sent to the terminal but in the data arguments they are not.
# The typical way to use it is..
#      printf "Hello ${CSI}${cBlue}%s${CSI}${cNorm}"  "$USER"
# ${CSI} starts an escape sequence. It is folled by 0,1, or 2 parameters and then the c* code which is a specific command.
# A long sequence of CSI cmds can be crafted and sent in one printf call which makes it possible that they will be acted on in one
# atomic operation.
#
# The string constants that begin with csi* include the ${CSI} start sequence so they can be used on their own. The ones that start
# with only a c* do not include the start sequence so they need to be used in a sequence starting wiht ${CSI}. most cmds have both
# versions so that they can be used simply on their own or be combined with other cmds. Multiple c* commands can follow a single
# ${CSI}
#
# This library also includes some functions starting with cui* that perform some operation on the terminal using escape codes.
#
# The history of escape codes is complicated and there are multiple tools for using them. tput is an alternative. At one point, the
# major issue was that many terminal types existed and a tool like tput had to detect the terminal type and set the correct codes
# for that terminal. There is now a pretty universal subset of codes.
#
# This library also contains some function unrelated to terminals that interact with the user in various way. confirm will prmpt
# the user for a binary choice and exit true or false. GetUser* are functions that get the user's prefered application for various
# functions.
#
# See Also:
# see http://www.shaels.net/index.php/propterm/documents/14-ansi-protocol
# see https://wiki.bash-hackers.org/scripting/terminalcodes
# see http://en.wikipedia.org/wiki/ANSI_escape_code
# see http://invisible-island.net/xterm/ctlseqs/ctlseqs.html

# usage: readKey <retVar>
# returns one key pressed by the user of the terminal.
# If the key pressed by the user is a printable character, that character is returned in <retVar>.
# If the key is a special key a string in the form of <code> is returned where code is a short nmemonic for the key press.
# Special Keys Nmemonics:
#    <esc>
#    <bs>
#    <del>    <shift-del>
#    <home>   <shift-home>
#    <end>    <shift-end>
#    <insert> <shift-insert>
#    <up>     <shift-up>
#    <down>   <shift-down>
#    <right>  <shift-right>
#    <left>   <shift-left>
#    <pgUp>   <shift-pgUp>
#    <pgDown> <shift-pgDown>
#
#    <f1>     <shift-f1>
#    <f2>     <shift-f2>
#    <f3>     <shift-f3>
#    <f4>     <shift-f4>
#    <f5>     <shift-f5>
#    <f6>     <shift-f6>
#    <f7>     <shift-f7>
#    <f8>     <shift-f8>
#    <f9>     <shift-f9>
#
#    <cntr-a>     <alt-a>      <alt-A>
#    <cntr-b>     <alt-b>      <alt-B>
#    <cntr-c>     <alt-c>      <alt-C>
#    <cntr-d>     <alt-d>      <alt-D>
#    <cntr-e>     <alt-e>      <alt-E>
#    <cntr-f>     <alt-f>      <alt-F>
#    <cntr-g>     <alt-g>      <alt-G>
#    <cntr-h>     <alt-h>      <alt-H>
#    <cntr-i>     <alt-i>      <alt-I>
#    <cntr-j>     <alt-j>      <alt-J>
#    <cntr-k>     <alt-k>      <alt-K>
#    <cntr-l>     <alt-l>      <alt-L>
#    <cntr-m>     <alt-m>      <alt-M>
#    <cntr-n>     <alt-n>      <alt-N>
#    <cntr-o>     <alt-o>      <alt-O>
#    <cntr-p>     <alt-p>      <alt-P>
#    <cntr-q>     <alt-q>      <alt-Q>
#    <cntr-r>     <alt-r>      <alt-R>
#    <cntr-s>     <alt-s>      <alt-S>
#    <cntr-t>     <alt-t>      <alt-T>
#    <cntr-u>     <alt-u>      <alt-U>
#    <cntr-v>     <alt-v>      <alt-V>
#    <cntr-w>     <alt-w>      <alt-W>
#    <cntr-x>     <alt-x>      <alt-X>
#    <cntr-y>     <alt-y>      <alt-Y>
#    <cntr-z>     <alt-z>      <alt-Z>
function cuiReadKey() { readKey "$@"; }
function readKey()
{
	local char;
	read -s -N1  char
	case $char in
		$'\033')
			read -s -t0.001 -N6 char
			case ${char:-empty} in
				empty) char="<esc>" ;;

				[3~) char="<del>"   ;;
				[H)  char="<home>"   ;;
				[F)  char="<end>"    ;;
				[2~) char="<insert>" ;;

				[A)  char="<up>"    ;;
				[B)  char="<down>"  ;;
				[C)  char="<right>" ;;
				[D)  char="<left>"  ;;
				[5~) char="<pgUp>"  ;;
				[6~) char="<pgDown>";;

				OP) char="<f1>"    ;;
				OQ) char="<f2>"    ;;
				OR) char="<f3>"    ;;
				OS) char="<f4>"    ;;
				[15~) char="<f5>"    ;;
				[17~) char="<f6>"    ;;
				[18~) char="<f7>"    ;;
				[19~) char="<f8>"    ;;
				[20~) char="<f9>"    ;;
				[24~) char="<f12>"   ;;

				'[3;2~') char="<shift-del>"   ;;
				'[1~')   char="<shift-home>"   ;;
				'[4~')   char="<shift-end>"    ;;
				'[2~')   char="<shift-insert>" ;;
				'[Z')    char="<shift-tab>" ;;

				'[1;2A')  char="<shift-up>"    ;;
				'[1;2B')  char="<shift-down>"  ;;
				'[1;2C')  char="<shift-right>" ;;
				'[1;2D')  char="<shift-left>"  ;;
				'[1;25~') char="<shift-pgUp>"  ;;
				'[1;26~') char="<shift-pgDown>";;

				'[1;5A')  char="<cntr-up>"    ;;
				'[1;5B')  char="<cntr-down>"  ;;
				'[1;5C')  char="<cntr-right>" ;;
				'[1;5D')  char="<cntr-left>"  ;;
				'[1;55~') char="<cntr-pgUp>"  ;;
				'[1;56~') char="<cntr-pgDown>";;

				'[1;2P')  char="<shift-f1>"    ;;
				'[1;2Q')  char="<shift-f2>"    ;;
				'[1;2R')  char="<shift-f3>"    ;;
				'[1;2S')  char="<shift-f4>"    ;;
				'[15;2~') char="<shift-f5>"    ;;
				'[17;2~') char="<shift-f6>"    ;;
				'[18;2~') char="<shift-f7>"    ;;
				'[19;2~') char="<shift-f8>"    ;;
				'[20;2~') char="<shift-f9>"    ;;
				'[24;2~') char="<shift-f12>"   ;;

				a) char="<alt-a>"  ;;
				b) char="<alt-b>"  ;;
				c) char="<alt-c>"  ;;
				d) char="<alt-d>"  ;;
				e) char="<alt-e>"  ;;
				f) char="<alt-f>"  ;;
				g) char="<alt-g>"  ;;
				h) char="<alt-h>"  ;;
				i) char="<alt-i>"  ;;
				j) char="<alt-j>"  ;;
				k) char="<alt-k>"  ;;
				l) char="<alt-l>"  ;;
				m) char="<alt-m>"  ;;
				n) char="<alt-n>"  ;;
				o) char="<alt-o>"  ;;
				p) char="<alt-p>"  ;;
				q) char="<alt-q>"  ;;
				r) char="<alt-r>"  ;;
				s) char="<alt-s>"  ;;
				t) char="<alt-t>"  ;;
				u) char="<alt-u>"  ;;
				v) char="<alt-v>"  ;;
				w) char="<alt-w>"  ;;
				x) char="<alt-x>"  ;;
				y) char="<alt-y>"  ;;
				z) char="<alt-z>"  ;;

				A) char="<alt-A>"  ;;
				B) char="<alt-B>"  ;;
				C) char="<alt-C>"  ;;
				D) char="<alt-D>"  ;;
				E) char="<alt-E>"  ;;
				F) char="<alt-F>"  ;;
				G) char="<alt-G>"  ;;
				H) char="<alt-H>"  ;;
				I) char="<alt-I>"  ;;
				J) char="<alt-J>"  ;;
				K) char="<alt-K>"  ;;
				L) char="<alt-L>"  ;;
				M) char="<alt-M>"  ;;
				N) char="<alt-N>"  ;;
				O) char="<alt-O>"  ;;
				P) char="<alt-P>"  ;;
				Q) char="<alt-Q>"  ;;
				R) char="<alt-R>"  ;;
				S) char="<alt-S>"  ;;
				T) char="<alt-T>"  ;;
				U) char="<alt-U>"  ;;
				V) char="<alt-V>"  ;;
				W) char="<alt-W>"  ;;
				X) char="<alt-X>"  ;;
				Y) char="<alt-Y>"  ;;
				Z) char="<alt-Z>"  ;;

			esac
			;;
		$'\177') char="<bs>" ;;
		$'\012') char="<cr>" ;;
		$'\011') char="<tab>";;

		$'\001') char="<cntr-a>"  ;;
		$'\002') char="<cntr-b>"  ;;
		$'\003') char="<cntr-c>"  ;;
		$'\004') char="<cntr-d>"  ;;
		$'\005') char="<cntr-e>"  ;;
		$'\006') char="<cntr-f>"  ;;
		$'\007') char="<cntr-g>"  ;;
		$'\008') char="<cntr-h>"  ;;
		$'\009') char="<cntr-i>"  ;;
		$'\010') char="<cntr-j>"  ;;
		$'\011') char="<cntr-k>"  ;;
		$'\012') char="<cntr-l>"  ;;
		$'\010') char="<cntr-m>"  ;;
		$'\014') char="<cntr-n>"  ;;
		$'\015') char="<cntr-o>"  ;;
		$'\016') char="<cntr-p>"  ;;
		$'\017') char="<cntr-q>"  ;;
		$'\018') char="<cntr-r>"  ;;
		$'\019') char="<cntr-s>"  ;;
		$'\020') char="<cntr-t>"  ;;
		$'\021') char="<cntr-u>"  ;;
		$'\022') char="<cntr-v>"  ;;
		$'\023') char="<cntr-w>"  ;;
		$'\024') char="<cntr-x>"  ;;
		$'\025') char="<cntr-y>"  ;;
		$'\026') char="<cntr-z>"  ;;
	esac
	returnValue "$char" "$1"
}

# usage: cuiSetTitle <title>
function cuiSetTitle()
{
	echo -en "\033]0;$1\a"
}

# usage: cuiGetScreenDimension <lineCountVar> <columnCountVar> [< <tty>]
# returns the hieght in lines and width in characters of the tty connected to stdin
# If stdin is not a tty, returns 1 and sets the values to 999999. The assumption is that the caller is getting the dimensions to
# clip or wrap the output so if there is no terminal. the dimensions should be large so that outp is not clipped nor wrapped.
# if that is not the case, the caller can check the return value
# Options:
#    --tty=<tty>  : example: /dev/tty or /dev/pts/2. instead of using the tty identified by stdin, use this one
#    -q) quiet. if there is no tty, return 999999,999999 instead of asserting an error
function CSIgetScreenDimension() { cuiGetScreenDimension "$@"; }
function cuiGetTerminalDimension() { cuiGetScreenDimension "$@"; }
function cuiGetScreenDimension()
{
	local tty quietFlag
	while [ $# -gt 0 ]; do case $1 in
		--tty) bgOptionGetOpt val: tty "$@" && shift ;;
		-q) quietFlag="-q" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# if not passed in, get the tty of this subshell which should be what stdin points to if its a tty
	if [ ! "$tty" ]; then
		tty="$(tty)"
		if [ ! -e "$tty" ]; then
			[ ! "$quietFlag" ] && assertError "could not find a tty to get the cursor position of"
			setReturnValue "$1" "999999"
			setReturnValue "$2" "999999"
			return 1
		fi
	fi

	local scrapVar
	read -r "${1:-scrapVar}" "${2:-scrapVar}" < <(stty size <$tty)
	return 0
}



# usage: cuiGetCursor [--tty=<tty>|/dev/pts/%3A] <cLineNumVar> <cColumnNumVar> [< <tty>]
# fills in the cLineNum and cColumnNum variable names passed in with the current cursor position
# of the tty connected to stdin. If stdin is not a tty, it sets <cLineNumVar> <cColumnNumVar> to -1
# and sets the exit code to 1.
# Note that this function must read and write to the tty to get the cursor position. No other read
# operations should be pending on the tty and if there is any input in the tty's buffer, it will be
# consumed and lost by this function.
# Params:
#    <cLineNumVar>    : the line (vertical) cursor position starting with 1 (top edge is 1)
#    <cColumnNumVar>  : the column (horizontal) cursor position starting with 1 (left edge is 1)
#    < <tty> (stdin)  : to get the cursor position of a specific tty, redirect the input of this
#                       function to that tty. Note that the stdout is ignored and not used.
# Options:
#    --tty=<tty>  : instead of using the tty identified by stdin, use this one
#    -q) quiet. if there is no tty, return -1,-1 instead of asserting an error
#    --preserveRematch) take a little longer to execute in order not to clobble BASH_REMATCH
function CSIgetCursor() { cuiGetCursor "$@"; }
function cuiGetCursor()
{
	local tty quietFlag preserveRematch
	while [ $# -gt 0 ]; do case $1 in
		--preserveRematch) preserveRematch="--preserveRematch" ;;
		--tty) bgOptionGetOpt val: tty "$@" && shift ;;
		-q) quietFlag="-q" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _lineValue="-1"
	local _colValue="-1"

	# if not passed in, get the tty of this subshell which should be what stdin points to if its a tty
	if [ ! "$tty" ]; then
		tty="$(tty)"
		if [ ! -e "$tty" ]; then
			[ ! "$quietFlag" ] && assertError "could not find a tty to get the cursor position of"
			setReturnValue "$1" "$_lineValue"
			setReturnValue "$2" "$_colValue"
			return 1
		fi
	fi

	# read seems to write the prompt to stderr. redirect 0,1,and 2 to $tty. writing with >&0 does not work b/c &0 is open for readonly
	local buf; IFS= read -sr -dR -p $'\e[6n' buf <$tty &>$tty
	if [ "$preserveRematch" ]; then
		read -r _lineValue _colValue < <(
			[[ "$buf" =~ $'\e['([0-9]*)\;([0-9]*)$ ]] || assertError -Vbuf:"$(echo "$buf" | cat -v)" "failed to read cursor position from the terminal"
			echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
		)
	else
		[[ "$buf" =~ $'\e['([0-9]*)\;([0-9]*)$ ]] || assertError -Vbuf:"$(echo "$buf" | cat -v)" "failed to read cursor position from the terminal"
		_lineValue="${BASH_REMATCH[1]}"
		_colValue="${BASH_REMATCH[2]}"
	fi
	setReturnValue "$1" "$_lineValue"
	setReturnValue "$2" "$_colValue"
	return 0
}

# usage: cuiSetScrollRegion <lineStartNum> <lineEndNum>
# set the horizontal band of the terminal that will be subject to scrolling.
# Note: When the scroll region is set, if a scroll is trigger by writing a new line at the bottom of the screen,
# it will reset the scroll region to the entire screen.
# Note that this may move the cursor to the 1,1 position
# Params:
#      <lineStartNum> : is the line number of the first line that will participate in scrolling (1 == top)
#      <lineEndNum>   : is the line number of the last line that will participate in scrolling ( )
function CSIsetScrollRegion() { cuiSetScrollRegion "$@"; }
function cuiSetScrollRegion()
{
	[ -t 1 ] || return 1
	printf "${CSI}${1:-0};${2:-0}$cSetScrollRegion"
}

# usage: cuiResetScrollRegion
# reset the scroll region to the entire terminal.
# Note that this may move the cursor to the 1,1 position
function cuiResetScrollRegion()
{
	[ -t 1 ] || return 1
	printf "${CSI}$cSetScrollRegion"
}


# usage: cuiHideCursor [> <tty>]
# tell the tty to *not* show an indicator at the cursor location
function cuiHideCursor()
{
	[ -t 1 ] || return 1
	printf "${csiHide}"
}

# usage: cuiShowCursor [> <tty>]
# tell the tty to show an indicator at the cursor location
function cuiShowCursor()
{
	[ -t 1 ] || return 1
	printf "${csiShow}"
}

# usage: cuiSetCursor <cLineNum> <cColumnNum> [> <tty>]
# Params:
#    <cLineNum>    : the line (vertical) cursor position starting with 1 (top edge is 1)
#    <cColumnNum>  : the column (horizontal) cursor position starting with 1 (left edge is 1)
#    > <tty> (stdin)  : to set the cursor position of a specific tty, redirect the output of this
#                       function to that tty.
function CSImoveTo() { cuiMoveTo "$@"; }
function cuiSetCursor() { cuiMoveTo "$@"; }
function cuiMoveTo()
{
	printf "${CSI}${1:-0};${2:-0}$cMoveAbs"
}

# usage: cuiMoveBy <lineDelta> <columnDelta>
# move the cursor a relative amount.
# Params:
# 	<lineDelta>   :  num lines to move down (pos) or up (neg)
# 	<columnDelta> :  num chars to move right (pos) or left (neg)
function CSImoveBy() { cuiMoveBy "$@"; }
function cuiMoveBy()
{
	local lineDelta="${1:-0}"
	local columnDelta="${2:-0}"
	local vCmd=B; [ $lineDelta   -lt 0 ] && vCmd=A && lineDelta=$((   0 - lineDelta   ))
	local hCmd=C; [ $columnDelta -lt 0 ] && hCmd=D && columnDelta=$(( 0 - columnDelta ))
	local moveStr=""
	((lineDelta!=0))   && moveStr+="${CSI}${lineDelta}${vCmd}"
	((columnDelta!=0)) && moveStr+="${CSI}${columnDelta}${hCmd}"
	printf "$moveStr"
}

# usage: cuiScrollTerm <count>
# scroll the current scroll region in the terminal by <count> lines
# Params:
#    <count> : the number of lines to scroll. Positive numbers scroll the existing lines up. Negative
#              numbers scroll them down
function termScroll() { cuiScrollTerm "$@"; }
function cuiScrollTerm()
{
	[ -t 1 ] || return 1
	local count="${1:-1}"
	if [ $count -gt 0 ]; then
		printf "${CSI}${count}$cScrollUp"
	elif [ $count -lt 0 ]; then
		printf "${CSI}${count#-}$cScrollDown"
	fi
}


# usage: cuiClrScr
# set the entire terminal to spaces and set the cursor to (1,1)
function cuiClrScr()
{
	[ -t 1 ] || return 1
	printf "${csiClrSrc}"
	cuiSetCursor 1 1
}






# # OBSOLETE: its easier and faster to just make the sequences like "${CSI}$x;$y;${cMoveAbs}". Now we have cuiRealizeFmtToTerm we do not need this
# # usage: printf " ... $(CSI [p1 ...] <cCMD>) ... "
# # This function assembles a CSI escape sequence. All CSI escape sequences use a standard format
# #      $CSI + <0 or more params apearated by ;> + $<cCode>
# # The string that this function produces is a textual ASCII sequence that represent the real binary sequence
# # that will effect the terminal. printf automatically decodes the text escape sequence into its binary
# # representation. echo does not by default but will if the -e switch is given.
# # Examples:
# #     echo -en "$(CSI $cSave)"      # saves the current cursor position. uses no params
# #     printf "$(CSI 4 $cDOWN)"      # moves the cursor down 4 lines. 1 is the default
# #     printf "$(CSI y x $cMoveAbs)" # moves the the absolute (y, x) cursor position
# function CSI()
# {
# 	[ -t 1 ] || return 1
# 	[ "$CSIOff" ] && return
# 	local params="" sep=""
# 	while [ $# -gt 1 ]; do
# 		params="${params}${sep}${1}"
# 		sep=";"
# 		shift
# 	done
# 	local cmd="$1"
#
# 	printf "${CSI}${params}${cmd}"
# }


declare -g _CSI="\033["
declare -g _OSC="\033]"

# usage: local $(cuiRealizeFmtToTerm [schemaArray1 .. schemaArrayN] < <destination>)
# usage: declare -g $(cuiRealizeFmtToTerm [schemaArray1 .. schemaArrayN] < <destination>)
# This is used in a command that writes output that contains $csi* format string variables to turn the variables
# on/off based on whether the output is going to a tty or not. When its not a tty, all the vars will be empty
# There are a base set of variables that always get defined by this function and the the schemeArrayN
# optionally define more variables that are specic to the script/application.
# Params:
#     <destination> : redirect the destination to stdin. It won't be read from. Its only used to test
#          whether stdin is a tty or not. stdout might seem more logical for this but stdout needs to
#          be a pipe to collect the output of the command.
# CSI Codes:
# CSI is a common standard that multiple terminals support for display painting.
# all CSI escape sequences use a standard form $CSI + <0orMoreParams> + $<cCode>
# when there are two or more params, they are separated by ';
# There are several sets of variables provided to use CSI codes in output.
#    $c<Name> variables:
#        variables that start with a lowercase 'c' and then a capitalized name are the component codes
#        that can be used to create a CSI sequence in the form "${CSI}${cBold}" or "${CSI}20;1;${cMoveAbs}"
#    $csi<Name> variables:
#        variables that start with 'csi*' include the $CSI start so they can be used alone like
#        "${csiBold}" or "${csiUP}".  Many commands do not have any parameters so using the csi*
#        version makes more sense. The c<Name> version is always available also to be consistent.
#        Commands that require parameters do not have associated csi* versions
#    $<userDefinedColorNames> variables:
#        These are defined by script authors in the indexes of cuiScheme arrays. See cuiColorTheme_sample1
#        for an example.
#        These are not primitive CSI commands. They are aliases for strings that can be used to achieve
#        font effects. The combined set of these from all the optional arrays passed into this function
#        make a color schema that can be editted at runtime.
function cuiRealizeFmtToTerm()
{
	if [ -t 0 ]; then
		# CSI and OSC are two different sets of escape code that start with a different escape char
		# most useful stuff is CSI. Set Window title is an OSC code
		local CSI="$_CSI"
		local OSC="$_OSC"
		echo "CSIOn=1"
		echo "CSIOff="
	else
		local CSI=""
		local OSC=""
		echo "CSIOn="
		echo "CSIOff=1"
	fi

	echo "CSI=${CSI}"
	echo "OSC=${OSI}"

	local cName csiName code
	for cName in "${!_csiCMD_p0[@]}"; do
		csiName="csi${cName#c}"
		code="${CSI:+${_csiCMD_p0[$cName]}}"
		echo "$cName=${code}		$csiName=${CSI}${code}"
	done
	for cName in "${!_csiCMD_p1[@]}"; do
		code="${CSI:+${_csiCMD_p1[$cName]}}"
		echo "$cName=${code}"
	done
	for cName in "${!_csiCMD_p2[@]}"; do
		code="${CSI:+${_csiCMD_p2[$cName]}}"
		echo "$cName=${code}"
	done

	# TODO: allow caller to pass in a scheme name, write out the aggregate map to a data file that will be the master/default theme. Then allow runtime designer to confiure multiple themes that satisfy that schema such that user can select from them
	while [ $# -gt 0 ]; do
		local colorArrayName="$1"; shift
		local -A colorArray=()
		arrayCopy  "$colorArrayName" colorArray
		for cName in "${!colorArray[@]}"; do
			code="${CSI:+${colorArray[$cName]}}"
			# TODO: lookup cName in run time config here to allow changing themes
			echo "$cName=${code}"
		done
	done
}

declare -Ag _csiCMD_p1=(
	[cToCol]="G"				# <col>
#(there seems to not be a cmd for this)	[cToLine]="G"				# <line>
)
declare -Ag _csiCMD_p2=(
	[cMoveAbs]="H"				# <line> <col>
	[cSetScrollRegion]="r"		# <lineStartNum> <lineEndNum>
)

declare -Ag _csiCMD_p0=(
	# cursor movement
	[cHide]="?25l"
	[cShow]="?25h"
	[cSave]="s"
	[cRestore]="u"
	[cUP]="A"
	[cDOWN]="B"
	[cRIGHT]="C"
	[cLEFT]="D"
	[cToSOL]="G"

	# clear / delete
	[cClrToEOL]="K"
	[cClrToSOL]="1K"
	[cClrLine]="2K"
	[cClrBelowCursor]="0J"
	[cClrAboveCursor]="1J"
	[cClrSrc]="2J"
	[cClrSavedLines]="3J"
	[cInsertLines]="L"
	[cDeleteLines]="M"
	[cInsertChars]="@"
	[cDeleteChars]="P"

	# scroll
	[cScrollUp]="S"
	[cScrollDown]="T"

	# line wrapping
	[cLineWrapOn]="?7h"
	[cLineWrapOff]="?7l"

	# pages
	[cSwitchToAltScreen]="?47h"
	[cSwitchToNormScreen]="?47l"
	[cSwitchToAltScreenAndBuffer]="?1049h"
	[cSwitchToNormScreenAndBuffer]="?1049l"

	# font attributes
	# see http://misc.flogisoft.com/bash/tip_colors_and_formatting
	[cNorm]="0m"
	[cFontReset]="0m"
	[cBold]="1m"
	[cFaint]="2m"
	[cItalic]="3m"
	[cUnderline]="4m"
	[cNoUnderline]="24m"
	[cOverline]="53m"
	[cNoOverline]="55m"
	[cBlink]="5m"
	[cReverse]="7m"
	[cConceal]="8m"
	[cStrikeout]="9m"

	# font colors
	[cDefColor]="39m"
	[cDefBkColor]="49m"

	[cBlack]="30m"
	[cRed]="31m"
	[cGreen]="32m"
	[cYellow]="33m"
	[cBlue]="34m"
	[cMagenta]="35m"
	[cCyan]="36m"
	[cWhite]="37m"

	[cHiBlack]="90m"
	[cHiRed]="91m"
	[cHiGreen]="92m"
	[cHiYellow]="93m"
	[cHiBlue]="94m"
	[cHiMagenta]="95m"
	[cHiCyan]="96m"
	[cHiWhite]="97m"

	[cBkBlack]="40m"
	[cBkRed]="41m"
	[cBkGreen]="42m"
	[cBkYellow]="43m"
	[cBkBlue]="44m"
	[cBkMagenta]="45m"
	[cBkCyan]="46m"
	[cBkWhite]="47m"

	[cHiBkBlack]="100m"
	[cHiBkRed]="101m"
	[cHiBkGreen]="102m"
	[cHiBkYellow]="103m"
	[cHiBkBlue]="104m"
	[cHiBkMagenta]="105m"
	[cHiBkCyan]="106m"
	[cHiBkWhite]="107m"
)

# Sample Color Scheme. Scripts can define one or more associative arrays like this one. When a script
# calls cuiRealizeFmtToTerm, it can pass in one or more of these array names. cuiRealizeFmtToTerm will
# turn the index names into variable names. The value will be either the empty string when realized to
# non-tty destinations or the value from the array. The values in the array are the default values.
# A mechanism will be added that will create a schema data file from the combined set of index names
# that can be edited with values that can override the default values provided in the script arrays
declare -Ag cuiColorTheme_sample1=(
	[csiColorDefault]="$_CSI${_csiCMD_p0[cDefBkColor]}$_CSI${_csiCMD_p0[cDefColor]}$_CSI${_csiCMD_p0[cNorm]}"
	[csiColorChanged]="$_CSI${_csiCMD_p0[cHiRed]}"
	[csiColorSelected]="$_CSI${_csiCMD_p0[cBold]}"
	[csiColorHilighted]="$_CSI${_csiCMD_p0[cHiYellow]}"
	[csiColorHilightBk]="$_CSI${_csiCMD_p0[cUnderline]}"
	[csiColorAttention]="$_CSI${_csiCMD_p0[cWhite]}$_CSI${_csiCMD_p0[cBkRed]}"
	[csiColorStatusLineDef]="$_CSI${_csiCMD_p0[cNorm]}${_CSI}48;2;64;64;64m${_CSI}38;2;252;255;255m"
	[csiColorCompleted]="$_CSI${_csiCMD_p0[cBlack]}$_CSI${_csiCMD_p0[cBkGreen]}"
	[csiColorError]="$_CSI${_csiCMD_p0[cHiRed]}"
	[csiColorH1]="$_CSI${_csiCMD_p0[cBlack]}$_CSI${_csiCMD_p0[cBkBlue]}$_CSI${_csiCMD_p0[cBold]}"
	[csiColorH2]="$_CSI${_csiCMD_p0[cBlack]}$_CSI${_csiCMD_p0[cBkBlue]}"
	[csiColorH3]="$_CSI${_csiCMD_p0[cBold]}"
)

# init the global version of the $csi* vars to reflect stdout(1)
declare -g $(cuiRealizeFmtToTerm cuiColorTheme_sample1)




# usage: cuiSetReadlineKeyHandler --shellCmd|-x <key> <shellCmd>
# usage: cuiSetReadlineKeyHandler --readlineFn  <key> <readlineFn>
# usage: cuiSetReadlineKeyHandler --text        <key> <text>
# readline is a function that many lunix cmdline programs including bash use to collect input from the user.
# The bash builtin 'read' is a wrapper over readline when invoked with the -e option.
# readline allows defining macros to keys. Bash allows us to access that feature when using read -e
# by using the 'bind' builtin. The bind builtin has a very peculiar quoting standard and is not clear
# about the difference between macros that are simply text that is inserted on the line, its builtin
# functions and shell cmds. This is a wrapper over bind that makes it easier to use.
# Params:
#    <key>      : a key identifier in emacs format. see "Readline Key Bindings" section of man bash
#                 to determine the string to use, run 'xev' in a terminal, click on the terminal and
#                 press a key to see what the emacs string id is for that key or key combination.
#    <shellCmd> : when --shellCmd|-x is specified, the macro will be executed as a shell script. i.e.
#                 it can be simple or compound command calling shell functions and external commands.
#    <readlineFn : when --readlineFn is specified, the macro will be interpreted as a readline internal
#                  function. See man readline or bind -l for a list.
#    <text>      : when --text is specified, the macro will be interpreted as text to insert into
#                  the cmdline string. If it ends in \015 (enter), it will cause readline to return
# See Also:
#    man(3) readline
#    man(1) bash (section Readline Key Bindings)
function bgbind() { cuiSetReadlineKeyHandler "$@"; }
function cuiSetReadlineKeyHandler()
{
	local macroType
	while [ $# -gt 0 ]; do case $1 in
		--shellCmd|-x) macroType="--shellCmd" ;;
		--readlineFn)  macroType="--readlineFn" ;;
		--text)        macroType="--text" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local key="$1"; shift
	local macroStr="$*"
	set -o emacs;
	case $macroType in
		--shellCmd)    bind -x '"'"$key"'":"'"$macroStr"'"' ;; # -x denotes shell command
		--readlineFn)  bind    '"'"$key"'":'"$macroStr"'' ;;   # no -x and unquoted macroStr denotes readlineFn
		--text)        bind    '"'"$key"'":"'"$macroStr"'"' ;; # no -x and quoted macroStr denotes text
		*) assertError -v key -v  -v macroType "one of --shellCmd|--readlineFn|--text needs to be specified"
	esac
}


# usage: cuiPrintColorTable
# usage: (source /usr/lib/bg_core.sh ; cuiPrintColorTable)
# print all the colors that we can make with CSI codes in a table
# this is a helper to people writing scripts to pick good colors
# See Also:
#   msgcat --color=test
#   colortest-16b
function cuiPrintColorTable()
{
	local esc=$'\033'
	for row in {0..15} ;
	do
	    rowtext=
	    for col in {0..15};
	    do
	        color=$(( $row * 16 + $col))
	        BG="${esc}[48;5;${color}m"
	        rowtext=${rowtext}$BG\   # note at leat two spaces after the \
	        if [[ $color -lt 100 ]]; then rowtext=${rowtext}$BG\   ;fi
	        if [[ $color -lt 10 ]]; then rowtext=${rowtext}$BG\   ;fi
	        rowtext=${rowtext}$BG${color}
	        rowtext=${rowtext}$BG\   # note at leat two spaces after the \
	    done
	    echo "${rowtext}${esc}[00m "
	done

	# for x in {0..8}; do
	#     for i in {30..37}; do
	#         for a in {40..47}; do
	#             echo -ne "\e[$x;$i;$a""m\\\e[$x;$i;$a""m\e[0;37;40m "
	#         done
	#         echo
	#     done
	# done
	# echo ""
}

# usage: cuiFlashScreen
# flash the terminal to get the user's attention. use sparingly
function cuiFlashScreen()
{
	printf \\e[?5h
	sleep 0.1
	printf \\e[?5l
}


# function cuiHasControllingTerminal() moved to bg_coreLibsMisc.sh

# usage: cuiGetSpinner <periodInMS> [<retVar>]
# this returns a single character that changes periodically to simulate a spinning wheel on a text display.
# it uses the current time to determine which of a rotating set of characters to return. each time the mod of the time in milliseconds
# passes <periodInMS>, the next character will be returned.
declare -ax _cuiGetSpinner_spinnerChars=( '\' '|' '/' '-' )
function cuiGetSpinner() {
	local period="$1"
	local t=$(( ($(date +"%s%N") / period /1000000) % ${#_cuiGetSpinner_spinnerChars[@]} ))
	returnValue "${_cuiGetSpinner_spinnerChars[$t]}" "$2"
}


# usage: cuiPromptForPassword [-c] <prompt> <passwordVar>
# This prompts the user interactively for a secret. The command should treat the returned text
# carefully without storing persistently or allowing it to be logged or displayed. The SDLC should
# identify any command that does this and subject it to additional review to ensure proper handling
# of the secret before the command is allowed to be added to a trusted repository.
#
# The user can cancel the command at the prompt with cntr-c
# Params:
#    <prompt>      : a prompt to let the user know what to type. nothing is added to this so it should
#                    typically end with a space or other delimiter
#    <passwordVar> : the name of the variable that will hold the text entered by the user
# Options:
#    -c  : confirm the password. This is typically used when the user is entering a new secret to make
#          sure that the user did not make a typo that would mean that they could not re-enter it later.
#          This will loop until the user sucessfully enters the same secret text twice.
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
# Security:
# Any command can ask the user for a password. We can not stop that. Users should know to only enter
# passwords into commands that are trusted. This is a waek point of security because many users do not
# understand how to know whether a command is trusted and who they are trusting.
#
# Commands ran from the system folders on a production serve in a domain are trusted commands in the
# domain. Production servers in a domain must ensure that only domain admins with command installation
# priviledge can add commands to the host's system folders. Typically this includes having a domain
# package repository that has a secure SDLC that gaurds entry into the repository and then ensuring
# that the host only installs packages from that source and that the host has only approved folders
# in its system path.
#
# Each user on a production host is responsible for knowing if they are running a trusted command or
# not. They have to do somthing special to run a command from somewhere other than a system folder.
#    * (run an untrusted cmd): prefix a command with a non-system path (like ./myCommand ... )
#    * (run an untrusted cmd): add a non-system folder to its PATH ENV var.
#
# A common source of untrusted commands are those cloned from git projects where a wider set of people can
# commit changes.
#
function askForPassword() { cuiPromptForPassword "$@"; }
function promptForPassword() { cuiPromptForPassword "$@"; }
function cuiPromptForPassword()
{
	local confirm
	while [[ "$1" =~ ^- ]]; do case $1 in
		-c) confirm="-c" ;;
	esac; shift; done
	local prompt=$1
	local passwordVar=$2; assertNotEmpty passwordVar

	cuiHasControllingTerminal || assertError "can not interact with the User because there is no controlling terminal"

	bgtrap 'stty echo; assertError "password prompt canceled by user"' SIGINT

	local done
	while [ ! "$done" ]; do
		# 'stty -echo' is POSIX but 'read -s' (which does the same thing) is BASH specific
		# bash reset stty settings so we dont have catch cntr-c to undo it
		stty -echo
		read -p "$prompt" pw1; echo
		[ "$confirm" ] && read -p "Repeat Password: " pw2; echo
		stty echo

		if [ ! "$confirm" ] || [ "$pw1" == "$pw2" ]; then
			done="1"
		else
			echo "error: entered passwords do not match. try again from first password. cntr-c to abort"
		fi
	done </dev/tty >/dev/tty

	bgtrap -r 'stty echo; assertError "password prompt canceled by user"' SIGINT

	varOutput -R "$passwordVar" "$pw1"
}



# usage: someCmd | wrapLines [-w <wrapWidth>] [-t] <lineIndentString> <wrappedLineIndentString>
# This filter wraps lines in a human friendly way that makes the output easier to read. Its meant to make
# it more clear which lines are logically together to form one long line of output and where each new logical
# output line starts. A plus sign (+) is added to the end of each continued line so that the last character in
# window will be + for any line that is continued
# Params:
#    <lineIndentString>        : this str will be prepended to all original output lines.
#    <wrappedLineIndentString> : this str will be prepended to any continued line
#        when an original input line is too long, the remainder is written to the next screen line and
#        this str will be prepended instead of lineIndent to indicate that this is part of the previous line
#        This continues until the last line fits.
# Options:
#    -w <wrapWidth> : defaults to the current width of the terminal. If its negative, that value is
#                     subtracted from the current width of the terminal (like a negative indent)
#    -t             : truncate instead of wrap. only the first line is output. continued lines are suppressed.
#    -s <startCol>  : instruct that the first line was started at this column that is wraps at the right place
#
# Example:
#   cat errorOut |  wrapLines "error: " "    + "
#   output
#     error: this is a really long error output description that is lon+
#         + ger than the terminal window width
function wrapLines()
{
	local cols truncMode startCol
	while [ $# -gt 0 ]; do case $1 in
		-t) truncMode="1" ;;
		-w*)  bgOptionGetOpt val: cols "$@" && shift ;;
		-s*)  bgOptionGetOpt val: startCol "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local indentFirst="${1}"
	local indentContt="${2:-   +}"
	local tabExpansion="   " #TODO: query the terminal to get the actual current value.

	if [ ! "$cols" ] || [[ "$cols" =~ ^- ]]; then
		# the default for tput is to return 80 cols if there is no terminal but we change that to 1000 so it does not
		# wrap when piping to a file.
		local windowWidth=$(( [ -t 1 ] || [ -t 2 ] ) && tput cols || echo 1000)
		cols=$(( windowWidth + cols ))
	fi

	[ $cols -le $(( ${#indentFirst} -3 )) ] && indentFirst=${indentFirst:0:$(( cols -3 ))}
	[ $cols -le $(( ${#indentContt} -3 )) ] && indentContt=${indentContt:0:$(( cols -3 ))}
	local firstWrapCount=$(( cols - ${#indentFirst} -2 -${startCol:-0} ))
	local wrapCountContt=$(( cols - ${#indentContt} -2 ))
	if [ "$truncMode" ]; then
		sed -e '
			s/[\t]/'"$tabExpansion"'/g;
			s/^.*/'"$indentFirst"'&/;
			s/^\(.\{'"$firstWrapCount"'\}\).*$/\1 +/g;
		'  <&0
	else
		sed -e '
			s/[\t]/'"$tabExpansion"'/g;
			s/^.*/|SOL|'"$indentFirst"'&/;
			s/|SOL|\('"$indentFirst"'.\{'"$firstWrapCount"'\}\)/\1 +\n|CON|'"$indentContt"'/g;
			:lather
			s/|CON|\('"$indentContt"'.\{'"$wrapCountContt"'\}\)/\1 +\n|CON|'"$indentContt"'/g;
			t lather
			s/|\(\(SOL\)\|\(CON\)\)|//
		'  <&0
	fi
}


#moved function isShellFromSSH()        to bg_coreCuiUserApps.sh
#moved function isGUIViable()           to bg_coreCuiUserApps.sh
#moved function wheresTheUserAt()       to bg_coreCuiUserApps.sh
#moved function __testAndReturnApp() {  to bg_coreCuiUserApps.sh
#moved function getUserCmpApp()         to bg_coreCuiUserApps.sh
#moved function getUserTerminalApp()    to bg_coreCuiUserApps.sh
#moved function getUserFileManagerApp() to bg_coreCuiUserApps.sh
#moved function getUserEditor()         to bg_coreCuiUserApps.sh
#moved function getUserPager()          to bg_coreCuiUserApps.sh
#moved function getUserBrowser()        to bg_coreCuiUserApps.sh
#moved function notifyUser()            to bg_coreCuiUserApps.sh
#moved function confirm()               to bg_coreCuiUserApps.sh



# usage: winCreate [--borders] [--defaultFont=<csiString>] <bufVar> <x1> <y1> <x2> <y2>
function winCreate()
{
	local bordersFlag defaultFont
	while [ $# -gt 0 ]; do case $1 in
		--borders)  bordersFlag="--borders" ;;
		--defaultFont*)  bgOptionGetOpt val: defaultFont "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local -n _wcWin="$1"
	[ "$bordersFlag" ] && _wcWin[bordersFlag]="$bordersFlag"
	_wcWin[x1]="$2"
	_wcWin[y1]="$3"
	_wcWin[x2]="$4"
	_wcWin[y2]="$5"
	_wcWin[width]=$((  _wcWin[x2] - _wcWin[x1] +1 ))
	_wcWin[height]=$(( _wcWin[y2] - _wcWin[y1] +1 ))
	_wcWin[curX]=1
	_wcWin[curY]=1
	[ "$defaultFont" ] && _wcWin[defaultFont]="$defaultFont"
}

# usage: winWriteLine <bufVar> <line>
function winWriteLine() {
	winWrite --linefeed "$@"
}

# usage: winWrite <bufVar> <line>
function winWrite() {
	local linefeedFlag
	while [ $# -gt 0 ]; do case $1 in
		--linefeed) linefeedFlag="--linefeed" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local -n _wcWin="$1"; shift
	local line; printf -v line -- "$@"

	local -a lines; splitString -d $'\n' -a lines "$line"

	local firstLine="1"
	for line in "${lines[@]}"; do
		if [ ! "$firstLine" ]; then
			_wcWin[curX]=1
			((_wcWin[curY]++))
		fi
		firstLine=""

		local lineLen tmpStr=""
		csiStrlen -R lineLen "$line"
		if (( (_wcWin[curX]-1+lineLen >= 0) && (_wcWin[curX]-1 <= _wcWin[width]) && (_wcWin[curY] >= 1) || (_wcWin[curY] <= _wcWin[height]) )); then
			csiSubstr -d "" --chopCSI    -R tmpStr -- "${_wcWin[lines${_wcWin[curY]}]}" "0"                                               "$((_wcWin[curX]-1))"
			csiSubstr -d "" --chopCSI -a -R tmpStr -- "$line"                           "$((((_wcWin[curX]-1)<0)?(-(_wcWin[curX]-1)):0))"
			csiSubstr -d "" --chopCSI -a -R tmpStr -- "${_wcWin[lines${_wcWin[curY]}]}" "$((_wcWin[curX]-1+lineLen))"
			csiRender tmpStr
			_wcWin[lines${_wcWin[curY]}]="${tmpStr}"
			((_wcWin[curX]+=lineLen))
		fi
	done
	if [ "$linefeedFlag" ]; then
		_wcWin[curX]=1
		((_wcWin[curY]++))
	fi
}

# usage: winWriteAt <bufVar> <cx> <cy> <line>
function winWriteAt() {
	local -n _wcWin="$1"; shift
	local cx="${1:-1}"; shift;   [[ "$cx" =~ ^[0-9+-]*$ ]] || assertError
	local cy="${1:-1}"; shift;   [[ "$cy" =~ ^[0-9+-]*$ ]] || assertError
	local line; printf -v line -- "$@"

	local -a lines; splitString -d $'\n' -a lines "$line"

	local firstLine="1"
	for line in "${lines[@]}"; do
		if [ ! "$firstLine" ]; then
			((_wcWin[curX]=cx))
			((_wcWin[curY]++))
		fi
		firstLine=""

		#------Hello World
		#65432101234567890
		#   s   e           cx=-2  e=1
		#   #### len=4
		#   abcd
		#   ---dello World = out
		local lineLen tmpStr=""
		csiStrlen -R lineLen "$line"
		if (( (cx-1+lineLen >= 0) && (cx-1 <= _wcWin[width]) && (cy >= 1) || (cy <= _wcWin[height]) )); then
			csiSubstr -d "" --chopCSI    -R tmpStr -- "${_wcWin[lines${cy}]}" "0"                          "$((cx-1))"
			csiSubstr -d "" --chopCSI -a -R tmpStr -- "$line"                 "$((((cx-1)<0)?(-(cx-1)):0))"
			csiSubstr -d "" --chopCSI -a -R tmpStr -- "${_wcWin[lines${cy}]}" "$((cx-1+lineLen))"
			csiRender tmpStr
			_wcWin[lines${cy}]="${tmpStr}"
			((_wcWin[curX]+=lineLen))
		fi
	done
	if [ "$linefeedFlag" ]; then
		_wcWin[curX]=cx
		((_wcWin[curY]++))
	fi
}

# usage: winPaint <bufVar>
function winPaint() {
	# TODO: The paintScript is composed with rendered \033 bytes b/c we 'printf "%s" "$paintScript"' at the end. Why did I do that
	#       instead of just doing 'printf "$paintScript"'? When I have time I will try it. The bg_debugger_integrated.sh uses this.
	local -n _wcWin="$1"
	local paintScript; printf -v paintScript "${CSI}${cSave}"
	local renderedCsiNorm; printf -v renderedCsiNorm "%s" "${csiNorm}"
	local i tmpStr
	for ((i=1; i<=_wcWin[height]; i++)); do
		local line="${_wcWin[lines${i}]}"
		local additionalFontAttributes="${_wcWin[defaultFont]}"
		if [ "${_wcWin[bordersFlag]}" ]; then
			if (( i == 1 && i == _wcWin[height] )); then
				additionalFontAttributes+="${csiOverline}${csiUnderline}"
			elif (( i == 1 )); then
				additionalFontAttributes+="${csiOverline}${csiNoUnderline}"
			elif (( i == _wcWin[height] )); then
				additionalFontAttributes+="${csiUnderline}${csiNoOverline}"
			else
				additionalFontAttributes+="${csiNoOverline}${csiNoUnderline}"
			fi
		fi
		printf -v additionalFontAttributes "%s" "$additionalFontAttributes"
		[ "$additionalFontAttributes" ] && line="${additionalFontAttributes}${line//"${renderedCsiNorm}"/${renderedCsiNorm}${additionalFontAttributes}}"

		local tmpStr; csiSubstr -R tmpStr --pad -- "$line" "0" "${_wcWin[width]}"
		csiRender tmpStr
		printf -v paintScript "%s${CSI}$((_wcWin[y1]+i-1));${_wcWin[x1]}${cMoveAbs}%s" "$paintScript" "$tmpStr"
	done
	printf -v paintScript "%s${csiNoOverline}${csiNoUnderline}${CSI}${cRestore}" "$paintScript"
	printf "%s" "$paintScript" || assertError
}

# usage: winClear <bufVar>
function winClear() {
	local -n _wcWin="$1"
	for ((i=1; i<=_wcWin[height]; i++)); do
		_wcWin[lines${i}]=""
	done
	_wcWin[curX]=1
	_wcWin[curY]=1
}

function winScrollOn() {
	local -n _wcWin="$1"
	[ ! "${_wcWin[xMax]}" ] && cuiGetScreenDimension _wcWin[yMax] _wcWin[xMax]
	(( _wcWin[x1]==1 && _wcWin[x2]==_wcWin[xMax] )) || assertError -v _wcWin "scroll region only works on windows that span the entire width of the terminal"
	cuiSetScrollRegion "${_wcWin[y1]}" "${_wcWin[y2]}"
	cuiMoveTo "${_wcWin[y1]}" 1
}

function winScrollOff() {
	cuiResetScrollRegion
}

# usage: csiSplitOnCSI <string> [<retArray>]
# splits apart the input <string> into alternating text and CSI escape sequences. Even elements returned ([0], [2], ...) are
# guaranteed to be text and odd elements are guaranteed to be CSI escape sequences. Text elements can be "" (empty string) whenever
# a CSI sequences is not preceeded by text such as when a CSI sequence appears first in the <string> or when multiple CSI sequences
# appear next to each other.
#
# Ascii vs Binary Escape:
# This function will recognize an ESC character either as the 4 characters "\033" or "\x1b" or "\x1B" or as the single binary,
# unprintable character $'\033'. The CSI sequences returned are always strings using the 4 character "\033" representation.
#
# In bash, "\033" is a 4 character string that respresents (to things that understand it), that those 4 characters should be replaced
# by a single character with the unprintable value of octal 033. $'\033' on the other hand is a single character string with that
# unprintable character.
#
# In bash, you almost always want to use strings with the 4 character description of the ESC character and not a string that actually
# contains the ESC character. Otherwise, every time you reference that string, it might process the escape sequence and change the
# string contents when you dont want to. Unlike other characters escaped by '\' (like \" or \\) bash will not remove the '\' when
# it appears before \0 or \x which makes it stable to pass these strings around without having to know how many times the '\' needs
# to be esascaped itself.
#
# We put CSI escape sequences in strings so that eventually when we pass the string to printf or echo -e, the escape character
# strings will be recognized and converted and then when that data gets to the terminal, the sequence will be acted on. Note that
# printf will only convert "\033" to $'\033' when it appears in the format string, not in a data argument.
#
function csiSplitOnCSI() {
	while [ $# -gt 0 ]; do case $1 in
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _string="$1"; shift
	local retArray="$1"; shift
	local retOpts=(--echo -1); [ "$retArray" ] && retOpts=(-a --retArray "$retArray")
	# empty the retArray since below we call it multiple times with the --append flag
	[ "$retArray" ] && outputValue --retArray "$retArray" --
	local rematch

	# for the regex test, we convert all the string representations of ESC to the actual, binary character because regex can only
	# stop the string of text on whether a single character matches or not. If we stopped on the '\' character, there would be false
	# positives when '\' the 3 characters following it are not '033'. Also, since there are several different ways to represent ESC,
	# this normalizes them so the algorithm does not have to deal with them all.
	# 2022-03 bobg: the three lines that convert \033 and \x1b text to binary and binary back to \033 were commented out. I dont
	#               remember why. The unit tests were failing so I uncommented them. We will see if there was a reason.
	_string="${_string//\\033/$'\033'}"
	_string="${_string//\\x1[bB]/$'\033'}"

	# Hello\033[34m World
	# '---''------''----'
	#                         .-Hello-----..---\033[-..--34--.?.----------------------.?.--------m---------. . World.
	while [[ "${_string}" =~ ^([^$'\033']*)($'\033'\[([0-9;]*)?([\ !\"#$%&\'()*+,./-]*)?[]@A-Z\^_\`a-z{|}~[])(.*)$ ]]; do
		#                     '-----1-----''---------------------------2------------------------------------''-5-'
		#                                            '---3---' '---------4------------'
		rematch=("${BASH_REMATCH[@]}")
		# rematch[1]=<asciiTextOrEmpty>
		# rematch[2]=<escapeSeq>
		# rematch[<last>]=<remainderToParse>
		rematch[2]="${rematch[2]//$'\033'/\\033}"
		outputValue "${retOpts[@]}" -- "${rematch[1]}" "${rematch[2]}"
		_string="${rematch[@]: -1}" #"
	done
	[ "$_string" ] && outputValue "${retOpts[@]}" -- "$_string" #"
	true
}

# usage: csiStrlen [-R <retVar>] <line>
# returns the length of <line> taking into account that <line> may contain CSI sequences that will not contribute to the length
# when printed to a terminal but do contribute to length(<line>)
function csiStrlen() {
	local retVar
	while [ $# -gt 0 ]; do case $1 in
		-R*)  bgOptionGetOpt val: retVar "$@" && shift ;;
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local line="$*"
	local outLen=0
	local parts; csiSplitOnCSI -- "$line" parts
	local i; for ((i=0; i<${#parts[@]}; i+=2)); do
		((outLen += ${#parts[i]} ))
	done
	returnValue "$outLen" "$retVar"
}

# usage: csiSubstr [--pad] [-a] [--R=<retVar>] <string> <start> <len>
# This is similar to the stdlib substr() function and bashes ${<string>:<start>:<len>} syntax with three differences.
#     1) if <string> contains CSI escape sequences they will ..
#          a) be ignored in calculating the <start> and <len> indexes into the string to return
#          b) all be copied to the output string. They will be in their original position if they are contained in the output string
#             or prepended or appended. If more than one is prepended/appended, they will retain their original order. CSI sequences
#             change the state of the terminal so they must all be preserved so that the state for each character in the string and
#             in the end will be the same as if the string was not shortened.
#     2) if <start> is negative, it does not wrap around to the end of the <string> but instead implements the virtual window behavior.
#     3) if the --pad option is specified, the output string will always be exactly <len> characters long, padding the front and
#        back of <string> as required.
#
# Virtual Window:
# The effect of the the <start> and --pad behavior is that the returned string is consistent with <start> and <len> describing a
# window on a virtual infinite string where the 0 index coresponds to the first character in <string>. Before and after <string>
# are virtual spaces. If the window contains a portion with virtual spaces, they will be included in the output string if --pad
# is specified but not otherwise.
#
# Output:
# If --pad is not specified, the output string will be what ever portion of <string> intersects the virtual window. If --pad is
# specified, the output will correspond extactly to the virtual window which may or may not include all or part of <string> with
# virtual spaces in the window before and after <string becoming actual spaces in the output.
#
# If --retVar=<retVar> is specified, the output string is assigned to the variable <retVar>. Otherwise it is written to stdout
#
# Params:
#    <string>  : the input string. May contain CSI sequences (like s="hello ${csiBlue}World")
#    <start>   : the numeric index into <string> that starts the return window. Only non-CSI characters are considered to occupy
#                positions. CSI sequences are considered invisible to determining the index position. Negative values refer to
#                positions filled with virtual spaces before the start of <string>. Values greater than or equal to the length of
#                <string> refer to positions filled with virtual spaces after the end of <string>
#    <len>     : The size of the window that describes the output string. <start> + <len> -1 is the virtual index position of the
#                of the last character that will be a part of the output string.
# Options:
#    --pad     : specifies that that the output string should be exactly <len> long. If <start> is nagative, spaces will be added
#                to the beginning of the output string up to the start of the <string> or the end of the virtual window. If <start>
#                + <len> is greater than the length of <string> spaces wil lbe added to the end of the output string.
#    -R|--retVar=<retVar> : <retVar> is a variable name that will receive the output string instead of it being written to stdout.
#    -a        : append flag. If <retVar> is specified the output string will be appended to the end of the value already in <retVar>
#                If <retVar> is not specified, -a has no affect.
# See Also:
#    man(3) csiSplitOnCSI
#    man(3) csiStrlen
#    man(3) csiSubstr
#    man(3) csiStrip
function csiSubstr() {
	local retOpts padFlag chopCSIFlag
	while [ $# -gt 0 ]; do case $1 in
		--) shift; break ;;
		--pad) padFlag="--pad" ;;
		--chopCSI) chopCSIFlag="--chopCSI" ;;
		*)  bgOptions_DoOutputVarOpts retOpts "$@" && shift ;;&
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _cssLine="$1";         shift
	local _cssStart="$1";        shift
	local _cssLen="${1:-10000}"; shift

	local _cssEnd=$((_cssStart+_cssLen))

	#      Hello World
	#65432101234567890
	#   s   e           s=-3  e=1
	#   ---- len=4
	#   ###H = out

	local _cssOut _cssOutLen=0 _cssRmLen=0 _cssCpLen=0
	if ((_cssStart<0)); then
		_cssOutLen=$(( ((-_cssStart) < _cssLen) ? (-_cssStart) : _cssLen ))
		_cssStart=0
		[ "$padFlag" ] && printf -v _cssOut "%*s" "$_cssOutLen"  "" #"
	fi
	local _cssParts; csiSplitOnCSI -- "$_cssLine" _cssParts
	local i; for ((i=0; i<${#_cssParts[@]}; i+=2)); do
		if ((_cssStart>0)); then
			_cssRmLen=$(( ((_cssStart) < ${#_cssParts[i]}) ?  (_cssStart) : ${#_cssParts[i]} ))
			_cssParts[i]="${_cssParts[i]:_cssRmLen}"
			((_cssStart-=_cssRmLen))
		fi

		if ((_cssStart==0 && _cssOutLen<_cssLen)); then
			_cssCpLen=$(( ((_cssLen-_cssOutLen) < ${#_cssParts[i]}) ? (_cssLen-_cssOutLen) : ${#_cssParts[i]} ))
			_cssOut+="${_cssParts[i]:0:_cssCpLen}"
			((_cssOutLen+=_cssCpLen))
		fi

		# cp _CSI term without inc outLen
		if [ ! "$chopCSIFlag" ] || ((  _cssOutLen < _cssLen )); then
			_cssOut+="${_cssParts[i+1]}"
		fi
	done

	[ "$padFlag" ] && printf -v _cssOut "%s%*s" "$_cssOut"  $((_cssLen-_cssOutLen)) ""
	outputValue "${retOpts[@]}" -- "$_cssOut" #"
}

# usage: csiStrip <lineVar>
# returns <line> with any CSI escape sequences removed.
function csiStrip() {
	local retVar
	while [ $# -gt 0 ]; do case $1 in
		-R*)  bgOptionGetOpt val: retVar "$@" && shift ;;
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	if [ $# -gt 0 ]; then
		local line="$*"
	else
		local line="${!retVar}"
	fi
	local  _csOut
	local parts; csiSplitOnCSI -- "$line" parts
	local i; for ((i=0; i<${#parts[@]}; i+=2)); do
		_csOut+="${parts[i]}"
	done
	returnValue "$_csOut" "$retVar"
}



# usage: csiRender <lineVar>
# changes \033 and \x1b into $'\033' so that the csi codes will work even in the data of a printf
function csiRender() {
	local -n lineVar="$1"
	lineVar="${lineVar//\\033/$'\033'}"
	lineVar="${lineVar//\\x1[bB]/$'\033'}"
}






# OBSOLETE: replaced by win* functions
function _printfAtInit()
{
	if [ ! "${_printfAt_xColMin+exists}" ]; then
		declare -g _printfAt_xColMin="1"
		declare -g _printfAt_yLineMin="1"
		declare -g _printfAt_xColMax="10000"
		declare -g _printfAt_yLineMax="10000"

		declare -g _printfAt_xColMinVP="1"
		declare -g _printfAt_yLineMinVP="1"
		declare -g _printfAt_xColMaxVP="10000"
		declare -g _printfAt_yLineMaxVP="10000"

		declare -g _printfAt_xColStart="1"
		declare -g _printfAt_yLineStart="1"
	fi
}

# usage: printfAt <xCol> <yLine> [--eol] [--sol] <fmtStr> ...
# This can be used like bash's printf (without the -v option) but it accepts for optional parameters
# in any order.
# There are a family of printfAt_* functions that can be used to influence how printfAt works.
# Features:
#    * buffer output by enclosing it in printfAt_startBufferedOutput / printfAt_endBufferedOutput
#    * limit output to within a virtual view port with printfAt_setViewport
#    * scroll output within a virtual view port with printfAt_scrollViewport[To]
# Options:
#    These options are unusual because <xCol> and <yLine> do not begin with - The first two numeric params
#    that appear before a param that can not be an options will be taken as xCol and yLine
#    <xCol>  : the column postion to start out at. The first numeric param is taken as xCol
#              1 is the first column on the left
#    <yLine> : the line postion to start out at. The second numeric param is taken as yLine
#              1 is the first line on the top.
#    --eol   : clear to the end of the line after writing the output.
#    --sol   : clear from the start of the line to xCol before writing the output.
#    --      : end of options. the rest of the cmd line will not be checked to see if they match options
# See Also:
#    printfAt_*
function termPrintfAt() { printfAt "$@"; }
function printfAt()
{
	if [ "${_printf_buf_xmin+exits}" ] && [ ! "${_printf_flushing+exists}" ]; then
		printfAt_buffered "$@"
		return
	fi

	_printfAtInit
	local xCol yLine clearToEOL clearToSOL cCnt=0
	while [[ "$1" =~ (^-)|(^[0-9][0-9]*$) ]]; do case $1:$cCnt in
		--eol*)  clearToEOL="${CSI}$cClrToEOL" ;;
		--sol*)  clearToSOL="${CSI}$cClrToSOL" ;;
		[0-9]*:0) xCol="$1";  ((cCnt++)) ;;
		[0-9]*:1) yLine="$1"; ((cCnt++)) ;;
		[0-9]*:*) break ;;
		--:*) shift; break ;;
		*) break ;;
	esac; shift; done

	local fmtStr="$1"; [ $# -gt 0 ] && shift

	# this can be turned on to debug page formatting issues
	local DBGFmt DBGContent
	if false; then
		DBGFmt="%2s "
		DBGContent="$yLine"
	fi

	local locationTerm=""
	if [ "$xCol$yLine" ]; then

		# adjust for the current viewport
		local xColGlb="$(( ${xCol:-1} + ${_printfAt_xColMin:-1} - 1 ))"
		local yLineGlb="$(( ${yLine:-1} + ${_printfAt_yLineMin:-1} - ${_printfAt_yLineStart:-1} ))"

		# if the line is beyond the the clipping win, the whole output is clipped
		[ ${yLineGlb} -lt ${_printfAt_yLineMin:-1} ] && return 0
		[ ${yLineGlb} -gt ${_printfAt_yLineMax:-10000} ] && return 0

		# to scroll and clip horizontally, we need to get the final formated string and then extract the
		# substring that falls within the viewport. The challenge is that the string can contain control
		# codes that do not ocupy a column cell so we need to parse the control codes and keep track of
		# the content position
		local xStrStart=$(( ${_printfAt_xColStart:-1} - 1 ))
		local xStrEnd=$(( ${_printfAt_xColStart:-1} + ( ${_printfAt_xColMax:-10000} - ${_printfAt_xColMin:-1} + 1 ) - 1 ))
		# TODO: this is commented out b/c we are not yet handling the xcol extents completely
		#if [ ${_printfAt_xColStart:-1} -ne 1 ] || [ ${_printfAt_xColMax:-10000} -lt 10000 ]; then
		if [ ${_printfAt_xColStart:-1} -ne 1 ]; then
			local totalStr; printf -v totalStr -- "$fmtStr" "$@"

			local char i="0" vi=0 outStr=""
			while [ $i -lt ${#totalStr} ]; do
				char="${totalStr:$i:1}"
				case $char in
					[\])
						if [ "${totalStr:$i:5}" == "\033[" ]; then
							outStr+="\033["; ((i+=5))
							while [  $i -lt ${#totalStr}  ] && [[ "$char" =~ [0-9\;] ]]; do
								outStr+="$char"; ((i++))
							done
							outStr+="$char"; ((i++))
						else
							[ ${vi:-0} -ge ${xStrStart:-0} ] && [ ${vi:-0} -le ${xStrEnd:-0} ] && outStr+="$char"
							((i++)); ((vi++))
						fi
						;;
					$'\033')
						outStr+="$char"; ((i++))
						char="${totalStr:$i:1}"
						case $char in
							# CSI codes. <ESC> <[> N[;N] <code>
							# N can be 1 or more digits
							$'[')
								outStr+="$char"; ((i++))
								while [  $i -lt ${#totalStr}  ] && [[ "${totalStr:$i:1}" =~ [-0-9\;] ]]; do
									outStr+="${totalStr:$i:1}"; ((i++))
								done
								outStr+="${totalStr:$i:1}"; ((i++))
								;;
							*)	outStr+="$char"; ((i++)) ;;
						esac
						;;
					[[:print:]\t])
						[ ${vi:-0} -ge ${xStrStart:-0} ] && [ ${vi:-0} -le ${xStrEnd:-0} ] && outStr+="$char"
						((i++)); ((vi++))
						;;
					*)	outStr+="$char"
						((i++))
						;;
				esac
			done
			printf -- "${CSI}${yLineGlb:-1};${xColGlb:-1}$cMoveAbs${clearToSOL}$outStr${clearToEOL}"
			return
		fi

		locationTerm="${CSI}${yLineGlb:-1};${xColGlb:-1}$cMoveAbs"
	fi

	if [ "$clearToEOL" ] && [[ "$fmtStr" =~ \\n ]]; then
		fmtStr="${fmtStr//\\n/$clearToEOL\\n}"
		clearToEOL=""
	fi
	printf -- "$locationTerm${clearToSOL}${DBGFmt}$fmtStr${clearToEOL}" $DBGContent "$@"
}




function printfAt_buffered()
{
	_printfAtInit
	local xCol="--" yLine="--" clearToEOL="--" clearToSOL="--" cCnt=0
	while [[ "$1" =~ (^-)|(^[0-9][0-9]*$) ]]; do case $1:$cCnt in
		--eol*)  clearToEOL="--eol" ;;
		--sol*)  clearToSOL="--sol" ;;
		[0-9]*:0) xCol="$1";  ((cCnt++)) ;;
		[0-9]*:1) yLine="$1"; ((cCnt++)) ;;
		[0-9]*:*) break ;;
		--:*) shift; break ;;
	esac; shift; done

	local fmtStr="$1"; [ $# -gt 0 ] && shift
	local lineBuffer; printf -v lineBuffer -- "$fmtStr" "$@"

	[ "$xCol" != "--" ]  && _printf_buf_xmin=$(( (xCol < _printf_buf_xmin) ? xCol : _printf_buf_xmin ))
	[ "$yLine" != "--" ] && _printf_buf_ymin=$(( (yLine < _printf_buf_ymin) ? yLine : _printf_buf_ymin ))
	[ "$xCol" != "--" ]  && _printf_buf_xmax=$(( (xCol > _printf_buf_xmax) ? xCol : _printf_buf_xmax ))
	[ "$yLine" != "--" ] && _printf_buf_ymax=$(( (yLine > _printf_buf_ymax) ? yLine : _printf_buf_ymax ))

	_printf_bufCalls+=("$xCol $yLine $clearToEOL $clearToSOL _$lineBuffer")
}

# usage: printfAt_getBufferedExtents <xColMinVar> <yLineMinVar> <xColMaxVar> <yLineMaxVar>
# before calling printfAt_endBufferedOutput, this can be called to find out the extents that the
# buffered output has written to. This is useful to adust the viewport before the output is written
function printfAt_getBufferedExtents()
{
	local xminValue="$(( (_printf_buf_xmin == 10000) ? 1 : _printf_buf_xmin ))"
	local yminValue="$(( (_printf_buf_ymin == 10000) ? 1 : _printf_buf_ymin ))"
	local xmaxValue="$(( (_printf_buf_xmax == -10000) ? 10000 : _printf_buf_xmax ))"
	local ymaxValue="$(( (_printf_buf_ymax == -10000) ? 10000 : _printf_buf_ymax ))"

	setReturnValue "$1" "$xminValue"
	setReturnValue "$2" "$yminValue"
	setReturnValue "$3" "$xmaxValue"
	setReturnValue "$4" "$ymaxValue"
}

# usage: printfAt_startBufferedOutput
# start buffing any calls made to printfAt. When printfAt_endBufferedOutput is later called, any
# printfAt output that was buffered will be written to the terminal. This buffer maintains the extends
# that the output is written to so that before printfAt_endBufferedOutput is called you can adjust
# the viewport.
function printfAt_startBufferedOutput()
{
	declare -g  _printf_bufCalls=()
	declare -g  _printf_buf_xmin=10000
	declare -g  _printf_buf_ymin=10000
	declare -g  _printf_buf_xmax=-10000
	declare -g  _printf_buf_ymax=-10000
}

# usage: printfAt_endBufferedOutput
# see printfAt_startBufferedOutput
function printfAt_endBufferedOutput()
{
	local _printf_flushing="1"
	local i xCol yLine clearToEOL clearToSOL outStr
	for (( i = 0; i < ${#_printf_bufCalls[@]}; i++ )); do
		read -r xCol yLine clearToEOL clearToSOL outStr <<<"${_printf_bufCalls[$i]}"
		[ "$clearToEOL" == "--" ] && clearToEOL="" || clearToEOL="--eol"
		[ "$clearToSOL" == "--" ] && clearToSOL="" || clearToSOL="--sol"
		[ "$xCol" == "--" ] && xCol=""
		[ "$yLine" == "--" ] && yLine=""

		printfAt $xCol $yLine $clearToEOL $clearToSOL -- "${outStr#_}"
	done

	local xColMinVP yLineMinVP xColMaxVP yLineMaxVP
	printfAt_getBufferedExtents xColMinVP yLineMinVP xColMaxVP yLineMaxVP
	for (( yLine = $((yLineMaxVP+1)); yLine < $((_printfAt_yLineMax-_printfAt_yLineMin +1 +_printfAt_yLineStart)); yLine++ )) do
		printfAt 1 $yLine --eol -- ""
	done

	unset _printf_bufCalls
	unset _printf_buf_xmin
	unset _printf_buf_ymin
	unset _printf_buf_xmax
	unset _printf_buf_ymax
}









# usage: printfAt_setViewport <xColMinTerm> <yLineMinTerm> <xColMaxTerm> <yLineMaxTerm> <xColMinVP> <yLineMinVP> <xColMaxVP> <yLineMaxVP>
# Set a clipping window that printfAt will observe
# Params:
#    <xColMinTerm> <yLineMinTerm> <xColMaxTerm> <yLineMaxTerm> : coordinates of the window in
#           terminal global cordinates relative to top left corner (1,1)
#    <xColMinVP> <yLineMinVP> <xColMaxVP> <yLineMaxVP> : the logical VP (viewport) coordinates of
#           the window. These are the extends of the logical view that is painted. When the VP extents
#           are larger than the Term (physical terminal) window extents the content can be scrolled
function printfAt_setViewport()
{
	_printfAtInit
	[ "$1" ] && _printfAt_xColMin="$1"
	[ "$2" ] && _printfAt_yLineMin="$2"
	[ "$3" ] && _printfAt_xColMax="$3"
	[ "$4" ] && _printfAt_yLineMax="$4"

	[ "$5" ] && _printfAt_xColMinVP="$5"
	[ "$6" ] && _printfAt_yLineMinVP="$6"
	[ "$7" ] && _printfAt_xColMaxVP="$7"
	[ "$8" ] && _printfAt_yLineMaxVP="$8"
}

# usage: printfAt_scrollViewportTo <xColStart> <yLineStart>
# Set the top left VP coordinates to these values
function printfAt_scrollViewportTo()
{
	_printfAtInit
	_printfAt_xColStart="${1:-1}"
	_printfAt_yLineStart="${2:-1}"
}

# usage: printfAt_scrollViewport <xColDelta> <yLineDelta>
# Set a clipping window that printfAt will observe
function printfAt_scrollViewport()
{
	_printfAtInit

	local xColDelta="${1:-0}"
	local yLineDelta="${2:-0}"

	local xColStartSaved="$_printfAt_xColStart"
	local yLineStartSaved="$_printfAt_yLineStart"

	_printfAt_xColStart=$(( ${_printfAt_xColStart:-1} + xColDelta))
	_printfAt_yLineStart=$(( ${_printfAt_yLineStart:-1} + yLineDelta))

	_printfAt_xColStart=$(( (_printfAt_xColStart<1) ? 1 : _printfAt_xColStart ))
	_printfAt_yLineStart=$(( (_printfAt_yLineStart<1) ? 1 : _printfAt_yLineStart ))

#	local max_xColStart=$(( (_printfAt_xColMaxVP-_printfAt_xColMinVP) - (_printfAt_xColMax-_printfAt_xColMin) +2 ))
	local max_yLineStart=$(( (_printfAt_yLineMaxVP-_printfAt_yLineMinVP) - (_printfAt_yLineMax-_printfAt_yLineMin) +2 ))

#	_printfAt_xColStart=$(( (_printfAt_xColStart > max_xColStart) ? max_xColStart : _printfAt_xColStart ))
	_printfAt_yLineStart=$(( (_printfAt_yLineStart > max_yLineStart) ? max_yLineStart : _printfAt_yLineStart ))

	[ "$xColStartSaved" != "$_printfAt_xColStart" ] || [ "$yLineStartSaved" != "$_printfAt_yLineStart" ]
}


# usage: printfAt_autoScrollUpdate  <rangeOfInterest_focus> <rangeOfInterest_start> <rangeOfInterest_end>
function printfAt_autoScrollUpdate()
{
	local rangeOfInterest_focus="${1:-0}"
	local rangeOfInterest_start="${2:-0}"
	local rangeOfInterest_end="${3:-0}"

	local visibleStart="$(( _printfAt_yLineStart ))"
	local visibleEnd="$(( _printfAt_yLineStart + (_printfAt_yLineMax-_printfAt_yLineMin)  ))"

	local delta=0
	if 		(( rangeOfInterest_start > 0 && rangeOfInterest_end > 0 \
			&& ( rangeOfInterest_start < visibleStart || rangeOfInterest_end > visibleEnd )  )); then
		local interestSize=$(( rangeOfInterest_end - rangeOfInterest_start +1 ))
		local windowSize=$(( _printfAt_yLineMax - _printfAt_yLineMin + 1 ))

		# the whole interest range fits so make the smallest move to bring it into view
		if (( interestSize <= windowSize )); then
			((
				delta+= (rangeOfInterest_start < visibleStart) \
			 		? rangeOfInterest_start - visibleStart \
					: rangeOfInterest_end - visibleEnd
			))

		# no overlap and too big so move nearest page into view
		elif (( (rangeOfInterest_start > visibleEnd) || (rangeOfInterest_end < visibleStart) )); then
			((
				delta+= (rangeOfInterest_start > visibleEnd) \
					? rangeOfInterest_start - visibleStart \
					: rangeOfInterest_end - visibleEnd
			))
		fi
		((visibleStart+=delta))
		((visibleEnd+=delta))
	fi

	if (( rangeOfInterest_focus > 0 )); then
		if (( rangeOfInterest_focus < visibleStart )); then
			(( delta+=rangeOfInterest_focus - visibleStart ))
		elif (( rangeOfInterest_focus > visibleEnd )); then
			(( delta+=rangeOfInterest_focus - visibleEnd ))
		fi
	fi

	# now scroll it
	printfAt_scrollViewport 0 "$delta"
}

#!/bin/bash


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












# CSI is a notation to refer to ansi escape sequences for terminals
# see http://en.wikipedia.org/wiki/ANSI_escape_code
# see http://invisible-island.net/xterm/ctlseqs/ctlseqs.html
# The advantage of using this CSI escape strings instead of tput is that you can create one
# big printf call that does a lot of stuf and leave the cursor back in the right place. Because it
# all in one API call there is a better chance that it will be atomic. Its best to serialize access
# to the terminal, but since all parties have to cooperate on obtaining the lock, its not always possible

# usage: cuiSetTitle <title>
function cuiSetTitle()
{
	echo -en "\033]0;$1\a"
}

# usage: cuiGetScreenDimension <lineCountVar> <columnCountVar> [< <tty>]
# returns the hieght in lines and width in characters of the tty connected to stdin
# If stdin is not a tty, returns 1 and sets the values to -1
function CSIgetScreenDimension() { cuiGetScreenDimension "$@"; }
function cuiGetTerminalDimension() { cuiGetScreenDimension "$@"; }
function cuiGetScreenDimension()
{
	if [ -t 0 ]; then
		# clear any pending data waiting to be read on the tty
#		local scrapVar; while read -t 0 < "$tty"; do read -r -n1 scrapVar <"$tty"; done
		local scrapVar; read -r "${1:-scrapVar}" "${2:-scrapVar}" < <(stty size)
		return 0
	else
		setReturnValue "$1" "-1"
		setReturnValue "$2" "-1"
		return 1
	fi
}



# usage: cuiGetCursor <cLineNumVar> <cColumnNumVar> [< <tty>]
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
function CSIgetCursor() { cuiGetCursor "$@"; }
function cuiGetCursor()
{
	local preserveRematch; [ "$1" == "--preserveRematch" ] && { preserveRematch="--preserveRematch"; shift; }
	local _lineValue="-1"
	local _colValue="-1"
	local result="1"
	if [ -t 0 ]; then
		local buf; IFS= read -sr -dR -p $'\e[6n' buf
		#echo "$count: '$buf'" | cat -v >> $_bgtraceFile
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
		result=0
	fi
	setReturnValue "$1" "$_lineValue"
	setReturnValue "$2" "$_colValue"
	return ${result:-0}
}

# usage: cuiSetScrollRegion <lineStartNum> <lineEndNum>
# set the horizontal band of the terminal that will be subject to scrolling.
# Note: When the scroll region is set, if a scroll is trigger by writing a new line at the bottom of the screen,
# it will reset the scroll region to the entire screen.
# Params:
#      <lineStartNum> : is the line number of the first line that will participate in scrolling (0 == top)
#      <lineEndNum>   : is the line number of the last line that will participate in scrolling (use )
function CSIsetScrollRegion() { cuiSetScrollRegion "$@"; }
function cuiSetScrollRegion()
{
	[ -t 1 ] || return 1
	printf "${CSI}${1:-0};${2:-0}$cSetScrollRegion"
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
	echo -en "${CSI}${1:-0};${2:-0}$cMoveAbs"
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
	echo -n "${CSI}${lineDelta}${vCmd}${CSI}${columnDelta}${hCmd}"
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






# OBSOLETE: its easier and faster to just make the sequences like "${CSI}$x;$y;${cMoveAbs}". Now we have cuiRealizeFmtToTerm we do not need this
# usage: printf " ... $(CSI [p1 ...] <cCMD>) ... "
# This function assembles a CSI escape sequence. All CSI escape sequences use a standard format
#      $CSI + <0 or more params apearated by ;> + $<cCode>
# The string that this function produces is a textual ASCII sequence that represent the real binary sequence
# that will effect the terminal. printf automatically decodes the text escape sequence into its binary
# representation. echo does not by default but will if the -e switch is given.
# Examples:
#     echo -en "$(CSI $cSave)"      # saves the current cursor position. uses no params
#     printf "$(CSI 4 $cDOWN)"      # moves the cursor down 4 lines. 1 is the default
#     printf "$(CSI y x $cMoveAbs)" # moves the the absolute (y, x) cursor position
function CSI()
{
	[ -t 1 ] || return 1
	[ "$CSIOff" ] && return
	local params="" sep=""
	while [ $# -gt 1 ]; do
		params="${params}${sep}${1}"
		sep=";"
		shift
	done
	local cmd="$1"

	printf "${CSI}${params}${cmd}"
}


# OBSOLETE: use cuiRealizeFmtToTerm
function cuiRealizeFmtToTermOld()
{
	local declFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		--getVars) declFlag="1" ;;
	esac; shift; done

	if [ "$declFlag" ]; then
		echo '
		CSIOff=
		CSI=

		cHide=					csiHide=
		cShow=					csiShow=
		cSave=					csiSave=
		cRestore=				csiRestore=
		cMoveAbs=
		cUP=					csiUP=
		cDOWN=					csiDOWN=
		cRIGHT=					csiRIGHT=
		cLEFT=					csiLEFT=
		cToCol=
		cToLine=
		cToSOL=					csiToSOL=

		cClrToEOL=				csiClrToEOL=
		cClrToSOL=				csiClrToSOL=
		cClrLine=				csiClrLine=
		cClrBelowCursor=		csiClrBelowCursor=
		cClrAboveCursor=		csiClrAboveCursor=
		cClrSrc=				csiClrSrc=
		cClrSavedLines=			csiClrSavedLines=
		cInsertLines=			csiInsertLines=
		cDeleteLines=			csiDeleteLines=
		cDeleteChars=			csiDeleteChars=

		cSetScrollRegion=
		cScrollUp=				csiScrollUp=
		cScrollDown=			csiScrollDown=

		cSwitchToAltScreen=		csiSwitchToAltScreen=
		cSwitchToNormScreen=	csiSwitchToNormScreen=

		cNorm=					csiNorm=
		cFontReset=				csiFontReset=
		cBold=					csiBold=
		cFaint=					csiFaint=
		cItalic=				csiItalic=
		cUnderline=				csiUnderline=
		cBlink=					csiBlink=
		cReverse=				csiReverse=
		cConceal=				csiConceal=
		cStrikeout=				csiStrikeout=

		cDefColor=				csiDefColor=
		cDefBkColor=			csiDefBkColor=

		cBlack=					csiBlack=
		cRed=					csiRed=
		cGreen=					csiGreen=
		cYellow=				csiYellow=
		cBlue=					csiBlue=
		cMagenta=				csiMagenta=
		cCyan=					csiCyan=
		cWhite=					csiWhite=

		cHiBlack=				csiHiBlack=
		cHiRed=					csiHiRed=
		cHiGreen=				csiHiGreen=
		cHiYellow=				csiHiYellow=
		cHiBlue=				csiHiBlue=
		cHiMagenta=				csiHiMagenta=
		cHiCyan=				csiHiCyan=
		cHiWhite=				csiHiWhite=

		cBkBlack=				csiBkBlack=
		cBkRed=					csiBkRed=
		cBkGreen=				csiBkGreen=
		cBkYellow=				csiBkYellow=
		cBkBlue=				csiBkBlue=
		cBkMagenta=				csiBkMagenta=
		cBkCyan=				csiBkCyan=
		cBkWhite=				csiBkWhite=

		cHiBkBlack=				csiHiBkBlack=
		cHiBkRed=				csiHiBkRed=
		cHiBkGreen=				csiHiBkGreen=
		cHiBkYellow=			csiHiBkYellow=
		cHiBkBlue=				csiHiBkBlue=
		cHiBkMagenta=			csiHiBkMagenta=
		cHiBkCyan=				csiHiBkCyan=
		cHiBkWhite=				csiHiBkWhite=

		csiColorDefault=		CSIColorDefault=		CSIcolorDefault=
		csiColorChanged=		CSIColorChanged=
		csiColorSelected=		CSIColorSelected=
		csiColorHilighted=		CSIColorHilighted=
		csiColorHilightBk=		CSIColorHilightBk=
		csiColorAttention=		CSIColorAttention=
		csiColorStatusLineDef=	CSIColorStatusLineDef=
		csiColorCompleted=		CSIColorCompleted=
		csiColorError=			CSIColorError=
		csiColorH1=				CSIColorH1=
		csiColorH2=				CSIColorH2=
		csiColorH3=				CSIColorH3=
		'
		return
	fi


	local isTerm=""; test -t 1 && isTerm="1"

	if [ "$isTerm" ]; then
		# TODO: detet the actual terminal type of the destination and send customized codes for the
		#       specific terminal. This is not a priority because almost all terminal these commands
		#       will run on will use these generic codes.
		CSIOff=

		CSI="\033["
		OSC="\033]"  # most useful stuf is CSI. Set Window title is an OSC code

		# cursor movement
		cHide="?25l"				csiHide="${CSI}${cHide}"
		cShow="?25h"				csiShow="${CSI}${cShow}"
		cSave="s"					csiSave="${CSI}${cSave}"
		cRestore="u"				csiRestore="${CSI}${cRestore}"
		cMoveAbs="H"				# (requires parameters)
		cUP="A"						csiUP="${CSI}${cUP}"
		cDOWN="B"					csiDOWN="${CSI}${cDOWN}"
		cRIGHT="C"					csiRIGHT="${CSI}${cRIGHT}"
		cLEFT="D"					csiLEFT="${CSI}${cLEFT}"
		cToCol="G"					# (requires parameters)
		cToLine="G"					# (requires parameters)
		cToSOL="G"					csiToSOL="${CSI}${cToSOL}"

		cClrToEOL="K"				csiClrToEOL="${CSI}${cClrToEOL}"
		cClrToSOL="1K"				csiClrToSOL="${CSI}${cClrToSOL}"
		cClrLine="2K"				csiClrLine="${CSI}${cClrLine}"
		cClrBelowCursor="0J"		csiClrBelowCursor="${CSI}${cClrBelowCursor}"
		cClrAboveCursor="1J"		csiClrAboveCursor="${CSI}${cClrAboveCursor}"
		cClrSrc="2J"				csiClrSrc="${CSI}${cClrSrc}"
		cClrSavedLines="3J"			csiClrSavedLines="${CSI}${cClrSavedLines}"
		cInsertLines="L"			csiInsertLines="${CSI}${cInsertLines}"
		cDeleteLines="M"			csiDeleteLines="${CSI}${cDeleteLines}"
		cDeleteChars="P"			csiDeleteChars="${CSI}${cDeleteChars}"

		cSetScrollRegion="r"		# (requires parameters)
		cScrollUp="S"				csiScrollUp="${CSI}${cScrollUp}"
		cScrollDown="T"				csiScrollDown="${CSI}${cScrollDown}"

		cSwitchToAltScreen="?47h"	csiSwitchToAltScreen="${CSI}${cSwitchToAltScreen}"
		cSwitchToNormScreen="?47l"	csiSwitchToNormScreen="${CSI}${cSwitchToNormScreen}"

		# font attributes
		# see http://misc.flogisoft.com/bash/tip_colors_and_formatting
		cNorm="0m"					csiNorm="${CSI}${cNorm}"
		cFontReset="0m"				csiFontReset="${CSI}${cFontReset}"
		cBold="1m"					csiBold="${CSI}${cBold}"
		cFaint="2m"					csiFaint="${CSI}${cFaint}"
		cItalic="3m"				csiItalic="${CSI}${cItalic}"
		cUnderline="4m"				csiUnderline="${CSI}${cUnderline}"
		cBlink="5m"					csiBlink="${CSI}${cBlink}"
		cReverse="7m"				csiReverse="${CSI}${cReverse}"
		cConceal="8m"				csiConceal="${CSI}${cConceal}"
		cStrikeout="9m"				csiStrikeout="${CSI}${cStrikeout}"

		# font colors
		cDefColor="39m"				csiDefColor="${CSI}${cDefColor}"
		cDefBkColor="49m"			csiDefBkColor="${CSI}${cDefBkColor}"

		cBlack="30m"				csiBlack="${CSI}${cBlack}"
		cRed="31m"					csiRed="${CSI}${cRed}"
		cGreen="32m"				csiGreen="${CSI}${cGreen}"
		cYellow="33m"				csiYellow="${CSI}${cYellow}"
		cBlue="34m"					csiBlue="${CSI}${cBlue}"
		cMagenta="35m"				csiMagenta="${CSI}${cMagenta}"
		cCyan="36m"					csiCyan="${CSI}${cCyan}"
		cWhite="37m"				csiWhite="${CSI}${cWhite}"

		cHiBlack="90m"				csiHiBlack="${CSI}${cHiBlack}"
		cHiRed="91m"				csiHiRed="${CSI}${cHiRed}"
		cHiGreen="92m"				csiHiGreen="${CSI}${cHiGreen}"
		cHiYellow="93m"				csiHiYellow="${CSI}${cHiYellow}"
		cHiBlue="94m"				csiHiBlue="${CSI}${cHiBlue}"
		cHiMagenta="95m"			csiHiMagenta="${CSI}${cHiMagenta}"
		cHiCyan="96m"				csiHiCyan="${CSI}${cHiCyan}"
		cHiWhite="97m"				csiHiWhite="${CSI}${cHiWhite}"

		cBkBlack="40m"				csiBkBlack="${CSI}${cBkBlack}"
		cBkRed="41m"				csiBkRed="${CSI}${cBkRed}"
		cBkGreen="42m"				csiBkGreen="${CSI}${cBkGreen}"
		cBkYellow="43m"				csiBkYellow="${CSI}${cBkYellow}"
		cBkBlue="44m"				csiBkBlue="${CSI}${cBkBlue}"
		cBkMagenta="45m"			csiBkMagenta="${CSI}${cBkMagenta}"
		cBkCyan="46m"				csiBkCyan="${CSI}${cBkCyan}"
		cBkWhite="47m"				csiBkWhite="${CSI}${cBkWhite}"

		cHiBkBlack="100m"			csiHiBkBlack="${CSI}${cHiBkBlack}"
		cHiBkRed="101m"				csiHiBkRed="${CSI}${cHiBkRed}"
		cHiBkGreen="102m"			csiHiBkGreen="${CSI}${cHiBkGreen}"
		cHiBkYellow="103m"			csiHiBkYellow="${CSI}${cHiBkYellow}"
		cHiBkBlue="104m"			csiHiBkBlue="${CSI}${cHiBkBlue}"
		cHiBkMagenta="105m"			csiHiBkMagenta="${CSI}${cHiBkMagenta}"
		cHiBkCyan="106m"			csiHiBkCyan="${CSI}${cHiBkCyan}"
		cHiBkWhite="107m"			csiHiBkWhite="${CSI}${cHiBkWhite}"


		# The following are meant to provide a level of indirection for color schema. Commands
		# can use these conceptual color names and then let the user override them.
		# TODO: make a system for declaring color schema sets and deploying them (plugins?)

		# this is one color scheme
		csiColorDefault="${csiDefBkColor}${csiDefColor}${csiNorm}"
		csiColorChanged="${csiHiRed}"
		csiColorSelected="${csiBold}"
		csiColorHilighted="${csiHiYellow}"
		csiColorHilightBk="${csiUnderline}"
		csiColorAttention="${csiWhite}${csiBkRed}"
		csiColorStatusLineDef="${csiDefBkColor}${csiDefColor}${csiNorm}"
		csiColorCompleted="${csiBlack}${csiBkGreen}"
		csiColorError="${csiHiRed}"
		csiColorH1="${csiHiWhite}${csiBkBlue}${csiBold}"
		csiColorH2="${csiBlack}${csiBkBlue}"
		csiColorH3="${csiBold}"

		# this is another color scheme using a RGB color def for a couple of colors
		csiColorDefault="${csiDefBkColor}${csiDefColor}${csiNorm}"
		csiColorChanged="${csiHiRed}"
		csiColorSelected="${csiBold}"
		csiColorHilighted="${csiHiYellow}"
		csiColorHilightBk="${csiUnderline}"
		csiColorAttention="${csiWhite}${csiBkRed}"
		csiColorStatusLineDef="${csiNorm}${CSI}48;2;64;64;64m${CSI}38;2;252;255;255m"
		csiColorCompleted="${csiBlack}${csiBkGreen}"
		csiColorError="${csiHiRed}"
		csiColorH1="${csiBlack}${csiBkBlue}${csiBold}"
		csiColorH2="${csiBlack}${csiBkBlue}"
		csiColorH3="${csiBold}"


		# aliases. we should search and replace these and get rid of them once the other naming is stable
		CSIColorDefault="$csiColorDefault"
		CSIcolorDefault="$csiColorDefault"
		CSIColorChanged="$csiColorChanged"
		CSIColorSelected="$csiColorSelected"
		CSIColorHilighted="$csiColorHilighted"
		CSIColorHilightBk="$csiColorHilightBk"
		CSIColorAttention="$csiColorAttention"
		CSIColorStatusLineDef="$csiColorStatusLineDef"
		CSIColorCompleted="$csiColorCompleted"
		CSIColorError="$csiColorError"
		CSIColorH1="$csiColorH1"
		CSIColorH2="$csiColorH2"
		CSIColorH3="$csiColorH3"
	fi
}

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
	[cToLine]="G"				# <line>
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
	[cDeleteChars]="P"

	# scroll
	[cScrollUp]="S"
	[cScrollDown]="T"

	# pages
	[cSwitchToAltScreen]="?47h"
	[cSwitchToNormScreen]="?47l"

	# font attributes
	# see http://misc.flogisoft.com/bash/tip_colors_and_formatting
	[cNorm]="0m"
	[cFontReset]="0m"
	[cBold]="1m"
	[cFaint]="2m"
	[cItalic]="3m"
	[cUnderline]="4m"
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
# call cuiRealizeFmtToTerm, it can pass in one or more of these array names. cuiRealizeFmtToTerm will
# turn the index names into variable names. The value will be either the empty string when realized to
# non-tty destinations or the value from the array. The values in the array are the default values.
# A mechanism will be added that will create a schema data file from the combined set of index names
# that can be edited with values that can override the default values provided in the script arrays
declare -Ag cuiColorTheme_sample1=(
	[csiColorDefault]="$_CSI${_csiCMD_p0[csiDefBkColor]}$_CSI${_csiCMD_p0[csiDefColor]}$_CSI${_csiCMD_p0[csiNorm]}"
	[csiColorChanged]="$_CSI${_csiCMD_p0[csiHiRed]}"
	[csiColorSelected]="$_CSI${_csiCMD_p0[csiBold]}"
	[csiColorHilighted]="$_CSI${_csiCMD_p0[csiHiYellow]}"
	[csiColorHilightBk]="$_CSI${_csiCMD_p0[csiUnderline]}"
	[csiColorAttention]="$_CSI${_csiCMD_p0[csiWhite]}$_CSI${_csiCMD_p0[csiBkRed]}"
	[csiColorStatusLineDef]="$_CSI${_csiCMD_p0[csiNorm]}${_CSI}48;2;64;64;64m${_CSI}38;2;252;255;255m"
	[csiColorCompleted]="$_CSI${_csiCMD_p0[csiBlack]}$_CSI${_csiCMD_p0[csiBkGreen]}"
	[csiColorError]="$_CSI${_csiCMD_p0[csiHiRed]}"
	[csiColorH1]="$_CSI${_csiCMD_p0[csiBlack]}$_CSI${_csiCMD_p0[csiBkBlue]}$_CSI${_csiCMD_p0[csiBold]}"
	[csiColorH2]="$_CSI${_csiCMD_p0[csiBlack]}$_CSI${_csiCMD_p0[csiBkBlue]}"
	[csiColorH3]="$_CSI${_csiCMD_p0[csiBold]}"
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
#    <text>      : when --readlineFn is specified, the macro will be interpreted as text to insert into
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
	        rowtext=${rowtext}$BG\
	        if [[ $color -lt 100 ]]; then rowtext=${rowtext}$BG\   ;fi
	        if [[ $color -lt 10 ]]; then rowtext=${rowtext}$BG\   ;fi
	        rowtext=${rowtext}$BG${color}
	        rowtext=${rowtext}$BG\
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

# usage: cuiHasControllingTerminal
# returns 0(true) if the command is running under a controlling terminal. The controlling terminal
# can be used to interact with the user. W/o one, it is probably being invoked from a daemon. The
# other common case is that a user is running a remote ssh command without the -t option.
function cuiHasControllingTerminal()
{
	# this sets the exit code to 0 or 1 based on if the controlling terminal device can be written to
	# by using it in a redirection. since the 'true' command never outputs anything, nothing will be
	# written to the terminal.
	# note: that /dev/tty always exists even if its not connected to a terminal
	# note that it is often suggested to use $(ps hotty $$) to get the psuedo term used by /dev/tty
	# and if its '?' then there is none but checking the redirect is 100 times faster.
	(true >/dev/tty)2>/dev/null
}

# usage: cuiGetSpinner <spinnerIndex>
# usage: echo $(cuiGetSpinner $mySpinnerCount); ((mySpinnerCount++))
# Each time this is called with incremented <spinnerIndex> value it returns the next character in a
# sequence that simulates a spinning wheel in a text display. The caller should increment <spinnerIndex>
# each time it wants the animation to change. This function wraps the <spinnerIndex> so the caller can
# continuously increment it.
function cuiGetSpinner()
{
	local spinnerIndex="$1"
	local spinner=( / - \\ \| )
	echo "${spinner[$(( spinnerIndex % ${#spinner[@]} ))]}"
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

	setRef "$passwordVar" "$pw1"
}

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

	bgtrap 'assertError "confirm prompt canceled by user"' SIGINT

	printf "$prompt (y/n)" >/dev/tty
	while [[ ! "$result" =~ ^[yYnN] ]]; do read -s -n1 result </dev/tty; done
	printf "$result\n" >/dev/tty

	bgtrap -r 'assertError "confirm prompt canceled by user"' SIGINT

	[[ "$result" =~ ^[yY] ]]
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
	while [[ "$1" =~ ^- ]]; do case $1 in
		-t) truncMode="1" ;;
		-w*) cols="$(bgetopt "$@")" && shift ;;
		-s*) startCol="$(bgetopt "$@")" && shift ;;
	esac; shift; done

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



# usage: isShellFromSSH
# returns true if the script has been invoked by a ssh term (or child of one)
# this should not be used to determin permissions. the user could get this to
# report falsely. Use this for niceties like deciding whether to launch a getUserCmpApp
# version of a program or a text based one.
function isShellFromSSH()
{
	[ "$SSH_TTY" ] || [ "$(who am i | grep "([0-9.]*)")" ]
}

# usage: isGUIViable
# returns true if the script has been invoked by a ssh term (or child of one)
# this should not be used to determin permissions. the user could get this to
# report falsely. Use this for niceties like deciding whether to launch a GUI
# version of a rpogram or a text based one.
function isGUIViable()
{
	[ ! "$SSH_TTY" ] && [ ! "$(who am i | grep "([0-9.]*)")" ]
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




# usage: (start)  progress -s <subTask> [<initialProgMsg>] [<target> [<current>] ]
# usage: (update) progress -u <progUpdateMsg> [<current>]
# usage: (end)    progress -e <subTask> [<resultMsg>]
# usage: (hide)   progress -h
# usage: (hide)   progress -g
#
# The progress function can be used in any function to indicate its progress in completing an operation.
# Its safe to use it in any function reguardless of whether the author expects it to be using in an interactive
# or batch script/command. The progress call indicates what the algorithm is doing without dictating how or
# or even if it is displayed to the user. Any function can be decorated with progress calls and if its
# executed in a batch envoronment, they will be close to noops. In interactive environments, the user can
# control if and how the progress messages are displayed by setting the progressDisplayType ENV variable.
# Progress state is kept in per thread/process memory so they work corectly in multi-threaded scripts.
#
# The typical usage is to put a call to progress -s (start scope) at the top of a function, progress -e (end scope)
# at the botton, and optionally one or more progress -u (update) in the middle.
#
# Options:
#    -s : start a sub-task under the current task
#    -u : update the state of the current task
#    -e : end the current sub-task and pop back to the previous
#    -h : hide. hint that the user does not need to see the progress UI anymore.
#    -g : get. get the progress state for the current thread
# Params:
#    <subTask>: id is used to identify the start and end of a sub-task. It is a single word, no spaces. It should
#               be short and reasonably mnemonic.
#    <*Msg>   : quoted, one line of text that describes the current operation. It typically should describe the
#               operation the will start after the progress call so that it will be displayed while that operation
#               progresses. If the start(-s) call is immediately followed by an update(-u) call, the msg can be ommitted.
#               in some forms of progress UI the end msg will display for such a short time that the user will not
#               see it, but its important b/c in other forms -- if the user is seeking more details it will be
#               visible and can provide important diagnostic information.
#   <target>  : in the start call, you can optionally provide an integer value which expect the algorithm
#               calling subsequent update calls will get to. For example if you are entering a loop of 245 iterations
#               and in the loop you call update, you can set target to 245. This optional information allows some
#               progress UI to display a bar/percentage indicator
#   <current> : when target was specified in start, some progress UIs will indecate the percentage complete as
#               (current / target *100). If target was not given some UIs will use this as a progressing counter
#.SH Separation of indicating and displaying progress
# The progress mechanism separates the two independent notions of 1) keeping a progress stack associated with the currently
# running thread and 2) some place to send progress messages.
# This facilitates nice feedback. A potentially long running function can call this to indicate to the user the progress
# and what is happening whether or not the calling application decides to display the progress and how it is displayed.
# The -s and -e forms are optional and should be used in pairs. -s starts a new sub-task by pushing it onto a stack so that
# subsequent -u calls are interpreted as being relative to that sub-task. -e will end that sub-task by popping it off the stack
#
#.SH How its displayed to the user:
#    This function is only responsible for keeping track of the progress stack for the enclosing process tree and to write
#    the current progress info to the $userFeedbackFD file descriptor whenever it changes. The $userFeedbackFD is set by the
#    progress_selectDisplayDriver function. If an application does not call progress_selectDisplayDriver, it will be called
#    on demand with the type specified as 'default'. The default can be changed in an environment variable or config file setting.
#
#    Even if the progress is not being displayed, the progress can be checked by sending the proc a kill USR1.
#
#.SH The Progress scope (process tree):
#    Each progressScope displays the progress of some linear task as it moves to compoletion. If multiple threads of execution
#    exists, they each need their own progressScope. Often each progress scope is shown on its own terminal line but the UI could
#    be tabs or panes etc...
#
#    The core idea is that all synchronous subshells can reuse the same progressScope because there is one synchrous thread of
#    actions that the progress feedback UI represents. Those actions may consist of sub parts which can be displayed as a hierarchy
#    but a sub part has to finish before the parent part proceeds so its still one synchronous progression.
#
#    Each asynchronous branch, however, is a separate thread of actions and it needs its own progress scope. If multiple asynchronous
#    threads reported to the same progressScope, it would be chaos as they represent more than one progression.
#
#    In a bash script many things create subshells synchronously which inherent their parents environment but can not update their
#    parent's environment. The progress scope is defined by an exported env variable which is automatically inherited by subshells.
#    The value of that variable points to a temp file. By writing to the temp file pointed to by that progressScope variable, the
#    subshell can contribute to the progression of the parents progress meter.
#
#    For typical, single threaded scripts there is a single progressScope that gets created only if needed. If a script or function
#    spawns new threads of execution (e.g. running a command/function in the background with '&') then care should be taken to clear
#    the progressScope variable in the childs environment so that it will create a new progressScope for the new thread of execution.
#    For example:
#         progressScope="" myBackgroundFn &
#    If the function running in the new thread calls this 'progress' function then the first call will see that progressScope is not
#    set and create a new progress scope.
#
#.SH ScopeFile Format:
#     The scope file has a line for each time start (-s) is called. If -u is called without calling -s, a -s with an empty description is implied
#     Each line has the following format:
#           field1 field2 fieldN...
#     Where:
#          field1=label
#          field2=progressMsg
#          field3=startTimeStamp
#          field4=lapTimeStamp
#          field5=currentTimeStamp
#          field6=target
#          field7=current
function progress()
{
	# 2016-06 bobg. by short circuiting this the off case at the top of this function, running 350 unit
	# tests went from 22sec(using oneline) to 20sec(using null w/o short circuit) to 16sec(short circuit)

	# if progress is being called for the first time and the script has not set a specific progress driver,
	# set the default driver now
	declare -gx userFeedbackFD
	declare -gx _progressCurrentType
	declare -gx _progressAlreadyInitialized
	if [ ! "$_progressCurrentType" ] && [ ! "$_progressAlreadyInitialized" ]; then
		declare -gx _progressAlreadyInitialized="1"
		progress_selectDisplayDriver default
	fi

	# if no progress display driver is created now, either its configured to be 'off' or it failed to
	# initialize or it was shut down.
	if [ ! "$_progressCurrentType" ] || [ "$_progressCurrentType" == "off" ]; then
		return 0
	fi

	local cmd="$1"; [ $# -gt 0 ] && shift


	if [ ! "$progressScope" ]; then
		/bin/mkdir -p "/tmp/bg-progress-$USER"
		export progressScope="/tmp/bg-progress-$USER/$BASHPID"
		touch "$progressScope"
		bgtrap -n progress-$BASHPID 'rm $progressScope &>/dev/null' EXIT
	fi

	# TODO: some refactors to consider....
	#       1) not sure if we need the temp file. We can pass info down through ENV variables and it seems that we do not pass info
	#          up. We can adopt the rule that a new subshell, identified by $BASHPID != $SAVEDPID, will implicitly create a new
	#          -s sub-task level. This means that an update never needs to change the information in a subtack that is not in its
	#          PID.

	local -a data
	local indent=0
	case $cmd in
		-s)
			indent=$([ -f "$progressScope" ] && wc -l < "$progressScope" || echo 0)
			local label="$1"
			local msg="$2"
			local target="$3"
			local current="$4"
			data[0]=$(bgawk -n '{printf("%s%s", sep, $1); sep="/"} END {printf("%s%s", sep, "'"$label"'")}' "$progressScope" 2>/dev/null)
			data[1]="$label"
			data[2]="$msg"
			data[3]=$(date +"%s%N")
			data[4]=${data[3]}
			data[5]=${data[3]}
			data[6]="${target}"
			data[7]="${current}"
			awkDataNormRef data[1] data[2] data[6] data[7]
			echo "${data[@]:1}" >> "$progressScope"
			;;
		-u)
			indent=$([ -f "$progressScope" ] && wc -l < "$progressScope" || echo 0)
			local msg="$1"
			awkDataNormRef msg
			local current="$2"
			bgawk -i -n '
				on {print last}
				{last=$0; on="1"}
				END {
					$2="'"${msg//\\/\\\\}"'"
					$4=$5
					$5="'"$(date +"%s%N")"'"
					$7="'"$(normAwkData "${current}")"'"
					print $0
				}
			' "$progressScope" 2>/dev/null
			data=( $(progressGet) )
			;;
		-e)
			local label; [[ "$1" =~ \  ]] && { label="$1"; [ $# -gt 0 ] && shift; }
			local msg="$1"
			data=( $(progressGet) )
			# TODO: add better debugging to find mismatched -s / -e pairs
			false && [ "${data[1]}" != "$(normAwkData "$label")" ] && echo "ending progress label ($label) does not match the current label (${data[1]})" >&2
			data[2]=$(normAwkData "$msg")
			data[4]=${data[5]}
			data[5]=$(date +"%s%N")
			data[7]=${data[6]} # current now equals target

			# note that we remove the scope from the file now, but the data[] object is already filled in with the
			# information about the end(-e) event and that is what will be sent to the progress UI below.
			bgawk -i -n '
				on {print last}
				{last=$0; on="1"}
				END {}
			' "$progressScope" 2>/dev/null
			indent=$([ -f "$progressScope" ] && wc -l < "$progressScope" || echo 0)
			;;
		-h) progressFeedbackCntr hide
			return
			;;
		-g) progressGet
			return
			;;
	esac 2>/dev/null

	# note that we don't always send the complete, detailed and structured data to the progress UI
	# b/c we want to support plain stdout and stderr and other simple 'log' destinations. Those things
	# have no inteligence to understand the content so the 'plain' and 'unstructured' types will format
	# the state in a reasonable way.
	# TODO: the $userFeedbackTemplate and $userFeedbackProtocol do not yet seem quite right. userFeedbackTemplate
	#       should only be used if $userFeedbackProtocol is unstructured, (unstructured should mean that the
	#       userFeedbackFD is a dumb terminal or logfile and in that case, only the selected $userFeedbackTemplate
	#       is used. All progressUI plugins should get the structured protocol that has all infomation.
	local str=""
	case $userFeedbackTemplate in
		plain) str="${data[0]}:${data[2]}" ;;
		detailed)
			local cmpTime=${data[3]//--/0}
			[ $cmd == "-u" ] && cmpTime=${data[4]//--/0}
			data[5]=${data[5]//--/0}
			local spaces=$(printf "%*s" $((indent*3)) "")
			local timeDelta=$(( ${data[5]:-0} - ${cmpTime:-0} ))
			str="$(bgNanoToSec "$timeDelta" 3) $spaces $cmd ${data[0]}:${data[2]} "
			;;
		*) str="${data[*]}" ;;
	esac

	if [ "$userFeedbackProtocol" == "structured" ]; then
		str="@1 $progressScope $str"
	else
		str="${str//%20/ }"
	fi

	# its ok if we do not write anything because the driver could have been turned off or in the process
	# of exiting
	if [ "$userFeedbackFD" ] && [ -w "/dev/fd/$userFeedbackFD" ]; then
		# 2019-09-17 bobg: When $userFeedbackFD is a PIPE, If there are no readers on it, then this write will raise a SIGPIPE signal
		# the default SIGPIPE handler will exit the process. This will happen if the driver coproc exits prematurely. I wonder if
		# it will also happen in the time when the driver is processing the command so maybe we need to indicate if $userFeedbackFD
		# is a PIPE and if so, make the protocol send a response to syncronize this message passing.
		#
		# SIGPIPE's purpose is to make the default action of writing to a broken PIPE to exit the process. This makes *nix command
		# piplines more reliable.We can turn that off by trapping SIGPIPE but a low level library should not change the default
		# for the script which might be pipable and rely on that behavior.  If this continues to be a problem we could set the trap
		# just around this call with bgTrapStack
		echo "$str" >&$userFeedbackFD 2>/dev/null
		[ "$userFeedbackSync" ] && sync
	fi
	return 0
}

# usage: data=( "$(progressGet)" )
# if something in the current thread is calling 'progress' this will get the current progress message
# if not, it returns the empty string
# Output Format:
#    this function returns the progress in a structured one line string format
#    fields are separated by whitespace.
#    Fields are normalized with normAwkData so that they do not contain spaces and are not empty
#    field0 is a genereated parent field. This conveniently preserves the 1 based index positions used in awk
#    when its converted to a zero based base array so that the field indexes documented in the progress function
#
function progressGet()
{
	# if set, progressScope is the file that this thread is writing its progress messages to
	if [ "$progressScope" ]; then
		awk '
			function norm(s) {
				if (s=="") s="--"
				if (s~"[ \t\n]") s="\"" s "\""
				gsub(" ","%20",s)
				gsub("\t","%09",s)
				gsub("\n","%0A",s)
				return s
			}
			{parent=parent sep $1; sep="/"}
			END {
				out=norm(parent)
				for (i=1; i<=NF; i++) {
					out=out " " norm($i)
				}
				print out
			}
		' "$progressScope" 2>/dev/null
	fi
}


# usage: currentLabel="$(progressGetActiveScopeLabel)"
# usage: if progressGetActiveScopeLabel -q; then ...
# this reports whether the progress system is active (someone has called progress) and optionally return the most
# recent scope label.
function progressGetActiveScopeLabel()
{
	# if progressScope is set, the progress system is being used. Pring the label of the last (most recent) scope
	# each scope has one line in the progressScope file
	if [ "$progressScope" ]; then
		[ "$1" != "-q" ] && awk 'END {print $1}' "$progressScope" 2>/dev/null
		return
	fi
	return 1
}



# this global array is a registry for progressDisplayType drivers.
# progressTypeRegistry[<typeName>]="<driverFunctionName>"
declare -gA progressTypeRegistry


# usage: progress_selectDisplayDriver <type> <template> <sync>
# A script calls this to determine how feedback from the 'progress' function is displayed. This function typically
# does not need to be called expicitly but a script can if it wants to prefer a certain type. If nothing in the script
# calls 'progress' or 'progress_selectDisplayDriver', this function wil lnever be called. If the script
# (or a function it uses) calls 'progress' but does not select a Display type, then this function will be called
# automatically, on demand with the type 'default'.
#
# See the comments for the 'progress' function. That is what scripts typically call to interact with this mechanism.
# Lower level functions call 'progress' without regard to how or even if the messages are displayed to the user. In
# all cases, this progress / userFeedback mechanism creates a new stream for progress updates and writing to stdout
# and stderr continue to behaive as expected.
#
# Types:
#    stdout : send progress messages to stdout, the same as echo would
#    stdout : send progress messages to stderr, the same as echo >&2 would
#    null   : suppress progress messages, the same as echo >/dev/null would
#    oneline: display each progress message from a process to one line, overwriting the last. When a (sub) process
#             calls 'progress' for the first time, the message will be echo'd to the terminal with a trailing newline
#             which often cause the screen to scroll. From then on, subsequent calls to 'progress' will overwrite that
#             same line. If stdout is not a terminal, oneline reverts to using the 'stdout' type. If the script or a
#             invoked external command writes to stdout or stderr, it will work as expected, scrolling the progress
#             lines up as needed. When a progress line scrolls past the top of the terminal, it stops updating
#    statusline:
#             this is simililar to oneline but newer and more simple. It does not need the output and input filter pros to
#             catch when the screen scrolls because it statusline sets the terminal scroll area so that the output scrolls separately
#             The statusline driver reserves a line at the bottom of the screen for each progressScope its asked to display.
#             Initially it reserves the last line for the next bash prompt when the command finishes. That eliminates a jump
#             at the end of the progress lines that are static throughout the command run. If the command produces output on
#             stdout or std error, it is written above the progress lines and scrolls without effecting the progress lines.
#    default: chooses a type based on the first one of these that is set :
#                1) '$progressDisplayType' env var if set
#                2) the /etc/bg-lib.conf[.]defaultProgressDisplayType if set
#                3) statusline if stdout is a terminal
#                4) stdout
#
# Templates:
#    plain   : (terse) parent:progressMsg
#    detailed: (more vebose) deltaTime cmd parent:progressMsg
#    full    : <all fields>
#
# Sync:
#    If sync parameter is non-empty, progress will sync the streams after each update. This adds a small but non-trivial
#    performance hit but makes it more likely the progress and stdout and sterr output  will be in the correct order.
#    This is not often needed. Its better to leave it blank.
#
# Protocol:
#    When the progress function writes the progress to the userFeedbackFD file, the line that it writes complies
#    with the protocol that the handler reading the userFeedbackFD requires. The userFeedbackProtocol environment
#    variable specifies which protocol should be used. Typically the handler sets the value of userFeedbackProtocol
#    and the progress function formats the line in accordance.
#
#    passThru:   formated for display. This is the default and is appropriate when the handler will not do any formating
#                stdout, stderr and null are simple pipes that display the information as received.
#    structured: each field is escaped so that they are white space separated. This makes it easier for the handler to
#                parse it. The first field is "@1" to indicate that its a strunctured line. The second filed is the
#                progressScope with is the name of the filename that contains the progress stack. The third and remaining
#                fields are the text as specified by the template but with escaped whitespace.
#
# Environment:
#    BGENV: progressDisplayType : (statusline|oneline|stderr|stdout|null) : determines how progress is displayed. see 'progress' function
#          /etc/bg-lib.conf[.]defaultProgressDisplayType : specify the progressDisplayType in a persistent config
function progress_selectDisplayDriver()
{
	local type="${1:-default}"
	export userFeedbackTemplate="${2:-plain}"
	export userFeedbackSync="$3"
	export userFeedbackProtocol="passThru"


	# if a previous driver is active, stop it
	if [ "$_progressCurrentType" ]; then
		local driverFnName="${progressTypeRegistry[$_progressCurrentType]}"
		[ "$driverFnName" ] && $driverFnName stop
		export _progressCurrentType=""
	fi

	# TODO: add termTitle progressDisplayType function to change xterm window title. This works via ssh too.
	# example: echo -en "\033]0;New terminal title $i\a"; sleep 1; done
	# example: set_term_title(){echo -en "\033]0;$1\a"}

	case $type in
		default)
			# in a deamon, the default is to not display any progress UI
			cuiHasControllingTerminal || return

			# respect the progressDisplayType ENV var and the /etc/bg-lib.conf config file. If those
			# are not set or set to 'default' then use 'statusline'
			local defaultType="statusline"
			if [ "$progressDisplayType" ]; then
				defaultType="$progressDisplayType"
			else
				defaultType="$(getIniParam /etc/bg-lib.conf . defaultProgressDisplayType "$defaultType")"
			fi
			[[ "${defaultType}" =~ ^[[:space:]]*default([[:space:]]|$) ]] && defaultType="statusline"

			# call ourselves again with the real display type (not 'default')
			progress_selectDisplayDriver $defaultType
			;;

		stdout)
			export _progressCurrentType="$type"
			export userFeedbackFD="1"
			;;

		stderr)
			export _progressCurrentType="$type"
			export userFeedbackFD="2"
			;;

		off)
			export _progressCurrentType=""
			export userFeedbackFD=""
			export userFeedbackTemplate=""
			;;

		null)
			export _progressCurrentType="$type"
			exec {userFeedbackFD}>/dev/null
			export userFeedbackFD
			;;

		*)
			local driverFnName="${progressTypeRegistry[$type]}"
			[ ! "$driverFnName" ] && assertError "unknown progress display type '$type'"

			# if the driver failed to start it could be that there is no controlling terminal so just
			# ignore it unless another use-case comes up
			if $driverFnName start; then
				export _progressCurrentType="$type"
			fi
			;;

	esac
# bgtrace "  !EXIT    |$(trap -p EXIT)|"
# bgtrace "  !SIGINT  |$(trap -p SIGINT)|"
# bgtrace "  !SIGTERM |$(trap -p SIGTERM)|"
}

# usage: progressFeedbackCntr <message to current driver ...>
# usage: progressFeedbackCntr start  <type> <template> <sync>
# The first form sends the command line untouched to the current active feedback driver.
# The second form is a synonom for progress_selectDisplayDriver
# if there is no active driver, the first form is a noop.
function progressFeedbackCntr()
{
	# this block handles msgs when no progress UI object exists yet
	if [ ! "$_progressCurrentType" ]; then
		if [ "$1" == "start" ]; then
			# calling control with "start" is a synonom for select...
			progress_selectDisplayDriver "$@"
			return
		fi
		# if no feedback UI is active, there is nothing to do
		return 1
	fi

	# its fine if the active feedback driver does not have a control function registered because some
	# like stdin, stderr, null are simple an have no controlls
	local driverFnName="${progressTypeRegistry[$_progressCurrentType]}"
	[ "$driverFnName" ] && $driverFnName "$@"
}


function myTestTrapHandler()
{
	local intrName="$1";    [ $# -gt 0 ] && shift
	local startingPID="$1"; [ $# -gt 0 ] && shift
	local isScript=" "; [ "$$" == "$BASHPID" ] && isScript="*"
	bgtrace " !TRAP $isScript'$BASHPID' createdIn='$startingPID' $intrName '$*'"
}


####################################################################################################
### Oneline progressFeedback UI Driver

# usage: progressTypeOnelineCntr start|stop|...  [parameters ...]
# this implements a progress feedback UI Driver class
# Its a Singleton object class implemented in this one function that is registered in the progressTypeRegistry
#
# The oneLine feedback UI works with the common terminal metaphore of a continuous scrolling page but
# progress updates always overwrite themseleves on the line in which they were first written.
# Each child process has separate status feedback so if a child process writes a progress message,
# the first time it writes on the next available line and from then on, that proccess will only overwrite
# that same line. This means that each new suproc that writes progress may cause the whole screen to
# scroll up and the previous status lines used by other subprocs will have moved up.
#
# stdout of the script is intercepted and inserted above the progress status line(s) so that the normal
# output only scrolls the text above it and the status lines stay at the bottom on the screen.
# When the UI is stopped (which typically happens when the script terminates, std output resumes after
# the status lines as normal and the last state of each status line will begin to scroll along with
# the other content.
function progressTypeOnelineCntr()
{
	local cmd="$1"; [ "$1" ] && shift
	case $cmd in
		stop)
			userFeedbackFD=""
			exec >&4 2>&5           # set the stdout and stderr back
			progressTypeOnelineCntr stopInputLoop
			procIsRunning "${progressPIDs[0]}" &&  { kill "${progressPIDs[0]}"; wait "${progressPIDs[0]}"; }
			procIsRunning "${progressPIDs[2]}" &&  { kill "${progressPIDs[2]}"; wait "${progressPIDs[2]}"; }
			unset progressPIDs
			export _progressCurrentType=""
			rm "${ipcFile}*" 2>/dev/null
			ipcFile=""
			stty echo
			;;

		# the (stop|start)InputLoop messages ar needed because scripts that need to read from stdin need to stop the driver
		# from reading from stdin so it does not fight over reading the input. I tried installing this loop as a filter
		# that replaces stdin with a pipe that it writes to but that does not work for things like sudo that bypass stdin
		# to read from the terminal pts device. Scripts should not be hardcoded to know about this driver so they send a message
		# the the actived driver like 'progressFeedbackCntr "stopInputLoop"'. Any driver that needs to will respond to that
		# message and other will ignore it.
		stopInputLoop)
			if [ "${progressPIDs[1]}" ]; then
				kill ${progressPIDs[1]}
				wait ${progressPIDs[1]}
				progressPIDs[1]=""
			fi
			;;

		startInputLoop)
			local inputLoopType="${2:-spinner}"
			if [[ "$inputLoopType" == "spinner" ]]; then
				progressTypeOnelineCntr "startInputLoopWithSpinner"
			else
				progressTypeOnelineCntr "startInputLoopWithoutSpinner"
			fi
			;;

		startInputLoopWithoutSpinner)
			# we should only start the stdin read loop if the 'oneline' feedback UI driver is active
			[ "$_progressCurrentType" == "oneline" ] || return 1

			# is is a co-process to read user input and display a spinner. If the user hits enter, the term
			# scrolls the term directly (local echo) so we need to catch that. We turn off echo and we process the
			# user input oursleves so that we can scroll in sync with the other output
			(
#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" INP LOOP' SIGTERM
#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" INP LOOP' SIGINT
#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" INP LOOP' EXIT
				# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
				stty -echo
				bgtrap 'stty echo' EXIT

				# the trap is the only way out of the loop SIGTERM is the default kill SIG
				bgtrap 'exit' SIGTERM
				while read -r buf; do
					startLock $ipcFile.lock
					echo >> "$ipcFile"
					printf "${csiToSOL}   ${csiToSOL}"
					echo
					endLock $ipcFile.lock
				done
				stty echo
			) >&4 <&6  &
			progressPIDs[1]=$!
			;;


		startInputLoopWithSpinner)
			# we should only start the stdin read loop if the 'oneline' feedback UI driver is active
			[ "$_progressCurrentType" == "oneline" ] || return 1

			# is is a co-process to read user input and display a spinner. If the user hits enter, the term
			# scrolls the term directly (local echo) so we need to catch that. We turn off echo and we process the
			# user input oursleves so that we can scroll in sync with the other output
			(
#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" INP LOOP' EXIT
#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" INP LOOP' SIGINT
#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" INP LOOP' SIGTERM
				sleep 1
				local spinner=( / - \\ \| )
				local spinCount=0
				printf " /]: "

				# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
				# turn echo off so that the linefeed will get written by us, so that we can update the ipcFile at the same time
				stty -echo
				bgtrap 'stty echo' EXIT

				# the trap is the only way out of hte loop SIGTERM is the default kill SIG
				bgtrap 'exit' SIGTERM
				while true; do
					sleep 0.2
					char=""
					IFS="" read -r -d '' -t 0.2  -n 1 char ; readCode=$?
					if [ "$char" == $'\n' ]; then
						startLock $ipcFile.lock
						echo >> "$ipcFile"
						printf "${csiSave}${csiToSOL}    ${csiRestore}"
						printf "$char"
						printf " /]: "
						endLock $ipcFile.lock
					else
						printf "$char"
					fi
					# read timeout. update spinner
					if [ $readCode -gt 128 ]; then
						startLock $ipcFile.lock
						printf "${csiSave}${csiToSOL} ${spinner[spinCount++%4]}]: ${csiRestore}"
						endLock $ipcFile.lock
					fi
				done;
				stty echo
			) >&4 <&0  &
			progressPIDs[1]=$!
			;;

		start)
##bgtrap 'myTestTrapHandler EXIT   "'"$BASHPID"'" SCRIPT' EXIT
##bgtrap 'myTestTrapHandler SIGINT "'"$BASHPID"'" SCRIPT' SIGINT
#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" SCRIPT' SIGTERM
			# if we are not attached to a terminal, revert to plain stdout
			if [ ! -t 1 ]; then
				export userFeedbackFD="1"
				export _progressCurrentType="stdout"
				return
			fi

			export _progressCurrentType="$type"
			declare -ga progressPIDs

			# since we redirect input to a background task, we need to make sure that we clean up
			bgtrap '
				#myTestTrapHandler SIGINT "'"$BASHPID"'" "START >>>>>>>>>>>>>>>>>>>>>>>>>"
#				progress_selectDisplayDriver off
				#myTestTrapHandler SIGINT "'"$BASHPID"'" "STOP  >>>>>>>>>>>>>>>>>>>>>>>>>"
			' SIGINT
			bgtrap '
				#myTestTrapHandler EXIT "'"$BASHPID"'" "START >>>>>>>>>>>>>>>>>>>>>>>>>"
				progress_selectDisplayDriver off
				#myTestTrapHandler EXIT "'"$BASHPID"'" "STOP  >>>>>>>>>>>>>>>>>>>>>>>>>"
			' EXIT
			local termHeight=$(tput lines 2>/dev/tty)
			local termWidth=$(tput cols 2>/dev/tty)
			ipcFile=$(mktemp)
			echo "start" > "$ipcFile"
			echo  > "${ipcFile}.signal"
			# save stdout and stderr in fd 4 and 5
			exec 4>&1
			exec 5>&2

			# this is a co-process to pipe stdout/stderr though so that we can count lines and
			# what ever else we want. This will be output from the script or children that does not use 'progress'
			pipeToStdStreamHandler=$(mktemp -u )
			mkfifo "$pipeToStdStreamHandler"
			(
#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" OUT LOOP' EXIT
#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" OUT LOOP' SIGINT
#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" OUT LOOP' SIGTERM
				local readCode lineEnd
				# the trap is the only way out of the loop
				bgtrap 'exit' SIGTERM
				while true; do
					line=""
					IFS="" read -r -t 0.7 line; readCode=$?
					if [ "$line" ]; then
						if [ $readCode -lt 128 ]; then
							startLock $ipcFile.lock
							printf "    ${line}\n"
							echo >> "$ipcFile"
							endLock $ipcFile.lock
						else
							printf "    ${line}"
						fi
					fi
				done;
			) >&4 <$pipeToStdStreamHandler &
			progressPIDs[0]=$!
			exec &>$pipeToStdStreamHandler

			progressTypeOnelineCntr startInputLoop

			# this is a coproc to read the progress lines and display them
			local pipeToProgressHandler=$(mktemp -u )
			mkfifo "$pipeToProgressHandler"
			(
#bgtrap 'myTestTrapHandler EXIT    "'"$BASHPID"'" PRO LOOP' EXIT
#bgtrap 'myTestTrapHandler SIGINT  "'"$BASHPID"'" PRO LOOP' SIGINT
#bgtrap 'myTestTrapHandler SIGTERM "'"$BASHPID"'" PRO LOOP' SIGTERM
				local lineOffset=1 progressScope
				# the trap is the only way out of the loop
				bgtrap 'exit' SIGTERM
				while IFS="" read -r line; do
					if [[ "$line" =~ ^@1\  ]]; then
						line="${line#@1 }"
						progressScope="${line%% *}"
						line="${line#* }"
						line="${line//%20/ }"
					fi
					startLock $ipcFile.lock
					line="${line:0:$termWidth}"
					if ! grep -q "^$progressScope:" "$ipcFile" 2>/dev/null; then
						echo "$progressScope:" >> "$ipcFile"
						printf "${csiToSOL}%s${csiClrToEOL}\n" "$line"
					else
						local lineNR="$(awk '
							$0~"^'"$progressScope"':" {printf("%s ", NR)}
						' "$ipcFile" 2>/dev/null || echo "err")"
						local totalNR="$(awk '
							END {print NR}
						' "$ipcFile" 2>/dev/null || echo "err")"


						lineOffset="$(awk '
							$0~"^'"$progressScope"':" {line=NR}
							END {print NR-line+1}
						' "$ipcFile" 2>/dev/null || echo "$lineOffset")"
						if [ $termHeight -gt $lineOffset ]; then
							printf "${csiToSOL}${CSI}$lineOffset${cUP}%s${csiClrToEOL}${csiToSOL}${CSI}$lineOffset${cDOWN}" "$line"
						fi
					fi
					endLock $ipcFile.lock
				done;
			) >&4 <$pipeToProgressHandler &
			progressPIDs[2]=$!
			exec {userFeedbackFD}>$pipeToProgressHandler
			export userFeedbackFD
			export userFeedbackProtocol="structured"
			;;

		hide)
			echo -n ""
			;;
	esac
}
progressTypeRegistry[oneline]="progressTypeOnelineCntr"


####################################################################################################
### StatusLine progressFeedback UI Driver


# usage: progressTypeStatusLineCntr start|stop|...  [parameters ...]
# this implements a progress feedback UI Driver class
# Its a Singleton object class implemented in this one function that is registered in the progressTypeRegistry
#
# this implements a progress feedback UI where progress lines are written in a 'status' line at the bottom of the screen.
# a new status line is allocated at the bottom of the screen for each new progressScope encountered
# at the end, the new shell prompt will be added at the bottom and all the status lines will scroll up like other output.
#
# This is a progressFeedbackUI driver control function. Its kind of like a Singleton object class. It is registered in the
# progressTypeRegistry map by its type name which is used in configuration to specify that it should be used.
function progressTypeStatusLineCntr()
{
	local cmd="$1"
	case $1 in
		stop)
			[ "$userFeedbackFD" ] && exec {userFeedbackFD}>&-
			wait "${progressPIDs[0]}"
			progressPIDs[0]=""
			userFeedbackFD=""
			;;
		start)
			declare -ga progressPIDs
			declare -g  progressTermFD=""

			# this driver needs to read and write the terminal
			cuiHasControllingTerminal || return 1

			local termHeight=$(tput lines 2>/dev/tty)
			local termWidth=$(tput cols 2>/dev/tty)

			# linesByScope has the offset from the bottom of each progressScope encountered
			local -A linesByScope

			# the block between ( and ) is a coproc to read the progress lines and display them in the status line
			local pipeToProgressHandler=$(mktemp -u /tmp/bgprogress-XXXXXXXXX); mkfifo -m 600 "$pipeToProgressHandler"; (
				local lineOffset=1 progressScope

				# init version of the $csi* vars in this coproc to reflect /dev/tty
				declare -g $(cuiRealizeFmtToTerm cuiColorTheme_sample1 </dev/tty)

				# this reserves a blank line at the bottom where the new prompt will go when the command ends
				# this makes it so the status line don't jump at the end
				# TODO:

				local fullScreen=$(( termHeight ))
				local partScreen=$(( termHeight ))

				builtin trap '
					printf "${CSI}0;$termHeight${cSetScrollRegion}${CSI}$((termHeight));0${cMoveAbs}${csiClrToEOL}" >/dev/tty
				' EXIT

				# when the calling process closes its FD to the pipe (and there are no other writers), read will exit with exit code 1
				while IFS="" read -r -u 3 line; do
					cmd=""
					if [[ "$line" =~ ^@1\  ]]; then
						line="${line#@1 }"
						progressScope="${line%% *}"
						line="${line#* }"
						line="${line//%20/ }"
					elif [[ "$line" =~ ^@2\  ]]; then
						cmd="hide"
					elif [[ "$line" =~ ^@end  ]]; then
						cmd="end"
					elif [[ "$line" =~ ^@rmPipe  ]]; then
						cmd="rmPipe"
					fi

					termHeight=$(tput lines 2>/dev/tty)
					termWidth=$(tput cols 2>/dev/tty)
					line="${line:0:$((termWidth-1))}"

					case $cmd in
						end) exit ;;

						# once both this copro and the calling process have redirected pipeToProgressHandler to make an open FD, we
						# do not need it in the filesystem anymore. The caller sends us this msg to say its ok to rm
						rmPipe)
							rm -f "$pipeToProgressHandler" || assertError
							;;

						hide)
							printf "${CSI}0;$termHeight${cSetScrollRegion}${CSI}$((termHeight));0${cMoveAbs}${csiClrToEOL}" >/dev/tty
							;;

						*)
							if  [ ! "${linesByScope[$progressScope]}" ]; then
								# offset the existing status line offsets to make room for the new one
								for i in ${!linesByScope[@]}; do
									(( linesByScope[$i]++ ))
								done
								linesByScope[$progressScope]="0"

								# set the scroll region to the whole screen and scroll everything up one line (including our status lines)
								# then set the scroll region to exclude our status lines and put the cursor at the end of the scroll region
								local fullScreen=$(( termHeight ))
								local partScreen=$(( termHeight - ${#linesByScope[@]} ))
								printf "${csiSave}${CSI}0;$fullScreen${cSetScrollRegion}${CSI}0;0${cMoveAbs}${CSI}1${cScrollUp}${CSI}0;$partScreen${cSetScrollRegion}${csiRestore}${csiUP}" >/dev/tty
							fi

							# we use the printf / CSI construct so that the entire sequence is one API call and (hopefully) one atomic write
							local statusLineNum=$(( termHeight - linesByScope[$progressScope] ))
							printf "${csiSave}${CSI}$statusLineNum;1${cMoveAbs}${csiBkMagenta}%s${csiClrToEOL}${csiDefBkColor}${CSI}${cRestore}" "$line" >/dev/tty
							;;
					esac
				done;
			) >>"$(bgtraceGetLogFile)" 2>&1 3<$pipeToProgressHandler &
			progressPIDs[0]=$!
			exec {userFeedbackFD}>$pipeToProgressHandler
			export userFeedbackFD
			export userFeedbackProtocol="structured"

			# let the loop know that we have finished with pipeToProgressHandler and it can delete it now from the file system
			echo "@rmPipe" >&$userFeedbackFD

			# since we change the scroll region, we need to make sure that we clean up
			bgtrap '
				progress_selectDisplayDriver off
			' EXIT

			# the default SIGPIPE will silently exit the process so we trap it and do a bgtrace to aid in debugging. Typically this
			# happens when the driver loop endsprematurely or during shutdown if there is a race condition
			bgtrap 'bgtrace "progressTypeStatusLineCntr: PIPE write signal caught. This means that the driver coproc was not reading the pipe when progress() wrote to  it."' PIPE
			;;

		hide)
			if [ "${progressPIDs[0]}" ]; then
				echo "@2" >&$userFeedbackFD

			fi
			;;
	esac
}
progressTypeRegistry[statusline]="progressTypeStatusLineCntr"

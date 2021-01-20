
function cuiRealizeFmtToTerm(onOff               ,csiName,csiValue) {
	cuiDeclareGlobals()
	if (onOff && onOff!="off") {
		for (csiName in _csiCMD_p0) {
			csiValue=_csiCMD_p0[csiName]
			SYMTAB[csiName]=csiValue
			sub("^c","csi",csiName)
			SYMTAB[csiName]=_CSI""csiValue
		}
	} else {
		for (csiName in _csiCMD_p0) {
			SYMTAB[csiName]=""
			sub("^c","csi",csiName)
			SYMTAB[csiName]=""
		}
	}
}

function cuiDeclareGlobals() {
	cHide="?25l"
	csiHide=_CSI"?25l"
	cShow="?25h"
	csiShow=_CSI"?25h"
	cSave="s"
	csiSave=_CSI"s"
	cRestore="u"
	csiRestore=_CSI"u"
	cUP="A"
	csiUP=_CSI"A"
	cDOWN="B"
	csiDOWN=_CSI"B"
	cRIGHT="C"
	csiRIGHT=_CSI"C"
	cLEFT="D"
	csiLEFT=_CSI"D"
	cToSOL="G"
	csiToSOL=_CSI"G"
	cClrToEOL="K"
	csiClrToEOL=_CSI"K"
	cClrToSOL="1K"
	csiClrToSOL=_CSI"1K"
	cClrLine="2K"
	csiClrLine=_CSI"2K"
	cClrBelowCursor="0J"
	csiClrBelowCursor=_CSI"0J"
	cClrAboveCursor="1J"
	csiClrAboveCursor=_CSI"1J"
	cClrSrc="2J"
	csiClrSrc=_CSI"2J"
	cClrSavedLines="3J"
	csiClrSavedLines=_CSI"3J"
	cInsertLines="L"
	csiInsertLines=_CSI"L"
	cDeleteLines="M"
	csiDeleteLines=_CSI"M"
	cDeleteChars="P"
	csiDeleteChars=_CSI"P"
	cScrollUp="S"
	csiScrollUp=_CSI"S"
	cScrollDown="T"
	csiScrollDown=_CSI"T"
	cSwitchToAltScreen="?47h"
	csiSwitchToAltScreen=_CSI"?47h"
	cSwitchToNormScreen="?47l"
	csiSwitchToNormScreen=_CSI"?47l"
	cNorm="0m"
	csiNorm=_CSI"0m"
	cFontReset="0m"
	csiFontReset=_CSI"0m"
	cBold="1m"
	csiBold=_CSI"1m"
	cFaint="2m"
	csiFaint=_CSI"2m"
	cItalic="3m"
	csiItalic=_CSI"3m"
	cUnderline="4m"
	csiUnderline=_CSI"4m"
	cBlink="5m"
	csiBlink=_CSI"5m"
	cReverse="7m"
	csiReverse=_CSI"7m"
	cConceal="8m"
	csiConceal=_CSI"8m"
	cStrikeout="9m"
	csiStrikeout=_CSI"9m"
	cDefColor="39m"
	csiDefColor=_CSI"39m"
	cDefBkColor="49m"
	csiDefBkColor=_CSI"49m"
	cBlack="30m"
	csiBlack=_CSI"30m"
	cRed="31m"
	csiRed=_CSI"31m"
	cGreen="32m"
	csiGreen=_CSI"32m"
	cYellow="33m"
	csiYellow=_CSI"33m"
	cBlue="34m"
	csiBlue=_CSI"34m"
	cMagenta="35m"
	csiMagenta=_CSI"35m"
	cCyan="36m"
	csiCyan=_CSI"36m"
	cWhite="37m"
	csiWhite=_CSI"37m"
	cHiBlack="90m"
	csiHiBlack=_CSI"90m"
	cHiRed="91m"
	csiHiRed=_CSI"91m"
	cHiGreen="92m"
	csiHiGreen=_CSI"92m"
	cHiYellow="93m"
	csiHiYellow=_CSI"93m"
	cHiBlue="94m"
	csiHiBlue=_CSI"94m"
	cHiMagenta="95m"
	csiHiMagenta=_CSI"95m"
	cHiCyan="96m"
	csiHiCyan=_CSI"96m"
	cHiWhite="97m"
	csiHiWhite=_CSI"97m"
	cBkBlack="40m"
	csiBkBlack=_CSI"40m"
	cBkRed="41m"
	csiBkRed=_CSI"41m"
	cBkGreen="42m"
	csiBkGreen=_CSI"42m"
	cBkYellow="43m"
	csiBkYellow=_CSI"43m"
	cBkBlue="44m"
	csiBkBlue=_CSI"44m"
	cBkMagenta="45m"
	csiBkMagenta=_CSI"45m"
	cBkCyan="46m"
	csiBkCyan=_CSI"46m"
	cBkWhite="47m"
	csiBkWhite=_CSI"47m"
	cHiBkBlack="100m"
	csiHiBkBlack=_CSI"100m"
	cHiBkRed="101m"
	csiHiBkRed=_CSI"101m"
	cHiBkGreen="102m"
	csiHiBkGreen=_CSI"102m"
	cHiBkYellow="103m"
	csiHiBkYellow=_CSI"103m"
	cHiBkBlue="104m"
	csiHiBkBlue=_CSI"104m"
	cHiBkMagenta="105m"
	csiHiBkMagenta=_CSI"105m"
	cHiBkCyan="106m"
	csiHiBkCyan=_CSI"106m"
	cHiBkWhite="107m"
	csiHiBkWhite=_CSI"107m"
}

BEGIN {

# CSI and OSC are two different sets of escape code that start with a different escape char
# most useful stuff is CSI. Set Window title is an OSC code
_CSI="\033["
_OSC="\033]"

# cursor movement
_csiCMD_p0["cHide"]="?25l"
_csiCMD_p0["cShow"]="?25h"
_csiCMD_p0["cSave"]="s"
_csiCMD_p0["cRestore"]="u"
_csiCMD_p0["cUP"]="A"
_csiCMD_p0["cDOWN"]="B"
_csiCMD_p0["cRIGHT"]="C"
_csiCMD_p0["cLEFT"]="D"
_csiCMD_p0["cToSOL"]="G"

# clear / delete
_csiCMD_p0["cClrToEOL"]="K"
_csiCMD_p0["cClrToSOL"]="1K"
_csiCMD_p0["cClrLine"]="2K"
_csiCMD_p0["cClrBelowCursor"]="0J"
_csiCMD_p0["cClrAboveCursor"]="1J"
_csiCMD_p0["cClrSrc"]="2J"
_csiCMD_p0["cClrSavedLines"]="3J"
_csiCMD_p0["cInsertLines"]="L"
_csiCMD_p0["cDeleteLines"]="M"
_csiCMD_p0["cDeleteChars"]="P"

# scroll
_csiCMD_p0["cScrollUp"]="S"
_csiCMD_p0["cScrollDown"]="T"

# pages
_csiCMD_p0["cSwitchToAltScreen"]="?47h"
_csiCMD_p0["cSwitchToNormScreen"]="?47l"

# font attributes
# see http://misc.flogisoft.com/bash/tip_colors_and_formatting
_csiCMD_p0["cNorm"]="0m"
_csiCMD_p0["cFontReset"]="0m"
_csiCMD_p0["cBold"]="1m"
_csiCMD_p0["cFaint"]="2m"
_csiCMD_p0["cItalic"]="3m"
_csiCMD_p0["cUnderline"]="4m"
_csiCMD_p0["cBlink"]="5m"
_csiCMD_p0["cReverse"]="7m"
_csiCMD_p0["cConceal"]="8m"
_csiCMD_p0["cStrikeout"]="9m"

# font colors
_csiCMD_p0["cDefColor"]="39m"
_csiCMD_p0["cDefBkColor"]="49m"

_csiCMD_p0["cBlack"]="30m"
_csiCMD_p0["cRed"]="31m"
_csiCMD_p0["cGreen"]="32m"
_csiCMD_p0["cYellow"]="33m"
_csiCMD_p0["cBlue"]="34m"
_csiCMD_p0["cMagenta"]="35m"
_csiCMD_p0["cCyan"]="36m"
_csiCMD_p0["cWhite"]="37m"

_csiCMD_p0["cHiBlack"]="90m"
_csiCMD_p0["cHiRed"]="91m"
_csiCMD_p0["cHiGreen"]="92m"
_csiCMD_p0["cHiYellow"]="93m"
_csiCMD_p0["cHiBlue"]="94m"
_csiCMD_p0["cHiMagenta"]="95m"
_csiCMD_p0["cHiCyan"]="96m"
_csiCMD_p0["cHiWhite"]="97m"

_csiCMD_p0["cBkBlack"]="40m"
_csiCMD_p0["cBkRed"]="41m"
_csiCMD_p0["cBkGreen"]="42m"
_csiCMD_p0["cBkYellow"]="43m"
_csiCMD_p0["cBkBlue"]="44m"
_csiCMD_p0["cBkMagenta"]="45m"
_csiCMD_p0["cBkCyan"]="46m"
_csiCMD_p0["cBkWhite"]="47m"

_csiCMD_p0["cHiBkBlack"]="100m"
_csiCMD_p0["cHiBkRed"]="101m"
_csiCMD_p0["cHiBkGreen"]="102m"
_csiCMD_p0["cHiBkYellow"]="103m"
_csiCMD_p0["cHiBkBlue"]="104m"
_csiCMD_p0["cHiBkMagenta"]="105m"
_csiCMD_p0["cHiBkCyan"]="106m"
_csiCMD_p0["cHiBkWhite"]="107m"

}
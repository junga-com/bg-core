# Library
# provides iniSection, iniParamName, iniValue, and iniLineType variables
# This awk library can be included in an awk script and any script that apears after it can
# rely on a set of ini* variables to be defined while processing each line.
# The default delimiter for settings lines is "=". You can change the delimiter by adding an awk cmd line
# option '-v iniDelim="<delim>"'. A line's first ocurance of iniDelim will separate <iniParamName> and
# iniValue therefore iniParamName can not contain iniDelim but iniValue can.
#
# Input Variables:
#    <iniTargetSection>: a section to focus on. inTarget will be true only when the current line is in this section.
#              "<sectName>"   : <sectName> matches the normalized section name
#              ".", "--", or "" : matches the top section before the first section line
#              "]all"           : matches all sections so that inTarget will always be true
#              "]none"          : matches no sections so that inTarget will always be false
# These variables define the protocol used to read and write the file so that this library can work with a number of variations
#    <paramDelim>  : default is "=". This character is used to separate the iniParamName from the iniValue.
#    <paramPad>    : default is "".  padding to use around <paramDelim> when writing a parameter line. Typically "" or " ".
#                    reading is always tolerant to whitespace around the <paramDelim>
#    <sectPad>     : default is " ". padding to use around <sectName> when writing a section line
#                    reading is always tolerant to whitespace around the <sectName>
#    <quoteMode>=(|single|double|none) : default is "" (empty strin).  when writing a parameter line this determines if quotes will
#                    be written around the value and which kind. if the <value> being written contains a '#' and
#                    <commentsStyle>=="EOL". quotes will be used even if this is set to "" (empty)
#                    quotes are always recognized and removed when reading lines -- not just around the value, but anywhere.
#    <commentsStyle>=(EOL|BEFORE|NONE): default is "EOL". This affects how comments asociated with section and parameters lines are
#                    handled. When writing a section or parameter line, this will determine how the comment is written. When reading
#                    lines, however, this only affects how unquoted '#' are treated. When set to "EOL", an unquoted '#' will begin
#                    the comment even if that means the line is no longer a valid line. This means that if a '#' is in a parmeter
#                    name or value or a section name, quotes must be used around that token.
#                    'EOL'    : When written, the comment will be placed at the end of the line folowing a '#' character.
#                               When reading, unquoted '#' will end the line syntax
#                    'BEFORE' : When written, the comment will be placed on a comment line immediately preceeding the line being written.
#                               When reading, unquoted '#' have no special meaning
#                    'NONE'   : When written, the comment will be ignored and not written to the file.
#                               When reading, unquoted '#' have no special meaning
#
#
# Line State Variables:
# An awk script that includes this library can use these variables in a line block to understand and manipulate the line.
#    <iniSection>      : the section name that the current line is in or empty string, "", if its before the first section header line
#    <iniSectionNorm>  : the section name that the current line is in or "." if its before the first section header line
#    <iniParamFullName>: '[<iniSectionNorm>]<iniParamName>' -- the iniParamName prepended with the normalized section that its in
#    <iniParamName>    : the name of the parameter (using iniDelim to parse) for the current line or empty if current line is not a setting
#    <iniValue>        : the value of the parameter (using iniDelim to parse) for the current line or empty if current line is not a setting
#    <iniLineType>     : the type of line of the current line
#            "comment"    : the first non-whitespace character is a "#".
#            "whitespace" : the line is empty or contains only whitespace
#            "section"    : the line is a section header of the form "[ <sectionName> ]"
#            "setting"    : the line is not any of the other lines. Note that this means that the line might not contain a iniDelim
#    <inTarget>        : true(1) or false(0) indicating if the current line is in the section specified in <iniTargetSection>
#    <iniComment>      : in the current line is a comment, or if another linetype has an EOL comment, this has the content of the comment
#    <iniValueQuoteStyle> : this indicates if the iniValue at this line is quoted and with what kind of quotes. Quotes are removed
#                        from iniValue so this allows us to know if quotes exist in the line


@include "bg_core.awk"

# usage: makeNewSectionLine(sectionName[, comment])
# returns the formatted section line, suitable for writing to an ini file
# Format:
#   '['<sectPad><sectionName><sectPad>']'[ # <comment>]
# Note that the literal '[' ']' are in quotes to distinguish from the [] around the EOL comment that indicate that its optional
# Params:
#    <sectionName> : the name of the section.
#    <comment> : a comment string to put at the end of the section line. If it does not already begin with a '#', one will
#                       be added
# Global Vars:
#    <sectPad> : is used to to determine what padding if any goes around the sectionName. Typically it is "" or " "
#    <commentsStyle> : ignore <comment> even if specified because this file protocol does not support comments
function makeNewSectionLine(sectionName, comment) {
	comment=normalizeComment(comment)
	return "["sectPad""sectionName""sectPad"]"((commentsStyle==EOL)?"":comment)
}

# usage: makeNewSettingLine(name[, value[, comment]])
# returns the formatted setting/parameter line, suitable for writing to an ini file
# Format:
#   <name><paramPad><paramDelim><paramPad><value>[ # <comment>]
# Params:
#    <name> : left hand side of the setting/parameter
#    <value>: right hand side of the setting/parameter
#    <comment> : a comment string to put at the end of the line. If it does not already begin with a '#', one will be added
# Global Vars:
#    <quoteMode> : determines if the value will be surrounded by quotes. If value contains a "#" quotes will be used automatically
#    <paramDelim> : is the delimiter used between the name and value. Typically it is "="
#    <paramPad> : is used to to determine what padding if any goes around name/value delimiter. Typically it is "" or " "
#    <commentsStyle> : ignore <comment> even if specified because this file protocol does not support comments
function makeNewSettingLine(name, value, comment, defaultQuoteStyle                           ,qCh,valueNeedsQuotes) {
	if (quoteMode ~ /^([1']|single)$/) qCh="'"
	if (quoteMode ~ /^([2"]|double)$/) qCh="\""
	if (!quoteMode && value ~ /[#]/) valueNeedsQuotes="needs"
	switch (quoteMode":"valueNeedsQuotes":"defaultQuoteStyle) {
		case /single/: qCh="'"; break
		case /(needs|double)/: qCh="\""; break
	}
	comment=normalizeComment(comment)
	return name""paramPad""paramDelim""paramPad""qCh""value""qCh""((commentsStyle==EOL)?"":comment)
}


# usage: parseINIFileLine(line)
# this parses the input <line> to set a group of global variables starting with ini*. The variables are documented in this
# library's man(7) page.
# See Also:
#    man(7) bg_ini.awk
function parseINIFileLine(line) {
	iniLineType=""
	iniParamName=""
	iniValue=""
	iniValueQuoteStyle=""
	iniParamFullName=""
	iniComment=""
	iniLineType="<error>" # if the parser below fails to set the iniLineType, it will have this value

	parserStartQuotingTokenizer(line, parser, "--parseChars==[]%20")
	parserEatWhitespace(parser)
	if (parserIsDone(parser)) {
		iniLineType="whitespace"
	} else if (parserGet(parser) == "[") {
		parseSectionLine(parser)
	} else if (parserGet(parser) ~ /^#/) {
		iniComment=parserNext(parser)
		iniLineType="comment"
	} else {
		parseSettingLine(parser)
	}
}

# this is called by the line parser if the first non-whitespac token is '['
function parseSectionLine(parser                      ,sectName,commStr) {
	parserNext(parser)
	sectName=parseUpToWithTrim(parser, "^]$")
	if (parserNext(parser) != "]") {
		iniLineType="invalid.section"
		parser["error"]="invalid section line starting with '['. No matching ']'"
		if (verbosity>0) bgtrace("awk ini parse error: "parser["error"])
		if (verbosity>1) warning(parser["error"])
		return(0)
	}
	# commentsStyle only affects settings lines because there does not seem to be a down side to recognizing comments after the section.
	if (parserGet(parser) ~ /^#/)
		commStr=parserNext(parser)

	if (!parserIsDone(parser)) {
		iniLineType="invalid.section"
		parser["error"]="invalid section. extra tokens after closing bracket"
		if (verbosity>0) bgtrace("awk ini parse error: "parser["error"])
		if (verbosity>1) warning(parser["error"])
		return(0)
	}

	iniSection=(sectName==".") ? "" : sectName
	iniSectionNorm=(iniSection=="") ? "." : iniSection
	inTarget=(iniTargetSection==iniSection || iniTargetSection=="]all") ? 1 : ""
	iniComment=commStr
	iniLineType="section"
}

# this is called by the line parser no other line type is recognized.
function parseSettingLine(parser                     ,pName) {
	parserEatWhitespace(parser)
	pName=parseUpToWithTrim(parser, paramDelimRE)
	if (parserNext(parser) !~ paramDelimRE) {
		iniLineType="invalid.setting"
		parser["error"]="invalid setting line. Missing '"paramDelim"'"
		if (verbosity>0) bgtrace("awk ini parse error: "parser["error"])
		if (verbosity>1) warning(parser["error"])
		return(0)
	}
	iniParamName=pName
	iniParamFullName="["iniSectionNorm"]"iniParamName

	# the value is everything up to the '#' or the end of the input (-1) depending on the commentsStyle config.
	iniValueQuoteStyle=parserGetType(parser); if (iniValueQuoteStyle!~/^(single|double|dollar)$/) iniValueQuoteStyle="none"
	iniValue=parseUpToWithTrim(parser, ((commentsStyle=="EOL")?"^#":-1))

	# if commentsStyle is not EOL, any '#' would have been eaten into the value so we dont need to put this in a further condition.
	if (parserGet(parser) ~ /^#/)
		iniComment=parserNext(parser)

	iniLineType="setting"
}

function normalizeComment(comment) {
	if ((comment) && (comment ~ /^\s*[^#]/)) comment=" # "comment
	if ((comment) && (comment !~ /^\s/)) comment=" "comment
	return(comment)
}

function dumpLineState(optionStr                          ,shortVal,shortComm) {
	if (optionStr~/-H/)
		printf("%*s %*s %*s %*s %*s %*s %*s\n",
			  2, "in",
			-16, "iniLineType",
			 -8, "Sect",
			-20, "PName",
			-30, "iniValue",
			-30, "iniComment",
			  0, "sourceLine")
	else {
		shortVal=iniValue
		if (length(shortVal)>30)
			shortVal=substr(shortVal,1,27)"..."
		shortComm=iniComment
		if (length(shortComm)>30)
			shortComm=substr(shortComm,1,27)"..."
		printf("%*s %*s %*s %*s %*s %*s |%*s\n",
			  2, inTarget,
			-16, iniLineType,
			 -8, iniSection,
			-20, iniParamName,
			-30, iniValue,
			-30, shortComm,
			  0, $0)
	}
}

BEGIN {
	# normallize the special values accepted for iniTargetSection
	iniTargetSection=(iniTargetSection=="." || iniTargetSection=="--") ? ("") : (iniTargetSection)

	# make the default verbosity 1
	if (verbosity=="") verbosity=1

	# make EOL the default commentsStyle
	if (!commentsStyle)
		commentsStyle="EOL"

	# make "=" the default paramDelim
	if (paramDelim=="") paramDelim="="

	# we create paramDelimRE because we treat the delimiter " " as being any run of consequtive whitespace
	paramDelimRE="^"((paramDelim==" ")?("\\s+"):(paramDelim))"$"
}

BEGINFILE {
	# we parse an imaginary line at the start of the file that sets the state as being in the top section
	parseINIFileLine("[.]")
}

{
	# parse each new line to set the ini* variables that describe this line
	parseINIFileLine($0)
}

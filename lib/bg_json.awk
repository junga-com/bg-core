@include "bg_core.awk"

function token() {return jtokens[jtokenCur]}
function nextToken() {
	if (jtokenCur <= jtokensCount)
		return jtokens[jtokenCur++]
}
function atEOF() {return jtokenCur > jtokensCount}

function addFlattenValue(jpath, value, valType, relName) {
	if (valType!~"(tArray)|(tObject)") {
		flatData[jpath]=value
		flatDataInd[flatDataCount++]=jpath
		if (! noJpathOutOpt)
			printf("%-24s %s\n", jpath, value)
	}
	valueHook(jpath, gensub(/%22/,"\"","g",value), valType, relName)
}

#function assert(message) {assertHit=1; printf("error: %s\n", message); exit 100}
function assertExpected(expected,actual) {
	if (expected!=actual)
		assert(sprintf("expected token %s but found '%s'", expected,actual))
}
function assertNumber(actual) {
	if (actual!~"[-]*[0-9.][0-9.eE+-]*")
		assert(sprintf("expect a number but found '%s'", actual))
}
function assertString(actual) {
	if (actual!~/^["].*["]$/)
		assert(sprintf("expect a quoted string but found '%s'", actual))
}
function expectToken(type,       value, aCount, baseJPath) {
	#printf("%-13s -at-> %s\n", type, token())
	valType=""
	switch (type) {
		case /[]{},:[]|(null)|(false)|(true)/ :
			value=token()
			assertExpected(type,value)
			nextToken()
			valType=type
			return value

		case "tNumber" :
			value=token()
			assertNumber(value)
			nextToken()
			valType="tNumber"
			return value

		case "tString" :
			value=token()
			assertString(value)
			nextToken()
			gsub(/^["]|["]$/,"", value)
			valType="tString"
			return value

		case "tArray" :
			baseJPath=jpath
			aCount=0
			expectToken(tListStart)
			eventHook("startList", baseJPath)
			while (token()!=tListEnd) {
				jpath=baseJPath"["aCount++"]"
				value=expectToken(tValue)
				addFlattenValue(jpath, value, valType, "<arrayEl>")
				if (token()==tListSep)
					nextToken()
			}
			jpath=baseJPath
			expectToken(tListEnd)
			eventHook("endList", baseJPath)
			valType="tArray"
			return

		case "tObject" :
			baseJPath=jpath
			expectToken(tObjStart)
			eventHook("startObject", baseJPath)
			while (token()!=tObjEnd) {
				name=expectToken(tString)
				# if the name contains '.' it will look like multiple objects in the jpath so we must escape them
				gsub(/[.]/,"%2E", name)
				if (bashObjects) {
					#gsub(/\^/,"%5E", name)
				}
				jpath=baseJPath"."name
				expectToken(tPairSep)
				value=expectToken(tValue)
				addFlattenValue(jpath, value, valType, name)
				if (token()==tListSep)
					nextToken()
			}
			expectToken(tObjEnd)
			eventHook("endObject", baseJPath)
			jpath=baseJPath
			valType="tObject"
			return

		case "tValue" :
			switch (token()) {
				case /^["]/    : return expectToken(tString); break
				case "["       : return expectToken(tArray); break
				case "{"       : return expectToken(tObject); break
				case /[]},:]/  : assertExpected(tValue,token()); break
				default        : return nextToken(); break
			}
			break
	}
}
BEGIN {
	# primitive tokens
	tString="tString"
	tNumber="tNumber"
	tTrue="true"
	tFalse="false"
	tNull="null"
	tPairSep=":"
	tListSep=","
	tObjStart="{"
	tObjEnd="}"
	tListStart="["
	tListEnd="]"

	# composite constructs
	tValue="tValue"
	tObject="tObject"
	tArray="tArray"

	split(topNamesStr,topNames)
}
{
	# collect the input in one big string because there is no guarantee that a construct wont span lines which will mess up the regex
	jdata=jdata""$0

	# Note on handling linefeeds in string data:
	# well formed json data requires linefeeds in strings to be escaped so conctenating the lines does not change the data.
	# however, this algorithm could support it but we dont because its not the standard. If we need to we could create a magic
	# token (e.g. __%0A__), add it bettween the lines we concatenate here, add it to the start of the regex (/__%0A__|...),
	# update the parser to silently pass them when they are a token by themsleves, and finally, search and replace in the strings.
}
END {
	# insert a line feed after each token and split jdata into a token array using \n as the delimiter
	gsub(/["][^[:cntrl:]"\\]*((\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})[^[:cntrl:]"\\]*)*["]|-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?|null|false|true|[[:space:]]+|./,
		"&\n",
		 jdata)
	gsub("[\n[:space:]]*\n[\n[:space:]]*", "\n", jdata)
	#bgtrace( jdata)
	jtokensCount = split(jdata, jtokens, "\n")
	jtokenCur=1
	jtokensCount-- # the last token is an empty line

	# the json data should consists of one value but it there are multiple tValues, read them into
	# different top<N> variables
	topCount=1
	flatDataCount=0

	for (i in topNames) {
		topName=jpath=topNames[i]
		value=expectToken(tValue)
		addFlattenValue(jpath, value, valType, topName)
	}


	# if there is more stream to read, assign each additional tValue to "top", "top1",..."topN"
	# until the stream is empty or jsonValuesReadCount has been read
	jpath="top"
	while (jsonValuesReadCount-- > 0 && ! atEOF()) {
		topName=jpath
		value=expectToken(tValue)
		addFlattenValue(jpath, value, valType, topName)
		jpath="top"topCount++
	}
}

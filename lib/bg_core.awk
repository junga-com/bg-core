@load "filefuncs"

#################################################################################################################################
### bg-core system functions

function manifestGetFile(                      manFile) {
	manFile=ENVIRON["bgVinstalledManifest"]
	return (manFile) ? manFile : "/var/lib/bg-core/manifest";
}

function manifestGet(assetTypeMatch, assetNameMatch, array                    ,manFile,cmd,script,asset) {
	manFile=manifestGetFile()
	assetTypeMatch="^" gensub(/^\^/,"","g",assetTypeMatch)
	assetNameMatch="^" gensub(/^\^/,"","g",assetNameMatch)
	script="$2~/"assetTypeMatch"/ && $3~/"assetNameMatch"/ {print $4}"
	cmd="awk '"script"' "manFile
	arrayCreate(array)
	while ((cmd | getline asset) >0) {
		arrayPush(array,asset)
	}
	close(cmd)
}

# TODO: change to use splitOptions() function
function templateFind(templateName, options                      ,manFile,templatePath,cmd) {
	manFile=manifestGetFile()
	while ((getline < manFile) >0) {
		if ($2=="template" && $3 == templateName) {
			templatePath = $4
			if ($1 == options["pkg"] || $1 == options["pkgOverride"])
				break;
		}
	}

	if (!templatePath) {
		cmd = "bg-core templates find " templateName
		cmd | getline templatePath
		close(cmd)
	}

	return templatePath
}

#################################################################################################################################
### Misc functions

# usage: hardExit(exitCode)
# wrapper over exit that will skip END sections. The builtin awk exit passes control to each END section before actually exiting.
# hardExit will exit without the END sections from running
# if called from an END section, hardExit is the same as exit.
function hardExit(exitCode) {
	_hardExit=exitCode
	if (_hardExit == "") _hardExit="0"
	exit _hardExit
}
# note that this END sections needs to be included early because END sections included before it will get executed after hardExit
END {if (_hardExit != "") exit _hardExit}

function max(a,b) {return (a>b)?a:b}
function min(a,b) {return (a<b)?a:b}
function abs(x)   {return (x>0)?x:-x}
# returns a value with the sign of a and the absolute value of the max(abs(a),abs(b))
function absmax(a,b     ,tmp) {tmp=max(abs(a),abs(b)); if (a!=0) return tmp*(a/abs(a)); return abs(tmp)}

function noop(p1,p2,p3,p4,p5,p6,p7,p8,p9,p10) {}

# usage: queueFileToScan(file1,where)
# add file1 to the list of input files that will be processed. 'where' determines if the file will be queued to be processed next
# or after any other input file in the queue.
# The input queue is the cmdline parameters ARGV/ARGC.  ARGIND is the index into ARGV of the input file currently being processed
# Params:
#    file1: the complete (relative or abs) path to the file
#    where: determines where file will be queued relative to other files in the input queue
#       empty(false) : (default) the file will be queued last, after files that are in the queue.
#       'next'(true) : it will be queues next, before the other files that have not yet begun processing.
function queueFileToScan(file1,where                 ,i) {
	if (where) {
		for (i=ARGC; i>ARGIND; i--)
			ARGV[i]=ARGV[i-1]
		ARGC++
		ARGV[ARGIND+1]=file1

	} else {
		ARGV[ARGC++]=file1
	}
}

# usage: queueFilesToScan(fileSpec,where)
# same as queueFileToScan (singlular) except fileSpec can be a multivalued list and each elemetn can contain wildcards
# See Also:
#    queueFileToScan
function queueFilesToScan(fileSpec,where             ,i,pathlist,addCount,insertInd) {
	fsExpandFiles(fileSpec, pathlist)
	addCount=length(pathlist)
	if (where) {
		for (i=ARGC; i>ARGIND; i--)
			ARGV[i+addCount]=ARGV[i-1]
		ARGC+=addCount
		insertInd=ARGIND
		for (i in pathlist)
			ARGV[++insertInd]=pathlist[i]

	} else {
		for (i in pathlist)
			ARGV[ARGC++]=pathlist[i]
	}
}


#################################################################################################################################
### Output functions

# usage: printfVars("<varName1>|<opt1> [...<varNameN>|<optN>]"                ,optionsStr)
# TODO: change to use splitOptions() function
# The input is a string of space separated global variable names and optional parameters that start with '-'
# This prints the listed awk global vars in a reasonable format.
# Note that you must use printfVars2 to print local function variables. printfVars2 works with global variobles also but the trade
# off is that printfVars allows a list of variables in one call but printfVars2 requires one call per variable.
# Params:
#    varNameN   : the name of a global awk variable to be displayed
#    optionsStr : a string of optional args that affect how subsequent varNames are printed. Note that options can be included
#                 among the varNames and effect only varNames from that point on.
# Options:
#    -l<str> : literal. write <str> to the output instead of interpreting it as a global varName
#    -o<filename> : redirect output to <filename>
#    -w<n>   : pad subsequent <varNames> to <n> characters
#
# See Also:
#    printfVars2 : print only one var at a time but works with local and netsted arrays that this function does not work with
#    (bash)printfVars : similar bash function
function printfVars(varNameListStr            ,optionsStr,level, varNameList, i,options,outFile) {
	level=0
	outFile="/dev/stderr"
	# TODO: change to use splitOptions() function
	spliti(optionsStr, options)
	lineEnd="\n"; if ("-1" in options) lineEnd=" "
	split(varNameListStr, varNameList)
	for (i in varNameList) {
		switch (varNameList[i]) {
			case /^-l/:
				gsub("%20"," ",varNameList[i])
				printf("%s ", substr(varNameList[i], 3))
				if (optionsStr !~ /-1/) printf("\n")
				break
			case /^-o/:
				outFile=substr(varNameList[i], 3)
				optionsStr=varNameList[i]" "optionsStr
				break
			case /^-/: optionsStr=optionsStr" "varNameList[i]; break
			default:
				if (varNameList[i] in SYMTAB) {
					printfVars2(level, varNameList[i], SYMTAB[varNameList[i]], optionsStr)
				}else{
					printf("%*s%s=<localVar-use-printfVars2()>"lineEnd, level*3, "", varNameList[i]) >> outFile
				}
		}
	}
	if (optionsStr ~ /-1/) printf("\n")
}

# usage: printfVars2(level, varName, varValue, optionsStr)
# TODO: change to use splitOptions() function
# This is an alternate form of printfVars that allows descending nested arrays of arrays and printing local variables but only
# accepts one variable with the name and value passed separately to print instead of a string list.
# printfVars is implemented with this function.
# Params:
#    level      : the indentation level. level*3 spaces will be printed before each line
#    varName    : the name to be displayed as the label for the variable being printed
#    varValue   : the value to be displayed for the variable being printed
#    optionsStr : a string of optional args
# See Also:
#    printfVars : print multiple vars at a time but only works with globals
#    (bash)printfVars : similar bash function
function printfVars2(level, varName, varValue, optionsStr,      i,optToken,options,lineEnd,maxWidth,outFile) {
	outFile="/dev/stderr"
	maxWidth=0
	if (match(varName,/(.*) (.*)$/, options)) {
		optionsStr=options[1]" "optionsStr
		varName=options[2]
	}
	# TODO: change to use splitOptions() function
	spliti(optionsStr, options)
	lineEnd="\n"; if ("-1" in options) lineEnd=" "
	for (optToken in options) switch (optToken) {
		case /^-w/:
			maxWidth=substr(optToken,3)
			break
		case /^-o/:
			outFile=substr(optToken, 3)
			break
	}
	sub("-w[0-9]*","",optionsStr)

	if (!isarray(varValue)) {
		if ("--brackets" in options)
			printf("%*s[%-*s]='%s'"lineEnd, level*3, "", maxWidth,varName, varValue) >> outFile
		else
			printf("%*s%-*s='%s'"lineEnd, level*3, "", maxWidth,varName, varValue) >> outFile
	} else {
		printf("%*s%s=<array>"lineEnd, level*3, "", varName) >> outFile

		maxWidth=0; for (i in varValue) maxWidth=max(maxWidth,length(i))

		for (i in varValue) if (!isarray(varValue[i]))
			printfVars2(level+1, i, varValue[i], "-w"maxWidth" --brackets "optionsStr)
		for (i in varValue) if (isarray(varValue[i]))
			printfVars2(level+1, i, varValue[i], "-w"maxWidth" --brackets "optionsStr)
	}
}



#################################################################################################################################
### Array functions

# usage: arrayPush(array, element)
# add <element> to the end of <array>
function arrayPush(array, element) {
	array[length(array)+1]=element
}

# usage: arrayPushArray(array)
# add a new,  empty array element to the end of <array>
function arrayPushArray(array, key, value                ,idx) {
	idx=length(array)+1
	if (key=="") {
		array[idx][1]=""
		split("", array[idx])
	} else {
		array[idx][key]=value
	}
	return(idx)
}

# usage: arrayPop(array)
# remove and return the last element from the end of <array>
function arrayPop(array                      , element) {
	element=array[length(array)]
	delete array[length(array)]
	return element
}

# usage: arrayShift(array)
# remove and return the first element from the start of <array>
function arrayShift(array                      , element, i,startLength) {
	startLength=length(array);
	element=array[1];
	for (i=1; i<length(array); i++)
		array[i]=array[i+1];
	delete array[length(array)]
	if (startLength-1 != length(array)) {
		printfVars2(0,"array after shift", array)
		assert("arrayShift: this function is only valid for packed numeric indexed arrays. startLength='"startLength"'   endLength='"length(array)"'")
	}
	return element
}

function arrayIndexOf(array, element           , i) {
	for (i=0; i<length(array); i++)
		if (element == array[i])
			return i
	return -1
}

# usage: arrayCopy(source, dest)
# copy the contents of one array var into another
# Return Value:
#   <count>  : the number of elements copied including in sub-arrays
function arrayCopy(source, dest,         i, count)
{
	delete dest
	for (i in source) {
		if (isarray(source[i])) {
			dest[i][1]=""
			count += arrayCopy(source[i], dest[i])
		} else {
			dest[i] = source[i]
			count++
		}
	}
	return count
}

# usage: arrayCopy2(source, destArray, destIndexName)
# this is a wrapper over arrayCopy that allows the destination to be an array in an array element.
# If you pass destArray[destIndexName] into arrayCopy, awk creates that element as a scalar that can not be converted to an array
# Return Value:
#   <count>  : the number of elements copied including in sub-arrays
function arrayCopy2(source, destArray, destIndexName,   i, count)
{
	split2("", destArray, destIndexName)
	arrayCopy(source, destArray[destIndexName])
}


# usage: arrayCreate(array)
# makes an array
# wrapper over the awk idiom split("", array) that is more readable
function arrayCreate(array) {
	split("", array)
}

# usage: arrayCreate2(array, elName)
# makes an array at array[elName]
# wrapper over the awk idiom split("", array) that works with arrays of arrays
function arrayCreate2(array, elName) {
	array[elName][1]=""
	split("", array[elName])
}

# MAN(3) split
# usage: spliti(str, array, [delim])
# Like split but puts the tokens in the indexes of array instead of the values
function spliti(str, array, delim    ,tmp,i,count) {
	if (!delim) delim=FS
	delete array
	count=split(str, tmp, delim)
	for (i in tmp)
		array[tmp[i]]=""
	return count
}

# MAN(3) split
# usage: spliti2(str, array, elName, [delim])
# Like spliti but puts the tokens in the indexes of array instead of the values
function spliti2(str, array, elName, delim    ,tmp,i) {
	if (!delim) delim=FS
	array[elName][1]=""
	return spliti(str, array[elName], delim)
}

# MAN(3) split
# usage: split2(str, array, elName, [delim])
# Like split but works to assign new,untyped sub-arrays elements which split can not do
function split2(str, array, elName, delim) {
	if (!delim) delim=FS
	array[elName][1]=""
	return split(str, array[elName], delim)
}

# usage: arrayJoin(array,sep)
# convert the <array> into a string by concatenating its elements separated by the string <sep>
function arrayJoin(array,sep) {
	return join(array,sep)
}

# usage: arrayJoini(array,sep)
# the same as arrayJoin but joins the indexes of <array> instead of its element values
function arrayJoini(array,sep) {
	return joini(array,sep)
}



#################################################################################################################################
### Debug functions

function bgtraceIsActive() {
	if (! ENVIRON["bgTracingOn"])
		return 0
	else if (ENVIRON["bgTracingOn"]~"^(file|on):") {
		_bgtraceFile=ENVIRON["bgTracingOn"]; sub("^(file|on):","",_bgtraceFile);  sub("^win$","",_bgtraceFile)

		_bgtraceFile=((_bgtraceFile)?_bgtraceFile:"/tmp/bgtrace.out")
	} else
		_bgtraceFile="/dev/stderr"
	return 1
}
function bgtrace(s) {
	if (!bgtraceIsActive()) return
	printf("%s\n",s) >> _bgtraceFile
	fflush(_bgtraceFile)
}
function bgtraceVars(s) {
	if (!bgtraceIsActive()) return
	printfVars("-o"_bgtraceFile" "s)
	fflush(_bgtraceFile)
}
# TODO: change to use splitOptions() function
function bgtraceVars2(level, varName, varValue, optionsStr                                     ,i) {
	if (!bgtraceIsActive()) return
	printfVars2(level, varName, varValue, optionsStr" -o"_bgtraceFile)
	fflush(_bgtraceFile)
}
function assert(msg                 ,outStr) {
	_fnName=_FILENAME; if (_fnName=="") _fnName=FILENAME
	_fnLine=_INDESC;   if (_fnLine=="") _fnLine=FNR
	_fnLineTxt=$0;     if (_INDESC~"((BEGIN)|(END))") _fnLineTxt="N/A"
	outStr=sprintf("awk assert error (%s) : %s\n   inputFile= %s : %s\n   input line= '%s'\n\n", scriptName, msg, _fnName, _fnLine, _fnLineTxt )
	print(outStr) > "/dev/stderr"
	bgtrace(outStr)
	hardExit(222)
}
function warning(msg, verbose       ,i,_fnName, _fnLine, _fnLineTxt,  outStr) {
	if (verbose) {
		_fnName=_FILENAME; if (_fnName=="") _fnName=FILENAME; gsub("^.*/","", _fnName)
		if (_fnName == "-") _fnName="stdin"
		_fnLine=_INDESC;   if (_fnLine=="") _fnLine=FNR
		_fnLineTxt=$0;     if (_INDESC~"((BEGIN)|(END))") _fnLineTxt="N/A"
		if (!scriptName) scriptName="<unknown>"
		outStr=sprintf("awk warning (%s) : %s\n   %s(%s): '%s'\n", scriptName, msg, _fnName, _fnLine, _fnLineTxt )
	} else {
		outStr=sprintf("awk warning : %s", msg)
	}
	print(outStr) > "/dev/stderr"
	bgtrace(outStr)
}
BEGIN {
	_INDESC="BEGIN"
}
{_INDESC=NR}
END {_INDESC="END"}

function dumpPatsplit(parts,seps) {
	printf("leading sep = |%s|\n", seps[0])
	for (i=1; i<=length(parts); i++)
		printf("  [%2s] %-30s |%s|\n", i, "|""parts[i]""|", "seps[i]")
}


#################################################################################################################################
### String functions

function strpad(str, len) {
	return sprintf("%s%*s", str, max(0,len-length(str)), "")
}

function appendStr(str,strToAdd,sep) {
	if (!sep) sep=","
	if (!str) sep=""
	return str sep strToAdd
}

# usage: join(array,sep)
# convert the <array> into a string by concatenating its elements separated by the string <sep>
function join(array,sep,           i,wsep,result) {
	if (!sep) sep=","
	wsep=""; result=""
	for (i in array) {
		result=result wsep array[i]
		wsep=sep
	}
	return result
}


# usage: joini(array,sep)
# the same as join but use the indexes of <array> instead of its element values
function joini(array,sep,           i,wsep,result) {
	if (!sep) sep=","
	wsep=""; result=""
	for (i in array) {
		result=result wsep i
		wsep=sep
	}
	return result
}

function strExtract(s, leadingRegEx, trailingRegEx) {
	sub(leadingRegEx,"",s)
	sub(trailingRegEx,"",s)
	return s
}

# usage: splitOptions(optStrOrArray, optionsOut)
# This is the latest (circa 2020-02) standard for passing options in awk function.
# Options can be passed in either as a string like "-fdata.txt --file=data.txt" or as an array where the option (-f --file) is the
# key and the argument if any is the value.
function splitOptions(optionsAryOrStr, options                    ,parts,i,rematch) {
	arrayCreate(options)
	if (!isarray(optionsAryOrStr)) {
		split(optionsAryOrStr, parts)
		for (i in parts) {
			gsub(/%20/," ", parts[i])
			if (match(parts[i], /^(-[^-])(.*)$/, rematch))
				options[rematch[1]]=rematch[2]
			else if (match(parts[i], /^(--[^=]*)(=(.*))?$/, rematch))
				options[rematch[1]]=rematch[3]
			else
				options[parts[i]]=""
		}
	} else {
		arrayCopy(optionsAryOrStr, options)
	}
}


#################################################################################################################################
### Newer Parsing functions.

# usage: parserStartQuotingTokenizer(line, parser,optionsAryOrStr)
# This creates a parser object to parse the input line. It completes a lexical operation that creates an array of lexical tokens
# and returns the parser array object ready to perform semantic iteration over those tokens.
#
# Lexical Tokenization:
# It performs a lexical tokenization of the input <line> by using the awk patsplit function. It uses a builtin regex express that
# can be modified with the --parseChars and --parseWords options. By default it follows these rules.
#      * "..."  double quoted strings (following bash rules) are returned as one token
#      * '...'  single quoted strings (following bash rules) are returned as one token
#      * $'...' quoted strings (following bash rules) are returned as one token
#      * EOL comments (following bash rules) are returned as one token
#      * sequences of whitespace are returned as one token
#      * sequences of characters that do not match any of the above are returned as one token.
# The --parserChar="<listOfChars>|minimal|all" modifies the above behavior. The 3 string types and EOL comments are always done
# but the tokenization of unquoted sequences before any unquoted # can be controled.
#    minimal  : this suppresses breaking tokens on whitespace.
#    all      : this adds all (is it all?) non alpha-numeric characters as break characters
#    <listOfChars> : a custom list of characters to use as break characters. Including a single space causes runs of whitespace to
#               be one token. Note that a space can not be passed as in the value to optionsAryOrStr as a string but you can use
#               %20 to indicate a space.
# Note that the default value and 'all' will result in a non-computed awk regex being used which may be more performant so its possible
# that better performance would be attained by using "all" and dealing with the extra tokens in the semantic parsing step.
#
# Semanitic Parsing:
# When the function returns, the <parser> array object is ready to iterate over the lexical tokens. The parse* functions can be used
# implement the specific semantics of the parser.
# Here is an example from bg_ini.awk. This is just the top level. The helper functions parseSectionLine and parseSettingLine parse
# those types of lines further.
#    parserStartQuotingTokenizer(line, parser, "--parseChars==[]")
#    parserEatWhitespace(parser)
#    if (parserIsDone(parser)) {
#       iniLineType="whitespace"
#    } else if (parserGet(parser) == "[") {
#       parseSectionLine(parser)
#    } else if (parserGet(parser) ~ /^#/) {
#       iniComment=parserNext(parser)
#       iniLineType="comment"
#    } else {
#       parseSettingLine(parser)
#    }
#
# The Returned Parser Object:
# The <parser> parameter passed in must be either unitialized or an array. It will be cleared and filled in with the lexical state
# of the input <line>. There are a number of functions that start with parse* that operate on the parser object. Typically, you
# only need to use those functions and do not need to reference the array element (aka member variables) of the <parser> array object.
# Member variables.  (aka array elements of the <parser> object)
#     ["len"]     : the number of lexical tokens in the "tokens" array. Note that the real array may have some junk left over past
#                   ["len"] so its important to use this var and not the length() function on ["tokens"]
#     ["tokens"]  : an array containing the lexical tokens that make of the input <line>
#     ["types"]   : an array containing the type name of each coresponding ["tokens"] element.
#                   'double'  : the token is a double quoted string ("..."). The quotes are removed from the token
#                   'single'  : the token is a single quoted string ('...'). The quotes are removed from the token
#                   'dollar'  : the token is a $'' quoted string ($'...'). The quotes are removed from the token
#                   'comment' : the token is an EOL comment string. the first character is always '#'
#      ["idx"]    : the index of the current token. parserGet() will return the token this points to.
# Methods. (aka functions that take a <parser> object as their first argument)
#      parserIsDone(<parser>)    : returns true if there are no more lexicl tokens to consume.
#      parserGet(<parser>)       : returns the current token being considered by the semanitic parsing algorithm
#      parserNext(<parser>)      : return the same token that parserGet would and also advances the idx pointer to the next
#                                  non-whitespace token.
#      parserPeek(<parser>)      : returns the next token or -1 if the current token is the last.
#      parserEatWhitespace(<parser>) : if the current token is whitespace, advances idx to the first non-whitespace token
#      parseUpToWithTrim(<parser>, <targetRE>) : returns the concatonated string from current to the first token after current that
#                                 matches the <targetRE> regexp. The matched token is not consumed. It is not present in the returned
#                                 string and current is left pointing at that token. If no matching token is found, all the remaining
#                                 tokens are consumed and current is left pointing at -1 which is the end and parserIsDone will
#                                 return true in that case.  If the last token before the matched token is whitespace, it is consumed
#                                 but not added to the returned string.
#
# Params:
#    <line>       : the input line to parse
#    <parser>     : an array variable that will be reset and filled in with the tokens produced by lexical breakup, ready for
#                   semantic parsing.
# Options:
# See splitOptions for details of passing options.
#    --parseChars=<chars>|all|default|minimal : See the "Lexical Tokenization" section for details.
function parserStartQuotingTokenizer(line, parser,optionsAryOrStr                    ,options,idxOut,idxIn,state) {
	splitOptions(optionsAryOrStr, options)
	arrayCreate(parser)
	arrayCreate2(parser,"tokens")
	arrayCreate2(parser,"types")
	arrayCreate2(parser,"seps")
	parser["line"]=line

	# process the --parseChars option.
	if (options["--parseChars"]=="") options["--parseChars"]="default"
	if (options["--parseChars"]=="minimal") options["--parseChars"]=""
	if (options["--parseChars"]!~ /^(default|all)$/) {
		# we allow the user to specify the characters in any order, but the [..] RE syntax is very particular as to where a '[',']'
		# or '-' can be placed so that they do not have special meaning. Also, we have to make sure our mandatory break characters
		# are in the set and not in the wrong place.
		options["--parseChars"]=options["--parseChars"]"'\"#\\\\"
		if (options["--parseChars"]~/[[]/) options["--parseChars"]=gensub(/[[]/,"","g",options["--parseChars"])"["
		if (options["--parseChars"]~/[-]/) options["--parseChars"]=gensub(/[-]/,"","g",options["--parseChars"])"-"
		if (options["--parseChars"]~/[]]/) options["--parseChars"]="]"gensub(/[]]/,"","g",options["--parseChars"])
	}
	parser["parseChars"]=options["--parseChars"]

	# this splits the input into anithing that might be a quoted string start or end and the runs inbetween
	switch (options["--parseChars"]) {
		case "default": parser["len"]=patsplit(line, parser["tokens"], /(['"#\\ ])|([^'"#\\ ]*)|(\s+)|([$]')|(\\")|(\\')/, parser["seps"]); break
		case "all":     parser["len"]=patsplit(line, parser["tokens"], /([]'"#\\|&;()<>=+{}:/,`!@$%^*~?.[:space:][-])|([^]'"#\\|&;()<>=+{}:/,`!@$%^*~?.[:space:][-]*)|(\s+)|([$]')|(\\")|(\\')/, parser["seps"]); break
		default:        parser["len"]=patsplit(line, parser["tokens"], "(["options["--parseChars"]"])|([^"options["--parseChars"]"]*)|(\\s+)|([$]')|(\\\\\")|(\\\\')", parser["seps"]); break
	}

	# this loop contracts the tokens in place. The idxOut will always be <= idxIn when we do an assignment so we will never overwrite
	# something that we have not yet considered and copied. As we join quouted string tokens, idxIn will get ahead of idxOut. We are
	# done when idxIn goes past the original length. idxOut at the end will be the new length of the token array
	idxOut=0 # this will be the last token in the output
	idxIn=1  # this will be the next token to test. This advance faster than idxOut as we concatonate tokens
	state="unquoted"
	while (idxIn<=parser["len"]) {
		#if (parser["seps"][idx-1]) warning("parser regex error. There should be no tokens not matched by an alternation term. unmatche token='"parser["seps"][idx-1]"'")
		#bgtrace(sprintf("  [%2s/%2s] %-10s %-13s %s", idxOut, idxIn, "("state")", "("parser["tokens"][idxIn]")", "|"parser["tokens"][idxOut]"|" ))
		switch (state" "parser["tokens"][idxIn]) {
			# starting the three different types of quoted bash strings
			case "unquoted $'": #'
				parser["openningQuote"]=parser["tokens"][idxIn++]
				parser["tokens"][++idxOut]=""
				state="dollar"
				parser["types"][idxOut]=state
			break;
			case "unquoted \"":
				parser["openningQuote"]=parser["tokens"][idxIn++]
				parser["tokens"][++idxOut]=""
				state="double"
				parser["types"][idxOut]=state
			break;
			case "unquoted '":
				parser["openningQuote"]=parser["tokens"][idxIn++]
				parser["tokens"][++idxOut]=""
				state="single"
				parser["types"][idxOut]=state
			break;
			case "unquoted #":
				parser["tokens"][++idxOut]="#"
				idxIn++
				state="comment"
				parser["types"][idxOut]=state
			break;

			# ending any type of string and going back to unquoted state
			# note that single ends with a ' or a \' because \ is not special inside single quotes
			case "double \"":
			case "dollar '":
			case "single '":
			case "single \\'":
				idxIn++
				state="unquoted"
			break

			# inside a double quoted string, \" gets changed to "
			case "double \\\"":
				parser["tokens"][idxOut]=parser["tokens"][idxOut]"\""
				idxIn++
			break

			# escaped ", ', and \ prevents them from starting a string or \ escaping the next char
			case "unquoted \\\"":
			case "unquoted \\'":
			case "unquoted \\\\":
				parser["tokens"][++idxOut]=substr(parser["tokens"][idxIn++], 2, 1)
			break

			# outside of any type of string, we just move the next idxIn token into the next idxOut spot.
			# note that in the fist run of unquoted tokens, this assignment is copying the same element into itself which is not
			# neccesary but does no harm.
			case /unquoted.*/:
				parser["tokens"][++idxOut]=parser["tokens"][idxIn++]
			break

			# inside any of the string types, we concatonate the current idxIn token into the current idxOut token
			default:
				parser["tokens"][idxOut]=parser["tokens"][idxOut]""parser["tokens"][idxIn++]
			break
		}
	}

	if (state == "unquoted" || state == "comment")
		state="wellformed"
	else {
		parser["tokens"][idxOut]=parser["openningQuote"]""parser["tokens"][idxOut]
		state="unterminated."state"String"
	}

	parser["quotedStringState"]=state
	parser["idx"]=1
	parser["len"]=idxOut
}

# OBSOLETE: replaced by parserStartQuotingTokenizer. This version uses the patsplit regex to group quoted strings into tokens, ignoring
#           the special meaning of characters within the string, It comes very close, but ultimately can not parse these lines correctly,
#           with the same code.  The problem is that regex cant treat \' differently than ' WRT determining where to end the string.
#           Double quotes have a similar problem which can be solved by replacing \" with %5C%22 and then replacing it back afterwards,
#           but since $'' and '' treat \' differently and we cant selelectively replace only the one inside $'' differently than those
#           inside '', the same trick does not seem to be workable. parserStartQuotingTokenizer avoids the problem by not trying to
#           group strings with the regex but instead breaking apart on all characters and tokens that might be the start or stop
#           of a string and then combining them after the fact.
#               foo=$'bob\'s #delemia'
#               foo='bob'\''s #delemia'
# usage: parserStartBashStyleTokenizer(inputLine, outArray)
# breaks <inputLine> into tokens which are returned in <outArray>
# Whitespace delimits tokens.
function parserStartBashStyleTokenizer(line,parser,optionsAryOrStr                           ,options,out,i,j,parts,unparts,seps,count,len,first,last,state) {
	splitOptions(optionsAryOrStr, options)
	arrayCreate(out)

	# the regex is good at reconizing quoted strings so that the data inside wont be parsed, except for the convention that a double
	# quote can be escaped inside a double quoted string by putting a '\' in front of it. So we escape that another way by replacing
	# '\"' with its %<hex> equivalent and them replacing them back in the token array.
	# We dont know at this point if the things we replace are inside a quoted string or not, so we also modify the regex to treat
	# %5C and %22 as tokens to split on.
	gsub(/\\\\"/,"%5C%5C\"",line) # we cant mistake \\" for an escaped double quote.
	gsub(/\\"/,"%5C%22",line)
	gsub(/%5C%5C"/,"\\\\\"",line) # we arent really interested in this case, so put it back now

	# even though \' has no special menaning in single quoted strings, it does in $'...' strings.
	# this is problematic because I see no way of recognizing in the regex that 'bla.. \' should end at \' but $'bla.. \' bla..' should not
	# 'bla.. \' this and that      ### $'bla.. \' bla..' this and that
	# 'bla.. 'MKR'  this and that   ### $'bla.. 'MKR' bla..' this and that
	# 'bla.. 'MKR'  this and that   ### $'bla.. 'MKR' bla..' this and that
	# <------><-><><--><   |
	gsub(/\\\\'/,"%5C%5C'",line) # if two '\' preceed the '"', we cant mistake it for an escaped double quote.
	gsub(/\\"/,"%5C%27",line)
	gsub(/%5C%5C'/,"\\\\'",line) # we arent really interested in this case, so put it back now

	# this regex should match everything. If it does not, the unmatched token will end up in a seps entry which is an error.
	# When I iterated seps to assert it was empty, I hit a very strange bug that would produce an ininite loop so its not checking
	# We use /<regex>/ style expresssions even though we have to conditionally choose them because we want the efficiency of it being compliled
	if ("--no-eolComments" in options)
		count=patsplit(line, out, /([a-zA-Z_][a-zA-Z0-9_]*)|([+-]?[0-9]+)|('[^']+')|(')|('[^']*$)|("[^"]+")|(")|("[^"]*$)|(\s+)|([|&;()<>])|([]=#+{}:/,`!@$%^*~?\\.[-])|(%5C)|(%22)|(%27)|([#].*$)/, seps)
		#                               <varname>           numbers        sQStr     sQ  unTermSQ  dQStr     dQ  unTermDQ  spces  metaChar       brCh                    escd\"'          EOLComm
	else
		count=patsplit(line, out, /([a-zA-Z_][a-zA-Z0-9_]*)|([+-]?[0-9]+)|('[^']+')|(')|('[^']*$)|("[^"]+")|(")|("[^"]*$)|(\s+)|([|&;()<>])|([]=#+{}:/,`!@$%^*~?\\.[-])|(%5C)|(%22)|(%27)/, seps)
		#                               <varname>           numbers        sQStr     sQ  unTermSQ  dQStr     dQ  unTermDQ  spces  metaChar       brCh                    escd\"'

	for (i=1; i<=length(out); i++) {
		# we dont have to decide
		gsub(/%5C%27/,"\\'",out[i])

		# double quoted strings
		if (out[i] ~ /^"[^"]*"$/) {
			out[i]=substr(out[i], 2, length(out[i])-2)
			# since we processed the special meaning of \" inside double quotes, remove the leading \ when we convert the " back
			gsub(/%5C%22/,"\"",out[i])

			# inside a double quote, `man bash` says that \ has special meaning when followed by $, `, ", \, or <newline>
			# we dont remove the leading \ from those other chars besides " because we did not preform the functions that make
			# those other chars special. If in a latter step some code does, it will need the \ to know that that char is not special
			# to it.

		# put back the escaped '\' and '"' that were not inside quoted strings so were separated into separate tokens
		} else if (out[i] == "%5C") {
			out[i]="\\"
		} else if (out[i] == "%22") {
			out[i]="\""
		# anywhere else where %5C%22 stayed together, put them back to \" . That sequence in these token dont have meaning at this
		# point but might latter when those tokens are processed.
		} else {
			gsub(/%5C%22/,"\\\"",out[i])
		}

		# $'...' quoted strings
		if (out[i] ~ /^[$]'[^']*'$/) {
			out[i]=substr(out[i], 2, length(out[i])-2)
			# in single quotes these sequences have no special meaning so put them back as they were
			gsub(/%5C%22/,"\"",out[i])
			gsub(/%5C%5C/,"\\",out[i])
		# other tokens
		} else {
			gsub(/%5C%22/,"\"",out[i])
			gsub(/%5C%5C/,"\\",out[i])
		}
	}

	parserCreate(out, parser)
	arrayCreate2(parser,"seps")
	arrayCopy(seps, parser["seps"])

	#dumpPatsplit(out,seps)
}

function parserDump(parser                          ,i) {
	#dumpPatsplit(parser["tokens"],parser["seps"])
	printf("len=%s\n", parser["len"])
	for (i=1; i<=parser["len"]; i++) {
		printf("%2s[%2s] |%s|\n", ((i==parser["idx"])?"->":""), i, parser["tokens"][i])
	}
}

function parserCreate(inputArray, parserArray) {
	arrayCreate(parserArray)
	arrayCreate2(parserArray,"tokens")
	parserArray["len"]=arrayCopy(inputArray, parserArray["tokens"])
	parserArray["idx"]=1
}


# return the token that idx currently points at
function parserGet(parser) {
	if (parser["idx"]>parser["len"])
		return(-1)
	return(parser["tokens"][parser["idx"]])
}


# return the type of the token that idx currently points at
function parserGetType(parser) {
	if (parser["idx"]>parser["len"])
		return("")
	return(parser["types"][parser["idx"]])
}

# peek ahead to see the value of the next token. Returns -1 if at the end.
function parserPeek(parser) {
	return( (parser["idx"]<parser["len"]) ? parser["tokens"][parser["idx"]+1] : -1 )
}

# return the current token and advance idx to the next non-whitespace token
function parserNext(parser                ,current) {
	if (parser["idx"]>parser["len"])
		return(-1)

	current=parser["tokens"][parser["idx"]]
	parser["idx"]++

	# eat whitespace
	while (parser["idx"]<=parser["len"] && parser["tokens"][parser["idx"]]~/^\s*$/)
	 	parser["idx"]++

	return( current )
}

# if current is whitespace, advance to the next non-whitespace token
function parserEatWhitespace(parser) {
	while (parser["idx"]<=parser["len"] && parser["tokens"][parser["idx"]]~/^\s*$/)
		parser["idx"]++
}

# true if either current is the end token or NOT equal to <target>
function parserIsDone(parser) {
	return(parser["idx"]>parser["len"])
}

# return the result of concatonating the current token with the following tokens up to the token before the first that <targetRE>
# matches. The token matching <targetRE> is not consumed and not present in the returned value. The current token is left pointing
# at the token that matches <targetRE>. If no tokens match <targetRE> all the remaining tokens are concatonated into the returned
# value and the current pointer (idx) will be one past the end indicating that parserIsDone will then return true.
# Whitespace is consumed into the return value except if the last token consumed is whitespace, it is not concatonated into the
# return value
function parseUpToWithTrim(parser, targetRE                ,token) {
	token=""
	while (!parserIsDone(parser) && parserGet(parser) !~ targetRE) {
		# dont append a trailing space
		if (parserGet(parser) !~ /^\s*$/  ||  (parserPeek(parser) !~ targetRE && parserPeek(parser) != "-1"))
			token=token""parserGet(parser)
		parser["idx"]++
	}
	return token
}






#################################################################################################################################
### Older Parsing functions.

# This initializes parseState as an array and fills in attributes for it to parse inputStr based on delimChars
# other parserCreate* functions can set it up to parse on other types of delimiters
# Params:
#    <parseState>    : the array variable that will hold the parser state. It can be an unitializaed variable or an array that will be cleared
#    <inputStr>      : the target of the parsing. This entry will be consumed and when its empty, the next call to parserConsume* will return false
#    <delimChars>    : a string of one or more characters that will split the input on
#    <inclDelimFlag> : if truthy, the trailing delimieter will be included in each consumed token
function reParserCreateFromDelimList(parseState, inputStr, delimChars, inclDelimFlag) {
	arrayCreate(parseState)
	parseState["input"] = inputStr
	parseState["delim"] = delimChars
	parseState["matchRegexp"] = "^([^"delimChars"]*)(["delimChars"])(.*)$"
	parseState["includeDelim"]=inclDelimFlag
	#bgtraceVars2(0,"parseState", parseState)
}

# run the parser once. The input string will be reduced by some amount of leading characters and those characters will be placed in token
function reParserConsumeNext(parseState                       ,rematch) {
	return reParserConsumeNextFromRE(parseState, parseState["matchRegexp"])
}

# like  reParserConsumeNext but the caller can specify the exact regex to use, overrided any that was initiallized by the parserCreate
# function. The regex must contain 3 () groups. [1] matches the consumed token, [2] the delimeter found at the end of token, [3] the
# remainder of the input left onconsumed
function reParserConsumeNextFromRE(parseState, regex                       ,rematch) {
	if (match( parseState["input"], regex, rematch)) {
		parseState["token"] = (parseState["includeDelim"]) ? rematch[1]""rematch[2]  : rematch[1];
		parseState["input"] = rematch[3];
		#bgtraceVars2(0,"parseState", parseState)
		return 1
	} else if (length(parseState["input"]) >0) {
		parseState["token"] = parseState["input"]
		parseState["input"] = "";
		#bgtraceVars2(0,"parseState", parseState)
		return 1
	} else {
		return 0
	}
}

function norm(s) {
	if (s=="") return "--"
	if (s~/[ \t\n]/) s="\"" s "\""
	gsub(/ /,"%20",s)
	gsub(/\t/,"%09",s)
	gsub(/\n/,"%0A",s)
	return s
}

function denorm(s) {
	if (!escapOutput) {
		if (s=="--") return ""
		gsub("%20"," ",s)
		gsub("%A","\n",s)
		gsub("%0A","\n",s)
		gsub("%09","\t",s)
	}
	return s
}

# usage: strSetExpandRelative(fullSet, defSet, relativeSet)
# See Also:
#    man(3ba) strSetExpandRelative
function strSetExpandRelative(fullSet, defSet, relativeSet                  ,resultSet,resultSetArray,element) {
	# expand the relative properties of defSet->fullSet and relativeSet->defSet
	if (defSet ~ /^[[:space:]]*[-+,:]/) defSet=fullSet" "defSet
	if (relativeSet ~ /^[[:space:]]*[-+,:]/) relativeSet=defSet" "relativeSet

	# expand any ocurances of "all"
	resultSet=relativeSet; gsub(/\yall\y/,fullSet,resultSet)

	# normalize the delimiters. [:,+-] can all be used as delimiters. Of them, only - needs special processing.
	# replace [:,+] with a space and add a space to the front of -. Now the list will be space separated and any element that is
	# to be subtracted will have a leading -.
	gsub(/-/," -",resultSet)
	gsub(/[:,+]/," ",resultSet)

	# note that we pad the ends with a space so that we can use spaces to delimit whole words
	# in the search and replace sub functions -- ${resultSet/ $column / }
	resultSet=" "resultSet" "

	# iterate the resultSet, removing the negated columns
	split(resultSet, resultSetArray)
	for (i in resultSetArray) {
		element=resultSetArray[i]
		if (element ~ /^-/) {
			# first remove the negated directive
			sub(" "element" "," ",resultSet)
			# then remove the first ocurrence of that column from the resultSet (without the leading -)
			sub(/^-/,"", element)
			sub(" "element" "," ",resultSet)
		}
	}
	return resultSet
}

# usage: stringTrimQuotes(str)
# returns str with one pair of enclosing single or double quotes removed. Leading and trialing spaces outside the quotes are
# removed but all spaces inside the quotes are preserved
function stringTrimQuotes(str       ,rematch) {
	if (match(str,/^[[:space:]]*[']([^']*)['][[:space:]]*$/,rematch))
		return rematch[1]
	if (match(str,/^[[:space:]]*["]([^"]*)["][[:space:]]*$/,rematch))
		return rematch[1]
	return str
}


# usage: stringExpand(str,context)
# expand str as a template that contains variable references of the form %<varName>[:<default>]%
# In addition, \n and \t are replaced with newline and tab characters
# Variable References:
# %<varName>[:<default>]%
# The default value is optional. varname is evalutated in the following order. The first one found is the value
#    (1) context[<varName>]  (the context passed in, if any)
#    (2) SYMTAB[<varName>]   (SYMTAB is a gawk extention that gives access to global variables)
#    (3) <default>
#    (4) <emptyString>
# Params:
#    str     : the template string containing %<varName>[:<default>]%
#    context : an array whose indexes are varNames.
function stringExpand(str,context                 ,_se_rematch,name,value,defaultValue) {
	# <someTextBefore>%variableName:defaultValure%<someMoreTextAfter>
	# <--rematch[1]-->|<rematch[3]>|<rematch[4]->|<--rematch[5]----->
	while (match(str,/^([^%]*)([%]([^:%]*)([^%]*)[%])(.*)$/,_se_rematch)) {
		name=_se_rematch[3]
		defaultValue=_se_rematch[4]
		if (name in context) {
			value=context[name]
		} else if (name in SYMTAB) {
			value=SYMTAB[name]
		} else if (name in ENVIRON) {
			value=ENVIRON[name]
		} else {
			value=defaultValue
		}
		str=_se_rematch[1]""value""_se_rematch[5]
	}
	gsub("\\\\n","\n",str)
	gsub("\\\\t","\t",str)
	return str
}


function expandTemplate(templateFilename, context, outFile            ,name,value,a,n,vars,parts) {
	if (!(templateFilename in seenTemplateFiles) && !fsExists(templateFilename))
		warning("template file does not exist: '"templateFilename"'")
	seenTemplateFiles[templateFilename]=1

	if (!outFile || outFile=="-") outFile="/dev/stdout"
	#outFile="/dev/stdout"
	printf("") > outFile
	while ((getline line < templateFilename) >0) {
		n=patsplit(line, vars, "%[^% ]*%", parts)
		for (i=0; i<=n; i++) {
			if (vars[i]) {
				name=substr(vars[i],2,length(vars[i])-2)
				split(name, a, ":")
				name=a[1]

				if (name in context) {
					value=context[name]
				} else if (name in SYMTAB) {
					value=SYMTAB[name]
				} else if (name in ENVIRON) {
					value=ENVIRON[name]
				} else {
					value=a[2]
				}

				printf("%s", value) >> outFile
			}
			printf("%s", parts[i]) >> outFile
		}
		print "" >> outFile
	}
	close(templateFilename)
	close(outFile)
}


#################################################################################################################################
### File functions


# usage: fsExists(f)
# returns true(1) if file f exists and false(0) if it does not exist
function fsExists(file1,     fileStats1,result) {
	if (!file1) return 0;
	result=stat(file1, fileStats1)
	return (result==0)
}

# usage: fsTouch(f)
# creates a file or folder.
# Params:
#    path       : a file or folder. If it ends in '/' its a folder, otherwise a file
#    parentFlag : if true and path is a folder, the -p option will be used to make the parent folders as needed.
function fsTouch(path, parentFlag         ,cmd,result) {
	if (path ~ /\/$/) {
		cmd="mkdir " ((parentFlag)?"-p ":" ") path" 2>/dev/null"
	} else {
		cmd="touch "path" 2>/dev/null"
	}
	result=system(cmd)
	return (result==0)
}

# usage: fsIsNewer(fileSpec, file2)
# return true if any file that fileSpec resolves to exists and is newer then file2 (or file2 does not exist)
# Params:
#    fileSpec  : can be one of these forms
#                * a string with a single filename
#                * a string with a wildcard character [*?]
#                * an array of fileSpecs
#    file2  : the single file to compare against
function fsIsNewer(fileSpec, file2                  ,i,fileStats1,fileStats2,pathlist) {
	# recurse arrays
	if (isarray(fileSpec)) {
		for (i in fileSpec)
			if (fsIsNewer(fileSpec[i],file2))
				return 1
		return 0

	# string with wilcards
	} else if (fileSpec ~ /[*?]/) {
		# wildcard case
		fsExpandFiles(fileSpec, pathlist)
		return fsIsNewer(pathlist, file2)

	# compare a single fileSpec to file2
	} else {
		# simple case. fileSpec is a filename
		if (stat(fileSpec, fileStats1)!=0) return 0
		if (stat(file2, fileStats2)!=0) return 1
		return (fileStats1["mtime"] > fileStats2["mtime"])
	}
}

# usage: fsExpandFiles(pathlist, outputArray)
# expand a string pathlist into an array containing one pathname per element. Pathlist is space separated list of fileSpecs.
# fileSpecs can contain spaces if it is quoted with single quotes. fileSpec may contain wildcards.
# Any fileSpec that does not contain wildcards is passed through without change and is not checked to see if the file object exists.
# And fileSpec that does contain wildcards is expanded by the shell but if it does not match any file objects, this function removes
# that fileSpec from the results.
# The default shell, sh, will be used to expand pathlist.
# Params:
#    pathlist    : this is a space separated string of fileSpecs. Characters such as spaces that are a part of a fileSpec should be
#                  surrounded by single quotes.
#    outputArray : an array that will receive the results. It will be deleted and then the results added.
#                  Each entry is a single file or folder name which may or may not exist in the file system but globs that do not
#                  match any file objects will be removed.
function fsExpandFiles(pathlist,paths                   ,pathsStr,result,cmd,i) {
	cmd="printf %s\\\\0 "pathlist
	result=(cmd | getline pathsStr)
	split(substr(pathsStr,1,length(pathsStr)-1),paths,"\0")
	# if any element in paths still contain wildcard chars, it does not match any files or folders so remove them
	for (i in paths)
		if (paths[i] ~ /[*?]/)
			delete paths[i]
}

# usage: fsIsDifferent(file1, file2)
function fsIsDifferent(file1, file2         ,cmd,result,fileStats1,fileStats2) {
	if (stat(file1, fileStats1)!=0 && stat(file2, fileStats2)!=0) return 0
	cmd="sh -c 'diff -q "file1" "file2" 2>&1 '"
	cmd | getline result
	close(cmd)
	return (result!="")
}

# usage: updateIfDifferent(srcFile, dstFile)
# overwrite dstFile with srcFile only if it is different and remove srcFile
# if srcFile does not exist, remove dstFile
# if the two files have the same content, leave dstFile alone without chnaging timetime or opening it for write
function updateIfDifferent(srcFile, dstFile               ,cmd,srcExists,dstExists) {
	fflush(srcFile)
	srcExists=fsExists(srcFile)
	dstExists=fsExists(dstFile)
	if (srcExists && fsIsDifferent(srcFile, dstFile)) {
		#print "updating "dstFile
		print "cat "srcFile" > "dstFile"; rm "srcFile | "sh"
		close("sh")
	} else if (!srcExists && dstExists) {
		print "rm "dstFile | "sh"
	} else if (srcExists) {
		print "rm "srcFile | "sh"
		close("sh")
	}
}

function fsRemove(file) {
	print "rm -f "file | "sh"
	close("sh")
}

#################################################################################################################################
### Path functions

# usage: pathGetCommon <path1> <path2>
# compare the two paths from left to right and return the prefix that is common to both.
# put another way, it returns the folder with the longest path that is a parent of both paths
# Example:
#    p1 = /var/lib/foo/data
#    p2 = /var/lib/bar/five/fee
#   out = /var/lib/
function pathGetCommon(p1, p2                                   ,t1,t2,out,finished)
{
	reParserCreateFromDelimList(t1, p1, "/", 1)
	reParserCreateFromDelimList(t2, p2, "/", 1)

	while ( t1["token"] == t2["token"] && ! finished ) {
		out=out""t1["token"]
		if (!reParserConsumeNext(t1)) finished="1"
		if (!reParserConsumeNext(t2)) finished="1"
	}

	return out
}


# usage: pathGetCanonStr -e <path>  [<retVar>]
# usage: canoPath="$(pathGetCanonStr "path")"
# return the canonical version of <path> without requiring that any part of it exists.
#
# Note that starting in Ubuntu 16.04, the realpath core gnu util is much more capable including
#       logical/physical symlink mode
# Note that "readlink -f" does something similar but expands any symlinks in the path. It also requires
# that all folders in the path must exist or it returns empty string. This function does not expand
# symlinks so that the logical path names are preserved but does simplify the path to its canonical form
#
# This is a pure string manipulation and does not reference the filesystem tree except for
# the -e option to turn a relative path into a absolute path.
# Often you want the full path relative to the current folder which is what the -e option does
#
# Params:
#    <retVar> : return the result in this variable name. default is to write result to stdout
# Options:
#    -e : use the environment to make a relative path absolute. If the path does not start with /
#         it will be prepended with either $home if it begins with ~ or $PWD. It does not matter
#         if the resulting path exists or not.
# Output:
#    if path is invalid the empty string will be returned and the exit code is 1
#    otherwise the canonical version is returned on stdout and the exit code is 0
#    if -e id specified the returned path will be absolute
#    The second param <retVar> is specified, it will be set with the value. otherwise the value
#    is written to stdout
# What it does:
#    removes any './', '//' sequences
#    removes any trailing /
#    process ../  by removing the previous part, handling adjacent ../../
#        if the path begins with /../ it is an invalid path because there is no previous part to remove
#        if the path begins with ../ it is relative to something this function can not know and any
#            leading ../../... sequences will not be removed
function pathGetCanonStr(path, useEnvFlag                                , parser, pathArray, origPath, out )
{
	origPath=path
	arrayCreate(pathArray)

	if (useEnvFlag) {
		if (path ~ /^~/ ) path=ENVIRON["HOME"]"/"substr(path, 2)
		if (!path || path ~ /^[^/]/)
			path=ENVIRON["PWD"]"/"path
		fi
	}

	reParserCreateFromDelimList(parser, path, "/")
	while ( reParserConsumeNext(parser) ) {
		switch (parser["token"]) {
			case "..":
				if (length(pathArray)==0 || (length(pathArray)==1 && pathArray[0]=="")) {
					warning("invalid path path="origPath)
					return ""
				}
				delete pathArray[length(pathArray)-1]
				break
			case ".":
				break
			case "":
				# if the first path is empty, it means its an absolute path starting with / but any other is a duplicate //
				if (length(pathArray)==0)
					pathArray[length(pathArray)]=parser["token"]
				break
			default:
				pathArray[length(pathArray)]=parser["token"]
		}
	}

	if ((length(pathArray)==1 && pathArray[0]==""))
		out="/"
	else
		out=join(pathArray,"/")
	return out
}


# # usage: pathCompare [-e] <p1> <p2>
# # compares two paths taking into account path globing (i.e. *)
# # Options:
# #    -e : pathGetCanonStr each path first which removes things that dont effect the meaning (like extra / "//" )
# #         and also makes the paths absolute.
# function pathCompare()
# {
# 	local envFlag=""
# 	while [[ "$1" =~ ^- ]]; do case $1 in
# 		-e) envFlag="1" ;;
# 	esac; shift; done
# 	# remove a trailing / because the presense of a trailing / or not does not change the meaning of the path
# 	local p1="${1%/}"
# 	local p2="${2%/}"
#
# 	if [ "$envFlag" ]; then
# 		p1="$(pathGetCanonStr -e "$p1")"
# 		p2="$(pathGetCanonStr -e "$p2")"
# 	fi
#
# 	# use the == op of [[ ]] because it understands * globing -- i.e "/var/*" is equal to "/var/lib"
# 	# replace spaces in the paths with '\ ' which escapes them so that [[ ]] does not break the tokens on spaces
# 	[[ ${p1// /\\ } == ${p2// /\\ } ]]
# }
#
#
# # usage: pathGetRelativeLinkContents <linkFrom> <linkTo> [<retVar>]
# # returns the relative path that would make a symlink at <linkFrom> point to the filessysem object at <linkTo>
# # linkFrom and linkTo do not need to be absolute, but they do need to be relative to the same PWD so that they
# # have a command path. this does not necessarily mean that they have any common parts in there strings.
# # Params:
# #    <linkFrom> : The path where a symlink cound be created. If this is a folder, its where an unamed symlink
# #                 in that folder could be created.
# #    <linkTo>   : The file or folder where the symlink will point to.
# #    <retVar>   : if provided, the result is returned in this variable instead of stdout
# function pathGetRelativeLinkContents()
# {
# 	local linkFrom="$1"
# 	local linkTo="$2"
#
# 	# if linkFrom ends in a / its a folder location. Put a dummy link name b/c the alogorithm assumes its a link
# 	[[ "$linkFrom" =~ /$ ]] && linkFrom+="linkFilename"
#
# 	local commonPath="$(pathGetCommon "$linkFrom" "$linkTo")"
#
# 	# if there is no common path, and either contains a protocol part, there path parts might still be
# 	# relative so parse out everything but the path part of the URLs and try again.
# 	# TODO: take into account if the users are different and the resource paths are relative they have different PWD
# 	if [ ! "$commonPath" ]; then
#  		local host1 host2
#  		[[ "${linkFrom}" =~ [:] ]] && parseURL "$linkFrom" "" "" "" host1 "" linkFrom
#  		[[ "${linkTo}" =~ [:] ]]   && parseURL "$linkTo"   "" "" "" host2 "" linkTo
#
# 		# if they refer to different hosts, they have nothing in common
# 		[ "$host1" ] && [ "$host2" ] && [ "$host1" != "$host2" ] && return
#
# 		# now restart with the paths now that niether have the host/protocol
# 		commonPath="$(pathGetCommon "$linkFrom" "$linkTo")"
# 	fi
#
# 	# if there is still no common path, and niether are absolute, assume that they are both relative to the PWD and add ./
# 	if [ ! "$commonPath" ] && [ "${linkFrom:0:1}" != "/" ] && [ "${linkTo:0:1}" != "/" ]; then
# 		commonPath="./"
# 		linkFrom="./$linkFrom"
# 		linkTo="./$linkTo"
# 	fi
#
# 	# if there is still no common path but one of them is absolute, we have to make the other one absoute using the PWD
# 	# note that if both are absolute, commonPath could not be empty (it would be at least "/")
# 	if [ ! "$commonPath" ]; then
# 		# TODO: it seems that we should call pathGetCanonStr on both unconditionally here but I don't want to test that now
# 		[ "${linkFrom:0:1}" == "/" ] && linkTo="$(pathGetCanonStr -e "$linkTo")"
# 		[ "${linkTo:0:1}" == "/" ] && linkFrom="$(pathGetCanonStr -e "$linkFrom")"
# 		commonPath="$(pathGetCommon "$linkFrom" "$linkTo")"
# 	fi
#
# 	local linkFromRel="${linkFrom#${commonPath%/}}"; linkFromRel="${linkFromRel#/}"
# 	local linkToRel="${linkTo#${commonPath%/}}"; linkToRel="${linkToRel#/}"
#
# 	# the first -e statement turns all the leading folders ("something>/") into ../
# 	# the second -e statement removes the filename of the link
# 	local result="$(echo "$linkFromRel" | sed -e 's|[^/][^/]*/|\.\./|g' -e 's|/*[^/]*$||')"
# 	returnValue "$result${result:+/}$linkToRel" "$3"
# }

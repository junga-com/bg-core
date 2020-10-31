@load "filefuncs"

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
# This prints a list of awk global vars. Note that local function variables will not work with this function but do with
# printfVars2
# Params:
#    varNameN   : the name of a global awk variable to be displayed
#    optionsStr : a string of optional args that apply to all. Note that options can be included among the varNames and effect
#                 only varNames from that point on.
# See Also:
#    printfVarss : print only one var at a time but works with local and netsted arrays that this function does not work with
#    (bash)printfVars : similar bash function
function printfVars(varNameListStr            ,optionsStr,level, varNameList, i,options,outFile) {
	level=0
	outFile="/dev/stderr"
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

		for (i in varValue)
			printfVars2(level+1, i, varValue[i], "-w"maxWidth" --brackets "optionsStr)
	}
}



#################################################################################################################################
### Array functions

# usage: arrayCopy(source, dest)
# copy the contents of one array var into another
# Return Value:
#   <count>  : the number of elements copied including in sub-arrays
function arrayCopy(source, dest,   i, count)
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
# Like split but works to assign new,untyped sub-arrays elements with split can not do
function split2(str, array, elName, delim) {
	if (!delim) delim=FS
	array[elName][1]=""
	return split(str, array[elName], delim)
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
function bgtraceVars2(level, varName, varValue, optionsStr) {
	if (!bgtraceIsActive()) return
	printfVars2(level, varName, varValue, optionsStr" -o"_bgtraceFile)
	fflush(_bgtraceFile)
}
function assert(msg) {
	_fnName=_FILENAME; if (_fnName=="") _fnName=FILENAME
	_fnLine=_INDESC;   if (_fnLine=="") _fnLine=FNR
	_fnLineTxt=$0;     if (_INDESC~"((BEGIN)|(END))") _fnLineTxt="N/A"
	printf("awk assert error (%s) : %s\n   inputFile= %s : %s\n   input line= '%s'\n\n", scriptName, msg, _fnName, _fnLine, _fnLineTxt ) > "/dev/stderr"
	hardExit(222)
}
function warning(msg, verbose,       _fnName, _fnLine, _fnLineTxt) {
	if (verbose) {
		_fnName=_FILENAME; if (_fnName=="") _fnName=FILENAME; gsub("^.*/","", _fnName)
		_fnLine=_INDESC;   if (_fnLine=="") _fnLine=FNR
		_fnLineTxt=$0;     if (_INDESC~"((BEGIN)|(END))") _fnLineTxt="N/A"
		if (!scriptName) scriptName="awkDataLibrary"
		printf("awk warning ($%s) : %s\n   %s(%s): '%s'\n\n", scriptName, msg, _fnName, _fnLine, _fnLineTxt ) > "/dev/stderr"
	} else {
		printf("awk warning ($awkDataLibrary) : %s\n", msg) > "/dev/stderr"
	}
}
BEGIN {
	_INDESC="BEGIN"
}
{_INDESC=NR}
END {_INDESC="END"}



#################################################################################################################################
### String functions

function appendStr(str,strToAdd,sep) {
	if (!sep) sep=","
	if (!str) sep=""
	return str sep strToAdd
}
function join(array,sep,           i,wsep,result) {
	if (!sep) sep=","
	wsep=""; result=""
	for (i in array) {
		result=result wsep array[i]
		wsep=sep
	}
	return result
}

function strExtract(s, leadingRegEx, trailingRegEx) {
	sub(leadingRegEx,"",s)
	sub(trailingRegEx,"",s)
	return s
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
		warning("template file does not exist: "templateFilename)
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
	return (result)
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
		print "updating "dstFile
		print "cat "srcFile" > "dstFile"; rm "srcFile | "sh"
		close("sh")
	} else if (!srcExists && dstExists) {
		print "rm "dstFile | "sh"
	}
}

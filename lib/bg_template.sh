
# Library
# Provides simple text templates without being dependant on any platform
# TODO: support a new expression syntax (like %[sectionName]settingName%) that uses the system wide config as its variable context
# This library provides template expansion from the linux command line without relying on any platform. The parser is written in
# bash ans awk which are generally available on any linux system.
#
# Expression Format:
# A template file can be any text file. If the contents contains expressions like %myVariableName%, the expression will be replaced
# with the value of the environmental variable named 'myVariableName'. The exression syntax supports default values and manditory
# values.
#    %+name% : a leading + in the variable name indicates that it is an error if the environment variable does not exist (it can be empty)
#    %name:guest% : a trailing : indicates that the text that follows, up to the closing % is the default value.
# See man(5) bgTemplateFileFormat for details on the full expression syntax
#
# Variable Context:
# The variable context that template variables are expanded against is the linux environmental variable system. Before expanding
# a template, the user can export context variables that are relavent to the template.
#      export myVariableName="some value"
#
# Template Files and Folders:
# A template can be specified as a path to a file or folder or as the assetName of a system template. System templates must be
# installed from a package or installed on the host by a user with sufficient priviledge. Use the 'bg-core templates list|types|find'
# commands to explore the installed system templates. See man(3) templateFind to understand how system template name collisions
# are handled.
#
# A template can specify a folder (aka directory) in which case the entire folder contents are copied to the destination path,
# expanding variable expressions in the names of the files and folders and expanding the contents of any text file. Binrary files
# are copied as is without expansion.
#
# Example:
#    $ cat - > /tmp/myTemplate
#    Hello %name:guest user%.
#    My favorite color is %+color%
#    <cntr-d>
#    $ bg-core templates expand /tmp/myTemplate
#
#    error: templateEvaluateVarToken: required template var 'color' is not defined
#        context='/tmp/myTemplate'
#
#    $ export color=blue
#    $ bg-core templates expand /tmp/myTemplate
#    Hello guest user.
#    My favorite color is blue
#    $ export name=Bob
#    $ bg-core templates expand /tmp/myTemplate
#    Hello Bob.
#    My favorite color is blue
#    $
#
# See Also:
#    man(1) bg-core-template
#    man(5) bgTemplateFileFormat
#    man(3) templateExpand
#    man(3) templateFind
#    man(3) templateList


# man(5) bgTemplateFileFormat
# The bg_template.sh library from the bg-core pacakge works on simple template files that are useful for configuration and other
# content. Templates can contain variable references in the formate described below which are replaced with the values of
# corresponding bash variables in the environment. If the template expansion is invoked in a sub process, only exported variables
# will be available but in scripts, the expansion functions can be invoked in the same shell so any variable in the bash scope can
# be used in the templates.
#
# Variable Syntax:
#   %[+]varName[:defaultValue]%
#   %[+]$objSyntax[:defaultValue]%
#   %% will expand to the literal empty string
#   %\% will expand to the literal %
#   %\\% will expand to the literal %%
#   (each \ in the escape sequence %\\\\% will become a literal %)
#   %now[:<format>]% will expand to the current time/date using <format>
#
#     +            : The optional leading + indicates that the variable is required. If varName is not defined as a shell variable,
#                    an error will be asserted. Note that the empty string is a valid value so a variable that whose value is ""
#                    will not result in an error.
#     varName      : the name of an ENV variable. The caller can set variables in the shell before expanding a template. If invoking
#                    a child process to do the expansion remember to export the variables first.
#     defaultValue : if the varName does not exist in the shell, the default value will be expanded. Note that if the variable exists
#                    and is equal to the empty string "", the default value will not be used. If no defaultValue is present, the
#                    empty string will be used as the value. The default value can not contain nested %varName% references but it
#                    can contain simple $varName references. If the leading + syntax is used, the defaultValue will not be used
#     $objSyntax   : If the first character after the optional + is a $ and/or the varName contains a '.' it is interpreted as an
#                    object reference. See man(3) completeObjectSyntax for that syntax
#     <format>     : for the special variable name 'now', the token after the ':' is interpreted as a format string instead of a
#                    default value. The value of <format> can be one of the following...
#                         'RFC5322'   :  This specifies the internet email date format as defined in REF5322 (or 2822 or 822)
#                         '<any other value>' : any other value for <format> will be passed on to the gnu date utility as  +<format>
#                                               because the date util format uses '%' characters which would be combersome to escape,
#                                               the all occurances of the '^' character will be replaced with '%' before passing to
#                                               the date utility.
#
#   note that the escape sequences are designed so that there wont be any unmatched % characters in the template content.
#
#   Everything between each pair of two % will be replaced with the results of the expansion. The opening and closing % must be on
#   the same line. The defaultValue can include "\n" to expand to multiple lines
#
# Variable Syntax Examples:
#     %color%      # no default -- replaced with "" if color is unset
#     %color:red%  # with default -- If color is set as an exported ENV var, its value will be used
#                    even if its value is the empty string "".
#                    if color is not set as an ENV var (never exported or unset) the default value "red"
#                    will be used
#     %color:$faveColor%  # with default refering to another variable -- if default contains a $, it is
#                    interpreted as a variable
#     %+color%     # required value -- if there is no env variable 'color', assert an error. If any
#                    ocurrence of color as a variable in the template has a +, then it is required.
#
# Directive Syntax:
# TODO: 2022-07 bobg: the extended syntaxt is not yet implemented in the C builtin version. In the builtin version, its easier to
#       support it in a better way. Consider supporting a non-line oriented syntax. %!if %, %!<directive> <p1>...<pN>%
#   The template expansion functions with the work "Extended" in their name support addtional directive syntax in template content.
#   A directive must start at the beginning of a line. The extended template syntax is processed line by line. Any %varname%
#   variable references are expanded on the line before the directive is processed so directives can contain variables.
#        %# comment...           # %# comments are not a part of the expanded template. # comments are passed through.
#        %set varname="value"    # define the value of a template variable which can be used in subsequent variable references
#        %include <templateSrc>  # read and expand the <srcTemplate> and then proceed to the next line.
#        %use filename           # Declare that future $include statements can use just the ini section name
#                                  from this file without specifying the whole filename. This can be used
#                                  multiple times. If the same section name is in multiple used files, it
#                                  is undefined which will be choosen.
#        %ifdef <var> <templateLine> # if <var> is defined, <templateLine> is printed to stdout.
#        %ifdef {                # if <var> is defined, the following lines, up to a %} or %else are processed
#                                  if its not defined, the following lines, up to a %} or %else are skipped
#        %else                   # after the last %if, this reverses the process/skip state up to the next %}
#        %}                      # terminates the last '%ifdef <var> {' line.
#        %end                    # ends causes empty lines immediately following it to be skipped. This is usefull
#                                  to allow empty lines to separate ini sections without becoming part of the
#                                  expanded output.
#        %inputVariables <p1> ..<pN> #
#        %<customDirective>      # the calling script can define additional supported directives by registering the
#                                  handler function name in templateCustomDirectives[<customDirective>]="myHandlerFunction"
#                                  TODO: implement these as plugins
#  * Lines that are not directives are passed through to stdout
#
# See Also:
#    man(3) completeObjectSyntax   : for syntax of the $objSyntax supported in variable references
#    man(3) templateExpand         : expand templates that only have variable references
#    man(3) templateExpandExtended : expand templates that only have directives and variable references


# moved function templateFind() to bg_coreSysRuntime.sh
# moved function templateList() to bg_coreSysRuntime.sh
# moved function templateTree() to bg_coreSysRuntime.sh
# moved function templateGetSubtypes() to bg_coreSysRuntime.sh


# usage: completeTemplateName <cur>
# do bash cmdline completion on a system template name. System templates are installed by packages or system admins on a host or
# domain.  They can be specified or listed by name without path. Their names are hierarchical using '.' to delimit the parts.
function completeTemplateName()
{
	local cur="$1"
	templateList  "${cur}" | awk -v cur="$cur" '
		@include "bg_core.awk";
		BEGIN {
			curDonePart=""
			if (cur ~ /[.]/) {
				curDonePart=gensub(/[.].*$/,".","g",cur)
				printf("$(cur:%s)\n", substr(cur, length(curDonePart)+1))
			}
			arrayCreate(results)
		}
		NF>0 {
			if ($0 ~ "^"cur) {
				leftover=gensub("^"curDonePart, "", "g", $0);
				if (!leftover)
					leftover="%20"
				results[leftover]=1
			}
		}
		END {
			if (length(results) >= 4) {
				for (i in results) {
					leftover=i;
					delete results[i];
					if (leftover ~ /[.]/) {
						leftover=gensub("[.].+$",".%3A","g", leftover)
					}
					results[leftover]=1
				}
			}
			for (i in results)
				printf("%s\n", i)
		}
	' | sort -u
}


# usage: templateGetContent [-f] <templateFile>[:<templateSection>] [<templateSection>]
# usage: templateGetContent -s <templateString>
# This sends the template content specified to stdout
# This function facilitates writing the template support functions so that they can be used by templateExpand
# and templateExpandStr. The command line supports passing in the contents as a string, or as a filename
# to be read or as an ini style section that should be extracted from inside a filename
# Params:
#    <templateFile>    : filename of the template. templateFind is used to turn it into a full path
#                        This filename can not contain : because that is used to separate the optional
#                        <templateSection>. If a template filename must contain a : the caller can escape
#                        it by replacing it with '%3A' before passing it into this function. After
#                        separating the <templateSection>, this function will replace all '%3A' with ':'
#    <templateSection> : if a section name is specified with a filename, then only the content
#                        from that INI style section is returned as the template content. <templateSection>
#                        can either be a second param or attached to <templateFile> with a :
#    <templateString>  : with the -s option, the entire command line is interpreted as the template content
# Options:
#     -s  : string. signifies that the command line is the template content (aka passed as a string)
#     -f  : file. signifies that the first parameter is template filename with optional ini section
function templateGetContent()
{
	local cmdLine=("$@")
	local inputType="file" templateFile templateSection
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s) inputType="string" ;;
		-f) inputType="file" ;;
	esac; shift; done

	case $inputType in
		file)
			if [[ "$1" =~ : ]]; then
				templateFile="${1%%:*}"
				templateSection="${1#*:}"
			else
				templateFile="$1"
				templateSection="$2"
			fi
			templateFile="${templateFile//%3A/:}"
			templateFind -R templateFile "$templateFile"

			[ -f "$templateFile" ] || assertError -v inputType -v templateFile -v templateSection -v cmdLine "template does not exist"

			local preCmd; [ -f "$templateFile" ] && [ ! -r "$templateFile" ] && preCmd="bgsudo "
			if [ "$templateSection" ]; then
				$preCmd iniSectionGet "$templateFile" "$templateSection"
			else
				$preCmd cat "$templateFile"
			fi
			;;

		string)
			echo "$*"
			;;
	esac
	return 0
}




# usage: templateListVars <templateSpec> [<templateSection>]
# usage: templateListVars -s <templateString>
# list the template vars used in a template. This function prints the results in a table of variable
# attributes. templateGetVarTokens also returns the variables in a template but in their raw token form.
# The command line is passed through to templateGetContent. See that function for a description of the
# params and options
# See Also:
#    templateGetContent
#    templateGetVarTokens
function templateListVars()
{
	local -a variables; mapfile -t variables < <(templateGetVarTokens "$@")

	local -A reqVars optVars
	local var; for var in "${variables[@]}"; do
		local rematch; match "$var" "^([+])?([^:]*):?(.*)?$" rematch
		local varName="${rematch[2]}"
		[[ "${varName}" =~ ^\\\\*$ ]] && continue
		if [ "${rematch[1]}" == "+" ]; then
			reqVars[$varName]="${reqVars[$var]:-${rematch[3]}}"
		else
			optVars[$varName]="${optVars[$var]:-${rematch[3]}}"
		fi
	done

	if [ ${#reqVars[@]} -gt 0 ]; then
		printf "Required Template Variables\n"
		for varName in "${!reqVars[@]}"; do
			local _nameETV _valueETV; templateEvaluateVarToken "$varName"  _nameETV _valueETV
			printf "   %-23s %-23s %s\n" "$varName" "def='${reqVars[$varName]}'" "cur='${_valueETV}'"
		done
	fi

	if [ ${#optVars[@]} -gt 0 ]; then
		printf "Optional Template Variables\n"
		for varName in "${!optVars[@]}"; do
			local _nameETV _valueETV; templateEvaluateVarToken "$varName"  _nameETV _valueETV
			printf "   %-23s %-23s %s\n" "$varName" "def='${optVars[$varName]}'" "cur='${_valueETV}'"
		done
	fi
}


# usage: templateGetVarTokens <templateSpec> [<templateSection>]
# usage: templateGetVarTokens -s <templateString>
# return a list of all unique variable tokens referenced in the template. variable tokens include
# annotations like the leading + and :<defaultValue>.  Different tokens may refer the same variable
# because some may have different annotations. This function is used by the template parser so that
# it can iterate and replace each token with a value.
# The function templateListVars also returns the the variables contained in a template but in a way that
# is more suitable for analysis instead of efficient expansion.
# The command line is passed through to templateGetContent. See that function for a description of the
# params and options
# See Also:
#    templateGetContent
#    templateListVars
function templateGetVarTokens()
{
	# "%(  ([$+]*     []:a-zA-Z0-9._[]* (:[^%]*)*)   |([\/]*)   )%"
	#     '$ or +'    '------<expr>---'  :<def>      or \\...
	templateGetContent "$@" \
		| grep -o "%\(\([$+]*[]:a-zA-Z0-9._[]*\(:[^%]*\)*\)\|\([/\]*\)\)%" \
		| tr -d "%" | sed -e "s/ /%20/g; /^[[:space:]]*$/d" \
		| LC_ALL=C sort -u | gawk '
			# this filter sorts the literal /+ and \+ tokens first so that the resulting script will replace the literal tokens with
			# a templateMagicEscToken first so that those % wont interfere with other matches
			/^[\/\\]+$/ {firstLines[NR]=$0; next}
			{lines[NR]=$0}
			END {
				for (i in firstLines)
					print firstLines[i];
				for (i in lines)
					print lines[i];
			}
		'
}



# usage: completeTemplateVariables <cword> <templateName> [<varTerm>..<varTermN>]
function completeTemplateVariables()
{
	local cword cur
	while [ $# -gt 0 ]; do case $1 in
		--cur*) bgOptionGetOpt val: cur "$@" && shift ;;
		--cword*) bgOptionGetOpt val: cword "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateName="$1"; shift
	if [ ${cword:-0} -eq 1 ]; then
		completeTemplateName "$templateName"
		return
	fi

	if [[ "${cur}" =~ : ]]; then
		echo "<completeTheValueForThisVar>"
		return
	fi

	local -A completedVars
	while [ $# -gt 0 ]; do
		local term="$1"; shift
		local rematch; match "$term" "^([+])?([^:]*):(.*)?$" rematch || continue
		local varName="${rematch[2]}"
		completedVars[${varName:-empty}]="${rematch[3]}"
	done

	local -a variables; mapfile -t variables < <(templateGetVarTokens "$templateName")

	local -A reqVars optVars definedVars
	local var; for var in "${variables[@]}"; do
		local rematch; match "$var" "^([+])?([^:]*):?(.*)?$" rematch
		local varName="${rematch[2]}"
		[[ "${varName}" =~ ^\\\\*$ ]] && continue
		[ "${completedVars[$varName]+exists}" ] && continue
		if [ "${rematch[1]}" == "+" ]; then
			reqVars[$varName]="${reqVars[$var]:-${rematch[3]}}"
		else
			optVars[$varName]="${optVars[$var]:-${rematch[3]}}"
		fi
		if [ "${!varName+exists}" ]; then
			definedVars[$varName]="${!varName}"
		fi
	done

	if [ ${#reqVars[@]} -gt 0 ]; then
		echo "<${#reqVars[@]}_requiredVarsNeedToBeCompleted>"
		echo "\$(suffix::%3A) ${!reqVars[@]}  \$(suffix)"
	else
		echo "<onlyOptionalVarsRemain>"
		echo "\$(suffix::%3A) ${!optVars[@]}  \$(suffix)"
	fi
}


# usage: templateEvaluateVarToken <exprToken> <nameVar> <valueVar> [<scrContextForErrors>]
# This is a helper function to the templateExpand* family of parser functions. This function defines what variable syntax is
# supported. Given the <exprToken> which could contain various syntax for default value and other features, this function parses
# out the variable name and attributes and then evaluates its value. The variable name and value are returned to the caller.
#
# The syntax that this function supports is documented in the man(5) bgTemplateFileFormat page defined at the top of this file.
#
# Variables used from Parent Scope :
#    _objectContextES : points to the current object context for evaluating object style template vars
# Params:
#    <exprToken>           : the template expression to evaluate as returned by templateGetVarTokens
#                            The <exprToken> is everything between the %% but does not include the %%
#    <nameVar>             : output var to receive the name of the variable being referenced in <exprToken>
#                            this is the <exprToken> with the optional + and default values removed
#    <valueVar>            : output var to receive the string value that the <exprToken> evaluates to
#    <scrContextForErrors> : optional context string. If this function asserts an error, this string
#                            is included as the context of where the error happened.
# See Also:
#    man(5) bgTemplateFileFormat
#    man(3) completeObjectSyntax (for syntax of the $objSyntax)
#    man(3) templateExpandExtended (for more syntax specific to it)
function templateEvaluateVarToken()
{
	local _expressionTokenETV="%${1//%20/ }%"
	local _nameVarETV="$2"
	local _valueVarETV="$3"; assertNotEmpty _valueVarETV
	local _contextETV="$4"

	local _nameValueETV _valueValueETV _defaultValueETV _requiredFlagETV _foundFlagETV

	# to check or change this regex, look at the bg_template.sh:templateExprRegex: unit test testcase
	local templateExprRegEx='%((([+])?(((config([[]([^]]+)[]])?([a-zA-Z0-9_]*+)))|(([$])([^:%]+))|(([a-zA-Z0-9_]*+)([[]([^]]+)[]])?))(:([^%]*))?)|([/\]*))%'
	local _idxReqFlag=3
	local _idxConfigExpr=6
	local _idxConfigSect=8
	local _idxConfigName=9
	local _idxObjFlag=11
	local _idxObjExpr=12
	local _idxEnvExpr=13
	local _idxEnvVar=14
	local _idxEnvInd=16
	local _idxDef=18
	local _idxEsc=19

	local rematch
	if match "${_expressionTokenETV}"  $templateExprRegEx rematch; then

		_requiredFlagETV="${rematch[$_idxReqFlag]}"
		_defaultValueETV="${rematch[$_idxDef]}"

		# if config type expression
		if [[ "${rematch[$_idxConfigExpr]}" == config* ]]; then
			local _sectETV="${rematch[$_idxConfigSect]}"
			local _settingETV="${rematch[$_idxConfigName]}"
			_nameValueETV="${rematch[$_idxConfigExpr]}"

			# cache the system wide config if it has not already been cached
			! type -t configFlatten &>/dev/null && import bg_config.sh  ;$L1;$L2
			if [ ${#_templateConfigCtx[@]} -eq 0 ]; then
				! varExists _templateConfigCtx && declare -gA _templateConfigCtx
				configFlatten -M _templateConfigCtx
			fi

			# look up the value if it exists
			[ "$_sectETV" == "." ] && _sectETV=""
			if [ ${_templateConfigCtx[${_sectETV}${_sectETV:+.}${_settingETV}]+exits} ]; then
				_valueValueETV="${_templateConfigCtx[${_sectETV}${_sectETV:+.}${_settingETV}]}"
				_foundFlagETV="1"
			fi

		# if Object type expression
		elif [ "${rematch[$_idxObjFlag]}" == "\$" ]; then
			_nameValueETV="${_objectContextES}${_objectContextES:+.}${rematch[$_idxObjExpr]}"
			if _valueValueETV="$(objEval $_nameValueETV 2>/dev/null)"; then
				_foundFlagETV="1"
			fi

		# if Environment Var type expression (the typical case)
		elif [ "${rematch[$_idxEnvExpr]}" ]; then
			_nameValueETV="${rematch[$_idxEnvExpr]}"
			if varExists "$_nameValueETV"; then
		 		_foundFlagETV="1"
				_valueValueETV="${!_nameValueETV}"
			elif [[ "$_nameValueETV" == now ]]; then
				_foundFlagETV="1"
				local format="$_defaultValueETV"
				case $format in
					RFC5322|rfc5322) _valueValueETV="$(date -R)" ;;
					*) _valueValueETV="$(date +"${format//^/%}")" ;;
				esac
			fi

		# if its one or more escaped %
		elif [ "${rematch[$_idxEsc]}" ]; then
			_foundFlagETV="1"
			if [[ "${rematch[$_idxEsc]}" == /* ]]; then
				_valueValueETV="${rematch[$_idxEsc]//\//$templateMagicEscToken}"
			else
				_valueValueETV="${rematch[$_idxEsc]//\\/$templateMagicEscToken}"
			fi

		# error: some unknown syntax
		else
			assertLogicError -v rematch "The template regex matched the expression but the code does not recognize which type of syntax matched"
		fi
	else
		assertError -v expression:_expressionTokenETV "Could not parse the template expression. Did not recognize it as any known syntax"
	fi

	# if its required but its not found, throw an exception
	if [ "$_requiredFlagETV" ] && [ ! "$_foundFlagETV" ]; then
		assertTemplateError -v context:_contextETV "The required template variable '$_nameValueETV' does not exist"
	fi

	# if not found, set the default value if any
	if [ ! "$_foundFlagETV" ]; then
		# SECURITY: we allow the default to refer to env variables as long as it does not contain special chars that could execute arbitrary code
		if [[ "$_defaultValueETV" =~ ^\$ ]]; then
			_defaultValueETV="${_defaultValueETV:1}"
			[[ ! "$_defaultValueETV" =~ ^[a-zA-Z0-9_]*$ ]] && assertTemplateError -v context:_contextETV -v expression:_expressionTokenETV "an indirect default value can not contain special characters besides the leading \$"
			_valueValueETV="${!_defaultValueETV}"
		else
			_valueValueETV="$_defaultValueETV"
		fi
	fi

	setReturnValue "$_nameVarETV" "$_nameValueETV"
	returnValue "$_valueValueETV" "$_valueVarETV"
}


# usage: templateExpandStr [-R <retVar>] [-o <objectScope>] [-s] <templateStr> [<scrContextForErrors>]
# Replaces variable references in <templateStr> with the values of the process's environment variables.
# Variable syntax and Examples:
#   see templateEvaluateVarToken for a description of the supported syntax
# Options:
#     -s : this is ignored by this function so that its command line is compatible with other template functions that support passing
#          either a -s <string> or a -f <file>
#     -o|--objCtx=<objectScope> : when a template variable begins with a $, it is interpreted as an object reference. The <objectScope> will be
#           prepended to the template variable so that the members of the <objectScope> object will be the global scope of template vars
#           The default is "" so that the callers bash variables are queried for individual objects.
# See Also:
#    man(5) bgTemplateFileFormat
#    templateEvaluateVarToken
#    templateListVars
#    templateExpand
#    templateExpandExtended
function expandString() { templateExpandStr "$@"; }
function templateExpandStr()
{
	if  [ "$bgCoreBuiltinIsInstalled" ]; then
		builtin bgCore $FUNCNAME "$@"
		return
	fi

	local _objectContextES retVar
	while [ $# -gt 0 ]; do case $1 in
		-s) ;;
		-o*|--objCtx) bgOptionGetOpt val: _objectContextES "$@" && shift ;;
		-R*) bgOptionGetOpt val: retVar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local str="$1"
	local scrContextForErrors="$2"
	local varNameToken

	# process the escape sequence to allow templates to contain a literal % and %%
	str="${str//%%/}"

	local _literalPercentsSeen
	for varNameToken in $(templateGetVarTokens -s $str); do
		[[ "$varNameToken" =~ ^\\\\*$ ]] && _literalPercentsSeen="1"
		[[ "$varNameToken" =~ ^/*$ ]] && _literalPercentsSeen="1"
		varNameToken="${varNameToken//%20/ }"
		local _nameETV="" _valueETV=""
		templateEvaluateVarToken "$varNameToken" _nameETV _valueETV "${scrContextForErrors:-string:${str:0:40}}"

		str="${str//%$varNameToken%/$_valueETV}"
	done
	[ "$_literalPercentsSeen" ] && str="${str//$templateMagicEscToken/%}"

	returnValue "$str" "$retVar"
}


templateMagicEscToken="|#0.0.7#|"


# usage: templateExpand [<options>] <srcTemplate> <dstFilename>|- [ <varName1>:<value1>..<varNameN>:<valueN>]
# usage: templateExpand [<options>] -s <stringContent> -d <dstFilename>  [ <varName1>:<value1>..<varNameN>:<valueN>]
# usage: templateExpand [<options>] -f <srcTemplate> -d <dstFilename>  [ <varName1>:<value1>..<varNameN>:<valueN>] ]
# Expands the <srcTemplate> and prints the results into <dstFilename> or to stdout
# Expand means that variable references in the template are replaced with the values of coresponding
# values of variables set in the linux ENV.  Variables can optionally be specified that will be added to
# the ENV just for the duration of the template expansion.
#
# Variable syntax and Examples:
#   see templateEvaluateVarToken for a description of the supported syntax
#
# Params:
#    <srcTemplate> : the source content to be expanded can be specified in several different ways. If neither the -f nor -s options
#            are incuded, then the first positional parameter will be interpreted as the <srcTemplate> file name. templateFind will
#            be used to get the absolute path.
#   <dstFilename>  : the destination where the expanded template wil be written. If it is '-' or '--' or '', it will be written to
#            stdout. If the -d option is not used to specify <dstFilename>, the first or second positional parameter (depending on
#            whether <srcTemplate> is the first) will be interpreted as <dstFilename>
#   <varNameN>:<valueN> or <varNameN>=<valueN> : attributes that will be exported in the ENV and available
#            for use in the template. A caller can also export variables into the ENV before calling this
#            function. Any specified on this command line will be in scope only for the template expansion.
# Options:
#    -s <string> : use <string> as the template content to expand
#    -f|--file=<srcTemplate> : use the content contained in <file> as the template content to expand. templateFind will be used to
#           get the absolute path
#    -d|--destination=<dstFilename> : send the output to this destination. '-', '--' and '' will cause it to be written to stdout
#    -o|--objCtx=<objectScope> : when a template variable begins with a $, it is interpreted as an object reference. The <objectScope> will be
#           prepended to the template variable so that the members of the <objectScope> object will be the global scope of template vars
#           The default is "" so that the callers bash variables are queried for individual objects.
#    -S <changedStatusVar> : <changedStatusVar> will be set to "1" if <destFile> is changed by this call
#    --interactive : if the destination file already exists and the expanded template is different, start a compare gui app to
#           allow the user to merge the changes
# See Also:
#    man(5) bgTemplateFileFormat
#    templateEvaluateVarToken
#    templateListVars
#    templateExpandStr
#    templateExpandExtended
function expandTemplate() { templateExpand "$@"; }
function templateExpand()
{
	if  [ "$bgCoreBuiltinIsInstalled" ]; then
		builtin bgCore $FUNCNAME "$@"
		return
	fi

	local origArgs=("$@")
	local _objectContextES changedStatusVar_ interactiveFlag mkdirFlag
	local srcTemplate srcTemplateParams srcTemplateContent srcTemplateSpecified
	local dstFilename dstFilenameSpecified fileOpts=() userOwner groupOwner permMode policy
	while [[ "$1" =~ ^- ]]; do case $1 in
		-p|--mkdir)   mkdirFlag="-p" ;;
		-u*|--user*)  bgOptionGetOpt val: userOwner  "$@" && shift; fileOpts+=(-u       "$userOwner" ) ;;
		-g*|--group*) bgOptionGetOpt val: groupOwner "$@" && shift; fileOpts+=(-g       "$groupOwner") ;;
		--perm*)      bgOptionGetOpt val: permMode   "$@" && shift; fileOpts+=(--perm   "$permMode"  ) ;;
		--policy*)    bgOptionGetOpt val: policy     "$@" && shift; fileOpts+=(--policy "$policy"    ) ;;
		-s*) bgOptionGetOpt val: srcTemplateContent "$@" && shift
			srcTemplateParams=(-s "$srcTemplateContent")
			srcTemplateSpecified="1"
			;;
		-f*|--file) bgOptionGetOpt val: srcTemplate "$@" && shift
			srcTemplateSpecified="1"
			;;
		-d*|--destination*) bgOptionGetOpt val: dstFilename "$@" && shift
			dstFilenameSpecified="1"
			;;
		-o*|--objCtx) bgOptionGetOpt val: _objectContextES "$@" && shift ;;
		-S*|--statusVar*) bgOptionGetOpt val: changedStatusVar_ "$@" && shift ;;
		--interactive) interactiveFlag="--interactive" ;;
	esac; shift; done
	[ ! "$srcTemplateSpecified" ] && { srcTemplate="$1"; shift; }
	[ ! "$dstFilenameSpecified" ] && { dstFilename="$1"; shift; }

	# either - or -- is interpretted as sending the output to stdout. '-' b/c gnu cmds do that and '--' b/c it signals the transition
	# to variable list on the cmdline
	[[ "$dstFilename" =~ ^--?$ ]] && dstFilename=""

	# if any name/value pairs were listed on the command line set them here
	while [ $# -gt 0 ]; do
		attribute="$1"; shift
		local _name="${attribute%%[:=]*}"
		local _value="${attribute#*[:=]}"
		local -x $_name=$_value
	done

	# add templateFile to var context for use in templates
	local -x templateFile="$srcTemplate"

	# TODO: add _templateStackPushFrame/_templateStackPopFrame and change assertError to assertTemplateError for better error messages

	# we allow the destination name to contain template vars too. Also it can be -- to disambiguate from the name/value pairs
	if [[ "$dstFilename" =~ % ]]; then
		dstFilename=$(filename=$dstFilename templateExpandStr $dstFilename) || assertError -v srcTemplate -v dstFilename "expanding dstFilename failed"
	fi

	# see if sudo is needed to read the input file or write the output file
	local sudoOpts; bgsudo --makeOpts sudoOpts ${srcTemplate:+-r "$srcTemplate"} ${dstFilename:+-w "$dstFilename"} -p "creating '${dstFilename##*/}' [sudo] "

	if [ "$srcTemplate" ]; then

		# if a complete path was not given, search for this template in the system template paths.
		local usedTemplatePath
		if [[ ! "$srcTemplate" =~ ^/ ]]; then
			usedTemplatePath="1"
			templateFind -R srcTemplate "$srcTemplate"
			[[ ! "$srcTemplate" =~ ^/ ]] && usedTemplatePath=""
		fi

		# if the source template is a folder, hand off to templateExpandFolder
		if [ -d "$srcTemplate" ]; then
			templateExpandFolder "${origArgs[@]}"
			return
		fi

		# if the source exists without searching the system template path but is not a text file the
		# expansion is trivially considered done and it collapses to the same as a copy. This supports
		# expandFolder which may expand a folder with no template content. Maybe this would be better
		# done there but it does make sense in this context. We do not send non-text files to stdout, but
		# maybe we should to support pipes?
		if [ ! "$usedTemplatePath" ] && [ -f "$srcTemplate" ] && [[ ! "$(file -ib $srcTemplate)" =~ ^text ]]; then
			if [ "$dstFilename" ] && [ "$srcTemplate" != "$dstFilename" ]; then
				fsMakeParent $mkdirFlag "$dstFilename"
				bgsudo -O sudoOpts cp "$srcTemplate" "$dstFilename"
			fi
			[ "$dstFilename" ] && [ ${#fileOpts[@]} -gt 0 ] && fsTouch --typeMode=f "${fileOpts[@]}" "$dstFilename"
			return 0
		fi

		srcTemplateParams=(-f "$srcTemplate")
	fi

	# prepare the script that will replace the variables that appear in the template. We build one big
	# sed script based on each unique token contained in the template and then run sed to do it in one
	# pass

	# the empty escape sequence is an empty string without the pair of % so templateGetVarTokens won't
	# return it. So put its rule in unconditionally
	local sedScript=""

	# now add a replacement sed command for each token found in the template.
	# note that we rely on templateGetVarTokens returning the %/% and %\% tokens first so that we will replace them with templateMagicEscToken
	# first so that those % do not interfere with other matches. e.g. "%/%name%/%" -> name should not be a token b/c its % are escaped
	local _literalPercentsSeen
	local varNameToken; for varNameToken in $(templateGetVarTokens "${srcTemplateParams[@]}" ); do
		[[ "$varNameToken" =~ ^\\\\*$ ]] && _literalPercentsSeen="1"
		[[ "$varNameToken" =~ ^/*$ ]] && _literalPercentsSeen="1"
		varNameToken="${varNameToken//%20/ }"
		local _nameETV="" _valueETV=""
		templateEvaluateVarToken "$varNameToken" _nameETV _valueETV "$srcTemplate"

		# we don't want sed to interpret \ in the data
		_valueETV="${_valueETV//\\/\\\\}"

		# the sed script will use / to delimit the s command so escape it in the data
		_valueETV="${_valueETV//\//\\/}"

		# escape the special regex characters so we can match the literal token even if it looks like a regex
		stringEscapeForRegex varNameToken

		# if the data contains the literal newline char, add the continuation char \ in front of it or sed gets confused
		_valueETV="${_valueETV//$'\n'/\\$'\n'}"

		newScriptPart='s/%'"${varNameToken//\//\\/}"'%/'"$_valueETV"'/g'
		printf -v sedScript "%s \n%s" "$sedScript" "$newScriptPart"
	done
	printf -v sedScript "%s \n%s" "$sedScript" "s/%%//g"
	[ "$_literalPercentsSeen" ] && printf -v sedScript "%s \n%s" "$sedScript" "s/$templateMagicEscToken/%/g"
	#bgtraceVars sedScript

	# call sed to do the actual expansion
	local results
	if [ "$dstFilename" ]; then
		if [ -e "$dstFilename" ] && [ "$interactiveFlag" ]; then
			local tmpDir; fsMakeTemp -d tmpDir
			templateGetContent "${srcTemplateParams[@]}" | sed -e "$sedScript" > "$tmpDir/expandedTemplate"
			results=("${PIPESTATUS[@]}")
			if (( ${results[0]:-0}+${results[1]:-0}+${results[2]:-0} == 0 )); then
				[ "$srcTemplate" ] && fsCopyAttributes "$srcTemplate" "$tmpDir/expandedTemplate"
				if fsIsDifferent "$tmpDir/expandedTemplate" "$dstFilename"; then
					bgsudo -w "$dstFilename" $(getUserCmpApp) "$tmpDir/expandedTemplate" "$dstFilename"
				fi
			fi
			fsMakeTemp --release tmpDir
		else
			templateGetContent "${srcTemplateParams[@]}" | sed -e "$sedScript" | pipeToFile $mkdirFlag "$dstFilename"
			results=("${PIPESTATUS[@]}")
			pipeToFile --didChange "$dstFilename" && setReturnValue "$changedStatusVar_" "1"
			if [ "$srcTemplate" ] && (( ${results[0]:-0}+${results[1]:-0}+${results[2]:-0} == 0 )); then
				fsCopyAttributes "$srcTemplate" "$dstFilename"
			fi
		fi
		[ "$dstFilename" ] && [ ${#fileOpts[@]} -gt 0 ] && fsTouch --typeMode=f "${fileOpts[@]}" "$dstFilename"
	else
		templateGetContent "${srcTemplateParams[@]}" | sed -e "$sedScript"
		results=("${PIPESTATUS[@]}")
	fi
	[ ${results[0]:-0} -gt 0 ] && assertError -v srcTemplateParams "could not read template contents"
	[ ${results[1]:-0} -gt 0 ] && assertError -v sedScript -v srcTemplate "sed failed"
	[ ${results[2]:-0} -gt 0 ] && assertError -v dstFilename "could not write to file"
	true
}






# usage: templateExpandFolder [-o <objectScope>] <templateFolder> <destinationFolder>
# This copies an entire folder tree to a new location expanding and template variable tokens found in
# file and folder names and inside any text files. Binary files are copied as is.
# This is used, for example, to create a new project folder from a template folder.
# Options:
#     -o|--objCtx=<objectScope> : when a template variable begins with a $, it is interpreted as an object reference. The <objectScope> will be
#           prepended to the template variable so that the members of the <objectScope> object will be the global scope of template vars
#           The default is "" so that the callers bash variables are queried for individual objects.
# See Also:
#    man(5) bgTemplateFileFormat
#    templateEvaluateVarToken
#    templateListVars
#    templateExpand
function templateExpandFolder()
{
	local _objectContextES="" fileOpts=() folderOpts=() userOwner groupOwner permMode policy
	while [[ "$1" =~ ^- ]]; do case $1 in
		-o*|--objCtx) bgOptionGetOpt val: _objectContextES "$@" && shift ;;
		-u*|--user*)  bgOptionGetOpt val: userOwner  "$@" && shift; fileOpts+=(-u "$userOwner");  folderOpts+=(-u "$userOwner") ;;
		-g*|--group*) bgOptionGetOpt val: groupOwner "$@" && shift; fileOpts+=(-g "$groupOwner"); folderOpts+=(-g "$groupOwner") ;;
		--perm*)      bgOptionGetOpt val: permMode   "$@" && shift
			if [[ "$permMode" =~ ^(groupread|groupwrite)$ ]]; then
				policy="$permMode"
				permMode=""
			else
				permMode="${permMode// }"
				[ ${#permMode} -eq 9 ] && permMode=".$permMode" # the caller can leave out the file type bit
				[ "$permMode" ] && [[ ! "$permMode" =~ ^[.][-r.][-w.][-xsS.][-r.][-w.][-xsS.][-r.][-w.][-x.]$ ]] && assertError -v permMode "The --perm=<rwxBits> must be a 9 or 10 character string matching [.]?[.r-][.w-][.x-][.r-][.w-][.x-][.r-][.w-][.x-]"
			fi
			;;
		--policy*) bgOptionGetOpt val: policy   "$@" && shift ;;
	esac; shift; done
	local intemplatename="$1";     assertNotEmpty intemplatename
	local outfoldername="${2%/}";  assertNotEmpty outfoldername

	# run the intemplatename through templateFind which will make it a full path or empty if not fund
	templateFind -R intemplatename "$intemplatename"
	intemplatename=${intemplatename%/}
	[ ! -d "$intemplatename" ] && assertError "the template folder '$intemplatename' does not exist"

	# process the permission options into fileOpts and folderOpts
	# note that we could simply pass the --perm and --policy options through for files and folders but its a bit more eifficient
	# to render them here since we may be creating lots of files and folders
	if [ "$permMode$policy" ]; then
		local filePerms="$permMode" folderPerms="$permMode"
		fsPolicyToPerms -R filePerms   --typeMode=f "$policy"
		fsPolicyToPerms -R folderPerms --typeMode=d "$policy"
		fileOpts+=(--perm "$filePerms")
		folderOpts+=(--perm "$folderPerms")
	fi

	# make the folder structure from the template in the new outfoldername folder
	fsTouch "${folderOpts[@]}" -dp  "$outfoldername/"
	local folderlist=$(find "$intemplatename" -mindepth 1 -type d -exec echo {} \;)
	for folder in $folderlist; do
		local relFolder="${folder#$intemplatename}"
		expandString -R relFolder "${relFolder#/}" || assertError -v folder -v intemplatename -v outfoldername "expanding folder name"
		fsTouch "${folderOpts[@]}" -dp  "$outfoldername/$relFolder"
	done

	local textFileList=$(find "$intemplatename"  -type f -exec echo {} \;)
	for txtfile in $textFileList; do
		local relTxtFile=${txtfile#$intemplatename/}
		templateExpand "${fileOpts[@]}" $txtfile $outfoldername/$relTxtFile
	done
	return 0
}


########################################################################################################################################
### generic extended template system
#   The extended template function support %directives to include other templates and set variable values
#   from inside templates. Plugins can register new directives to add new features specific to a particular application.

# $templateCustomDirectives allows a script that uses this system to extent the template directives used in template files.
# For example: templateCustomDirectives[newDirectiveName]="functionNameThatHandlesTheDirective"
declare -A templateCustomDirectives

# a script that uses this system can set this variable to specify one or more folders where templates can be found. folders are : separated
# OBSOLETE: search for all uses of this and upgrade to the new templateFind way
#export bgTemplatePath="${bgTemplatePath}"


# usage: _templateStackPushFrame
# This is a helper function for the templateExpand functions.
# Each time a %include directive is encounted, this function creates a new associative array to keep
# track of it. A main advantage is that when an error occurs, assertTemplateError can walk the stack
# and show the file, line number, and template line at each nested stack frame so that the user can
# see the context of the error. It also allow features to accumulate state and unwind it in an intuitive
# way. Relative iniSections can be search for in the order of most recent context first so that each
# template that includes others, can set state that becomes the default but then  can be overriden just
# for the duration of an include.
#
# It assumes that there is only one logical template expand operation in any given PID and time. Typically,
# template expand operations are done in a subshell to limit the effect of exporting template variables.
# Each subshell has its own global named space so the global _templateContext can have independent state
# for each expand operation that might be going on at the same time. If a template directive expands a
# template it can choose to create a subshell an set its _templateContext="" so that it is independent.
# If it simply calls the expand function, the state will be logically part of the ongoing expansion.
function _templateStackPushFrame()
{
	# declare it global without setting it (not sure if this is needed since we are not setting any attributes)
	declare -g _templateContext

	# save the current state into the current stack frame. Note that the top level won't save anything
	# because we are only initiaizing the first frame and there is no parent scope
	if varIsAMapArray $_templateContext; then
		local varName; for varName in $templateStateList; do
			printf -v "$_templateContext[$varName]"     "%s" "${!varName}"
		done
	fi

	# create a new stack frame associative array and push it onto the stack.
	# the previos current will be set as the parent of this new frame so that we have a linked list.
	local parentContext="$_templateContext"
	genRandomIDRef _templateContext 9 "[:alnum:]"
	declare -gA $_templateContext="()"
	printf -v "$_templateContext[parent]" "%s" "$parentContext"
}

# usage: _templateStackPopFrame
# This is a helper function for the templateExpand functions.
# This is the compliment to _templateStackPushFrame call after finishing an include directive
# it removes the current template context and replaces it with its parent
function _templateStackPopFrame()
{
	# delete the current frame and restore its parent as the new current
	declare -g _templateContext
	varIsAMapArray $_templateContext || return 1
	local oldContext="$_templateContext"
	_templateContext="$(deRef $oldContext[parent])"
	unset $oldContext

	# restore the current state from the new current stack frame. Note that the top level wont restore
	# anything because it removed the last frame and no state is left
	if varIsAMapArray $_templateContext; then
		local varName; for varName in $templateStateList; do
			printf -v "$varName"     "%s" "$(deRef $_templateContext[$varName])"
		done
	fi

	return 0
}

# usage: _templateGetCurrentScopeFiles <curScopeFilesVar>
# This walks the template stack and returns all the template files
# See Also:
#    _templateStackPushFrame
function _templateGetCurrentScopeFiles()
{
	local curScopeFilesVar="$1"
	eval "$curScopeFilesVar=()"
	local context=$_templateContext
	while varIsAMapArray $context; do
		eval "$curScopeFilesVar+=("$(deRef $context[templateFile])")"
		eval "$curScopeFilesVar+=($(deRef $context[filesInScope]))"
		context="$(deRef $context[parent])"
	done
}

# usage: assertTemplateError <message>
# This assert will include the template stack trace so that the user will have context. Its pretty
# good and only showing stuff that exists so that its not ugly if its used in a place that might not
# have some expected context.
# Options:
#   -f) include the list of template files that are in scope whose iniSection names can be refered to
#       without qualifying the file name.
#    -v <varName> : pass through to assertError to dispalay the context of the error
# See Also:
#    _templateStackPushFrame
function assertTemplateError()
{
	local -a opts filesFlag
	while [ $# -gt 0 ]; do case $1 in
		-v*) bgOptionGetOpt opt: opts "$@" && shift ;;
		-f)  filesFlag="-vtemplateFilesInScope" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local message="$1"

	# save the current state so that we can access it in a stack frame like the others
	if varIsAMapArray $_templateContext; then
		local varName; for varName in $templateStateList; do
			printf -v "$_templateContext[$varName]"     "%s" "${!varName}"
		done
	fi

	local stkTraceFmtSize=0
	local _stkContext="$_templateContext"
	while varIsAMapArray $_stkContext; do
		local countStr="$(deRef $_stkContext[templateName])$(deRef $_stkContext[templateSection])$(deRef $_stkContext[templateLineNum])"
		(( stkTraceFmtSize < ${#countStr}+3 )) && stkTraceFmtSize=$((${#countStr}+3))
		_stkContext="$(deRef $_stkContext[parent])"
	done

	local -a stack=()
	local _stkContext="$_templateContext"
	while varIsAMapArray $_stkContext; do
		local section="$(deRef $_stkContext[templateSection])"; [ "$section" ] && section=":$section"
		local lineNum="$(deRef $_stkContext[templateLineNum])"; [ "$lineNum" ] && lineNum="($lineNum)"
		local name="$(deRef $_stkContext[templateName])"
		local stkTmplateLine="$(deRef $_stkContext[templateLine])"
		local stkLine="$(printf "%${stkTraceFmtSize}s : %s" "$name$section$lineNum" "$stkTmplateLine" )"
		stack=("$stkLine"  "${stack[@]}")
		_stkContext="$(deRef $_stkContext[parent])"
	done

	[ "$filesFlag" ] && local templateFilesInScope; _templateGetCurrentScopeFiles templateFilesInScope

	local templateLineFlag; [ "$templateLine" ] && templateLineFlag="-vtemplateLine"
	local stackFlag; [ "$stack" ] && stackFlag="-vstack"
	assertError $templateLineFlag $stackFlag $filesFlag "${opts[@]}" "$message"
}



# usage: templateEnterNewScope <srcTemplate>
# This is called whenever a new template content is going to be started. Typically at the start of
# templateExpandExtended and in the %include dirctive.
# It saves the current context state on the tempplateStack and then starts a new stack frame from
# the information it derives from <srcTemplate>
# It also parses <srcTemplate> into the parent context variables templateFile templateName templateSection templateLineNum
#    <srcTemplate> : comes from the '%include <srcTemplate>' directive or the initial call param..
#          The result may be context sensitive. The template files being on the stack and any brought into scope
#          with the  '%use <templateName>' directive make of the current scope. Any section name in that scope
#          can be refered to without explicitly naming its file. The order of the scope is important because the
#          section names in more recent scopes hide similarly named sections in earlier scopes
#
# Param:
#    <srcTemplate> : specifies some template content -- either a whole template file or a section
#       It can take several forms:
#          filename[:]            # content is the entire file
#          filename:sectionName   # content is the INI section "[ <sectionName> ]" from that file
#          [:]varSectionName      # content is the INI section in the most recent template file in scope where it is found
#       Note that section names can contain a : as long as the : that separates the file is present.
#       Note that if the : is not present, the function first tries interpreting it as a section name
#       and then if not found, it tries it as a file name.
# Context Variables set:
#    <templateFile>    : If the content exists, this will be the path to acces it
#    <templateSection> : If the content is an INI section within the file this will be set. If the
#                        content is the entire file, this will be empty.
#    <templateName>    : This is the name of the file without the path. Useful for syntax error messages.
#    <templateLineNum> : The line number in the file where the content begins. For entire files this
#                        will be 0. For sections it will be the line number of the INI section line.
#                        Useful for syntax error messages.
function templateEnterNewScope()
{
	_templateStackPushFrame

	local srcTemplate="$1"
	local found currentFilesInScope

	# if its fully qualified parse out what we know
	if [[ "$srcTemplate" =~ : ]]; then
		templateFile="${srcTemplate%%:*}"
		templateSection="${srcTemplate#*:}"
	fi

	# if the file name is not explicitly set, lets see if we can find it by looking for the section
	# in the set of current files in scope (being used)
	# we might know the section name or we might have to try srcTemplate as a possible section
	if [ ! "$templateFile" ]; then
		_templateGetCurrentScopeFiles currentFilesInScope
		read -r templateFile templateSection templateName templateLineNum < \
			<(gawk -v iniTargetSection="${templateSection:-$srcTemplate}" '
				'"$awkLibINIFiles"'
				inTarget {
					contextFile=FILENAME; sub("^.*/","",contextFile)
					print FILENAME "  " iniTargetSection "  " contextFile "  " FNR
					found=1
					exit (found)?0:1
				}
				END {exit (found)?0:1}
			' $(fsExpandFiles -f  "${currentFilesInScope[@]}") )
		[ "$templateFile" ] && found="1"
	fi

	# next, if it wasn't fully qualified, see if srcTemplate matches a file name in the template paths
	if [ ! "$templateFile" ] && [[ ! "$srcTemplate" =~ : ]]; then
		templateFind -R templateFile "$srcTemplate"
		if [ "$templateFile" ]; then
			templateSection=""
			templateName="${templateFile##*/}"
			templateLineNum="1"
			found="1"
		fi
	fi

	# if the templateFile was set explicitly with the : and find it
	if [ ! "$found" ] && [ "$templateFile" ]; then
		templateFind -R templateFile "$templateFile"
		if [ "$templateFile" ]; then
			templateName="${templateFile##*/}"
			templateLineNum="1"

			# if there is also a section specified, find it in the file
			if [ "$templateSection" ]; then
				read -r templateLineNum < \
					<(gawk -v iniTargetSection="${templateSection}" '
						'"$awkLibINIFiles"'
						inTarget {
							print FNR
							exit
						}
					' "$templateFile" )
				[ ! "$templateLineNum" ] && assertTemplateError -v templateFile -v templateSection -v srcTemplate "the section was not found in the template file"
			fi
			found="1"
		fi
	fi

	[ ! "$found" ] && assertTemplateError -f -v srcTemplate -v templateFile -v templateSection "could not find a template file in the system template paths"
}

# usage: templateLeaveScope
# This should be called in pairs with templateEnterNewScope
# See Also:
#    templateEnterNewScope
function templateLeaveScope()
{
	_templateStackPopFrame
}


# usage: templateExpandExtended [-o <objectScope>] <srcTemplate> [--] [ <varName1>:<value1>..<varNameN>:<valueN> ]
# This expands template content with these additional features/differences over templateExpand:
#   * Output is always sent to stdout. If you want to write to a file use ...
#     example: templateExpandExtended <srcTemplate> | pipeToFile <dstFilename>
# Variables used from Parent Scope :
#    _objectContextES : points to the current object context for evaluating object style template vars
# Params:
#    <varNameToken> : the variable token as written in the template file and returned by templateGetVarTokens
#         The <varNameToken> is everything between the %% but does not include the %%
#    <nameReturnVar> : output var to receive the name of the variable being referenced
#    <valueReturnVar> : output var to receive the string value that the token evaluates to
#    <scrContextForErrors> : optional context string. If this function asserts an error, this string
#         is included as the context of where the error happened.
# Options:
#     -o|--objCtx=<objectScope> : when a template variable begins with a $, it is interpreted as an object reference. The <objectScope> will be
#           prepended to the template variable so that the members of the <objectScope> object will be the global scope of template vars
#           The default is "" so that the callers bash variables are queried for individual objects.
#     --getInputVariables : some extended templates use the %inputVariables directive to get values that
#                           the caller passes into this function. Bash completion routines can use this
#                           option to get the list of variables that are expected so that it can prompt the
#                           user to enter them
# See Also:
#    man(5) bgTemplateFileFormat
function expandTemplateExtended() { templateExpandExtended "$@"; }
function templateExpandExtended()
{
	local _objectContextES getInputVariablesFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-o*|--objCtx) bgOptionGetOpt val: _objectContextES "$@" && shift ;;
		--getInputVariables) getInputVariablesFlag="1" ;;
	esac; shift; done
	local srcTemplate="$1"; shift

	# any variables that we define in this string will be local to this template run and be pushed onto
	# a stack frame when ever a include directive starts and restored from the stack frame when it ends
	local templateStateList="defaultScopeModifier inEndSect templateFile templateName templateSection templateLineNum templateLine condBlockState condBlockLevel expandedLine line firstToken filesInScope"
	local -x $templateStateList

	templateEnterNewScope "$srcTemplate"

	# make stdin also available on fd 3 so that confirm can read user input from it
	[ ! -t 3 ] && exec 3<&0

	_templateProcessOneScope "$@" || templateAbort="$?"

	[ -t 3 ] && exec 3>&-

	templateLeaveScope

	return $templateAbort
}

# usage: _templateProcessOneScope
# helper function for templateExpandExtended
function _templateProcessOneScope()
{
	defaultScopeModifier="export"
	inEndSect=""
	condBlockLevel=0

	# pipe the content into a while loop to scan it one line at a time
	while IFS="" read -r templateLine; do
		(( templateLineNum++ ))
		_templateProcessOneLine "$@" || return
	done < <(templateGetContent -f "$templateFile" "$templateSection")

	[ $condBlockLevel -gt 0 ] && assertTemplateError "%unmatched block. tempate ended without closing the open conditional block"
}

# usage: _templateProcessOneLine
# helper function for templateExpandExtended
function _templateProcessOneLine()
{
	# expand the variables found on this line regardless of whether its a directive or a content line
	expandedLine="$(expandString "$templateLine")" || assertTemplateError "variable expansion error "
	line="$expandedLine"

	# get the first token and check to see if it is a directive n the case statement. If its not, the case will
	# fall through to the default processing which just echo's the line
	parseOneBashToken line firstToken

	# if we are currently in false condition, turn all lines except the ones that will effect the condition
	# into a comment that will be skipped
	if [ $condBlockLevel -gt 0 ] && [ ! "$condBlockState" ]; then
		[[ ! "$firstToken" =~ ^(%})|(%else)|(%end) ]] && firstToken="%#"
	fi

	case $firstToken in
		%use)
			# usage: %use filename
			local fullFillPath; templateFind -R fullFillPath "$line"
			[ ! "$fullFillPath" ] && assertTemplateError "%use directive: file '$line' not found in system template paths"
			strSetAdd -n -S filesInScope "$fullFillPath"
			;;

		%include)
			# usage: %include filename                  # include entire file
			# usage: %include [filename]:[sectionName]  # include INI section from file
			# usage: %include [:]sectionName            # include INI section from the current file or a file set by $use
			local includedContentLocationSpec
			parseOneBashToken line includedContentLocationSpec

			local includedContentFile includedContentSection includedParseContextFile includedParseContextLineNumber
			templateEnterNewScope "$includedContentLocationSpec"

			_templateProcessOneScope || templateAbort="1"

			templateLeaveScope
			[ "$templateAbort" ] && return 1
			;;

		%set)
			# usage: %set [local |global ]varName=["]valueText["]

			local scopeModifier="$defaultScopeModifier"
			local continuationOption="" tempToken="" sep="" token="" completelyRead=""
			while [ ! "$completelyRead" ]; do
				parseOneBashToken -q $continuationOption line tempToken
				local res=$?
				if [ ! "$token" ] && [[ "$tempToken" =~ ^(local)|(export)$ ]]; then
					scopeModifier="$tempToken"
				else
					token="$token${sep}$tempToken"
				fi
				continuationOption="" sep=" "
				case $res in
					1) completelyRead="1" ;;
					# 2 means the line ends in a \
					3) continuationOption="--cont 3" ;;&  # 3 means it ran out of line while in a single quote
					4) continuationOption="--cont 4" ;;&  # 4 means it ran out of line while in a double quote
					2|3|4) IFS="" read line || completelyRead="1"; sep=$'\n' ;;
				esac
			done

			# now token contains the 'varName=value' statement
			if [[ ! "$token" =~ ^[[:space:]]*[^[:space:]]*=.* ]] || [ "$line" ]; then
				assertTemplateError "%set statement: expecting '[local|global ]varName=\"varVaue\"' Quotes are optional unless value contains spaces"
			fi

			[ "$varTraceFlag" ] && echo "$contentSection : %set $scopeModifier $token" >&2

			if ! eval $scopeModifier "$token" 2>/dev/null; then
				assertTemplateError "%set statement: evaluation failed of '$scopeModifier $token'"
			fi
			;;

		%inputVariables)
			# usage: %inputVariables varName1 [ varName2 ... [ varNameN ] ] ]
			if [ "$getInputVariablesFlag" ]; then
				getInputVariablesFlag="found"
				echo "$line"
				return 101
			fi
			local paramName
			for paramName in $line; do
				if [ "${#@}" -eq 0 ]; then
					assertTemplateError "%inputVariables: caller did not provide enough input values. Ran out on '$paramName' of '$line'"
				fi
				paramValue="${1#$paramName:}"; shift
				eval export $paramName=\"$paramValue\"
			done
			;;

		%ifdef)
			# usage: $ifdef <varname> <one template line>
			# usage: $ifdef <varname> {
			#        <lines>
			#        %}
			local varname; parseOneBashToken line varname
			local condState=""; [ "${!varname:+test}" == "test" ] && condState="1"
			if [[ "$line" =~ [{][[:space:]]*$ ]]; then
				local openBrace; parseOneBashToken line openBrace
				(( condBlockLevel++ ))
				condBlockState="$condState"
			elif [ "$condState" ]; then
				echo "$line"
			fi
			;;

		%})
			# usage: $}
			# This ends a condition block. See $ifdef

			[ "$line" ] && assertTemplateError "%} directive: leftover tokens. The %} should be on a line by itself "
			[ $condBlockLevel -le 0 ] && assertTemplateError "%} directive: unmatched block end. There was no open conditional block to close "

			(( condBlockLevel-- ))
			;;

		%else)
			# usage: $else
			# Then ends a condition block and enters the opposite condition. See $ifdef

			[ "$line" ] && assertTemplateError "%else directive: leftover tokens. %else should be on a line by itself "
			[ $condBlockLevel -le 0 ] && assertTemplateError "%else directive: unmatched block end. There was no open conditional block when else was encounted"

			varToggleRef condBlockState "" "1"
			;;

		%end)
			# usage: %end -- ignore blank lines until the next non blank line
			[ $condBlockLevel -gt 0 ] && assertTemplateError "%end directive: unmatched block. tempate ended without closing the open conditional block"
			inEndSect="1"
			continue
			;;

		%#*)
			# usage: %# this comment will not be included in the output.
			continue
			;;

		%*)
			[ "$getInputVariablesFlag" ] && continue

			directiveName=${firstToken#%}
			handlerFn=${templateCustomDirectives[$directiveName]}
			if [ "$handlerFn" ] && [ "$(type -t $handlerFn)" == "function" ]; then
				eval $handlerFn \"$templateLine\" \"$parseContextFile\" \"$templateLineNum\"
			else
				assertTemplateError "unknown directive '$firstToken'"
			fi
			;;

		*)
			[ "$getInputVariablesFlag" ] && continue

			# its a free form template line so just echo it.  The end directive lets us empty lines until the
			# next non-blank line. Lines with whitespace are not empty
			if [ "$line" == "" ]; then
				[ ! "$inEndSect" ] && echo "$expandedLine"
			else
				inEndSect=""
				echo "$expandedLine"
			fi
			;;
	esac
}


# usage: cr_templateIsExpanded [-c|--check-content] <templateSpec> <destFile>
# declare that a file should exist. Apply will expand the specified template file to create the file to make it exist
# Options:
#     -c|--check-content : Normally, the contents of the destFile are not considered, If the file exists, that is sufficient
#               the -c option changes that so that the template will be expanded to a temp file every time the cr_ statement
#               is checked and if there are any differences in the content the check will fail. Apply will replace the contents
#     -e : use extended template parser which support directives in the template
DeclareCreqClass cr_templateIsExpanded
function cr_templateIsExpanded::construct() {
	contentFlag=""
	templateParser="templateExpand"
	fileOpts=()
	while [ $# -gt 0 ]; do case $1 in
		-c|--check-content)  contentFlag="-c" ;;
		-e)  templateParser="templateExpandExtended" ;;
		-u*|--user*)  bgOptionGetOpt opt: fileOpts   "$@" && shift ;;
		-g*|--group*) bgOptionGetOpt opt: fileOpts   "$@" && shift ;;
		--perm*)      bgOptionGetOpt opt: fileOpts   "$@" && shift ;;
		--policy*)    bgOptionGetOpt opt: fileOpts   "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	templateSpec="$1"
	destFile="$2"

	templateFind -R templateFile "$templateSpec"
}
function cr_templateIsExpanded::check() {
	[ ! -e "$destFile" ] && return 1
	[ ${#fileOpts[@]} -gt 0 ] && { ! fsTouch --checkOnly "${fileOpts[@]}" "$destFile" && return 1; }
	[ ! "$contentFlag" ] && return 0

	# if the templateSpec is not valid, we cant expand it
	{ [ ! "$templateFile" ] || [ ! -e "$templateFile" ]; } && return 1

	[ -d "$templateFile" ] && assertError "can not use -c option with a folder template (yet)"

	# check if the content would change...
	local tmpFile; fsMakeTemp tmpFile
	$templateParser "$templateFile" "$tempFile"
	fsIsDifferent  "$tempFile" "$destFile"
}
function cr_templateIsExpanded::apply() {
	if [ ! -e "$destFile" ] || [ "$contentFlag" ]; then
		if [ "$tempFile" ] && [ -f "$tempFile" ]; then
			cat "$tempFile" | fsPipeToFile "${fileOpts[@]}" "$destFile"
		else
			$templateParser "${fileOpts[@]}" "$templateFile" "$destFile"
		fi
	else
		fsTouch "${fileOpts[@]}" "$destFile"
	fi
}

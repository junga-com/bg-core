#!/bin/bash


# Library
# This library implements an object oriented syntax for bash scripts. It is not meant to make OO the principle for bash script
# writing. Bash should remain a simple scripting system where plain functions and simple data variables are used for most tasks.
#
# What this system provides is a way to organize and keep track of bash arrays in a way that they can be created, passed around,
# nested and eventually destroyed.
#
# There is a concept of the bash heap (see man(3) newHeapVar) that makes allocating a variable number of bash variables feasable.
# (i.e. you dont have to mange the names of these variables so that they dont collide in the global namespace). Object associative
# arrays can be declared explicitly `local -A myobj; ConstructObject ...` or on the heap `local myobj; ConstructObject ...`
#
# There is the concept of an <objRef> variable which is like a pointer to an associative array. An <objRef> is a string so it can be
# passed around to functions and stored in other arrays (things that can not be done with an array variable). There is a whole syntax
# that is supported with an <objRef> that supports many object oriented concepts and features.
#
# An <objRef> and be derenced with `local -n myvar=$($myvarRef.getOID)`. The variable myvar can then be used as either an <objRef>
# or as a plain bash associative array. Using it as an array, querying and setting elements is as efficient as any bash script.
#
# The strategy should be to use bash objects to organize the top level of a complex script and then use straight bash array syntax
# to work with the data. Low level library functions that might be called many times in a script should not require the use of
# this bash OO syntax.
#
# When a script needs to obtain information about some external concept like a git repo or a project folder, using bash objects
# can make the spript more efficient by providing a way to obtain the information once and then cache it in an associative array
# for the remainder of the script instead of each function that operates on the concept having to repeat the process of obtaining
# the information about the concept.
#
# A script author should think about calling 10's of these object syntax method calls per user action and not 100's or thousands.
#
# The main benefit to writing a method instead of a regular bash function is that is has access to a special local variable called
# 'this'. It behaves as if the function declares "local -n this=<someArray>" where the particuar <someArray> is determined by how
# the method is invoked. The algorithm instide the method can be just as efficient as any bash function, access the this array
# with native bash syntax.
#
# Supported OO features:
#     * static class data and methods
#     * polymorphism -- virtual functions
#     * dynamic construction
#     * chaining virtual functions by calling $super.methodName
#     * overriding virtual mechanism by calling a specific Class version of a function. ($myObject.ClassName::methodName)
#
# Example Bash Object Syntax:
# 	source /usr/lib/bg_common.sh
#
# 	DeclareClass Animal
# 	function Animal::__construct() { this[name]="$1"; }
# 	function Animal::whoseAGoodBoy() { echo "I am a ${this[_CLASS]}"; }
#
# 	DeclareClass Dog Animal
# 	function Dog::__construct() { : do Dog init. You dont have to define a __construct; }
# 	function Dog::whoseAGoodBoy() { echo "Is it me? I want to be a good dog."; }
#
# 	DeclareClass Cat Animal
# 	function Cat::whoseAGoodBoy() { echo "Whatever, Cats are girls. Oh BTW, my I need some fresh food"; }
#
# 	ConstructObject Dog george "George"
# 	$george.wagFrequency="45Htz" # add some more data to this object on the fly...
#
# 	ConstructObject Cat kes "kes"
# 	$kes.sleepSchedule="22/7"
#
# 	echo "Hey George, whoose a good boy?"
# 	$george.whoseAGoodBoy
#
# 	echo
# 	echo "Hey Kes, whoose a good boy?"
# 	$kes.whoseAGoodBoy
#
# 	printfVars "" -l"About George" george
# 	printfVars "" -l"About Kes" kes
#
# Run and Output...
# 	# bobg@thedead:~/bg-lib$ bashTests/test.sh
# 	# Hey George, whoose a good boy?
# 	# Is it me? I want to be a good dog.
# 	#
# 	# Hey Kes, whoose a good boy?
# 	# Whatever. Oh BTW, my I need some fresh food
# 	#
# 	# About George
# 	# wagFrequency : 45Htz
# 	# name         : George
# 	#
# 	# About Kes
# 	# name         : kes
# 	# sleepSchedule: 22/7
# 	#
# 	# bobg@thedead:~/bg-lib$
# 	#
#
# Member Variables:
# There are several ways to access the member variables stored in an object's associate array.
# From inside method functions the 'this' variable is accessed like any other associative array bash variable ...
#     this[<varName>]="..."                      eg. this[name]="spot"
#     foo="${this[<varName>]}"                   eg. foo="${this[name]}"
# From outside the Class methods the OO syntax can be used...
#     $<objRef>.<varName>="..."                  eg. $dog.name="spot"
#     <bashVar>=$($<objRef>.<varName>)           eg. foo="$($dog.name)"
#     Note that the OO syntax starts with a "$" which sets it apart from typical bash statements
# From outside the Class methods the object's associative array can be retrieved and then accessed efficiently ...
#     local -n <oidRef>="$($<objRef>.getOID)"    eg. local -n dogOID="$($dog.getOID)"
#     <oidRef>[<varName>]="..."                  eg. dogOID[name]="spot"
#     <bashVar>="${<oidRef>[<varName>]}"         eg. foo="${dogOID[name]}"
#     Note that <oidRef> also works with the OO syntax...
#     $<oidRef>.<varName>="..."                  eg. $dogOID.name="spot"
#     <bashVar>=$($<oidRef>.<varName>)           eg. foo="$($dogOID.name)"
#     That works because bash uses [0] as the default element when an array reference is used without a subscript and the OID array
#     initializes [0] with the objRef string that referes to that OID array.
# When constructing an Object the object assocaitive array can be the objRef...
#     local -A dog; ConstructObject Dog dog
#     $dog.name="Spot"
#     dog[name]="Spot"
#
# Static Member Variables:
# Static member variables are stored in a global associative array with the name of the class.
#     <className>[<staticVarName>]="..."         eg. Dog[types]="good bad"
# From inside an Instance of that class "static" can be used...
#     static[<staticVarName>]="..."              eg. static[types]="good bad"
#
# Member Functions:
# Typical method invocation...
#     $<objRef>.<methodName> [<p1> ... <p2>]     eg. $dog.bark
# Static Class method...
#     $<className>.<methodName> [<p1> ... <p2>]  eg. $Dog.howMany
# Calling a method defined in the super class from inside a method...
#     $super.<methodName>                        eg. $super.resize
# From inside a method, polymorphism can be overridden for efficiency...
#     # if jyou know that <methodName> is not virtual in your class, it can be called directly from anoter method in the class as
#     # efficiently as any function call.
#     <className>::<methodName> [<p1> ... <p2>]
#
#
# How It Works:
# This mechanism uses the bash associative array variable type as the object instance. That array can be explicitly named and created
# or 'allocated' dynamically on the 'heap'. Its most common to allocate on the heap. See man(3) newHeapVar
#
# An object's attributes are stored in its associtive array. By convention, array entry names that start with '_' are system variables
# maintained by the Class/Object mechanism and those that do not are logically part of the Object. Some system variables are useful
# to the script autor, like _CLASS. The script author can make system variables so that they are hidden by default as long as they
# take care to name them uniquly so that they are not likely to collide with system member variables added in the future.
#
# Member functions are declared the same way as any other bash function but with a particular naming convention. By naming the
# function with the convention <className>::<methodName>, the function will automatically be part of the <className> class and
# callable as a method on instances of class <className> or other classes that derive from <className>.
# Example:.
#    function Dog::speak() { echo "woof"; }
#
# Object references are normal string variables that are initialized with a syntax that is a call to _bgclassCall.
# Example object syntax call.
#      $myPet.speak "$p1"
# expands to: '_bgclassCall' '<oid>' '<className>' '<hierarchyCallLevel>' '|.speak' '<valueOfP1>'
# myPet can be a normal bash variable with the contents "_bgclassCall <oid> <className> <hierarchyCallLevel> |" or it can be
# the bash variable of the object's associtive array directly because for an array variable, $myPet is the same as ${myPet[0]}
# and the [0] element of object arrays contain ObjRef to itself.
# where
#    _bgclassCall is a stub function that uses the first 4 parameters passed to it and the class VMT table to setup the this
#                 variable and call the speak method associated with the correct class
#    <oid> is the name od the global associated array for this instance -- something like 'aQoUszTyE'
#    <className> is the class that the reference is cast as. This is typically the most derived class but can be any of the base
#                classes and depends on how the object reference is initialized
#    <hierarchyCallLevel> is an adjustment to the virtual lookup mechanism to allow refering to a more super class than <className>
#    '|' is a separator that allows _bgclassCall to know reliably that the <hierarchyCallLevel> will not get accidentally merged
#                into the .<methodName> paramter. It could have been any character. It has nothing to do with piping which bash
#                processes before this point to separate a line into 'simple commands'
# The dot syntax between the object reference and the methodName is a just a visual nicety. A space could have been used just
# the same, but it would not have looked as much like an object reference. Any character that is not a valid in a variable name
# will cause bash to see '$myPet' as a variable to expand in its 'parameter expansion' stage and then execute the resulting
# tokens as a command (_bgclassCall) and parameters (<oid> <className> <hierarchyCallLevel> |.<methodName> <p1> <p2> ...)
# No space follows the | so that the 4th parameter will be merged with the | by design. When an object reference variable is
# passed around, quotes would be needed to preserve a trailing space so this ensures that object refs can be assigned naturally.
# Besides the '.', '=', '[' '+' and '-' are supported as part of various operator syntax. See _bgclassCall for supported syntaxes.
#
# The DeclareClass function creates a global associative array with the name of the class that represents the class object.
# That array contains the static members of the class and the list of non-static member functions.
#   Example:.
#      $ import bg_objects.sh ;$L1
#      $ DeclareClass Animal
#      $ echo $Animal
#      _bgclassCall Animal Class 0 |
#
#   Maintaining the VMT:.
#   For a logical organization of code, the DeclareClass statement should be located above the method function definitions of that
#   class so at the time the DeclareClass is executed as the script file is sourced, the corresponding methods are not yet known.
#   The bg_objects.sh library maintains lazy construction mechanism for class tables so that the VMT is not built until the first
#   time a method of the class is called. At that time, all the functions that match the regex <className>::.* will be added to the
#   class's VMT so that they can be found when a object reference invokes their method name.
#   If additional class methods are subsequently sourced, we want to know that the VMT needs to be rebuilt. We use the import feature
#   of the bg_lib.sh to record the import state counter at the time we build a VMT table. Each new library that is sourced results
#   in that counter being incremented. Also, code that dynamically adds functions can use importCntr to increment that counter.
#   When _bgclassCall is processing a reference invocation, if any VMT in the hierachy has a lower import counter number than the
#   current, its VMT is rebuilt.
#
# See Also:
#    DeclareClass    : function and OO syntax for introducing a new class
#    ConstructObject : function and OO syntax for creating a new instance of a class (i.e. a new object)
#    _bgclassCall    : internal function that is the stub that make the object reference syntax work.



# usage: DeclareClass <className> [<baseClass> [<atribName1:val1> .. <atribNameN:valN>]]
# This brings a new class into existance by creating a global associative array named "<className>" which, itself is a valid object
# instance.  The optional <atribNameN:valN>'s' will initialize values in that array.
#
# The Member functions (aka Methods) of the class are named <className>::* and can be defined before or after the class is Declared.
# The first time an instance of <className> is created, the <className> array will be updated with a list of functions in the bash
# environment at that time whose name starts with <className>::*.  If a new script library is imported after that, the next time
# a <className> object is referenced, the environment will be rescanned to pick up any new <className>::* functions.
#
# Its important for the script author to define the <className>::* functions in the script before any global code that creates an
# instance of that <className> so that those member functions will be found when the VMT is initially built.
#
# Accessing Class Static Member Variables:
# Inside methods of the Class, the class's array can be refered to as "static" which is a -n alias to the <className> global array
#     example: "static[<attribName>]="<val>", foo="${static[<attribName>]}"
#
# Outside of its methods its refered to as <className>
#     example: "<className>[<attribName>]="<val>", foo="${<className>[<attribName>]}"
#
# Params:
#    <className>       : the name of the new class. By convention it should be capitalized
#    <baseClassName>   : (default=Object) the name of the class that the new class derives from.
#    <atribNameN:valN> : static class attributes to set in the new class static object.
function DeclareClass()
{
	local className="$1"; shift
	[ "$1" == ":" ] && shift  # the colon is optional syntax sugar
	local baseClass; [[ ! "$1" =~ : ]] && { baseClass="$1" ; shift; }  # attributes must have a : so if there is none, its baseclass
	[ "$className" != "Object" ] && baseClass="${baseClass:-Object}"

	[ "$baseClass" == "Class" ] && assertError "
		The special class 'Class' can not be sub classed. You can, however customize Class...
		  * add attributes to a particular Class when its declared. see man DeclareClass
		  * declare methods for use by all Class's like 'function Class::mymethod() { ...; }'
		"

	declare -gA $className
	declare -gA ${className}_vmt="()"
	if ubuntuVersionAtLeast trusty; then
		ConstructObject Class "$className" "$@"

		# a class author can define <className>::__staticConstruct() function before calling DeclareClass to do special static init
		# __staticConstruct is the end of the recursive, self defining nature of the Object / Class system
		# Its similar to the concept of having a sub class of Class to represent each different Class, but
		# instead of defining a whole new sub class (which itself would need to have a unique class data instance
		# to represent what it is), we only allow that a staticConstructor be defined. This way the loop ends
		# and the programmer has a way to define the construction of the particular Class instance.
		if type -t $className::__staticConstruct &>/dev/null; then
			# the __staticConstruct is invoked in the context of the particular Class. Since there is no instance of type <className>
			# 'this' is null. The __staticConstruct should be written to use 'static' as the thing that its constructing.
			local this="$NullObjectInstance"
			local -n static="$className"
			$className::__staticConstruct "$@"
		fi
	fi
}

# usage: DeclareClass <className> [<baseClassName> [<atribName1:val1> .. <atribNameN:valN>]]
# This is the constructor for objects of type Class. When DeclareClass is used to bring a new class into existence it creates the
# global <className> associative array and then uses this function to fill in its contents.
# A particular <className> can preform extra construction on its class object by defining a <className>::__staticConstruct function
# *before* calling DeclareClass. This Class::__construct() will be called first to init the associative array and then
# <className>::__staticConstruct will be called with this set to the class object.
function Class::__construct()
{
	# TODO: implement a delayed construction mechanism for class obects.
	#       this Class::__construct is called when ever DeclareClass is called to bring a new Class into existance
	#       that is typically done in libraries at their global scope so that it happens when they are sourced.
	#       this function implementation should do the minimal work required and delay anything it can to when an instance is
	#       used for the first time. An ::onFirstUse method could be added and called by ConstructObject when the <className>[instanceCount]
	#       is incremented from 0

	# Since each class does not have its own *class* constructor, we allow DeclareClass to specify attributes to assign.
	# TODO: this makes DeclareClass and plugins_register very similar. They should merge when 10.04 support is completely dropped
	[ $# -gt 0 ] && parseDebControlFile this "$@"

	this[name]="$className"
	this[baseClass]="$baseClass"

	### Iterate the hierarchy to maintain the global _classIsAMap and super and sub class lists in all involved classes

	declare -gA _classIsAMap
	[ ! "$baseClass" ] && _classIsAMap[$className,Object]=1
	_classIsAMap[$className,$className]=1

	local _cname="$baseClass";
	this[classHierarchy]="$className"
	while [ "$_cname" ]; do
		local existCheck="$_cname[name]"
		[ ! "${!existCheck+exists}" ] && assertError -v className -v baseClass -v this[classHierarchy] -v _cname "'$className' inherits from '$_cname' which does not exist"

		# maintain a map that lets us quickly tell if something 'isA' something else
		_classIsAMap[$className,$_cname]=1

		# this[classHierarchy] is the ordered chain of super classes.
		this[classHierarchy]="${_cname}${this[classHierarchy]:+ }${this[classHierarchy]}"

		# add ourselves to the list of sub (derived) classes in the super (base) classes list member
		stringJoin -a -d " " -e -R "$_cname[subClasses]" "$className"

		# walk to the next class in the inheritance
		local _baseClassRef="$_cname[baseClass]"
		_baseClassRef="${!_baseClassRef}" || assertError  -v _cname -v _baseClassRef ""

		# check that we are not in an infinite loop. This should end when _cname is "Object" and its's baseclass is "" but if any
		# class hierarchy gets messed up and a class (Object or otherwise) has its self as a base class, then we should assert an error
		# TODO: this does not detect complex loops A->B->C->A  use _isAMap or a local map for for this loop to detect it we revisit the same class in this loop
		[ "$_cname" == "${_baseClassRef}" ] && assertError -v className -v baseClass -v this[classHierarchy] "Inheritance loop detected"
		_cname="${_baseClassRef}"
	done

	# typically a class's methods defined after the DeclareClass line so we delay creating the list of methods until the first
	# object construction
	#Class::getClassMethods
}

# usage: <Class>.isA <className>
# returns true if this class has <className> as a base class either directly or indirectly
function Class::isA()
{
	local className="$1"
	[ "${_classIsAMap[${this[name]},$className]+exists}" ]
}

# usage: <Class>.reloadMethods
#
function Class::reloadMethods()
{
	this[_vmtCacheNum2]=-1
	#importCntr bumpRevNumber
}

# TODO: this is diconected from the _classMakeVMT/_classUpdateVMT mechaisms -- merge
# usage: <Class>.getMethods [<retVar>]
# return a list of method names defined for this class. By default This does not return methods inherited from base
# classes. The names do not include the leading <className>:: prefix.
# Options:
#    -i|--includeInherited   : include inherited methods
#    -d|--delimiter=<delim>  : use <delim> to separate the method names. default is " "
# Params:
#    <retVar> : return the result in this variable
function Class::getClassMethods()
{
	local includeInherited delim=" "
	while [ $# -gt 0 ]; do case $1 in
		-i|--includeInherited) includeInherited="-i" ;;
		-d*|--delimiter) bgOptionGetOpt val: delim "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local retVar="$1"
	_classUpdateVMT "${this[name]}"

	local -A methods=()

	local method; for method in ${this[methods]//${this[name]}::}; do
		methods[$method]=1
	done

	if [ "$includeInherited" ]; then
		local method; for method in ${this[inheritedMethods]}; do
			methods[${method#*::}]=1
		done
	fi

	local methodList="${!methods[*]}"
	returnValue "${methodList// /$delim}" $retVar
}

# DEPRECIATED: use the syntax --  $myObj.myMember.new <className> [<p1> .. <pN>]
# usage: NewObject <className>
# usage: local myObj="$(NewObject MyClass)"
# This is an alternate syntax to ConstructObject which allows assigning the ref in one line. The trade off is
# that since this is called in a subshell, it can not create the array in the callers scope (env). So it only
# returns a reference to a new random global "heap" object. On the first call, it will be created and initialized
# Parameters can not be passed to the constructor b/c the only way would be to put them in the reference where they
# would be for every call. We could devise a way to ignore them on anything but the first call, but that seems ugly
# so lets wait and see if its needed.
# If the first call is to the method "__construct", it can be used to pass parameters to the constructor.
function NewObject()
{
	local _CLASS="${1:-Object}"
	[ $# -gt 1 ] && assertError "
		parameters can not be passed to the constructor with NewObjct.
		Use ConstructObject or invoke the __construct explicitly.
		cmd: 'NewObject $@'
	"
	local _OID
	varGenVarname _OID 9 "[:alnum:]"
	echo "_bgclassCall ${_OID} $_CLASS 0 |"
}



# usage: ConstructObject <className> <objRefVar> [<p1> ... <pN>]
# usage: ConstructObject <className>::<dynamicConstructionData> <objRefVar> [<p1> ... <pN>]
# usage: local -A <objRef>; ConstructObject <className> <objRef> [<p1> ... <pN>]
# usage: local -n <objRef>; ConstructObject <className> <objRef> [<p1> ... <pN>]
# usage: local <objRef>;    ConstructObject <className> <objRef> [<p1> ... <pN>]
# This creates a new Object instance assigned to <objRef>.
#
# An object instance is a normal bash associative array that has some special elements filled in. The term OID is used to refer to
# that array. Elements in the OID whose index name starts with an _ (underscore) are system attributes and are not considered
# logical member variables. The element [0] also starts out as a system variable but if [0] is unset or reassigned, it will no
# longer treated as a system attribute. All other elements are considered member variables of the object.
#
# An <objRef> is a string variable formatted such that when derefernced, it will make an method call on the object. This <objRef>
# string is initially set in the [0] element of the object associative array which makes the array variable name a valid <objRef>
# because bash treats [0] as the default element when an array variable is used as a scalar.
#
# The caller should declare <objRefVar> before calling ConstructObject and the attributes with which it is declared will affect how
# the object is created.
#     local -A <objRefVar>;...  #  the local array <objRefVar> will be the object and no other variable will be created so that when
#             <objRefVar> passes out of scope, <objRefVar> will no longer exist. The destructor will not be called automatically.
#     local -n <objRefVar>;...  #  the object will be created as a heap variable (see man(3) newHeapVar) and <objRefVar> will be
#             set to that OID. Its important the the caller does not initialize <objRefVar> at all.
#     local <objRefVar>; ...  # the object will be created as a heap variable (see man(3) newHeapVar) and <objRefVar> will be set
#             with an ObjRef string that points to the new OID. The -n version is prefered to this, but this version allows
#              <objRefVar> to be an array entry which can not be a -n nameRef
#
# Dynamic Construction Support:
# Dynamic construction is an OO feature which allows you to create some sub class of <className> based on data passed when constructing
# an object. For this to work you define a function <className>::ConstructObject() and when using his function to create a new object
# specify the class name as "<className>::<dynamicContrustionData>" where <dynamicContrustionData> will be the first parameter passed to
# <className>::ConstructObject(), followed by <p1>...<pN>.
# Params:
#    <className> : The name of the Class of Object to be created. The class defines the methods that will be available including the
#                  <className>::__construct() method that is called automatically during the ConstructObject call
#                  If <className> is suffix like <className>::<data> and <className> defines a <className>::ConstructObject static method,
#                  this function will delegate construction to that static method passing <data> and then p1..pN and parameters.
#                  This allows dynamic construction where the particular subclass that gets constructed depends on the runtime <data>
#    <objRef>    : The name of the variable that will be used to refer to the new object.
#                  stack scope. When the caller declares <objRef> to be of type -A, it will be the object's associative array implementation
#                       and the object's scope will be limited to the function where it is declared.
#                  heap scope. When the caller passes in a plain variable as <objRef>, the new object's associative array implementation
#                       will be created on the global 'heap' and <objRef> will be set with the ObjRef string that refers to the new heap object
#                       This object will stay in scope until its explicitly deleted so it will live past the function that defines it
#    <p?>        : parameters that will be passed to the __construct method to initiate the new object's state
#
# Syntax For Using the Constructed Object:
# The range of syntax supported on the $objRef is defined in the _bgclassCall function which dispatches all $objRef calls
#   ObjRef Syntax
#   objRef can be a simple var that contains a ObjRef string
#   or it can be the object's associative array b/c [0] contains the ObjRef string and $ary is a synonym for ${ary[0]} )
#     Method Calls
#         $objRef.<methodName> <p1> <p2>
#         All methods defined for <className> and any of its super classes can be called. Class Object is a super class of all objects.
#     Member Assignment
#         $objRef.<memberVariableName>="something"
#     Member Access
#         local foo="$($objRef.<memberVariableName>)"
#     Nested Calls
#         $objRef.<memberObjectName>[.<memberObjectName>]<anySyntax>
#     Convert a ObjRef to object's associative array implementation variable (works regardless of whether objRef is already an associative array ref)
#         local -n objAry=$($objRef.getOID)
#
# Direct Array Reference:
# The $<objRef>... syntax is convenient but inefficient compared to native bash variable manipulation. Since <objRef> is a string
# variable, you can pass it to bash functions and store it in other bash array elements.  Then when you want to work with it, you
# can dereference it into a bassh associative array with the local -n feature.
#
#    local -n myObj=$($myObjRef.getOID)
#    Member Assignment
#        myObj[<memberVariableName>]="something"
#    Member Access
#        local foo=${myObj[<memberVariableName>]}
#
# ObjRef string format:
#    `_bgclassCall <OID> <Class> <hierarchLevel> |`
# Where
#    <OID> is the actual bash variable name of the associative array that holds the object data.
#    <Class> is the type of object that this ObjRef points to. The actual Class of <OID> may be a sub class of <Class>
#    <hierarchLevel> is an offset that affects how polymorphism chooses the version of a method to call. It is how the super. syntax
#          is implemented.
# When command is of the form `$<objRef>.<something...>`, bash will first replace $<objRef> with its content and then parse the line
# into tokens that are executed. The result is a call to _bgclassCall where <something..> is passed in as the operation to be performed.
# The range of syntax supported in <something...> is defined by the _bgclassCall function.
function ConstructObject()
{
	bgDebuggerPlumbingCode=(1 "${bgDebuggerPlumbingCode[@]}")
	[[ "${BASH_VERSION:0:3}" < "4.3" ]] && assertError "classes need the declare -n option which is available in bash 4.3 and above"
	local _CLASS="$1"; assertNotEmpty _CLASS "className is a required parameter"

	### support dynamic base class implemented construction
	if [[ "$_CLASS" =~ :: ]] && type -t ${_CLASS//::*/::ConstructObject} &>/dev/null; then
		_CLASS="${1%%::*}"
		local data="${1#*::}"
		shift
		local objName="$1"; shift
		$_CLASS::ConstructObject "$data" "$objName" "$@"
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		return
	fi

	# _objRefVar is a variable name passed to us so strip out any unallowed characters for security.
	# SECURITY: clean _objRefVar by removing all but characters that can be used in a variable name. foo[bar] is a valid name.
	local _objRefVar="${2//[^a-zA-Z0-9\[\]_]}"; assertNotEmpty _objRefVar "objRefVar is a required parameter as the second argument"

	# query the type attributes of _objRefVar. we support _objRefVar being declared in several different ways which affects whether
	# it will be the object array or it will be a pointer to a new heap object array.
	local _objRefVarAttributes; varGetAttributes "$_objRefVar" _objRefVarAttributes

	# this fixes a bug in pre 5.x bash where declare -p $2 would report that it does not exist if it has not yet been initialized
	# The caller can declare an associative array variable to use for this object like `local -A foo; ConstructObject Object foo`
	# Its valid to assign a string to both a -A and -a array -- it gets stored in the [0] element. If _objRefVar is a nameRef, this
	# would mess it up. In 5.x, _objRefVarAttributes will be 'n'
	[ ! "$_objRefVarAttributes" ] && { eval ${_objRefVar}=\"\"; varGetAttributes "$_objRefVar" _objRefVarAttributes; }

	# if _objRefVar is not the name of an associative array, create one on the heap and use _objRefVar to store the objRef to that
	# heap object. If its not an A array, it can be a string or a -n nameRef.
	local _OID
	local -n this
	# its an unitialized -n nameRef
	if [ "$_objRefVarAttributes" == "n" ]; then
		newHeapVar -A  _OID
		printf -v $_objRefVar "%s" "${_OID}"
		this="$_OID"

	# its an A (associative) array that we can use as our object
	elif [[ "$_objRefVarAttributes" =~ A ]]; then
		_OID="$_objRefVar"
		this="$_objRefVar"

	# its a plain string variable
	else
		newHeapVar -A  _OID
		printf -v $_objRefVar "%s" "_bgclassCall ${_OID} $_CLASS 0 |"
		this="$_OID"
	fi
	shift 2 # the remainder of parameters are passed to the __construct function

	this[_OID]="$_OID"
	this[_CLASS]="$_CLASS"
	local -n class="$_CLASS"

	# create the ObjRef string at index [0]. This supports $objRef.methodName syntax where objRef
	# is the associative array itself. because in bash, $objRef is a shortcut for $objRef[0]
	this[0]="_bgclassCall ${_OID} $_CLASS 0 |"
	this[_Ref]="${this[0]}"

	# _classMakeVMT will set all the methods known at this point. It records the id of the current
	# sourced library state which is maintained by 'import'. At each method call we will call it again and
	# will quickly check to see if more libraries have been sourced which means that it should check to see
	# if more methods are known
	#_classMakeVMT
	_classUpdateVMT "${this[_CLASS]}"

	local -n _VMT="${this[_CLASS]}_vmt"

	# invoke the constructors from Object to this class
	local _cname; for _cname in ${class[classHierarchy]}; do
		unset -n static; local -n static="$_cname"
		bgDebuggerPlumbingCode=0
		type -t $_cname::__construct &>/dev/null && $_cname::__construct "$@"
		_resultCode="$?"; bgDebuggerPlumbingCode=1
	done

	[ "${_VMT[_method::postConstruct]}" ] && ${this[_Ref]}.postConstruct
	bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
	true
}

# usage: _classUpdateVMT [-f|--force] <className>
# update the VMT information for this <className>.
# If the _vmtCacheNum2 attribute of the class is not equal to the current import revision number, rescan the sourced functions for
# any matching our class method naming scheme that associated them with this class.
# Then it visits each class in the hierarchy, starting at the most base class and sets entries in the vmt array for each method in
# the class. As each class is visited, methods with the same name overwrite methods from previous classes so that in the end, the
# method implementation from the most derived class will set set for each name.
#
# Prarms:
#    <className> : the class for which to update the VMT.  Each of its base classes will also be updated since it needs to know
#                  all methods of all base classes to decide which method implementation should be used.
# Options:
#    -f|--force  : rescan all the classes in this hierachy even if the import revision number is current.
# See Also:
#    Class::reloadMethods
# usage: _classUpdateVMT [-f|--force] <className>
function _classUpdateVMT()
{
	local forceFlag
	while [ $# -gt 0 ]; do case $1 in
		-f|--force)   forceFlag="-f" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local className="$1"; shift; #assertNotEmpty className
	local -n class="$className"

	# force resest the _vmtCacheNum2 attributes of this entire class hierarchy so that the algorithm will rescan them all this run
	if [ "$forceFlag" ]; then
		local -n _oneClass; for _oneClass in ${class[classHierarchy]}; do
			_oneClass[_vmtCacheNum2]="-1"
		done
		unset -n _oneClass
	fi

	local currentCacheNum; importCntr getRevNumber currentCacheNum

	if [ "${class[_vmtCacheNum2]}" != "$currentCacheNum" ]; then
		class[_vmtCacheNum2]="$currentCacheNum"

		_classScanForClassMethods "$className" class[methods]
		class[inheritedMethods]=""

		# fill in the vmt in order from most super class to our class so that earlier methods are overwritten by later methods
		local -n vmt="${className}_vmt"
		local _oneCname; for _oneCname in ${class[classHierarchy]}; do
			local -n _oneClass="$_oneCname"

			if [ "${_oneClass[_vmtCacheNum2]}" != "$currentCacheNum" ]; then
				_classUpdateVMT "$_oneCname"
			fi

			[ "$_oneCname" != "$className" ] && class[inheritedMethods]+="${class[inheritedMethods]:+$'\n'}${_oneClass[methods]}"

			local _mname; for _mname in ${_oneClass[methods]}; do
					vmt["_method::${_mname#$_oneCname::}"]="$_mname"
			done
		done

		# add one off methods added with Object::addMethod. These methods override any others with the same short name
		local _mname; for _mname in ${class[addedMethods]}; do
			vmt[_method::${_mname#*::}]="$_mname"
		done

		#bgtraceVars className vmt
	fi
}

# usage: _classScanForClassMethods <className> <retVar>
function _classScanForClassMethods()
{
	local className="$1"
	local retVar="$2"
	returnValue "$(compgen -A function ${className}::)" $retVar
}


# usage: DeleteObject <objRef>
# destroy the specified object
# This will invoke the __desctruct method of the object if it exists.
# Then it unsets the object's array
# After calling this, future use of references to this object will asertError
function DeleteObject()
{
	# if the caller passes in the contents of an ObjRef string with or without quotes, "$*" will be that string
	local objRef="$*"
	local -a parts=( $objRef )

	# if the caller passed in the name of a variable that contains an ObjRef string, there will be only one part.
	# note that this is different from $# because the ObjRef could have been quoted
	if [ ${#parts[@]} -eq 1 ]; then
		unset objRef; local -n objRef="$1"
		parts=( $objRef )
	fi

	# assert that the second term in the objRef is an associative array
	[[ "$(declare -p "${parts[1]}" 2>/dev/null)" =~ declare\ -[gilnrtux]*A ]] || assertError "'$objRef' is not a valid object reference"

	local -n this="${parts[1]}"
	local -n _VMT="${this[_CLASS]}_vmt"

	# local -n subObj; for subObj in $(VisitObjectMembers this); do
	# 	DeleteObject "$subObj"
	# done

	[ "${_VMT[_method::__destruct]}" ] && $this.__destruct
	unset this
}


# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |.<methodName> p1 p2 ... pN
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |.<class>::<methodName> p1 p2 ... pN
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |.<memberVarName>=<value>
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |.<memberVarName>
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |[<memberVarName>]=<value>
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |[<memberVarName>]
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |.<memberObjName>.<...>
# usage: _bgclassCall <oid> <className> <hierarchyCallLevel> |[<memberObjName>].<...>
# This is the internal method call stub. It is typically only called by objRef invocations. $objRef.methodName
# Variables Provided to the method:
#     super   : objRef to call the version of a method declared in a super class. Its the same ObjRef as this but with the <hierarchyCallLevel> term incremented
#     this    : a ref to the associative array that stores the object's state
#     static  : a ref to the associative array that stores the object's Class information. This can store static variables
#     _VMT    : a ref to the associative array that is the vmt (virtual method table) for this object
#     _OID    : name of the associative array that stores the object's state
#     _CLASS  : name of the class of the object (the highest level class, not the one the method is from)
#     _METHOD : name of the method(function) being invoked
#    _*       : there are a number of other local vars that are unintentionally passed to the method
# TODO: consider rewriting this using the ParseObjExpr function. It is more simple and maybe more efficient and needs to be in sync with the choices made in this function.
# See Also:
#    ParseObjExpr
#    completeObjectSyntax
function _bgclassCall()
{
#bgtraceBreak
	bgDebuggerPlumbingCode=(1 "${bgDebuggerPlumbingCode[@]}")
	# if <oid> does not exist, its because the myObj=$(NewObject <class>) syntax was used to create the
	# object reference and it had to delay creation because it was in a subshell.
	if ! varIsA array "$1"; then
		[[ "$1" =~ ^a[[:alnum:]]{8}$ ]] || assertError "bad object reference. The object is out of scope. \nObjRef='_bgclassCall $@'"
		declare -gA "$1=()"
		if [[ "$4" =~ ^[._]*construct$ ]]; then
			local _OID="$1"; shift
			local _CLASS="$1"; shift
			ConstructObject "$_CLASS" "$_OID" "$@"
			bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
			return
		else
			ConstructObject "$2" "$1"
		fi
	fi

	# the local variables we declare in this function will be available to access in the method function
	local _OID="$1";           shift
	local _CLASS="$1";         shift
	local _hierarchLevel="$1"; shift
	local _memberTermWithParams="$*"; _memberTermWithParams="${_memberTermWithParams#|}"
	local _memberTerm="$1";    shift; _memberTerm="${_memberTerm#|}"

	# its a noop to refer to an object without including a member, like $foo
	[ "${_memberTerm//[]. []}" ] || {
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		return
	}

	local -n this=$_OID || {
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		assertError -v _OID -v _CLASS -v _memberTermWithParams "could not setup Object calling context '$(declare -p this)'"
	}
	local -n static="${this[_CLASS]}"
	local super="_bgclassCall ${_OID} $_CLASS $((_hierarchLevel+1)) |"

	# _classMakeVMT returns quickly if new scripts have not been sourced or Class::reloadMethods has not been called
	#_classMakeVMT
	_classUpdateVMT "${this[_CLASS]}"

	local -n _VMT="${this[_CLASS]}_vmt"

	# _memberTerm is the expression the caller typed after the objRef. It could be
	#      1) a method call                      .<methodName> <p1> <p2> ...
	#      2) a member var reference             .<memberVar> or [<memberVar>]
	#      3) a member var assignment            .<memberVar>=<expresion> or [<memberVar>]=<expresion>
	#      4) a chained member object reference  .<m1>.<m2>.<m3>... or [<m1>]<m2>.<m3>
	# _mnameShort will be the first attribute name in _memberTerm
	# _memberVal is the current value of the this[$_mnameShort]
	local _mnameShort _memberVal
	case ${_memberTerm:0:1} in
		[)	_mnameShort="${_memberTerm:1}"
			_mnameShort="${_mnameShort%%[]]*}"
			_memberTerm="${_memberTerm#*]}"
			_memberTermWithParams="${_memberTermWithParams#*]}"
			;;
		.)	_mnameShort="${_memberTerm:1}"
			_mnameShort="${_mnameShort%%[].+=[]*}"
			_memberTerm="${_memberTerm#*$_mnameShort}"
			_memberTermWithParams="${_memberTermWithParams#*$_mnameShort}"
			;;
		*)	_mnameShort="${_memberTerm%%[].+=[]*}"
			_memberTerm="${_memberTerm#*$_mnameShort}"
			_memberTermWithParams="${_memberTermWithParams#*$_mnameShort}"
			;;
	esac

	local _memberVal
	[ "${_mnameShort}" ] && _memberVal="${this[${_mnameShort}]}"

	#bgtraceVars -1 _memberTerm _memberVal _mnameShort

	local _resultCode

	# some hard coded methods that can be called on a member even if that member is not an object or does not exist
	# When these methods are called directly on an object (not in a chained member reference), they are invoked normally and do not hit this case
	if [ "$_memberTerm" == ".unset" ]; then
		[ "${_memberVal:0:12}" == "_bgclassCall" ] && DeleteObject "$_memberVal"
		[ "${_mnameShort}" ] && unset this[${_mnameShort}]
	elif [ "$_memberTerm" == ".exists" ]; then
		[ "${_mnameShort}" ] && [ "${this[${_mnameShort}]+isset}" ]
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		return
	elif [ "$_memberTerm" == ".isA" ]; then
		# if its not an Object Ref, isA returns false, if it is, set the exit code by callong the isA method.
		[ "${_memberVal:0:12}" == "_bgclassCall" ] && $_memberVal"$_memberTerm" "$@"
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		return
	elif [ "$_memberTerm" == "=new" ]; then
		local newObjectClass="${1:-Object}"; shift
		local newObject
		# if [ "$newObjectClass" == "BashArray" ]; then
		# 	genRandomIDRef newObject 9 "[:alnum:]"
		# 	newObject="BashArray_$newObject"
		# 	declare -ga $newObject="()"
		# elif [ "$newObjectClass" == "BashMap" ]; then
		# 	newObject="BashMap_$newObject"
		# 	genRandomIDRef newObject 9 "[:alnum:]"
		# 	declare -gA $newObject="()"
		# else
		# 	ConstructObject "$newObjectClass" newObject "$@"
		# fi
		ConstructObject "$newObjectClass" newObject "$@"
		this[${_mnameShort}]="$newObject"

	elif [ "$_mnameShort" == "static" ]; then
		$static"$_memberTerm" "$@"

	# member chaining syntax
	#    $foo.bar.doIt p1 p2
	#    $foo[bar].doIt p1 p2
	# TODO: (maybe) change this to if '[ "${_memberTerm:0:1}" =~ [].] ]]; ... and remove _memberVal from above
	#       i.e. base it on the syntax instead of whether the the next attribute is a object
	#   $this.<memberFunct> [<p1> .. p2]
	elif [ "${_memberVal:0:12}" == "_bgclassCall" ]; then
		$_memberVal"$_memberTerm" "$@"

	# member variable appending assignment syntax
	#   $this.<classVarName>+=<newValue>
	elif [ "${_memberTerm:0:2}" == "+=" ]; then
		local sq="'" ssq="'\\''"
		_memberTerm="${_memberTermWithParams#+=}"
		[ ! "$_mnameShort" ] && {
			bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
			assertError -v errorToken:_memberTerm "Invalid object syntax in member terms"
		}
		eval "this[${_mnameShort}]+='${_memberTerm//$sq/$ssq}'"

	# member variable assignment syntax
	#   $this.<classVarName>=<newValue>
	elif [ "${_memberTerm:0:1}" == "=" ]; then
		local sq="'" ssq="'\\''"
		_memberTerm="${_memberTermWithParams#=}"
		[ ! "$_mnameShort" ] && {
			bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
			assertError -v errorToken:_memberTerm "Invalid object syntax in member terms"
		}
		eval "this[${_mnameShort}]='${_memberTerm//$sq/$ssq}'"

	# If there is _memberTerm left over at this point, then it must be an object member that has not yet been created.
	# This block creates a member object of type Object on demand. If we remove or comment out this block the next block
	# will assert an error in this case
	elif [ "$_memberTerm" ]; then
		[ ! "$_mnameShort" ] && {
			bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
			assertError -v errorToken:_memberTerm "Invalid object syntax in member terms"
		}
		this[${_mnameShort}]="$(NewObject Object)"
		${this[${_mnameShort}]}$_memberTerm "$@"

	# If there is _memberTerm left over at this point, then none of the previous cases knew how to handle it so assert an error
	elif [ "$_memberTerm" ]; then
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		assertError -v _memberVal -v _memberTerm -v _mnameShort "'${_mnameShort}' is not an Object reference member of '$_OID'"

	# calling a super class method syntax
	#   $super.<method>
	# TODO: refactor $super. implementation. The current imp only works when initiated from the most subclass because
	#       it uses classHierarchy from the start. What it needs to do is always be related from the
	#       the class that the function its used in is in.
	#       Option1: the <hierarchyCallLevel> position in an obj ref could become a list of optional flags. the super ref would just have that flag
	#           set. Hear we would detect that flag, get the calling method's class from the bash call stack, and increment the hierarchy from there.
	#       Option2: Set the super ref just before calling each method. At that time we can extract the methods' class and change the class position in the
	#           the super ref to be set to the base class of the method's class. This seems more correct but takes a small performance hit on every method call.
	#           Also we would need to change this function to respect the class in the ref over the class in the object's instance array. That also seems more
	#           correct. That would require moving the VMT from the object instance arrays to the class arrays. That was something that I was considering anyway.
	#           I think the performance hit of this will be negligbable.
	elif [ ${_hierarchLevel:-0} -gt 0 ]; then
		# This version might be better but needs to be tested
		#local h=(${static[classHierarchy]}) superName
		#local i=$((${#h[@]}-1)); while [ $_hierarchLevel -gt 0 ] && [ $((--i)) -ge 0 ]; do
		#	type -t ${h[$i]}::${_mnameShort} &>/dev/null && ((_hierarchLevel--))
		#done
		#local _METHOD="${h[$i]}::${_mnameShort}"
		#[ $_hierarchLevel -eq 0 ] && $_METHOD "$@"

		local h="${static[classHierarchy]}" superName
		local i=0; while [ "$h" ] && [ $i -lt $_hierarchLevel ]; do
			[[ ! "$h" =~ \  ]] && h=""
			h="${h% *}"
			superName="${h##* }"
			type -t ${superName}::${_mnameShort} &>/dev/null && ((i++))
		done
		if [ "$superName" ]; then
			local _METHOD="${superName}::${_mnameShort}"
			objOnEnterMethod "$@"
			bgDebuggerPlumbingCode=0
			$_METHOD "$@"
			_resultCode="$?"; bgDebuggerPlumbingCode=1; return "$_resultCode"
		fi

	# member function with explicit Class syntax
	#   $this.<class>::<memberFunct> [<p1> .. p2]
	elif [[ "$_mnameShort" =~ :: ]]; then
		local _METHOD="$_mnameShort"
		objOnEnterMethod "$@"
		bgDebuggerPlumbingCode=0
		$_METHOD "$@"
		_resultCode="$?"; bgDebuggerPlumbingCode=1; return "$_resultCode"

	# member function syntax
	#   $this.<memberFunct> [<p1> .. p2]
	elif [ "${_VMT[_method::${_mnameShort}]+isset}" ]; then
		local _METHOD="${_VMT[_method::${_mnameShort}]}"
		objOnEnterMethod "$@"
		bgDebuggerPlumbingCode=0
		$_METHOD "$@"
		_resultCode="$?"; bgDebuggerPlumbingCode=1; bgtraceVars _resultCode; return "$_resultCode"

	# member variable read syntax. Its ok to read a non-existing member var, but if parameters were provided, it looks like a method call
	#   echo $($this.<memberVar>)
	elif [ ! "$*" ]; then
		echo "${this[${_mnameShort}]}"
		[ "${this[${_mnameShort}]+test}" == "test" ]

	# not found error
	else
		bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
		assertError -v _OID -v _memberTermWithParams "member '$_mnameShort' not found for class $_CLASS"
	fi
	bgDebuggerPlumbingCode=("${bgDebuggerPlumbingCode[@]:1}")
}


function assertThisRefError()
{
	local callStatement="\$this$*"
	assertError -v callStatement "The \$this syntax is being used outside a non-static method"
}
this='assertThisRefError '




# This hook is called before each method
function objOnEnterMethod()
{
	# if the _traceMethods system attrib is set, trace the function call
	case ${this[_traceMethods]:-0} in
		1) [ "$_CLASS" != "Object" ] && bgtrace "$_CLASS::$_METHOD" ;;
		2) bgtrace "$_CLASS::$_METHOD $@" ;;
		3) bgtrace "$_CLASS::_OID.$_METHOD $@" ;;
	esac
}

# usage: objEval <objExpr>
# This evaluates an object expression that is stored in a string.
# Even though "eval <objExpr>" works the same as this function, if objEval comes from an untrusted source,
# objEval is safer because it checks that the first term is a valid oject reference
# For example, the normal way to dereference an expression is in a script write..
#      local msgName="$($obj.msg.name)"
# but if "$obj.msg.name" is in a string (for example obtained from a template file,
#      objExpr='$obj.msg.name'
#      local msgName="$(objEval $objExpr)"
function objEval() { ObjEval "$@"; }
function ObjEval()
{
	local objExpr="$1"; shift
	objExpr="${objExpr#$}"
	local oPart="${objExpr%%[.[]*}"
	local mPart="${objExpr#$oPart}"
	local callExpr="${!oPart}"
	[ "${callExpr:0:12}" == "_bgclassCall" ] || assertError "invalid object expression '$objExpr'. '\$$oPart' is not an object reference"
	# TODO: escape $objExpr so that it cant be a compound statement
	# SECURITY: escape $objExpr so that it cant be a compound statement
	eval \$$objExpr "$@"
}


# usage: GetOID <objRef> [<retVar>]
# usage: local -n obj=$(GetOID <objRef>)
# usage: local -n obj; GetOID obj
# This returns the name of the underlying array name embedded in an objRef. The result is similar to $objRef.getOID except this is
# more efficient because it simply parses the <objRef> instead of invoking a method call.
#
# An <objRef> is a string that points to an object instance such as what is returned by ConstructObject.
#
# This function is typically used to make a local array reference to the underlying array. An array reference can be used for
# anything that an objRef can but in addition, the member variables can be accessed directly as bash array elements
#
# Params:
#   <objRef> : the string that refers to an object. For simple bash variables that refer to objects, this is their value.
#              for bash arrays that refer to objects, it  the value of the [0] element. In either case, you call this
#              function like
#                  GetOID $myObj   (or GetOID "$myObj"  -- the double quotes are optional)
#   <retVar> : return the OID in this var instead of on stdout
function GetOID()
{
	local goid_retVar=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		# DEPRECIATED: -R is supported for legacy code
		-R) goid_retVar="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local objRef="$*"
	local oidVal
	if [ "{$objRef}"  == "" ]; then
		oidVal="NullObjectInstance"

	# this is the normal case
	elif [ "${objRef:0:12}"  == "_bgclassCall" ]; then
		oidVal="${objRef#_bgclassCall }"
		oidVal="${oidVal%% *}"

	# this is when objRef is a variable that points to an objRef
	elif [[ "$objRef" =~ ^[[:word:]]*$ ]] && [[ "{$!objRef}"  =~ "^_bgclassCall" ]]; then
		oidVal="${!objRef}"
assertError -v oidVal -v objRef "DEVTEST: check that this is correct. I think that we still need to extract teh array name from oidVal "

	# unknown
	else
		assertError "unknown object ref '$objRef'"
	fi

	returnValue "$oidVal" "$goid_retVar"
}

# usage: IsAnObjRef <objRef>
# returns true if <objRef> is a variable whose content matches "^_bgclassCall .*"
# The <objRef> variable should be deferenced like "IsAnObjRef $myObj" instead of "IsAnObjRef myObj"
# Params:
#   <objRef> : the string to be tested
function IsAnObjRef()
{
	local objRef="$*"
	[ "${objRef:0:12}"  == "_bgclassCall" ]
}





# usage: ParseObjExpr <objExpr> <oidPartVar> <remainderPartVar> <oidVar> <remainderTypeVar>
# Params:
# TODO: consider making this the definitive place for all bash Object syntax. Currently (circa 2016-07)
#       the _bgclassCall is the definitive keeper of the syntax and this function has to be kept in sync.
# See Also:
#    _bgclassCall
#    completeObjectSyntax()
function ParseObjExpr()
{
	local objExpr="$1"
	local oidPartVar="$2"
	local remainderPartVar="$3"
	local oidVar="$4"
	local remainderTypeVar="$5"

	local origObjExpr="$objExpr"
	local oidPartValue=""
	local remainderPartValue="$objExpr"
	local currentOID
	local remainderTypeValue=""
	local refParts memberRef tmpRef currentCLASS

	if [[ "$remainderPartValue" =~ ^\$[[:alnum:]_]+ ]]; then
		local nextTerm="${BASH_REMATCH}"
		memberRef="${nextTerm#[$]}" #"

		refParts=(${!memberRef})

		if [ "${refParts[0]}" == "_bgclassCall" ] && varIsAMapArray "${refParts[1]}"; then
			currentOID="${refParts[1]}"
			currentCLASS="${refParts[2]}"
			oidPartValue+="$nextTerm"
			remainderPartValue="${remainderPartValue#$nextTerm}"
		fi
	fi

	while [ "$currentOID" ] && [[ "$remainderPartValue" =~ ^([[:punct:]])([[:alnum:]_]+)[]]{0,1} ]]; do
		local nextTerm="${BASH_REMATCH}"
		local op="${BASH_REMATCH[1]}"
		memberRef="${BASH_REMATCH[2]}"
		if [ "$memberRef" == "static" ]; then
			tmpRef="$currentCLASS"
		else
			tmpRef="$currentOID[$memberRef]"
		fi
		refParts=(${!tmpRef})
		if [[ ! "$nextTerm" =~ ^((.unset)|(.exists)|(.isA)|(=new))$ ]] \
				&& [ "${refParts[0]}" == "_bgclassCall" ] \
				&& varIsAMapArray "${refParts[1]}"; then
			currentOID="${refParts[1]}"
			currentCLASS="${refParts[2]}"
			oidPartValue+="$nextTerm"
			remainderPartValue="${remainderPartValue#${nextTerm//[]]/\\]}}"
		else
			break
		fi
	done


	if [ "$currentOID" ]; then
		local -n currentAry="$currentOID"
		local -n currentVMT="${currentAry[_CLASS]}_vmt"
	 fi
	[ "$remainderPartValue" == ']' ] && remainderPartValue=""

	if    [ ! "$remainderPartValue" ];                                    then  remainderTypeValue="empty"
	elif [[   "$remainderPartValue" =~ ^\$ ]];                            then  remainderTypeValue="objRef"
	elif [[   "$remainderPartValue" =~ ^((.unset)|(.exists)|(=new))$ ]];  then  remainderTypeValue="builtin"
	elif [[   "$remainderPartValue" =~ ^= ]];                             then  remainderTypeValue="assignment"
	elif  [   "${currentAry[$memberRef]+exists}" ];                       then  remainderTypeValue="memberVar"
	elif  [   "${currentVMT["_method::$memberRef"]+exists}" ];            then  remainderTypeValue="method"
	else                                                                        remainderTypeValue="unknown"
	fi
	[ "$oidPartVar" ]       && printf -v $oidPartVar       "%s" "$oidPartValue"
	[ "$remainderPartVar" ] && printf -v $remainderPartVar "%s" "$remainderPartValue"
	[ "$oidVar" ]           && printf -v $oidVar           "%s" "$currentOID"
	[ "$remainderTypeVar" ] && printf -v $remainderTypeVar "%s" "$remainderTypeValue"
}


# usage: completeObjectSyntax "<partialExpression>"
# Bash command line completion routine for object expressions. The actual supported boject syntax is
# defined in two places -- ParseObjExpr and _bgclassCall.
# Object Syntax:
#  Informal: $<objRef><memberRef>[...<memberRef>] [<p1> .. <pN>]
#  Formal:
#  $<objRef><memberRefChain> <argList>
#  <objRef>         = <stringVariable> # The string must contain a particular format. Functions that return
#                       object references return a string with this format.
#                       "_bgclassCall <oid> <className> <hierarchyCallLevel> |"
#                   = <associativeArrayName> # an array initialized as an object will have its [0] member
#                       set to an obj reference string that referes to itself. Bash makes [0] the default
#                       subscript so $arrayName.<memberRefChain> will evaluate correctly.
#  <memberRefChain> = <memberRef><memberRef>...<memberRef>
#  <memberRef>      = .<memberDynamicMethod>
#                   = .<memberBuiltinMethod>
#                   = .<memberVar>
#                   = [<memberVar>]
#                   = =new <constructorArgs>
#                   = <operator><string>
#  <memberDynamicMethod> = <bashFunctionName> # defined like -- function <ClassName>::bashFunctionName() { ; }
#  <memberBuiltinMethod> = unset|exists|isA
#  <memberVar>           = <bashVarName> any associative array index that is not a reserved word.
#                          names that start with '_' are hidden in that they are not included in default member iteration
#  [<memberVar>]         = member vars can be refered to with . or [] notation
#  <operator> = +=|=
# See Also:
#    ParseObjExpr
#    _bgclassCall
function completeObjectSyntax()
{
	local cur="$1"

	local oidPart remainderPart oid remainderType
	ParseObjExpr "$cur" oidPart remainderPart oid remainderType

	if [ ! "$oid" ]; then
		vwords="$(compgen -A variable )"
		for vword in $vwords; do
			if IsAnObjRef "${!vword}"; then
				echo " ${vword}%3A"
			fi
		done
	else
		echo "cur:$remainderPart "
		local -n currentScope="$oid"
		if [ ! "$remainderPart" ]; then
			echo " [%3A .%3A"
			return
		fi
		# . completes only methods and [ completes only variables. The user has to start a var with
		# _ before system vars are offered
		local term; for term in "${!currentScope[@]}"; do
			case $term:$remainderPart in
				_method::*:.*) echo " .${term#_method::}" ;;
				_method::*)    : ;;
				_*:'[_'*)      echo " [${term}]%3A" ;;
				_*:*)          : ;;
				*)             echo " [${term}]%3A" ;;
			esac
		done
		[[ "$remainderPart" =~ ^[[] ]] && echo " [static]%3A"
		local term; for term in "=new" ".unset" ".exists" ".isA"; do
			echo " ${term}%3A"
		done
	fi
}



####################################################################################################################
### Defining the Object::methods


function Object::getOID()
{
	echo "$_OID"
}

function Object::getRef()
{
	# its also in ${this[0]} but [0] is more at risk of being accidentally overwritten
	echo "${this[_Ref]}"
}

# usage: $obj.isA <className>
# returns true if this $obj has <className> as a base class either directly or indirectly
function Object::isA()
{
	local className="$1"
	[ "${_classIsAMap[${_CLASS},$className]}" ]
}

function Object::eval()
{
	local cmdLine="$1"; shift

	# commands that start with ":" are run in the global context (w/o the $this)
	if [[ "$cmdLine" =~ ^: ]]; then
		${cmdLine#:} "$@"

	# if : is not prefixed, cmd's are run the $this content (i.e. member functions)
	else
		$this.$cmdLine "$@"
	fi
}


# usage: $obj.clone [-s] <newRefVar>
# creates a new heap Object that is initialized to the same state as $obj
# i.e. it makes an exact copy of $obj
# Params:
#    <newRefVar> : the name of the variable that the obj reference to the new object will be stored in
#                  An obj reference is the string that produces a method call to that object and is also
#                  stored in the object's implementation array at index [0]
# Options:
#    -s : shallow copy flag. Normally, members of obj that are obj references are also cloned so that the entire
#         new object shares no data with the original object. When -s is specified, object members are not copied
#         so both the original and newly cloned objects will both point to the same copy of any member objects and
#         the newly cloned object will not be independant.
function Object::clone()
{
	local shallowFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s) shallowFlag="-s" ;;
	esac; shift; done

	local newRefVar="$1"
	local newOID
	genRandomIDRef newOID 9 "[:alnum:]"
	[ "$newRefVar" ] && eval $newRefVar=\${this[_Ref]/${this[_OID]}/$newOID}

	# declStr is the complete bash serialized state of $this
	local declStr="$(declare -p "$_OID")"

	# _OID appears multiple times in the declStr -- replace them all
	declStr="${declStr//$_OID/$newOID}"
	declStr="${declStr/declare -/declare -g}"

	# create the new, global instance of the object
	eval $declStr
	local -n that="$newOID"

	if [ ! "$shallowFlag" ]; then
		local memberName; for memberName in $($that.getIndexes); do
			local memberValue="${that[$memberName]}"
			if [ "${memberValue:0:12}" == "_bgclassCall" ]; then
				$memberValue.clone that[$memberName]
			fi
		done
	fi
}

function Object::getMethods()
{
	local i; for i in "${!_VMT[@]}"; do
		echo ${i#_method::}
	done
}

# usage: $obj.hasMethod <methodName>
# returns true if the object has the specified <methodName>
function Object::hasMethod()
{
	[ "${_VMT[_method::$1]}" ]
}

# usage: $obj.addMethod <methodName>
# adds a specific, one-off method to an Object instance
function Object::addMethod()
{
	local _mname="$1"
	local _mnameShort="${_mname#*::}"

	assertError "DEV: this method needs to be updated because the _VMT is now shared amoung instances"

	this[_addedMethods]+=" $_mname"
	_VMT[_method::${_mnameShort}]="$_mname"
}


function Object::getAttributes()
{
	Object::getIndexes "$@"
}

function Object::getIndexes()
{
	local i; for i in "${!this[@]}"; do
		if [[ ! "$i" =~ ^((_)|(0$)) ]]; then
			echo $i
		fi
	done
}

function Object::getValues()
{
	local i; for i in "${!this[@]}"; do
		if [[ ! "$i" =~ ^((_)|(0$)) ]]; then
			echo ${this[$i]}
		fi
	done
}

function Object::getSize()
{
	local size=0
	local i; for i in "${!this[@]}"; do
		if [[ ! "$i" =~ ^((_)|(0$)) ]]; then
			((size++))
		fi
	done
	echo $size
}

function Object::get()
{
	echo "${this[$1]}"
}

function Object::set()
{
	this[$1]="$2"
}

function Object::exists()
{
	return 0
}

function Object::unset()
{
	DeleteObject $this[0]
}

function Object::clear()
{
	local i; for i in "${!this[@]}"; do
		if [[ ! "$i" =~ ^((_)|(0$)) ]]; then
			unset this[$i]
		fi
	done
}

# usage: $obj.fromString [<str>]
# Fill in the object's attributes from the string that is in "name:value" lines format
# if str is not specified or if it is "-" it is read from stdin to support piping
# String format:
#   The format is compatible with debian control files
#   The string is multiline with each line being one of four kinds of lines.
#    	'<name> : <value>'  # define an attribute
#    	'+ ...'             # continue values that have multiple lines.  Initial whitespace and first space after + is ignored
#    	'#...'              # whole line comments are ignored
#    	''                  # empty lines are ignored
# See Also:
#    fromJSON
function Object::fromDebControl() { Object::fromString "$@"; }
function Object::fromString()
{
	local line name value

	# the exec line opens a new file handle that reads the $@ string as a file and stores the file handle in $fd
	local fd=0;	[ $# -gt 0 ] && exec {fd}<<<"$@"

	while read -u $fd -r line; do
		if [[ "$line" =~ [^[:space:]].*: ]]; then
			IFS=':' read -r name value <<<$line
			name="$(trimString "$name")"
			value="$(trimString "$value")"
			if [ "${value:0:12}" == "_bgclassCall" ]; then
				local objType _donotneed objRef
				read -r _donotneed _donotneed objType _donotneed <<<$value
				ConstructObject "$objType" value
				value="${value}"
			fi

			if [[ "$name" =~ [.[] ]]; then
				$this.$name="$value"
			else
				this[$name]="${value//\\n/$'\n'}"
			fi

		elif [[ "$line" =~ ^[[:space:]]*[+] ]]; then
			assertNotEmpty name "a '<name> : <value>' line must preceed any '+...' continuation line "
			line="${line#*+}"
			line="${line# }"
			this[$name]+=$'\n'"${line//\\n/$'\n'}"
		else
			assertError -v line  "could not parse line
				Format: four kinds of lines
					'<name> : <value>'  # define an attribute
					'+ ...'             # continue values that have multiple lines.  Initial whitespace and first space after + is ignored
					'#...'              # whole line comments are ignored
					''                  # empty lines are ignored
			"
		fi
	done
	# if we opened a file handle, close it now
	[ ${fd:-0} -ne 0 ] && exec {fd}<&-
}

# usage: $obj.toString
# Write the object's attributes to stdout
# Format: debian control file: see details in Object::fromString
# See Also:
#    toJSON
function Object::toDebControl() { Object::toString "$@"; }
function Object::toString()
{
	local titleName
	while [ $# -gt 0 ]; do case $1 in
		--title*) bgOptionGetOpt val: titleName "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local indexes=$($this.getIndexes)

	local labelWidth=0
	local attrib; for attrib in $indexes; do
		((labelWidth=(labelWidth<${#attrib}) ?${#attrib} :labelWidth ))
	done

	#((labelWidth=(labelWidth<6) ?labelWidth : 6))

	local indent="" indentWidth=labelWidth
	if [ "$titleName" ]; then
		printf "%s : %s\n" "${titleName}" "${this[_CLASS]}"
		indent="   "
		((indentWidth+=3))
	fi

	local attrib; for attrib in $indexes; do
		local value="${this[$attrib]}"
		if [ "${value:0:12}" == "_bgclassCall" ]; then
			local parts=($value)
			value="<instance> of ${parts[2]}"
			#value="${parts[0]}  <instance>  ${parts[2]}"
			printf "${indent}%-${labelWidth}s: %s\n" "$attrib" "$value" | awk -v indentWidth="$indentWidth" -v indent="$indent" '{if (NR>1) printf("%-*s+ ", indentWidth, ""); print $0}'
			${this[$attrib]}.toString | awk -v attrib="$attrib" '{printf("  %s%s%s\n", attrib, ($1~/^[[]/)?"":".", $0)}'
		else
			printf "${indent}%-${labelWidth}s: %s\n" "$attrib" "$value" | awk -v indentWidth="$indentWidth" -v indent="$indent" '{if (NR>1) printf("%-*s+ ", indentWidth, ""); print $0}'
		fi
	done
}


# usage: $obj.fromFlatINI -s <scope>
# Populate the object's attributes from the attributes represented in the input INI file
# This function can read flat and setioned INI files. Attributes in sections become <sectName>.<name>
# Format:
#	INI file: (supports both flat and section headers for sub object notation)
#     name=value
#     sectName.name=value
#     [ sectName ]
#     name=value
# See Also:
#    toJSON
#    toDebControl
function Object::fromINI() { Object::fromFlatINI "$@"; }
function Object::fromFlatINI()
{
	local line name value

	# the exec line opens a new file handle that reads the $@ string as a file and stores the file handle in $fd
	local fd=0;	[ $# -gt 0 ] && exec {fd}<<<"$@"

	local curSectPrefix=""
	while read -u $fd -r line; do
		if [[ "$line" =~ ^[[:space:]]*[#] ]] || [[ "$line"  =~ ^[[:space:]]*$ ]]; then
			continue
		elif [[ "$line" =~ ^[[:space:]]*[[][[:space:]]*(.*)[[:space:]]*[]][[:space:]]*$ ]]; then
			read -r curSectPrefix <<<${BASH_REMATCH[1]}
			[ "$curSectPrefix" ] || assertError -v line  "could not parse section INI line"
			curSectPrefix+="."
		elif [[ "$line" =~ = ]]; then
			IFS='=' read -r name value <<<$line
			name="${curSectPrefix}$(trimString "$name")"
			value="$(trimString "$value")"

			if [[ "$name" =~ [.[] ]]; then
				$this.$name="${value//\\n/$'\n'}"
			else
				this[$name]="${value//\\n/$'\n'}"
			fi
		else
			assertError -v line  "could not parse INI line"
		fi
	done
	# if we opened a file handle, close it now
	[ ${fd:-0} -ne 0 ] && exec {fd}<&-
}

# usage: $obj.toFlatINI -s <scope>
# Write the object's attributes to stdout
# Format:
#	INI file:
#     name=value
#   nested member objects are written as name.subname=value
#   This does not write sections ([ sectionName ]) -- that's what "flat" means
# See Also:
#    toJSON
#    toDebControl
function Object::toFlatINI()
{
	local scope
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s) scope="$2"; shift ;;
	esac; shift; done

	local attrib; for attrib in $($this.getIndexes); do
		local value="${this[$attrib]}"
		if [ "${value:0:12}" == "_bgclassCall" ]; then
			$this.$attrib.toFlatINI -s ${scope}${scope:+.}$attrib
		else
			printf "%s=%s\n" "${scope}${scope:+.}$attrib" "${value//$'\n'/\\n}"
		fi
	done
}



# usage: $obj.restoreFile <fileName>
# Fill in the object's attributes from the text file specified
# Format: debian control file: see details in Object::fromString
# See Also:
#    fromJSON
#    fromString (deb control file)
# TODO: separate this into serialize/deserial functions that can be used for any type, not just files
# TODO: include the specific type in the header line and restore that type
# TODO: See if we can unify the "_bgclassCall  <instance>  Object" content that indicates a class should be built with the serialized header line "<Object> v1.0 fmtType"
function Object::restoreFile()
{
	local fileName="$1"; assertFileExists "$fileName"
	$this.clear

	# the exec line opens a new file handle that reads the  file and stores the file handle in $fd
	local fd; exec {fd}<"$fileName"

	local fileType fileVersion fmtType
	read  -u $fd -r fileType fileVersion fmtType
	[ "$fileType" == "<Object>" ] || assertError "unknonw file type. first line is not a known header"

	# read the rest of the input stream
	$this.from$fmtType <&$fd

	# close file handle
	exec {fd}<&-
}

# usage: $obj.saveFile [-t <fmtType>] <fileName>
# Write the object's attributes to the text file specified. The file will be overwritten.
# File Format:
#    The first line of the file is a string that identifies the file type and version.
#    the rest of the file in the content that complies with the type specified in the first line
# Options:
#    -t <fmtType> : specify the format type to use for the file
# See Also:
#    toJSON
function Object::saveFile()
{
	local fmtType="String"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-t) fmtType="$(bgetopt "$@")" && shift ;;
	esac; shift; done
	local fileName="$1"; assertNotEmpty fileName

	printf "%s %s %s\n" "<Object>" "v1.0" "${fmtType#to}" > "$fileName"
	$this.to${fmtType#to} >> "$fileName"
}

####################################################################################################################
### bootstrap the leaf instances Object Class "global Class Instances"

# We manually fill in the associative arrays for a few object Instances because when DeclareClass and ConstructObject
# are called to created the Class and Object class instnaces, they will refer to themselves.
# these arrays are probably over specified here. When "DeclareClass Class" is called, probably the only thing that it needs is the
# Class[hierarchy] member to be pre-filled in. It does no harm to fill in the others, but they will be overwritten by
# DeclareClass so we could leave them out. It was a useful check to print out the Class and Object associative arrays
# before and after to see if they were consistent.

# this is the Instance of 'Class' that describes 'Class'
declare -A Class=(
	[name]="Class"
	[baseClass]="Object"
	[classHierarchy]="Object Class"
	[_OID]="Class"
)
# this is the Instance of 'Class' that describes 'Object'
declare -A Object=(
	[name]="Object"
	[baseClass]=""
	[classHierarchy]="Object"
	[_OID]="Object"
)
declare -A Object_vmt=()

DeclareClass Class
DeclareClass Object

# we don't call ConstructObject for the Null Object because the [0],[_Ref] value is an assert instead of the normal format
# we protect against re-defining it in case we reload the library
[ ! "${NullObjectInstance[_OID]}" ] && declare -rA NullObjectInstance=(
	[_OID]="NullObjectInstance"
	[0]="assertError Null Object reference called <NULL>"
	[_Ref]="assertError Null Object reference called <NULL>"
)



# Class stack
# Stack is an Object that can push and pop strings. Since object references are strings, you can store
# objects in the stack
# Members:
#    length : number of elements in the stack
#    e<N>   : stack element N  (the e is added so not to conflict with [0] which needs to be the object ref)
DeclareClass Stack
function Stack::__construct()
{
	this[length]=0
}

# usage: $obj.getSize [-R <retVar>]
# returns the number of elements in the stack on stdout or <retVar>
# Options:
#     -R <retVar> : return the result in this variable instead of stdout
function Stack::getSize()
{
	local retVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R) retVar="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	returnValue "${this[length]}" $retVar
}

# usage: $obj.push <stringValue ...>
# add a new element to the end of the stack.
function Stack::push()
{
	this[e${this[length]}]="$@"
	((this[length]++))
}

# usage: $obj.pop [-R <retVar>]
# returns the last element and removes it from the stack.
# Options:
#     -R <retVar> : return the result in this variable instead of stdout
# Exit Codes:
#    0 : true. an item was returned
#    1 : false. the stack was empty so no item was returned
function Stack::pop()
{
	local retVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R) retVar="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	(( this[length] <=0 )) && return 1

	((this[length]--))
	local element="${this[e${this[length]}]}"
	unset this[e${this[length]}]

	returnValue "$element" $retVar
}

# usage: $obj.peek [-R <retVar>] [<countFromEnd>]
# returns the last element and removes it from the stack.
# Params:
#     <countFromEnd> : the number of elements from the end to return. default is 0 meaning the last
#                      element
# Options:
#     -R <retVar> : return the result in this variable instead of stdout
function Stack::peek()
{
	local retVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R) retVar="$(bgetopt "$@")" && shift ;;
	esac; shift; done
	local countFromEnd="${1:-0}"

	local index=$(( this[length] -1 - countFromEnd ))
	(( index < 0 )) && return 1

	local element="${this[e$index]}"
	returnValue "$element" $retVar
}

# usage: $obj.clear
# removes all elements from the stack
function Stack::clear()
{
	while (( this[length] > 0 )); do
		((this[length]--))
		unset this[e${this[length]}]
	done
	return 0
}

# usage: $obj.isEmpty
# Exit Codes:
#    0 : true. stack is empty
#    1 : false. stack is not empty
function Stack::isEmpty()
{
	(( this[length] == 0 ))
}




# OBSOLETE? See BashArray and BashMap. The intention was to allow a real -a array to be stored but that did not work. Stack is better. We can add a Queue too
# An Array is a simple Object that can be used like a numeric array. Arrays are typically only used as member attributes
# of objects because bash arrays can not be array elements of other arrays (Objects are bash associate arrays where the elements
# are the member attributes)
# This underlying implementation uses an associative Array like all Objects but the difference is that...
#    1) the [0] does not contain the object reference. This means that a bash variable ref to the implementation
#       associative Array can not be used like an Object ref (i.e. $myArray.<method> does not work)
#       However, when an Array is referenced as a member attribute of a parent Object, Object call syntax works fine.
#       (i.e. $myObject.myArray.getIndexes works).
#       Scripts should use real bash arrays most of the time. Array is useful when you need a member of an Object to
#       be act like a numberic array. For a member that acts like an associate array, just use Object.
#    2) the Object methods that work on member attributes only recognize numeric indexes as array elements.
#       It not ilegal to set and reference non numeric attributes, but the getSize, getIndexes, and getAttributes methods
#       will ignore them.
DeclareClass Array
function Array::__construct()
{
	this[0]=""
	this[_length]=0
}

function Array::getSize()
{
	local size=0
	local i; for i in "${!this[@]}"; do
		if [[ "$i" =~ ^[0-9]*$ ]]; then
			((size++))
		fi
	done
	echo $size
}

function Array::getAttributes()
{
	local i; for i in "${!this[@]}"; do
		if [[ "$i" =~ ^[0-9]*$ ]]; then
			echo $i
		fi
	done
}

function Array::getIndexes()
{
	local i; for i in "${!this[@]}"; do
		if [[ "$i" =~ ^[0-9]*$ ]]; then
			echo $i
		fi
	done
}

function Array::getValues()
{
	local i; for i in "${!this[@]}"; do
		if [[ "$i" =~ ^[0-9]*$ ]]; then
			echo ${this[$i]}
		fi
	done
}


function BashArray::__construct()
{
	this[_basharray]="${this[_OID]}_array"
	declare -ga ${this[_basharray]}="()"
}
function BashArray::getArray()
{
	returnValue "${this[_basharray]}" $1
}
function BashArray::toString()
{
	local -n _data="${this[_basharray]}"
	local labelWidth=0
	local attrib; for attrib in "${!_data[@]}"; do
		((labelWidth=(labelWidth<${#attrib}) ?${#attrib} :labelWidth ))
	done
	for attrib in "${!_data[@]}"; do
		local value="${_data[$attrib]}"
		if [ "${value:0:12}" == "_bgclassCall" ]; then
			local parts=($value)
			value="<instance> of ${parts[2]}"
			printf "%-${labelWidth}s: %s\n" "$attrib" "$value" | awk -v labelWidth="$labelWidth" '{if (NR>1) printf("%-*s+ ", labelWidth, ""); print $0}'
			$value.toString | awk -v attrib="$attrib" '{printf("  %s%s%s\n", attrib, ($1~/^[[]/)?"":".", $0)}'
		else
			printf "%-${labelWidth}s: %s\n" "[$attrib]" "$value" | awk -v labelWidth="$labelWidth" '{if (NR>1) printf("%-*s+ ", labelWidth, ""); print $0}'
		fi
	done
}
function BashArray::bgtrace()
{
	bgtraceIsActive || return 0

	local level=0 rlevel=100 recurseFlag="-r" attribsOff="" methodsOff="" sysAttrOff="" headersOff=""
	while [ $# -gt 0 ]; do case $1 in
		-l*) bgOptionGetOpt val: level "$@" && shift ;;
		-r)  varToggleRef recurseFlag "-r"  ;;
		--rlevel*) bgOptionGetOpt val: rlevel "$@" && shift
			# setting rlevel on the initial call implies that recursion should start on
			[ ${level:-0} -eq 0 ] && recurseFlag="-r"
			;;
		--rstate) recurseFlag="$2"; shift   ;;
		-h)  varToggleRef headersOff "-h"  ;;
		-a)  varToggleRef attribsOff "-a" ;;
		-m)  varToggleRef methodsOff "-m" ;;
		-s)  varToggleRef sysAttrOff "-s" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# if we have reached the recursion level limit, set recurseFlag to off
	[ ${level:-0} -ge ${rlevel:-0} ] && recurseFlag=""

	# $level increases by +1 each recursion but $rlevel keeps it initial value from the first call
	local pad="$(printf %$((${level}*3))s)"

	#[ ! "$headersOff" ] && bgtrace "${pad}$_CLASS::$_OID :"
	echo "${pad}$_CLASS::$_OID :" >>$_bgtraceFile

	bgtraceVars "$pad   " :"${this[_basharray]}"
}

DeclareClass BashArray



function BashMap::__construct()
{
	this[_basharray]="${this[_OID]}_map"
	declare -gA ${this[_basharray]}="()"
}
function BashMap::getArray()
{
	returnValue "${this[_basharray]}" $1
}
function BashMap::toString()  { BashArray::toString "$@" ; }
function BashMap::bgtrace()   { BashArray::bgtrace "$@" ; }

DeclareClass BashMap

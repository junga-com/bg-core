#!/bin/bash


# Library
# This library implements an object oriented syntax for bash scripts. It is not meant to make OO the principle for bash script
# writing. Bash should remain a simple scripting system where plain functions and simple data variables are used for most tasks.
#
# This Object and class system provides a relatively efficient, light weight mechanism to organize bash code better when it is used
# to define operations on something that is one of multiple ocurances on the server, particularly if multiple instancstans of that
# thing are accesed in one script. In that case this OOP pattern greatly simplifies the high level organization of the code and avoids
# repeated discovery of the target's attributes. Even though the bash functions called as methods are significantly heavier than
# normal bash function calls, that is outweighed by a simple pattern for avoiding repeated work that may be much heavier.
#
# A script should think about calling 10's of these object syntax method calls per user action and not 100's or thousands.
#
# The main benefit to writing a method instead of a regular bash function is that is has access to a special local variable called
# 'this'. It behaves as if the function declares "local -A this=()" except that it keeps its data from one Method call to the next.
# and there is a different 'this' array for object instance created.
#
# Many OO features are supportted.
#     * static class data and methods
#     * virtual functions
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
# 	function Dog::__construct() { : do Dog init. You dont have to define a __constructor; }
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
#
# How It Works:
# This mechanism uses the bash associative array variable type as the object instance. Every object created, regardless of whether
# its created in a function or at a global scope, gets the this array created in the global scope with a randomly generated name.
# This is akin to allocating memory on a heap. The name of the array is refered to as its 'OID' (object ID) and is akin to its memory
# address in a low level language.
#
# An object's attributes are stored in its associtive array. By convention, array entry names that start with '_' are system variables
# maintained by the Class/Object mechanism and those that do not are logically part of the Object. Some system variables are useful
# to the script autor, like _CLASS
#
# Member functions are declared the same way as any other bash function but with a particular naming convention. By naming the
# function with the convention <className>::<methodName>, the function will automatically be part of the <className> class and
# callable as a method on instances of class <className> or other classes that derive from <className>.
# Example:.
#    function Dog::speak() { echo "woof"; }
#
#   Object references are normal string variables that are initialized with a syntax that is a call to _bgclassCall.
#   Example:.
#      $myPet.speak "$p1"
#      expands to: '_bgclassCall' '<oid>' '<className>' '<hierarchyCallLevel>' '|.speak' '<valueOfP1>'
#      myPet is a normal bash variable with the contents "_bgclassCall <oid> <className> <hierarchyCallLevel> |"
#      where
#         _bgclassCall is a stub function that uses the first 4 parameters passed to it and the class VMT table to setup the this
#                      variable and call the speak method associated with the correct class
#         <oid> is the name od the global associated array for this instance -- something like 'aQoUszTyE'
#         <className> is the class that the reference is cast as. This is typically the most derived class but can be any of the base
#                     classes and depends on how the object reference is initialized
#         <hierarchyCallLevel> is an adjustment to the virtual lookup mechanism to allow refering to a more super class than <className>
#         '|' is a separator that allows _bgclassCall to know reliably that the <hierarchyCallLevel> will not get accidentally merged
#                     into the .<methodName> paramter. It could have been any character. It has nothing to do with piping which bash
#                     processes before this point to separate a line into 'simple commands'
#      The dot syntax between the object reference and the methodName is a just a visual nicety. A space could have been used just
#      the same, but it would not have looked as much like an object reference. Any character that is not a valid in a variable name
#      will cause bash to see '$myPet' as a variable to expand in its 'parameter expansion' stage and then execute the resulting
#      tokens as a command (_bgclassCall) and parameters (<oid> <className> <hierarchyCallLevel> |.<methodName> <p1> <p2> ...)
#      No space follows the | so that the 4th parameter will be merged with the | by design. When an object reference variable is
#      passed around, quotes would be needed to preserve a trailing space so this ensures that object refs can be assigned naturally.
#      Besides the '.', '=', '[' '+' and '-' are supported as part of various operator syntax. See _bgclassCall for supported syntaxes.
#
#   The DeclareClass function creates an instance of the Class object to contian the VMT and and other information about that particular
#   class including static variables. The name of the class becomes a global string variable initiated with an object reference to the
#   class's instance array.
#   Example:.
#      DeclareClass Dog Animal
#      echo $Dog -> "_bgclassCall au0F8qRDp Class 0 |"
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
# This brings a new class into existance by creating a global associative array named "<className>"
# That array store the static variables associated with the class. The optional <atribNameN:valN>'s' will be set in the array.
# There are no prerequisites. The Member functions (aka Methods) of the class can be defined before or after the class is Declared.
# Any function named <className>::* will be available as a method to call on object instances of that class or derived classes.
# Methods are associated with a Class dynamically the first time a reference of that class is used and again after any new libraries
# are imported
# Accessing Class Static Member Variables:
# Inside methods of the Class, the class's array can be refered to as "static"
#     example: "static[<attribName>]="<val>", foo="${static[<attribName>]}"
# Outside of its methods its refered to as <className>
#     example: "<className>[<attribName>]="<val>", foo="${<className>[<attribName>]}"
# Params:
#    <className>       : the name of the new class. By convention it should be capitalized
#    <baseClassName>   : (default=Object) the name of the class that the new class derives from.
#    <atribNameN:valN> : static class attributes to set in the new class static object.
function DeclareClass()
{
	local className="$1"; shift
	local baseClass; [[ ! "$1" =~ : ]] && { baseClass="$1" ; shift; }
	[ "$className" != "Object" ] && baseClass="${baseClass:-Object}"

	[ "$baseClass" == "Class" ] && assertError "
		The special class 'Class' can not be sub classed. You can, however customize Class...
		  * add attributes to a particular Class when its declared. see man DeclareClass
		  * declare methods for use by all Class's like 'function Class::mymethod() { ...; }'
		"

	declare -gA $className
	if ubuntuVersionAtLeast trusty; then
		ConstructObject Class "$className" "$@"
	fi
}

# usage: DeclareClass <className> [<baseClassName> [<atribName1:val1> .. <atribNameN:valN>]]
# This is the constructor for objects of type Class. This is called when a DeclareClass is used to bring a new class into existence.
# A global associative variable named <className> is declared and then this function is used to initialize it.
function Class::__construct()
{
	# TODO: implement a delayed construction mechanism for class obects.
	#       this Class::__construct is called when ever DeclareClass is called to bring a new Class into existance
	#       that is typically done in libraries at their global scope so that it happens when they are sourced.
	#       this function implementation should do the minimal work required and delay anything it can to when an instance is
	#       used for the first time. An ::onFirstUse method could be added and called by ConstructObject when the <className>[instanceCount]
	#       is incremented from 0

	# Since each class does not have its own constructor, we allow DeclareClass to specify attributes to assign.
	# TODO: this makes DeclareClass and plugins_register very similar. They should merge when 10.04 support is completely dropped
	[ $# -gt 0 ] && parseDebControlFile this "$@"

	this[name]="$className"
	this[baseClass]="$baseClass"

	declare -gA _classIsAMap
	[ ! "$baseClass" ] && _classIsAMap[$className,Object]=1

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
		local baseSubClassesRef="$_cname[subClasses]"
		stringJoin -a -d " " -e -R "$baseSubClassesRef" "$className"

		# walk to the next class in the inheritance
		local _baseClassRef="$_cname[baseClass]"
		_baseClassRef="${!_baseClassRef}" || assertError  -v _cname -v _baseClassRef ""

		# check that we are not in an infinite loop. This should end when _cname is "Object" and its's baseclass is "" but if any
		# class hierarchy gets messed up and a class (Object or otherwise) has its self as a base class, then we should assert an error
		# TODO: this does not detect complex loops A->B->C->A  use _isAMap or a local map for for this loop to detect it we revisit the same class in this loop
		[ "$_cname" == "${_baseClassRef}" ] && assertError -v className -v baseClass -v this[classHierarchy] "Inheritance loop detected"
		_cname="${_baseClassRef}"

	done

	# typically a class's methods defined after the DeclareClass line so we delay this until the first object construction
	# The Class and Object class's are bootstrapped in a way that their base methods are alreadyset at this point
	# so we do not want to init it to "" here.
	#this[methods]=""
}

# usage: <Class>.isA <className>
# returns true if this class has <className> as a base class either directly or indirectly
function Class::isA()
{
	local className="$1"
	[ "${_classIsAMap[${this[name]},$className]}" ]
}

# usage: <Class>.reloadMethods
#
function Class::reloadMethods()
{
	importCntr bumpRevNumber
}


# usage: <Class>.getMethods [<retVar>]
# return a list of methods defined for this class. By default This does not return methods inherited from base
# classes.
# Options:
#    -i : include inherited methods
# Params:
#    <retVar> : return the result in this variable
function Class::getClassMethods()
{
	local includeInherited retVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-i) includeInherited="-i" ;;
	esac; shift; done
	retVar="$1"

	local currentCacheNum; importCntr getRevNumber currentCacheNum

	if [ ! "${this[methods]}" ] || [ "${this[_getClassMethodsCacheNum]}" != "$currentCacheNum" ]; then
		this[methods]="$(compgen -A function ${this[name]}::)"
		this[_getClassMethodsCacheNum]="$currentCacheNum"
		[ "${this[baseClass]}" ] && eval \$${this[baseClass]}.getClassMethods -i ${this[_OID]}[inheritedMethods]
	fi

	if [ "$includeInherited" ]; then
		returnValue "${this[methods]} ${this[inheritedMethods]}" $retVar
	else
		returnValue "${this[methods]//${this[name]}::/}" $retVar
	fi
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
	genRandomIDRef _OID 9 "[:alnum:]"
	echo "_bgclassCall ${_OID} $_CLASS 0 |"
}



# usage: ConstructObject <className> <objRef> [<p1> ... <pN>]
# usage: ConstructObject <className>::<dynamicConstructionData> <objRef> [<p1> ... <pN>]
# usage: local -A <objRef>; ConstructObject <className> <objRef> [<p1> ... <pN>]
# usage: local <objRef>;    ConstructObject <className> <objRef> [<p1> ... <pN>]
# This creates a new Object instance. An object instance is a normal bash associative array that has some special elements filled in
# Elements whose index name starts with an _ (underscore) are system attributes and are not considered logical member variables.
# All other elements are considered member variables of the object.
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
#  ArrayRef Syntax
#  ArrayRef is a bash native variable that references the associative array that is the object's underlying representation.
#  all the ObjRef syntax still works b/c [0] contains the ObjRef string and $ary is a synonym for ${ary[0]}
#  in addition, you can access the member variables directly.
#     Member Assignment
#         aryRef[<memberVariableName>]="something"
#     Member Access
#         local foo=${aryRef[<memberVariableName>]}
#
# How It Works:
#    The 'magic' that makes it act like an Object is the Object Reference String (ObjRef). If a variable 'objRef' contains an
#    ObjRef string, a bash command line like "$objRef.methodName" results in $objRef being replaced by the ObjRef string it contains
#    and then the resultant line being executed as a command. ObjRefs always begin with "_bgclassCall ..." so all object syntax that
#    begins with $objRef calls that function which then dispatches the method call based on the rest of the line after the .
#    The '.' is not special in the mechanism. It is just a character that is not valid in variable names so $objRef.something results
#    in $objRef being expanded and the result concatenated with ".something"
function ConstructObject()
{
	[[ "${BASH_VERSION:0:3}" < "4.3" ]] && assertError "classes need the declare -n option which is available in bash 4.3 and above"
	local _CLASS="$1"; assertNotEmpty _CLASS "className is a required parameter"

	### support dynamic base class implemented construction
	if [[ "$_CLASS" =~ :: ]] && type -t ${_CLASS//::*/::ConstructObject} &>/dev/null; then
		_CLASS="${1%%::*}"
		local data="${1#*::}"
		shift
		local objName="$1"; shift
		$_CLASS::ConstructObject "$data" "$objName" "$@"
		return
	fi


	# ConstructObject can either turn an existing associative array passed in by the caller into an object or create a
	# new, global associative array on the 'heap' (which is a random global namespace) and return a reference to that new
	# object. Either way, $2 is the name of the variable in the callers scope that will refer to the object.
	# If the name in $2 is an associative array, it is used directly, otherwise the variable name in $2 is filled in with the reference.
	# Either way, the caller will be able to use the variable name (lets call it varName) passed in as $2 as an Object reference
	# because $varName will resolve to the text of the object ref in both cases. If varName is a simple string var, we set it to the
	# obj ref text. If its an associative array, we set varName[0] to the obj ref text and $varName is a shortcut for $varName[0]

	# first assume that $2 is the name of an associative array we can use
	local _OID="$2"; assertNotEmpty _OID "objRefVar is a required parameter"

	# The caller typically declares the objRef name passed in $2 as either an associative array (local -A objName) or a plain variable
	# (local objName), but without assigning it any value because this funciton is meant to initialize it. When you declare a new
	# variable in bash without assigning it, declare -p will report that its not yet defined. However, the attributes that are
	# specified in the declaration are remembered and will take effect once its assigned a value. By assigning an empty string to
	# it, we force it to be declared to the point that we can use declare -p to report the correct attributes. Its valid to assign
	# a string to an array -- it gets stored in the [0] element.
	eval $2=\"\"

	# if $2 is not name of an associative array, create one on the heap and use $2 just to store the objRef to that heap object
	if [[ ! "$(declare -p "$2" 2>/dev/null)" =~ declare\ -[gilnrtux]*A ]]; then
		genRandomIDRef _OID 9 "[:alnum:]"
		declare -gA $_OID="()"
		eval $2=\"_bgclassCall ${_OID} $_CLASS 0 \|\"
	fi
	shift 2 # the remainder of parameters are passed to the __construct function

	local -n this="$_OID"
	this[_OID]="$_OID"
	this[_CLASS]="$_CLASS"

	# create the ObjRef string at index [0]. This supports $objRef.methodName syntax where objRef
	# is the associative array itself. because in bash, $objRef is a shortcut for $objRef[0]
	this[0]="_bgclassCall ${_OID} $_CLASS 0 |"
	this[_Ref]="${this[0]}"

	# copy the ordered classHierarchy list from the Class instance to our new Object Instance
	# note that since $_CLASS is a map variable name, we have to deferference it in two steps
	this[_classHierarchy]="$_CLASS[classHierarchy]"; this[_classHierarchy]="${!this[_classHierarchy]}" || assertError ""

	# _classMakeVMT will set all the methods known at this point. It records the id of the current
	# sourced library state which is maintained by 'import'. At each method call we will call it again and
	# will quickly check to see if more libraries have been sourced which means that it should check to see
	# if more methods are known
	_classMakeVMT

	# invoke the constructors from Object to this class
	local _cname; for _cname in ${this[_classHierarchy]}; do
		unset -n static; local -n static="$_cname"
		type -t $_cname::__construct &>/dev/null && $_cname::__construct "$@"
	done

	# if this is a Class Object, register and call the Class's __staticConstruct
	# __staticConstruct is the end of the recursive, self defining nature of the Object - Class system
	# Its similar to the concept of having a sub class of Class to represent each different Class, but
	# instead of defining a whole new sub class (which itself would need to have a unique class data instance
	# to represent what it is), we only allow that a staticConstructor be defined. This way the loop ends
	# and the programmer has a way to define the construction of the it's particular Class instance.
	# Class::__construct can also exist to do generic Class Instance construction.
	if [ "$_CLASS" == "Class" ] && type -t $_OID::__staticConstruct &>/dev/null; then
		# TODO: move this to the _classMakeVMT function. Here, we will just call it if it exists for this object.
		this[_method::__staticConstruct]="$_OID::__staticConstruct"
		# the __staticConstruct is invoked in the context of the particular Class not the "Class Class"
		# our $this pointer refers to the object of type Class that we are now constructing but in the
		# context of the class that Class represents, this object is referenced as $static.
		local this="$NullObjectInstance"
		unset -n static; local -n static="$_OID"
		$_OID::__staticConstruct "$@"

		# set $this and $static back to the context of this "Class" Object so that postConstruct (if defined)
		# will run in the right context. postConstruct does not seem useful for Class Instances because Class
		# can not have sub classes declared but it is consistent to do this.
		unset -n this;   local -n this="$_OID"
		unset -n static; local -n static="$_CLASS"
	fi

	[ "${this[_method::postConstruct]}" ] && $this.postConstruct
	true
}

# usage: _classMakeVMT <objRef>
# TODO: currently we maintain a separate VMT per object and when a new library is sourced, they all become dirty and
#       will rebuild on the object's next method invocation. We could now create shared VMT. The full hierarchy string
#       can be the key. The hierarchy string for each class is constant and when an object is created, the object's
#       hierarchy string is copied from the class. If we allow multiple inheritance and/or runtime mixins, the object's
#       hierarchy string can become unique. However you arrive at an ordered hierarchy string, it alone determines the
#       contents of its VMT. Since all the object instances that have the same hierarchy string, have the same methods,
#       and except for rebuilding the VMT if and when more functions are sourced, the VMT is read only, object refs can
#       be changed to store just the name of the VMT associative array. The _bgclassCall function will create a
#       "local -n _VMT=" pointer and use it instead of "this" for method lookups. Since bash requires that threads be
#       run in a sub proc which has a copy of the environment, no locking should be needed.
# _classMakeVMT will set all the methods known at this point in the objects this array. It records the id of the current
# sourced library state which is maintained by 'import'. If that ID has not changed snce the last time it built the VMT
# for this object, it returns quickly. We call this at each method call so that if more libraries are sourced which might
# have provided more methods that will effect the VMT, they will be included. The script writer can also call the static
# Class::reloadMethods to cause all VMT to rebuild on their object's next method call.
# See Also:
#    Class::reloadMethods
function _classMakeVMT()
{
	local currentCacheNum; importCntr getRevNumber currentCacheNum
	[ "${this[_vmtCacheNum]}" == "$currentCacheNum" ] && return
	[ "${this[_CLASS]}" != "Class" ] && this[_vmtCacheNum]="$currentCacheNum"

	# TODO: consider if we do not need _classHierarchy anymore. Every object has a _CLASS which is
	#       that contains classHierarchy which is the same as _classHierarchy in the object instance.
	#       We could allow _classHierarchy to be changed at runtime for a specific object. That would be
	#       like dynamic mixins -- maybe Aspects. If we got rid of _classHierarchy then this function
	#       would be more simple. It would just use Class::getMethod -i to get the method list (or
	#       just point to the Class's VMT)

	# register members into the 'this' array for all inherited classes in order of most super (Object) to most sub
	# so that the children's methods override the parent's
	# members overwrite the parent's
	local _cname; for _cname in ${this[_classHierarchy]}; do

		# the list of method names are cached in the Class object but when the class is declared, most
		# methods have not yet been defined because its more natural to DeclareClass the class and then
		# follow it with the methods. Also some methods will be provided by later libraries like the Object::bgtrace
		# This code delays making the method list until the first instance is created and then will also
		# recreate the list if more libraries have been loaded.
		local cnameMethodsRef="$_cname[methods]"
		local cnameMethodCacheNumRef="$_cname[_getMethodCacheNum]"

		if [ ! "${!cnameMethodsRef}" ] || [ "${!cnameMethodCacheNumRef}" != "$currentCacheNum" ]; then
			printf -v "$cnameMethodsRef"        "%s" "$(compgen -A function $_cname::)" || assertError -v _cname -v currentCacheNum -v this -v this[_classHierarchy] ""
			printf -v "$cnameMethodCacheNumRef" "%s" "$currentCacheNum"
		fi
		local _mname; for _mname in ${!cnameMethodsRef}; do
			local _mnameShort="${_mname#$_cname::}"
			this[_method::${_mnameShort}]="$_mname"
		done
	done

	# add one off methods added with Object::addMethod
	local _mname; for _mname in ${this[_addedMethods]}; do
		local _mnameShort="${_mname#*::}"
		this[_method::${_mnameShort}]="$_mname"
	done
}



# usage: DeleteObject <objRef>
# destroy the specified object
# This will invoke the __desctruct method of the object if it exists.
# Then it unsets the object's array
# After calling this, and future use of references to this object will asertError
function DeleteObject()
{
	# TODO: recursively delete members.
	local objRef="$*"
	local -a parts=( $objRef )
	if [ ${#parts[@]} -eq 1 ]; then
		unset -n objRef; local -n objRef="$1"
		parts=( $objRef )
	fi

	# assert that the second term in the objRef is an associative array
	[[ "$(declare -p "${parts[1]}" 2>/dev/null)" =~ declare\ -[gilnrtux]*A ]] || assertError "'$objRef' is not a valid object reference"

	local -n this="${parts[1]}"
	[ "${this[_method::__destruct]}" ] && $this.__destruct "$@"
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
	# if <oid> does not exist, its because the myObj=$(NewObject <class>) syntax was used to create the
	# object reference and it had to delay creation because it was in a subshell.
	local _OID="$1[*]"; if [ ! "${!_OID}" ]; then
		[[ "$1" =~ ^a[[:alnum:]]{8}$ ]] || assertError "bad object reference. The object is out of scope. \nObjRef='_bgclassCall $@'"
		declare -gA "$1=()"
		if [[ "$4" =~ ^[._]*construct$ ]]; then
			local _OID="$1"; shift
			local _CLASS="$1"; shift
			ConstructObject "$_CLASS" "$_OID" "$@"
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
	[ "${_memberTerm//[]. []}" ] || return

	local -n this=$_OID || assertError -v _OID -v _CLASS -v _memberTermWithParams "could not setup Object calling context '$(declare -p this)'"
	local -n static=$_CLASS
	local super="_bgclassCall ${_OID} $_CLASS $((_hierarchLevel+1)) |"

	# _classMakeVMT returns quickly if new scripts have not been sourced or Class::reloadMethods has not been called
	_classMakeVMT

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


	# some hard coded methods that can be called on a member even if that member is not an object or does not exist
	# When these methods are called directly on an object (not in a chained member reference), they are invoked normally and do not hit this case
	if [ "$_memberTerm" == ".unset" ]; then
		[ "${_memberVal:0:12}" == "_bgclassCall" ] && DeleteObject "$_memberVal"
		[ "${_mnameShort}" ] && unset this[${_mnameShort}]
	elif [ "$_memberTerm" == ".exists" ]; then
		[ "${_mnameShort}" ] && [ "${this[${_mnameShort}]+isset}" ]
		return
	elif [ "$_memberTerm" == ".isA" ]; then
		# if its not an Object Ref, isA returns false, if it is, set the exit code by callong the isA method.
		[ "${_memberVal:0:12}" == "_bgclassCall" ] && $_memberVal"$_memberTerm" "$@"
		return
	elif [ "$_memberTerm" == "=new" ]; then
		local newObjectClass="${1:-Object}"; shift
		local newObject; ConstructObject "$newObjectClass" newObject "$@"
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
		assertNotEmpty _mnameShort
		eval "this[${_mnameShort}]+='${_memberTerm//$sq/$ssq}'"

	# member variable assignment syntax
	#   $this.<classVarName>=<newValue>
	elif [ "${_memberTerm:0:1}" == "=" ]; then
		local sq="'" ssq="'\\''"
		_memberTerm="${_memberTermWithParams#=}"
		assertNotEmpty _mnameShort
		eval "this[${_mnameShort}]='${_memberTerm//$sq/$ssq}'"

	# If there is _memberTerm left over at this point, then it must be an object member that has not yet been created.
	# This block creates a member object of type Object on demand. If we remove or comment out this block the next block
	# will assert an error in this case
	elif [ "$_memberTerm" ]; then
		assertNotEmpty _mnameShort
		this[${_mnameShort}]="$(NewObject Object)"
		${this[${_mnameShort}]}$_memberTerm "$@"

	# If there is _memberTerm left over at this point, then none of the previous cases knew how to handle it so assert an error
	elif [ "$_memberTerm" ]; then
		assertError -v _memberVal -v _memberTerm -v _mnameShort "'${_mnameShort}' is not an Object reference member of '$_OID'"

	# calling a super class method syntax
	#   $super.<method>
	# TODO: refactor $super. implementation. The current imp only works when initiated from the most subclass because
	#       it uses _classHierarchy from the start. What it needs to do is always be related from the
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
		#local h=(${this[_classHierarchy]}) superName
		#local i=$((${#h[@]}-1)); while [ $_hierarchLevel -gt 0 ] && [ $((--i)) -ge 0 ]; do
		#	type -t ${h[$i]}::${_mnameShort} &>/dev/null && ((_hierarchLevel--))
		#done
		#local _METHOD="${h[$i]}::${_mnameShort}"
		#[ $_hierarchLevel -eq 0 ] && $_METHOD "$@"

		local h="${this[_classHierarchy]}" superName
		local i=0; while [ "$h" ] && [ $i -lt $_hierarchLevel ]; do
			[[ ! "$h" =~ \  ]] && h=""
			h="${h% *}"
			superName="${h##* }"
			type -t ${superName}::${_mnameShort} &>/dev/null && ((i++))
		done
		if [ "$superName" ]; then
			local _METHOD="${superName}::${_mnameShort}"
			objOnEnterMethod "$@"
			$_METHOD "$@"
		fi

	# member function with explicit Class syntax
	#   $this.<class>::<memberFunct> [<p1> .. p2]
	elif [[ "$_mnameShort" =~ :: ]]; then
		local _METHOD="$_mnameShort"
		objOnEnterMethod "$@"
		$_METHOD "$@"

	# member function syntax
	#   $this.<memberFunct> [<p1> .. p2]
	elif [ "${this[_method::${_mnameShort}]+isset}" ]; then
		local _METHOD="${this[_method::${_mnameShort}]}"
		objOnEnterMethod "$@"
		$_METHOD "$@"

	# member variable read syntax. Its ok to read a non-existing member var, but if parameters were provided, it looks like a method call
	#   echo $($this.<memberVar>)
	elif [ ! "$*" ]; then
		echo "${this[${_mnameShort}]}"
		[ "${this[${_mnameShort}]+test}" == "test" ]

	# not found error
	else
		assertError -v _OID -v _memberTermWithParams "member '$_mnameShort' not found for class $_CLASS"
	fi
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
	eval \$$objExpr "$@"
}


# usage: GetOID [-R <retVar>] <objRef>
# usage: local -n obj=$(GetOID <objRef>)
# This returns the name of the underlying array embedded in an objRef. An objRef is a string that allows
# calling methods and accessing members of an obj like $objRef.<member>
# An array variable that has been constructed as an Object acts like an objRef b/c the [0] element of the
# array is the objRef string that points to that same array and an array used without a [] will return the value
# of [0].
# This function is typically used to make a local array reference to the underlying array. An array reference
# can be used for anything that an objRef can but in addition, the array elements can be accessed directly too.
# Params:
#   <objRef> : the string that refers to an object. For simple bash variables that refer to objects, this is their value.
#              for bash arrays that refer to objects, it  the value of the [0] element. In either case, you call this
#              function like
#                  GetOID $myObj   (or GetOID "$myObj"  -- the double quotes are optional)
# Options:
#     -R <retVar> : return the OID in this var instead of on stdout
function GetOID()
{
	local goid_retVar=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R) goid_retVar="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local objRef="$*"
	local oidVal
	if [ "{$objRef}"  == "" ]; then
		oidVal="NullObjectInstance"
	elif [ "${objRef:0:12}"  == "_bgclassCall" ]; then
		oidVal="${objRef#_bgclassCall }"
		oidVal="${oidVal%% *}"
	elif [[ "$objRef" =~ ^[[:word:]]*$ ]] && [[ "{$!objRef}"  =~ "^_bgclassCall" ]]; then
		oidVal="${!objRef}"
	else
		assertError "unknown object ref '$objRef'"
	fi

	returnValue "$oidVal" "$goid_retVar"
}

# usage: IsAnObjRef <objRef>
# returns true if <objRef> is a variable whose content matches "^_bgclassCall .*"
# The <objRef> variable should be deferenced like "IsAnObjRef $myObj" instead of "IsAnObjRef myObj"
# Params:
#   <objRef> : the string that refers to an object. For simple bash variables that refer to objects, this is their value.
#              for bash arrays that refer to objects, it  the value of the [0] element. In either case, you call this
#              function like
#                  GetOID $myObj   (or GetOID "$myObj"  -- the double quotes are optional)
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
		memberRef="${nextTerm#[$]}"

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

	[ "$currentOID" ] && local -n currentAry="$currentOID"
	[ "$remainderPartValue" == ']' ] && remainderPartValue=""

	if    [ ! "$remainderPartValue" ];                                    then  remainderTypeValue="empty"
	elif [[   "$remainderPartValue" =~ ^\$ ]];                            then  remainderTypeValue="objRef"
	elif [[   "$remainderPartValue" =~ ^((.unset)|(.exists)|(=new))$ ]];  then  remainderTypeValue="builtin"
	elif [[   "$remainderPartValue" =~ ^= ]];                             then  remainderTypeValue="assignment"
	elif  [   "${currentAry[$memberRef]+exists}" ];                       then  remainderTypeValue="memberVar"
	elif  [   "${currentAry["_method::$memberRef"]+exists}" ];            then  remainderTypeValue="method"
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
		# _ before system vara are offered
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
	[_classHierarchy]="Object Class"
)
# this is the Instance of 'Class' that describes 'Object'
declare -A Object=(
	[name]="Object"
	[baseClass]=""
	[classHierarchy]="Object"
	[_OID]="Object"
	[_classHierarchy]="Object Class"
)

DeclareClass Class
DeclareClass Object

# we don't construct the Null Object because the [0],[_Ref] value is an assert instead of the normal format
# we protect against re-defining it in case we reload the library
[ ! "${NullObjectInstance[_OID]}" ] && declare -rA NullObjectInstance=(
	[_OID]="NullObjectInstance"
	[_classHierarchy]="Object"
	[0]="assertError Null Object reference called <NULL>"
	[_Ref]="assertError Null Object reference called <NULL>"
)


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
	local i; for i in "${!this[@]}"; do
		if [[ "$i" =~ ^_method:: ]]; then
			echo ${i#_method::}
		fi
	done
}

# usage: $obj.hasMethod <methodName>
# returns true if the object has the specified <methodName>
function Object::hasMethod()
{
	[ "${this[_method::$1]}" ]
}

# usage: $obj.addMethod <methodName>
# adds a specific, one-off method to an Object instance
function Object::addMethod()
{
	local _mname="$1"
	local _mnameShort="${_mname#*::}"

	this[_addedMethods]+=" $_mname"
	this[_method::${_mnameShort}]="$_mname"
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
	local attrib; for attrib in $($this.getIndexes); do
		local value="${this[$attrib]}"
		if [ "${value:0:12}" == "_bgclassCall" ]; then
			local parts=($value)
			value="${parts[0]}  <instance>  ${parts[2]}"
			printf "%-13s: %s\n" "$attrib" "$value" | awk '{if (NR>1) printf("%-13s+ ",""); print $0}'
			$this.$attrib.toString | wrapLines -w12000 	"$attrib." ""
		else
			printf "%-13s: %s\n" "$attrib" "$value" | awk '{if (NR>1) printf("%-13s+ ",""); print $0}'
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




# OBSOLETE? this seems not very useful now. The intention was to allow a real -a array to be stored but that did not work. Stack is better. We can add a Queue too
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



####################################################################################################################
### Example Code


### Defining a Class

#DeclareClass Equipment
#
#function Equipment::oneMeth()
#{
#	echo "	Equipment::oneMeth: class: $_CLASS this is this: '$this' $@"
#	$this.twoMeth "twoing it"
#   # set is the same as this[ipNum]=172.17.0.33 except that it could be overriden to take other actions when  attributes
#   # are set.
#	$this.set ipNum 172.17.0.33
#}
#
#function Equipment::twoMeth()
#{
#	echo "	Equipment::twoMeth: class: $class this is this: $this $@    ipNum=${this[ipNum}"
#}
#
#function Equipment::search()
#{
#   local attributeNames="$(awkDataCache_getColums equipment)"
#	local $attributeNames
#	read -r $attributeNames < <(awkData_lookup all "$@")
#   local attr; for attr in $attributeNames; do
#		this[$attr]=${!attr}
#   done
#}
#
#function Equipment::bgtrace()
#{
#	echo  "overrride  super='$super'"
#
#   # now call the base class version (if that is desired)
#	#$super.bgtrace
#}


#### Using an Object
#
# creating a local object that lives only for the duration of the function call...
#function myTest()
#{
#   # note that the empty () are important. otherwise bash does not create it until used and
#   # ConstructObject won't be able to tell that its an existing array
#	local -A equipObj=()
#	ConstructObject Equipment equipObj
#	#declare -p equipObj
#
#	$equipObj.search name:waldo
#   echo "waldo's IP is ${this[ip]}"
#}
#
# creating a 'heap' object that could be passed back from a function
#function equipGetSelf()
#{
#	local equipObj
#	ConstructObject Equipment equipObj
#
#	$equipObj.search name:"$(hostname -s)"
#   echo "$equipObj"
#}
#
# Optionally, you can declare the object reference to a dynamic (aka heap) object with the -n
# option (Ubuntu 14.04 and later -- not supported in 12.04). This will result in it becoming a
# reference to the underlying array. It will work exactly the same for object method calls but
# it will also allow accessing the array elements directly without using complex sysntax.
#declare -n equipObj
#ConstructObject Equipment equipObj
#$equipObj.bgtrace
#equipObj[color]="blue"
#echo "color=${this[color]}"
#
#
#
#echo "###########################"
#$equipObj.oneMeth with .
#
#echo "my oid =${equipObj[_OID]}"
#
#echo "###########################"
#$equipObj.getOID
#echo "###########################"
#$equipObj.getMethods
#echo "###########################"
#$equipObj.getAttributes
#echo "###########################"
#$equipObj.set color blue
#echo "###########################"
#$equipObj.get color
#echo "###########################"
#$equipObj.bgtrace
#
#function doSome()
#{
#	local -n eq1="$1"
#	local -n eq2="$2"
#	echo "eq1 -> $($eq1.get ipNum)"
#	echo "eq2 -> $($eq2.get ipNum)"
#}
#
#declare -n equipObj2
#ConstructObject Equipment equipObj2
#$equipObj2.set ipNum "4545"
#
#doSome equipObj equipObj2

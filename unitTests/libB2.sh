




function b2()
{
	case $1 in
		b2USR1)
			trap 'bgStackPrint $stackPrintOpts' USR1
			kill -USR1 $BASHPID; shift
			;;
		b2USR1OneDown)
			trap 'oneDown' USR1
			kill -USR1 $BASHPID; shift
			;;
	esac
	a1 "$@" "${foo:-a1_arg1}"
}

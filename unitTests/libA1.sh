

function a1()
{
	case $1 in
		a1Assert)
			assertError "a1 is asserting an error"
		;;

		a1DBG)
			builtin trap 'bgStackFreeze --all "" "$BASH_COMMAND" "$LINENO"
				bgStackPrint $stackPrintOpts
				builtin trap "" DEBUG
			' DEBUG
			: noop next cmd
			# bgStackFreeze --all "" "similulatedCmd sc1 sc2" "15"
			# bgStackPrint $stackPrintOpts
		;;

		a1NoFreeze)
			bgStackPrint $stackPrintOpts
			;;

		*)	bgStackFreeze --all
			bgStackPrint $stackPrintOpts
		;;
	esac
}

#
# hello world
#

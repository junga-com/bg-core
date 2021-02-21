








function c3()
{
	b2 "$@" "b2_p1" 'b2_p2' b2_p3
}




function c3USR1()
{
	trap 'bgStackPrint $stackPrintOpts' USR1
	kill -USR1 $BASHPID
}

function c3USR1_func()
{
	trap 'oneDown' USR1
	kill -USR1 $BASHPID
}

function c3USR1FirstLine_DBG()
{
	trap 'aNoopCommand' USR1
	builtin trap 'dbgLINENO="$LINENO"
		if [ "$LINENO" == "2" ]; then
			bgStackFreeze --all "" "$BASH_COMMAND" "$dbgLINENO"
			bgStackPrint $stackPrintOpts
			builtin trap "" DEBUG
		fi
	' DEBUG
	kill -USR1 $BASHPID
}


function c3USR1_DBG()
{
	trap 'aNoopCommand' USR1
	builtin trap 'dbgLINENO="$LINENO"
		if [[ "$BASH_COMMAND" =~ ^aNoopCommand ]]; then
			bgStackFreeze --all "" "$BASH_COMMAND" "$dbgLINENO"
			bgStackPrint $stackPrintOpts
			builtin trap "" DEBUG
			(exit 1)
		fi
	' DEBUG
	kill -USR1 $BASHPID
}

function c3USR1_func_DBG()
{
	trap 'oneDown off' USR1
	builtin trap 'dbgLINENO="$LINENO"
		if [[ "$BASH_COMMAND" =~ ^aNoopCommand ]]; then
			bgStackFreeze --all "" "$BASH_COMMAND" "$dbgLINENO"
			bgStackPrint $stackPrintOpts
			builtin trap "" DEBUG
			(exit 1)
		fi
		(exit 0)
	' DEBUG
	kill -USR1 $BASHPID
}

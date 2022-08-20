








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
			builtin trap "" DEBUG
			bgStackFreeze --all "" "$BASH_COMMAND" "$dbgLINENO"
			bgStackPrint $stackPrintOpts
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
			setExitCode 1
		fi
	' DEBUG
	kill -USR1 $BASHPID
}

function c3USR1_func_DBG()
{
	trap 'oneDown off' USR1
	builtin trap 'dbgLINENO="$LINENO"
		if [[ "$BASH_COMMAND" =~ ^aNoopCommand ]]; then
			builtin trap "" DEBUG
			bgStackFreeze --all "" "$BASH_COMMAND" "$dbgLINENO"
			bgStackPrint $stackPrintOpts
			setExitCode 1
		fi
		setExitCode 0
	' DEBUG
	kill -USR1 $BASHPID
}

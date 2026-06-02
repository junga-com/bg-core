#!/usr/bin/bash
# GNU bash, version 5.0.17(1)-release (x86_64-pc-linux-gnu)
# still present in
# GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)
function shouldReturnFalse() {
	false
	return
	#return false # this works
}
trap 'shouldReturnFalse && echo "woops"' EXIT

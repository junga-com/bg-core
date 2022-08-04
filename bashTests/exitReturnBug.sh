#!/usr/bin/bash
# GNU bash, version 5.0.17(1)-release (x86_64-pc-linux-gnu)
function shouldReturnFalse() {
	false
	return
}
trap 'shouldReturnFalse && echo "woops"' EXIT

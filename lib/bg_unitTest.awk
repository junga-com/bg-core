@include "bg_libCore.awk"


# library to parse *.ut scripts

BEGIN {
	arrayCreate(utFuncs)
}

BEGINFILE {
	if (fullyQualyfied)
		utFilePrefix=gensub(/(^.*unitTests[/])|([.]ut$)/,"","g",FILENAME)":"
}

### gather ut_<testcase>=() variable info

# the start
$1~/ut_.*=/ {
	inParams=gensub(/=.*$/,"","g", $1)
	next
}

# the end
inParams && /^)/ {
	inParams=""
	next
}

# utParams in the middle
inParams && $1~/^[[].*[]]=.*$/ {
	utParams=gensub(/(^[[])|(]=.*$)/,"","g",$1)
	utPByFunct[inParams][length(utPByFunct[inParams])]=utParams
}

### gather ut_<testcase>() function info

# the start
$1=="function" && $2~/^ut_.*[(][)]/{
	utFunc=gensub(/[(][)]$/,"","g", $2)
	utFuncs[length(utFuncs)]=utFunc;
	funcLineStart[utFunc]=FNR
	next
}

# the end
utFunc && /^}[[:space:]]*$/ {
	funcLineEnd[utFunc]=FNR
	utFunc=""
	next
}

# expect comments in the middle
utFunc && $1=="#" && $2=="expect" {
	funcExpectComments[utFunc]=gensub(/^.*expect[[:space:]]+/,"","g",$0)
}

END {
	for (i in utFuncs) {
		utFunc=utFuncs[i]

		if (lineNumFlag)
			lineNumPrefix=sprintf("%4s %4s ", funcLineStart[utFunc], funcLineEnd[utFunc])

		if (expectCommentsFlag)
			expectCommentsSuffix=funcExpectComments[utFunc]

		if (utFunc in utPByFunct) {
			for (j in utPByFunct[utFunc]) {
				utParams = utPByFunct[utFunc][j]
				printf("%s%s%s:%s %s\n", lineNumPrefix, utFilePrefix, gensub(/^ut_/,"","g",utFunc), utParams, expectCommentsSuffix)
			}
		} else {
			printf("%s%s%s: %s\n", lineNumPrefix, utFilePrefix, gensub(/^ut_/,"","g",utFunc), expectCommentsSuffix)
		}
	}
}

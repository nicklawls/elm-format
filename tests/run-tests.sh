#!/bin/bash

#shellcheck -e SC2002 "./tests/run-tests.sh" || exit 1
#shellcheck "./build-package.sh" || exit 1
#shellcheck "./package/linux/build-package.sh" || exit 1

cabal test || exit 1
cabal build || exit 1

ELM_FORMAT="./dist/build/elm-format/elm-format"
if which md5 > /dev/null; then
	MD5="md5"
else
	MD5="md5sum"
fi

function returnCodeShouldEqual() {
	[ "$?" -eq "$1" ] || exit 1
}

function shouldOutputTheSame() {
	echo "$1" "$2"
	diff <(echo "$1") <(echo "$2") || exit 1
}

function outputShouldRoughlyMatchPatterns() {
	PATTERNS_FILE="$1"
	OUTPUT="$2"

	MATCHES=$(echo "$OUTPUT" | grep -F -f "$PATTERNS_FILE")
	[[ "$(echo "$MATCHES" | wc -l)" == "$(wc -l < "$PATTERNS_FILE")" ]] || exit 1
}

function compareFiles() {
	EXPECTED="$1"
	ACTUAL="$2"

	diff -u "$ACTUAL" "$EXPECTED"
	returnCodeShouldEqual 0
	echo -n "Checksum: "
	"$MD5" "$ACTUAL"
}

function checkWaysToRun() {
	cp "tests/test-files/good/Simple.elm" "_input.elm"
	cp "tests/test-files/transform/Examples.elm" "_input2.elm"

	INPUT="_input.elm"
	INPUT_2="_input2.elm"
	OUTPUT="formatted.elm"
	DIRECTORY="tests/test-files/directory"
	RECURSIVE_DIRECTORY="tests/test-files/recursive-directory"

	NONEXISTENT="DoesNotExist.elm"
	EMPTY_DIR=$(mktemp -d -t elm-format-tests.XXXXXXXXXX)

	echo
	echo "------------------------------"
	echo "# WAYS TO RUN"
	echo

	echo "## elm-format --help"
	HELP=$("$ELM_FORMAT" --help 2>&1)
	returnCodeShouldEqual 0

	echo "## elm-format -h"
	SHORTHELP=$("$ELM_FORMAT" -h 2>&1)
	returnCodeShouldEqual 0
	shouldOutputTheSame "$HELP" "$SHORTHELP"

	echo "## elm-format"
	NOARGS=$("$ELM_FORMAT" 2>&1)
	returnCodeShouldEqual 0
	shouldOutputTheSame "$HELP" "$NOARGS"

	echo "## elm-format INPUT --validate does not change things"
	"$ELM_FORMAT" "$INPUT_2" --validate 1>/dev/null
	compareFiles "tests/test-files/transform/Examples.elm" "$INPUT_2"
	returnCodeShouldEqual 0

	echo "## elm-format INPUT --validate with unformatted file exits 1"
	"$ELM_FORMAT" "$INPUT_2" --validate 1>/dev/null
	returnCodeShouldEqual 1

	echo "## elm-format INPUT --validate with formatted file exits 1"
	"$ELM_FORMAT" "$INPUT_2" --yes 1>/dev/null
	"$ELM_FORMAT" "$INPUT_2" --validate 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format INPUT (answer = y)"
	echo "y" | "$ELM_FORMAT" "$INPUT" 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format INPUT (answer = n)"
	echo "n" | "$ELM_FORMAT" "$INPUT" 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format INPUT --yes"
	"$ELM_FORMAT" "$INPUT" --yes 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format --yes INPUT"
	"$ELM_FORMAT" --yes "$INPUT" 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format NONEXISTENT"
	"$ELM_FORMAT" "$NONEXISTENT" 1>/dev/null
	returnCodeShouldEqual 1

	echo "## elm-format INPUT --output OUTPUT"
	"$ELM_FORMAT" "$INPUT" --output "$OUTPUT" 1>/dev/null
	returnCodeShouldEqual 0
	compareFiles "$INPUT" "$OUTPUT" 1>/dev/null

	echo "## cat INPUT | elm-format --stdin"
	cat "$INPUT" | "$ELM_FORMAT" --stdin > "$OUTPUT"
	returnCodeShouldEqual 0
	compareFiles "$INPUT" "$OUTPUT"

	echo "## cat INPUT | elm-format --stdin INPUT"
	STDOUT=$(cat "$INPUT" | "$ELM_FORMAT" --stdin "$INPUT" 2>&1)
	returnCodeShouldEqual 1

	echo "## cat INPUT | elm-format --stdin --output OUTPUT"
	cat "$INPUT" | "$ELM_FORMAT" --stdin --output "$OUTPUT" 1>/dev/null
	returnCodeShouldEqual 0
	compareFiles "$INPUT" "$OUTPUT" 1>/dev/null

	echo "## cat INPUT | elm-format INPUT --stdin --output OUTPUT"
	cat "$INPUT" | "$ELM_FORMAT" "$INPUT" --stdin --output "$OUTPUT" 1>/dev/null
	returnCodeShouldEqual 1

	echo "## elm-format DIRECTORY --output OUTPUT"
	"$ELM_FORMAT" "$DIRECTORY" --output "$OUTPUT" 1>/dev/null
	returnCodeShouldEqual 1

	echo "## elm-format DIRECTORY (answer = n)"
	echo "n" | "$ELM_FORMAT" "$DIRECTORY" 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format DIRECTORY (answer = y)"
	echo "y" | "$ELM_FORMAT" "$RECURSIVE_DIRECTORY" 1>/dev/null 2>/dev/null
	returnCodeShouldEqual 1
	# invalid file in the nested directory
	# if recursion didn't work, return code would be 0
	# because it never got to the nested invalid file

	echo "## elm-format DIRECTORY --yes"
	"$ELM_FORMAT" "$DIRECTORY" --yes 1>/dev/null 2>/dev/null
	returnCodeShouldEqual 1

	echo "## elm-format EMPTY_DIRECTORY"
	"$ELM_FORMAT" "$EMPTY_DIR" 1>/dev/null
	returnCodeShouldEqual 1

	echo "## elm-format INPUT --validate"
	"$ELM_FORMAT" "$INPUT" --validate 1>/dev/null
	returnCodeShouldEqual 0

	echo "## elm-format INPUT --validate --yes"
	"$ELM_FORMAT" "$INPUT" --validate --yes 1>/dev/null
	returnCodeShouldEqual 0


	echo "# OK!"
	echo "------------------------------"
}

function checkGood() {
	INPUT="tests/test-files/good/$1"
	OUTPUT="formatted.elm"

	echo
	echo "## good/$1"
	time "$ELM_FORMAT" "$INPUT" --output "$OUTPUT" 1>/dev/null
	returnCodeShouldEqual 0
	compareFiles "$INPUT" "$OUTPUT"
}

function checkGoodAllSyntax() {
	checkGood "AllSyntax/$1.elm"
	checkGood "AllSyntax/BlockComments/$1.elm"
	checkGood "AllSyntax/LineComments/$1.elm"
}

function checkBad() {
	INPUT="tests/test-files/bad/$1"
	EXPECTED="tests/test-files/bad/${1%.*}.output.txt"

	echo "## bad/$1"
	STDOUT=$(cat "$INPUT" | "$ELM_FORMAT" --stdin 2>&1)
	returnCodeShouldEqual 1
	outputShouldRoughlyMatchPatterns "$EXPECTED" "$STDOUT"
}

function checkTransformation() {
	INPUT="tests/test-files/transform/$1"
	OUTPUT="formatted.elm"
	EXPECTED="tests/test-files/transform/${1%.*}.formatted.elm"

	echo
	echo "## transform/$1"
	time "$ELM_FORMAT" "$INPUT" --output "$OUTPUT" 1>/dev/null
	returnCodeShouldEqual 0
	compareFiles "$EXPECTED" "$OUTPUT"
}


echo
echo
echo "# elm-format test suite"

checkWaysToRun

checkGood Simple.elm
checkGood AllSyntax/AllSyntax.elm
checkGoodAllSyntax Module
checkGoodAllSyntax Declarations
checkGoodAllSyntax Patterns
checkGoodAllSyntax Types
checkGoodAllSyntax Expressions
checkGood Comments.elm
checkGood AllSyntax/GLShader.elm
checkGood AllSyntax/Literals.elm
checkGood AllSyntax/Comments.elm
checkGood ApiSketch.elm

checkGood evancz/start-app/StartApp.elm
checkGood TheSeamau5/elm-check/Check.elm
checkGood rtfeldman/dreamwriter/Editor.elm
checkGood rtfeldman/dreamwriter/LeftSidebar.elm
checkGood rtfeldman/dreamwriter/RightSidebar.elm
checkGood rtfeldman/dreamwriter/WordGraph.elm
checkGood avh4/elm-fifo/Fifo.elm

checkBad Empty.elm
checkBad UnexpectedComma.elm
checkBad UnexpectedEndOfInput.elm

checkTransformation Examples.elm
checkTransformation QuickCheck-4562ebccb71ea9f622fb99cdf32b2923f6f9d34f-2529668492575674138.elm
checkTransformation QuickCheck-94f37da84c1310f03dcfa1059ce870b73c94a825--6449652945938213463.elm

echo
echo "# GREAT SUCCESS!"

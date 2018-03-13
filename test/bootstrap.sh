#!/bin/sh

set -o errexit
set -o nounset
IFS=' 	
'

if test "${IS_TEST_CASE:-1}" -eq '1'
then
	DIR_TESTCASES="$(cd -- "$(dirname -- "$0")" && pwd -P)"
	DIR_TEST="$(dirname "${DIR_TESTCASES}")"
else
	DIR_TEST="$(cd -- "$(dirname -- "$0")" && pwd -P)"
	DIR_TESTCASES="${DIR_TEST}/tests"
fi
DIR_ROOT="$(dirname "${DIR_TEST}")"
DIR_BIN="${DIR_ROOT}/bin"
DIR_TEMP="${DIR_TEST}/temp"
DIR_SOURCE="${DIR_TEMP}/source"
DIR_DESTINATION="${DIR_TEMP}/destination"

BIN_MAIN="${DIR_BIN}/incremental-git-filterbranch.sh"
if test ! -f "${BIN_MAIN}"
then
	echo 'Failed to detect environment'>&2
	exit 1
fi

alias git-source='git -C "${DIR_SOURCE}"'
alias git-destination='git -C "${DIR_DESTINATION}"'

initializeRepositories () {
	rm -rf "${DIR_TEMP}"
	mkdir "${DIR_TEMP}"

	git init --quiet "${DIR_SOURCE}"
	git-source config --local user.email 'email@example.com'
	git-source config --local user.name 'John Doe'

	echo 'test'>"${DIR_SOURCE}/in-root"
	git-source add --all
	git-source commit --quiet --message 'Commit #1'
	git-source tag tag-01

	mkdir "${DIR_SOURCE}/subdir"
	echo 'test'>"${DIR_SOURCE}/subdir/subfile"
	git-source add --all
	git-source commit --quiet --message 'Commit #2'

	git-source tag tag-02

	echo 'test'>>"${DIR_SOURCE}/in-root"
	git-source add --all
	git-source commit --quiet --message 'Commit #3'

	git-source tag tag-03
	
	echo 'test'>>"${DIR_SOURCE}/in-root"
	git-source add --all
	git-source commit --quiet --message 'Commit #3'

	git init --bare --quiet "${DIR_DESTINATION}"
}

getTagList () {
	printf '%s\n' $(git -C "${1}" show-ref --tags | sed -E 's:^.*?refs/tags/::' || true)
}

itemInList () {
	for itemInListItem in ${2}
	do
		if test "${1}" = "${itemInListItem}"
		then
			return 0
		fi
	done
	return 1
}

itemNotInList () {
	if itemInList "${1}" "${2}"
	then
		return 1
	else
		return 0
	fi
}

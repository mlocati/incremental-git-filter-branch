#!/bin/sh
#
# Wrapper for git-filter-branch so that we can use it in an incremental
# way.
#
# Copyright (c) Michele Locati, 2018
#
# MIT license
# https://github.com/mlocati/incremental-git-filter-branch/blob/master/LICENSE
#

# Exit immediately if a pipeline, a list, or a compound command, exits with a non-zero status.
set -o errexit
# Treat unset variables and parameters other than the special parameters "@" and "*" as an error when performing parameter expansion.
set -o nounset
# Set the Internal Field Separator
IFS=' 	
'

die () {
	printf '%s\n' "${1}">&2
	exit 1
}

usage () {
	if test $# -eq 1
	then
		printf '%s\n\n%s\n' "${1}" "Type ${0} --help to get help">&2
		exit 1
	fi
	printf '%s' "Usage:
${0} [-h | --help] [--workdir <workdirpath>]
	[--whitelist <whitelist>] [--blacklist <blacklist>]
	[--no-hardlinks] [--no-atomic] [--no-lock] [--]
	<sourcerepository> <filter> <destinationrepository>
	Apply git filter-branch in an incremental way

Where:

--workdir workdirpath
	set the path to the directory where the temporary local repositories are created.
	By default, we'll use a directory named temp in the current directory.
--whitelist <whitelist>
	a whitespace-separated list of branches be included in the process.
	Multiple options can be specified.
	By default, all branches will be processed.
--blacklist <blacklist>
	a whitespace-separated list of branches to be excluded from the process.
	Multiple options can be specified.
	By default, all branches will be processed.
	Blacklisted branches take the precedence over whitelisted ones.
--no-hardlinks
	Do not create hard links (useful for file systems that don't support it).
--no-atomic
	Do not use an atomic transaction when pushing to the destination repository.
--no-lock
	Do not acquire an exclusive lock (useful for systems that don't have flock(1)).
sourcerepository
	The URL or path to the source repository.
filter
	The list of parameters to be passed to the git filter-branch command.
destinationrepository
	The URL or path to the destination repository.

You can prefix branch names in both whitelist and blacklist with 'rx:': in this case a regular expression check will be performed.
For instance: --whitelist 'master rx:release\\/\\d+(\\.\\d+)*' will match 'master' and 'release/1.1'
"
	exit 0
}


readParameters () {
	WORK_DIRECTORY="$(pwd)/temp"
	BRANCH_WHITELIST=''
	BRANCH_BLACKLIST=''
	NO_HARDLINKS=''
	ATOMIC='--atomic'
	NO_LOCK=''
	while :
	do
		if test $# -lt 1
		then
			usage 'Not enough arguments'
		fi
		readParameters_currentArgument="${1}"
		case "${readParameters_currentArgument}" in
			--)
				shift 1
				break
				;;
			-h|--help)
				usage
				;;
			--workdir)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				WORK_DIRECTORY="${2}"
				if test -z "${WORK_DIRECTORY}"
				then
					die 'The working directory option is empty'
				fi
				shift 2
				;;
			--whitelist)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				BRANCH_WHITELIST="${BRANCH_WHITELIST} ${2}"
				shift 2
				;;
			--blacklist)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				BRANCH_BLACKLIST="${BRANCH_BLACKLIST} ${2}"
				shift 2
				;;
			--no-hardlinks)
				NO_HARDLINKS='--no-hardlinks'
				shift 1
				;;
			--no-atomic)
				ATOMIC='--no-atomic'
				shift 1
				;;
			--no-lock)
				NO_LOCK='yes'
				shift 1
				;;
			-*)
				usage "Unknown option: ${readParameters_currentArgument}"
				;;
			*)
				break
				;;
		esac
	done
	if test $# -lt 3
	then
		usage 'Not enough arguments'
	fi
	if test $# -gt 3
	then
		usage 'Too many arguments'
	fi
	SOURCE_REPOSITORY_URL="${1}"
	if test -z "${SOURCE_REPOSITORY_URL}"
	then
		die 'The source repository location is empty.'
	fi
	FILTER="${2}"
	if test -z "${FILTER}"
	then
		die 'The filter is empty.'
	fi
	DESTINATION_REPOSITORY_URL="${3}"
	if test -z "${DESTINATION_REPOSITORY_URL}"
	then
		die 'The destination repository location is empty.'
	fi
}

absolutizeUrl () {
	absolutizeUrl_url="${1}"
	case "${absolutizeUrl_url}" in
		[/\\]* | ?*:*)
			;;
		*)
			absolutizeUrl_url=$(cd "${absolutizeUrl_url}" && pwd)
			;;
	esac
	printf '%s' "${absolutizeUrl_url}"
}

checkFilter () {
	checkFilter_some=0
	while :
	do
		if test $# -lt 1
		then
			break
		fi
		checkFilter_some=1
		checkFilter_optName="${1}"
		shift 1
		case "${checkFilter_optName}" in
			--setup)
				if test $# -lt 1
				then
					die "Invalid syntax in filter (${checkFilter_optName} without command)"
				fi
				shift 1
				;;
			--tag-name-filter)
				die "You can't use --tag-name-filter (it's handled automatically)"
				;;
			--*-filter)
				if test $# -lt 1
				then
					die "Invalid syntax in filter (${checkFilter_optName} without command)"
				fi
				shift 1
				;;
			--prune-empty)
				;;
			*)
				die "Invalid syntax in filter (unknown option: ${checkFilter_optName})"
				;;
		esac
	done
	if test ${checkFilter_some} -lt 1
	then
		die 'The filter is empty.'
	fi
}

normalizeParameters () {
	echo '# Normalizing source repository URL'
	SOURCE_REPOSITORY_URL=$(absolutizeUrl "${SOURCE_REPOSITORY_URL}")
	echo '# Normalizing destination repository URL'
	DESTINATION_REPOSITORY_URL=$(absolutizeUrl "${DESTINATION_REPOSITORY_URL}")
	echo '# Checking filter'
	# shellcheck disable=SC2086
	checkFilter ${FILTER}
}

checkEnvironment () {
	if test -z "${NO_LOCK}"
	then
		if ! command -v flock >/dev/null
		then
			die 'The flock command is not available. You may want to use --no-lock option to avoid using it (but no concurrency check will be performed).'
		fi
	fi
	if ! command -v git >/dev/null
	then
		die 'The required git command is not available.'
	fi
	if ! command -v sed >/dev/null
	then
		die 'The required sed command is not available.'
	fi
	if ! command -v grep >/dev/null
	then
		die 'The required grep command is not available.'
	fi
	if ! command -v cut >/dev/null
	then
		die 'The required grep command is not available.'
	fi
	if ! command -v md5sum >/dev/null
	then
		die 'The required md5sum command is not available.'
	fi
}


initializeEnvironment () {
	if ! test -d "${WORK_DIRECTORY}"
	then
		mkdir --parents -- "${WORK_DIRECTORY}" || die "Failed to create working directory ${WORK_DIRECTORY}"
	fi
	SOURCE_REPOSITORY_DIR=${WORK_DIRECTORY}/source-$(md5 "${SOURCE_REPOSITORY_URL}")
	WORKER_REPOSITORY_DIR=${WORK_DIRECTORY}/worker-$(md5 "${SOURCE_REPOSITORY_URL}${DESTINATION_REPOSITORY_URL}")
}

acquireLock () {
	if test -z "${NO_LOCK}"
	then
		exec 9>"${WORKER_REPOSITORY_DIR}.lock"
		while :
		do
			if flock --exclusive --timeout 3 9
			then
				break
			fi
			echo 'Lock detected... Waiting that it becomes available...'
		done
	fi
}

prepareLocalSourceRepository () {
	prepareLocalSourceRepository_haveToCreateMirror=1
	if test -f "${SOURCE_REPOSITORY_DIR}/config"
	then
		echo '# Updating source repository'
		if git -C "${SOURCE_REPOSITORY_DIR}" remote update --prune
		then
			prepareLocalSourceRepository_haveToCreateMirror=0
		fi
	fi
	if test ${prepareLocalSourceRepository_haveToCreateMirror} -eq 1
	then
		echo '# Cloning source repository'
		rm -rf "${SOURCE_REPOSITORY_DIR}"
		git clone --mirror "${SOURCE_REPOSITORY_URL}" "${SOURCE_REPOSITORY_DIR}"
	fi
}

getSourceRepositoryBranches () {
	echo '# Listing source branches'
	# List all branches and takes only the part after "refs/heads/", and store them in the SOURCE_BRANCHES variable
	SOURCE_BRANCHES=$(git -C "${SOURCE_REPOSITORY_DIR}" show-ref --heads | sed -E 's:^.*?refs/heads/::')
	if test -z "${SOURCE_BRANCHES}"
	then
		die 'Failed to retrieve branch list'
	fi
}

getTagList () {
	# List all tags and takes only the part after "refs/heads/"
	printf '%s\n' $(git -C "${1}" show-ref --tags | sed -E 's:^.*?refs/tags/::' || true)
}

branchInList () {
	branchInList_branch="${1}"
	branchInList_list="${2}"
	for branchInList_listItem in ${branchInList_list}
	do
		if test -n "${branchInList_listItem}"
		then
			case "${branchInList_listItem}" in
				rx:*)
					branchInList_substring=$(printf '%s' "${branchInList_listItem}" | cut -c4-)
					if printf '%s' "${branchInList_branch}" | grep -Eq "^${branchInList_substring}$"
					then
						return 0
					fi
					;;
				*)
					if test "${branchInList_branch}" = "${branchInList_listItem}"
					then
						return 0
					fi
					;;
			esac
		fi
	done
	return 1
}

getBranchesToProcess () {
	echo '# Determining branches to be processed'
	WORK_BRANCHES=''
	for getBranchesToProcess_sourceBranch in ${SOURCE_BRANCHES}
	do
		if ! branchInList "${getBranchesToProcess_sourceBranch}" "${BRANCH_BLACKLIST}"
		then
			getBranchesToProcess_branchPassed=''
			if test -z "${BRANCH_WHITELIST}"
			then
				getBranchesToProcess_branchPassed='yes'
			elif branchInList "${getBranchesToProcess_sourceBranch}" "${BRANCH_WHITELIST}"
			then
				getBranchesToProcess_branchPassed='yes'
			fi
			if test -n "${getBranchesToProcess_branchPassed}"
			then
				WORK_BRANCHES="${WORK_BRANCHES} ${getBranchesToProcess_sourceBranch}"
			fi
		fi
	done
	if test -z "${WORK_BRANCHES}"
	then
		die 'None of the source branches passes the whitelist/blacklist filter'
	fi
}

prepareWorkerRepository () {
	prepareWorkerRepository_haveToCreateRepo=1
	if test -f "${WORKER_REPOSITORY_DIR}/.git/config"
	then
		echo '# Checking working repository'
		if git -C "${WORKER_REPOSITORY_DIR}" rev-parse --git-dir >/dev/null 2>/dev/null
		then
			prepareWorkerRepository_haveToCreateRepo=0
		fi
	fi
	if test ${prepareWorkerRepository_haveToCreateRepo} -eq 1
	then
		echo '# Creating working repository'
		rm -rf "${WORKER_REPOSITORY_DIR}"
		echo '# Adding mirror source repository to working repository'
		git clone ${NO_HARDLINKS} --local --origin source "${SOURCE_REPOSITORY_DIR}" "${WORKER_REPOSITORY_DIR}"
		echo '# Adding destination repository to working repository'
		if ! git -C "${WORKER_REPOSITORY_DIR}" remote add destination "${DESTINATION_REPOSITORY_URL}"
		then
			rm -rf "${WORKER_REPOSITORY_DIR}"
			exit 1
		fi
		echo '# Fetching data from cloned destination repository'
		if ! git -C "${WORKER_REPOSITORY_DIR}" fetch --prune destination
		then
			rm -rf "${WORKER_REPOSITORY_DIR}"
			exit 1
		fi
	fi
}

processBranch () {
	processBranch_branch="${1}"
	processBranch_notUpdated=1
	echo '  - fetching'
	git -C "${WORKER_REPOSITORY_DIR}" fetch --quiet --tags source "${processBranch_branch}"
	echo '  - checking-out'
	git -C "${WORKER_REPOSITORY_DIR}" checkout --quiet --force -B "filter-branch/source/${processBranch_branch}" "remotes/source/${processBranch_branch}"
	echo '  - determining delta'
	processBranch_range="filter-branch/result/${processBranch_branch}"
	processBranch_last=$(git -C "${WORKER_REPOSITORY_DIR}" show-ref -s "refs/heads/filter-branch/filtered/${processBranch_branch}" || true)
	if test -n "${processBranch_last}"
	then
		processBranch_range="${processBranch_last}..${processBranch_range}"
	fi
	processBranch_fetchHead=$(git -C "${WORKER_REPOSITORY_DIR}" rev-parse FETCH_HEAD)
	if test "${processBranch_last}" = "${processBranch_fetchHead}"
	then
		echo '  - nothing new, skipping'
	else
		echo '  - initializing filter'
		rm -f "${WORKER_REPOSITORY_DIR}/.git/refs/filter-branch/originals/${processBranch_branch}/refs/heads/filter-branch/result/${processBranch_branch}"
		git -C "${WORKER_REPOSITORY_DIR}" branch --force "filter-branch/result/${processBranch_branch}" FETCH_HEAD
		rm -rf "${WORKER_REPOSITORY_DIR}.filter-branch"
		echo "  - filtering commits"
		# shellcheck disable=SC2086
		if git -C "${WORKER_REPOSITORY_DIR}" filter-branch \
			${FILTER} \
			--tag-name-filter 'IFS=$(printf "\r\n") read -r tag; printf "filter-branch/converted-tags/%s" "${tag}"' \
			-d "${WORKER_REPOSITORY_DIR}.filter-branch" \
			--original "refs/filter-branch/originals/${processBranch_branch}" \
			--state-branch "refs/filter-branch/state" \
			--force \
			-- "${processBranch_range}"
		then
			processBranch_foundSomething=1
		else
			# May fail with "Found nothing to rewrite"
			processBranch_foundSomething=0
		fi
		echo "  - storing state"
		git -C "${WORKER_REPOSITORY_DIR}" branch -f "filter-branch/filtered/${processBranch_branch}" FETCH_HEAD
		if test ${processBranch_foundSomething} -eq 1
		then
			processBranch_notUpdated=0
		fi
	fi
	return ${processBranch_notUpdated}
}

processBranches () {
	processBranches_pushRefSpec=''
	for processBranches_branch in ${WORK_BRANCHES}
	do
		echo "# Processing branch ${processBranches_branch}"
		processBranch "${processBranches_branch}" || true
		processBranches_pushRefSpec="${processBranches_pushRefSpec} filter-branch/result/${processBranches_branch}:${processBranches_branch}"
	done
	echo '# Listing source tags'
	processBranches_sourceTags=$(getTagList "${SOURCE_REPOSITORY_DIR}")
	echo '# Determining destination tags'
	for processBranches_sourceTag in ${processBranches_sourceTags}
	do
		processBranches_rewrittenTag="filter-branch/converted-tags/${processBranches_sourceTag}"
		if git -C "${WORKER_REPOSITORY_DIR}" rev-list --max-count=0 "${processBranches_rewrittenTag}" 2>/dev/null
		then
			processBranches_pushRefSpec="${processBranches_pushRefSpec} ${processBranches_rewrittenTag}:${processBranches_sourceTag}"
		fi
	done
	echo "# Pushing to destination repository"
	# shellcheck disable=SC2086
	git -C "${WORKER_REPOSITORY_DIR}" push --quiet --force ${ATOMIC} destination ${processBranches_pushRefSpec}
}

md5 () {
	printf '%s' "${1}" | md5sum | sed -E 's: .*$::'
}

readParameters "$@"
normalizeParameters
checkEnvironment
initializeEnvironment
acquireLock
prepareLocalSourceRepository
getSourceRepositoryBranches
getBranchesToProcess
prepareWorkerRepository
processBranches
echo "All done."


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

# Exit with 1.
#
# Arguments:
#   $1: the message to be printed
die () {
	printf '%s\n' "${1}">&2
	exit 1
}


# Print the usage and exit.
#
# Arguments:
#   $1 [optional]: if specified, a short usage message will be printed and we'll exit with 1;
#                  if not specified: a full syntax will be printed and we'll exit with 0
usage () {
	if test $# -eq 1
	then
		printf '%s\n\n%s\n' "${1}" "Type ${0} --help to get help">&2
		exit 1
	fi
	printf '%s' "Usage:
${0} [-h | --help] [--workdir <workdirpath>]
	[--branch-whitelist <whitelist>] [--branch-blacklist <blacklist>]
	[--tag-whitelist <whitelist>] [--tag-blacklist <blacklist>]
	[--tags-plan (visited|all|none)]
	[--tags-max-history-lookup <depth>]
	[--no-hardlinks] [--no-atomic] [--no-lock] [--]
	<sourcerepository> <filter> <destinationrepository>
	Apply git filter-branch in an incremental way

Where:

--workdir workdirpath
	set the path to the directory where the temporary local repositories are created.
	By default, we'll use a directory named temp in the current directory.
--branch-whitelist <whitelist>
	a whitespace-separated list of branches to be included in the process.
	Multiple options can be specified.
	By default, all branches will be processed.
--branch-blacklist <blacklist>
	a whitespace-separated list of branches to be excluded from the process.
	Multiple options can be specified.
	By default, all branches will be processed.
	Blacklisted branches take the precedence over whitelisted ones.
--tag-whitelist <whitelist>
	a whitespace-separated list of tags to be included in the process.
	Multiple options can be specified.
--tag-blacklist <blacklist>
	a whitespace-separated list of tags to be excluded from the process.
	Multiple options can be specified.
	Blacklisted tags take the precedence over whitelisted ones.
--tags-plan
   how tags should be processed. This can be one of these values:
	  visited: process only the tags visited (default)
	  none: do not process any tag
	  all: process all tags
--tags-max-history-lookup
	limit the depth when looking for best matched filtered commit when --tags-plan is 'all'.
	By default this value is 20.
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

You can prefix branch/tag names in both whitelists and blacklists with 'rx:': in this case a regular expression check will be performed.
For instance: --branch-whitelist 'master rx:release\\/\\d+(\\.\\d+)*' will match 'master' and 'release/1.1'
"
	exit 0
}


# Parse the command arguments and exits in case of errors.
#
# Arguments:
#   $@: all the command line parameters
readParameters () {
	WORK_DIRECTORY="$(pwd)/temp"
	BRANCH_WHITELIST=''
	BRANCH_BLACKLIST=''
	TAG_WHITELIST=''
	TAG_BLACKLIST=''
	TAGS_PLAN='visited'
	PROCESS_TAGS_MAXHISTORYLOOKUP=20
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
			--branch-whitelist)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				BRANCH_WHITELIST="${BRANCH_WHITELIST} ${2}"
				shift 2
				;;
			--branch-blacklist)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				BRANCH_BLACKLIST="${BRANCH_BLACKLIST} ${2}"
				shift 2
				;;
			--tag-whitelist)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				TAG_WHITELIST="${TAG_WHITELIST} ${2}"
				shift 2
				;;
			--tag-blacklist)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				TAG_BLACKLIST="${TAG_BLACKLIST} ${2}"
				shift 2
				;;
			--tags-plan)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				case "${2}" in
					'all')
						TAGS_PLAN='all'
						;;
					'visited')
						TAGS_PLAN='visited'
						;;
					'none')
						TAGS_PLAN=''
						;;
					*)
						usage "Invalid value of the ${readParameters_currentArgument} option"
						;;
				esac
				shift 2
				;;
			--tags-max-history-lookup)
				if test $# -lt 2
				then
					usage 'Not enough arguments'
				fi
				PROCESS_TAGS_MAXHISTORYLOOKUP="${BRANCH_BLACKLIST} ${2}"
				if ! test "${PROCESS_TAGS_MAXHISTORYLOOKUP}" -eq "${PROCESS_TAGS_MAXHISTORYLOOKUP}" 2>/dev/null
				then
					usage "Value of ${readParameters_currentArgument} should be numeric"
				fi
				if test "${PROCESS_TAGS_MAXHISTORYLOOKUP}" -lt 1
				then
					usage "Value of ${readParameters_currentArgument} should be greater than 0"
				fi
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
	if test -z "${TAGS_PLAN}"
	then
		if test -n "${TAG_WHITELIST}" -o -n "${TAG_BLACKLIST}"
		then
			die "You can't use --tag-whitelist or --tag-blacklist when you specify '--tags-plan none'"
		fi
	fi
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
	SOURCE_REPOSITORY_URL=$(absolutizePath "${SOURCE_REPOSITORY_URL}")
	FILTER="${2}"
	if test -z "${FILTER}"
	then
		die 'The filter is empty.'
	fi
	checkFilter ${FILTER}
	DESTINATION_REPOSITORY_URL="${3}"
	if test -z "${DESTINATION_REPOSITORY_URL}"
	then
		die 'The destination repository location is empty.'
	fi
	DESTINATION_REPOSITORY_URL=$(absolutizePath "${DESTINATION_REPOSITORY_URL}")
}


# Check if a string is a directory. If so, return its absolute path, otherwise the string itself.
#
# Arguments:
#   $1: the string to be checked
#
# Output:
#   The absolute path (if found), or $1
absolutizePath () {
	if test -d "${1}"
	then
		printf '%s' "$(cd "${1}" && pwd)"
	else
		printf '%s' "${1}"
	fi
}


# Check the contents of the <filter> argument and die in case of errors.
#
# Arguments:
#   $@: all parts of the filter
checkFilter () {
	checkFilter_some=0
	while test $# -ge 1
	do
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


# Check that the system has the required commands, and exit in case of problems.
checkEnvironment () {
	if test -z "${NO_LOCK}"
	then
		if ! command -v flock >/dev/null
		then
			die 'The flock command is not available. You may want to use --no-lock option to avoid using it (but no concurrency check will be performed).'
		fi
	fi
	for checkEnvironment_command in git sed grep md5sum
	do
		if ! command -v "${checkEnvironment_command}" >/dev/null
		then
			die "The required ${checkEnvironment_command} command is not available."
		fi
	done
	checkEnvironment_vMin='2.15.0'
	checkEnvironment_vCur=$(git --version | cut -d ' ' -f3)
	checkEnvironment_vWork=$(printf '%s\n%s' "${checkEnvironment_vCur}" "${checkEnvironment_vMin}" | sort -t '.' -n -k1,1 -k2,2 -k3,3 -k4,4 | head -n 1)
	if test "${checkEnvironment_vWork}" != "${checkEnvironment_vMin}"
	then
		die "This script requires git ${checkEnvironment_vMin} (you have git ${checkEnvironment_vWork})."
	fi
}


# Initialize the working directory and associated variables, and exit in case of problems.
initializeEnvironment () {
	if ! test -d "${WORK_DIRECTORY}"
	then
		mkdir --parents -- "${WORK_DIRECTORY}" || die "Failed to create the working directory ${WORK_DIRECTORY}"
	fi
	WORK_DIRECTORY=$(absolutizePath "${WORK_DIRECTORY}")
	SOURCE_REPOSITORY_DIR=${WORK_DIRECTORY}/source-$(md5 "${SOURCE_REPOSITORY_URL}")
	WORKER_REPOSITORY_DIR=${WORK_DIRECTORY}/worker-$(md5 "${SOURCE_REPOSITORY_URL}${DESTINATION_REPOSITORY_URL}")
}


# Acquire a lock (if allowed by options): we'll return from this function once the lock has been acquired
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


# Create or update the mirror of the source repository.
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


# Store in the SOURCE_BRANCHES variable the list of the branches in the source repository.
# Exit if no branch can be found.
getSourceRepositoryBranches () {
	echo '# Listing source branches'
	# List all branches and takes only the part after "refs/heads/", and store them in the SOURCE_BRANCHES variable
	SOURCE_BRANCHES=$(git -C "${SOURCE_REPOSITORY_DIR}" show-ref --heads | sed -E 's:^.*?refs/heads/::')
	if test -z "${SOURCE_BRANCHES}"
	then
		die 'Failed to retrieve branch list'
	fi
}


# Get the tags that exist in a specific branch of the source repository.
#
# Arguments:
#   $1: the branch name
#
# Output:
#   The list of tags (one per line)
getSourceRepositoryTagsInBranch () {
	git -C "${SOURCE_REPOSITORY_DIR}" tag --list --merged "refs/heads/${1}" 2>/dev/null || true
}


# Get the list of all the tags that exist in a repository.
#
# Arguments:
#   $1: the directory of the repository
#
# Output:
#   The list of tags (one per line)
getTagList () {
	# List all tags and takes only the part after "refs/heads/"
	git -C "${1}" show-ref --tags | sed -E 's:^.*?refs/tags/::' || true
}


# Check if a string is in a white/black list.
#
# Arguments:
#   $1: the string to be checked
#   $2: the white/black list
#
# Return:
#   0 (true): if the string is in the list
#   1 (false): if the string is not in the list
stringInList () {
	for stringInList_listItem in ${2}
	do
		if test -n "${stringInList_listItem}"
		then
			case "${stringInList_listItem}" in
				rx:*)
					stringInList_substring=$(printf '%s' "${stringInList_listItem}" | cut -c4-)
					if printf '%s' "${1}" | grep -Eq "^${stringInList_substring}$"
					then
						return 0
					fi
					;;
				*)
					if test "${1}" = "${stringInList_listItem}"
					then
						return 0
					fi
					;;
			esac
		fi
	done
	return 1
}


# Check if a string satisfies whitelist and blacklist checks.
#
# Arguments:
#   $1: the string to be checked
#   $2: the whitelist
#   $3: the blacklist
#
# Return:
#   0 (true): if the string satisfies the criteria
#   1 (false): if the string does not satisfy the criteria
stringPassesLists () {
	if stringInList "${1}" "${3}"
	then
		return 1
	fi
	if test -z "${2}"
	then
		return 0
	fi
	if stringInList "${1}" "${2}"
	then
		return 0
	fi
	return 1
}


# Store in the WORK_BRANCHES variable the list of the branches to be processed (checking the white/black lists).
# Die if no branch can be found.
getBranchesToProcess () {
	echo '# Determining the branches to be processed'
	WORK_BRANCHES=''
	for getBranchesToProcess_branch in ${SOURCE_BRANCHES}
	do
		if stringPassesLists "${getBranchesToProcess_branch}" "${BRANCH_WHITELIST}" "${BRANCH_BLACKLIST}"
		then
			WORK_BRANCHES="${WORK_BRANCHES} ${getBranchesToProcess_branch}"
		fi
	done
	if test -z "${WORK_BRANCHES}"
	then
		die 'None of the source branches passes the whitelist/blacklist filter'
	fi
}


# Create the worker repository (if it does not already exist)
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


# Process a branch, fetching it from the mirror of the source repository.
# Any relevat tag will also be processed.
#
# Arguments:
#   $1: the name of the branch to work with
processBranch () {
	echo '  - fetching'
	git -C "${WORKER_REPOSITORY_DIR}" fetch --quiet --tags source "${1}"
	echo '  - checking-out'
	git -C "${WORKER_REPOSITORY_DIR}" checkout --quiet --force -B "filter-branch/source/${1}" "remotes/source/${1}"
	echo '  - determining delta'
	processBranch_range="filter-branch/result/${1}"
	processBranch_last=$(git -C "${WORKER_REPOSITORY_DIR}" show-ref -s "refs/heads/filter-branch/filtered/${1}" || true)
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
		rm -f "${WORKER_REPOSITORY_DIR}/.git/refs/filter-branch/originals/${1}/refs/heads/filter-branch/result/${1}"
		git -C "${WORKER_REPOSITORY_DIR}" branch --force "filter-branch/result/${1}" FETCH_HEAD
		rm -rf "${WORKER_REPOSITORY_DIR}.filter-branch"
		echo "  - filtering commits"
		processBranch_tags=''
		if test -z "${TAGS_PLAN}"
		then
			processBranch_tags=''
		else
			processBranch_tags=$(getSourceRepositoryTagsInBranch "${1}")
		fi
		if test -z "${processBranch_tags}"
		then
			processBranch_tagNameFilter=''
		else
			# shellcheck disable=SC2016
			processBranch_tagNameFilter='read -r tag; printf "filter-branch/converted-tags/%s" "${tag}"'
		fi
		rm -rf "${WORKER_REPOSITORY_DIR}.map"
		exec 3>&1
		# shellcheck disable=SC2086
		if processBranch_stdErr=$(git -C "${WORKER_REPOSITORY_DIR}" filter-branch \
			${FILTER} \
			--remap-to-ancestor \
			--tag-name-filter "${processBranch_tagNameFilter}" \
			-d "${WORKER_REPOSITORY_DIR}.filter-branch" \
			--original "refs/filter-branch/originals/${1}" \
			--state-branch "refs/filter-branch/state" \
			--force \
			-- "${processBranch_range}" \
			1>&3 2>&1 | tee /dev/stderr
		)
		then
			processBranch_rc=0
		else
			processBranch_rc=1
		fi
		exec 3>&-
		if test "${processBranch_rc}" -ne 0
		then
			if test -n "${processBranch_stdErr##*Found nothing to rewrite*}"
			then
				die 'git failed'
			fi
		else
			if test "${TAGS_PLAN}" = 'all' -a -n "${processBranch_tags}"
			then
				if ! processBranchTag_availableTags="$(git -C "${WORKER_REPOSITORY_DIR}" tag --list | grep -E '^filter-branch/converted-tags/' | sed -E 's:^filter-branch/converted-tags/::')"
				then
					processBranchTag_availableTags=''
				fi
				for processBranch_tag in ${processBranch_tags}
				do
					if ! itemInList "${processBranch_tag}" "${processBranchTag_availableTags}"
					then
						if stringPassesLists "${processBranch_tag}" "${TAG_WHITELIST}" "${TAG_BLACKLIST}"
						then
							processNotConvertedTag "${processBranch_tag}"
						fi
					fi
				done
			fi
		fi
		echo "  - storing state"
		git -C "${WORKER_REPOSITORY_DIR}" branch -f "filter-branch/filtered/${1}" FETCH_HEAD
	fi
}


# Print the SHA-1 hash of the tag of the work repository (if found).
#
# Arguments:
#   $1: the name of the tag
#
# Output:
#   The SHA-1 of the tag, or nothing if the tag does not exist
getWorkingTagHash () {
	git -C "${WORKER_REPOSITORY_DIR}" rev-list -n 1 "refs/tags/${1}" 2>/dev/null || true
}


# Print the SHA-1 hash of the nearest translated commit corresponding to a specific original commit.
#
# Arguments:
#   $1: the SHA-1 hash of the original commit
#   $2: the allowed history depth
#
# Output:
#   The SHA-1 hash of the translated commit (if it can be found within $2 depth), or nothing otherwise
#
# Return:
#   0 (true): if the translated commit has been found (and printed)
#   1 (false): if the translated commit couldn't be found
getTranslatedNearestCommitHash () {
	if test "${2}" -lt 1 -o -z "${PROCESS_TAGS_VISITEDHASHES##* ${1} *}"
	then
		return 1
	fi
	PROCESS_TAGS_VISITEDHASHES="${PROCESS_TAGS_VISITEDHASHES}${1} "
	if getTranslatedNearestCommitHash_v="$(grep -E "^${1}:" "${WORKER_REPOSITORY_DIR}.map")"
	then
		printf '%s' "${getTranslatedNearestCommitHash_v#${1}:}"
		return 0
	fi
	for getTranslatedNearestCommitHash_v in $(git -C "${WORKER_REPOSITORY_DIR}" rev-list --parents -n 1 "${1}")
	do
		if test "${getTranslatedNearestCommitHash_v}" != "${1}"
		then
			if getTranslatedNearestCommitHash "${getTranslatedNearestCommitHash_v}" "$(( $2 - 1))"
			then
				return 0
			fi
		fi
	done
	return 1
}


# Tries to create a new translated tag, associating it to the nearest translated commit
#
# Arguments:
#   $1: the name of the tag to be translated
processNotConvertedTag () {
	printf '  - remapping tag %s\n' "${1}"
	processNotConvertedTag_tagOriginalHash="$(getWorkingTagHash "${1}")"
	if test -z "${processNotConvertedTag_tagOriginalHash}"
	then
		printf 'Failed to get hash of tag %s\n' "${1}">&2
		exit 1
	fi
	if test ! -f "${WORKER_REPOSITORY_DIR}.map"
	then
		git -C "${WORKER_REPOSITORY_DIR}" show refs/filter-branch/state:filter.map >"${WORKER_REPOSITORY_DIR}.map"
	fi
	PROCESS_TAGS_VISITEDHASHES=' '
	if processNotConvertedTag_commitHash="$(getTranslatedNearestCommitHash "${processNotConvertedTag_tagOriginalHash}" "${PROCESS_TAGS_MAXHISTORYLOOKUP}")"
	then
		printf '%s -> filter-branch/converted-tags/%s (%s -> %s)\n' "${1}" "${1}" "${processNotConvertedTag_tagOriginalHash}" "${processNotConvertedTag_commitHash}"
		git -C "${WORKER_REPOSITORY_DIR}" tag --force "filter-branch/converted-tags/${1}" "${processNotConvertedTag_commitHash}"
	else
		printf 'Failed to map tag %s\n' "${1}">&2
	fi
}


# Process all the branches listed in the WORK_BRANCHES variable, and push the result to the destination repository.
processBranches () {
	processBranches_pushRefSpec=''
	for processBranches_branch in ${WORK_BRANCHES}
	do
		echo "# Processing branch ${processBranches_branch}"
		processBranch "${processBranches_branch}"
		processBranches_pushRefSpec="${processBranches_pushRefSpec} filter-branch/result/${processBranches_branch}:${processBranches_branch}"
	done
	if test -n "${TAGS_PLAN}"
	then
		echo '# Listing source tags'
		processBranches_sourceTags=$(getTagList "${SOURCE_REPOSITORY_DIR}")
		echo '# Determining destination tags'
		for processBranches_sourceTag in ${processBranches_sourceTags}
		do
			if stringPassesLists "${processBranches_sourceTag}" "${TAG_WHITELIST}" "${TAG_BLACKLIST}"
			then
				processBranches_rewrittenTag="filter-branch/converted-tags/${processBranches_sourceTag}"
				if git -C "${WORKER_REPOSITORY_DIR}" rev-list --max-count=0 "${processBranches_rewrittenTag}" 2>/dev/null
				then
					processBranches_pushRefSpec="${processBranches_pushRefSpec} ${processBranches_rewrittenTag}:${processBranches_sourceTag}"
				fi
			fi
		done
	fi
	echo "# Pushing to destination repository"
	# shellcheck disable=SC2086
	git -C "${WORKER_REPOSITORY_DIR}" push --quiet --force ${ATOMIC} destination ${processBranches_pushRefSpec}
}


# Calculate the MD5 hash of a string.
#
# Arguments:
#   $1: the string for which you want the MD5 hash
#
# Output:
#   The MD5-1 hash of $1
md5 () {
	printf '%s' "${1}" | md5sum | sed -E 's: .*$::'
}


# Check if a string is in a list (separated by spaces, tabs or new lines)
#
# Arguments:
#   $1: the string
#   $2: the list of strings
#
# Return:
#   0 (true): $1 is in $2
#   1 (false): $1 is not in $2
itemInList () {
	for itemInList_item in ${2}
	do
		if test "${1}" = "${itemInList_item}"
		then
			return 0
		fi
	done
	return 1
}


readParameters "$@"
checkEnvironment
initializeEnvironment
acquireLock
prepareLocalSourceRepository
getSourceRepositoryBranches
getBranchesToProcess
prepareWorkerRepository
processBranches
echo "All done."

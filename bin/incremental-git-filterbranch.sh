#!/usr/bin/env bash
#
# ### AUTHORS ###
#
# - Michele Locati <michele@locati.it>
#
#
# ### LICENSE ###
#
# MIT - https://github.com/mlocati/incremental-git-filter-branch/blob/master/LICENSE
#
#
# ### CONFIGURATION ###
#
# The source repository
SOURCE_REPOSITORY_URL=https://github.com/mlocati/incremental-git-filter-branch.git
# The destination repository
DESTINATION_REPOSITORY_URL=git@github.com:your/repository.git
# The filter to be applied
FILTER='--subdirectory-filter bin'
# The path to a local directory where we'll process the repositories
WORK_DIRECTORY="$(pwd)/temp"
# A space-separated list of branches to limit filtering to
BRANCH_WHITELIST=''
# A space-separated list of branches not to be parsed
BRANCH_BLACKLIST=''
#


# Exit immediately if a pipeline, a list, or a compound command, exits with a non-zero status.
set -o errexit
# Any trap on ERR is inherited by shell functions, command substitutions, and commands executed in a subshell environment.
set -o errtrace
# The return value of a pipeline is the value of the last (rightmost) command to exit with a non-zero status, or zero if all commands in the pipeline exit successfully
set -o pipefail
# Treat unset variables and parameters other than the special parameters "@" and "*" as an error when performing parameter expansion.
set -o nounset

function setupEnvironment {
	echo '# Setting up environment'
	if [[ -z "${SOURCE_REPOSITORY_URL-}" ]]; then
		echo 'Missing variable: SOURCE_REPOSITORY_URL' >&2
		exit 1
	fi
	if [[ -z "${DESTINATION_REPOSITORY_URL-}" ]]; then
		echo 'Missing variable: DESTINATION_REPOSITORY_URL' >&2
		exit 1
	fi
	if [[ -z "${FILTER-}" ]]; then
		echo 'Missing variable: FILTER' >&2
		exit 1
	fi
	if [[ -z "${WORK_DIRECTORY-}" ]]; then
		echo 'Missing variable: WORK_DIRECTORY' >&2
		exit 1
	fi
	if [[ -z "${BRANCH_WHITELIST-}" ]]; then
		BRANCH_WHITELIST=''
	else
		BRANCH_WHITELIST=$(printf "${BRANCH_WHITELIST}" | sed -r 's:[ \t\r\n]+: :g')
		BRANCH_WHITELIST=$(trim "${BRANCH_WHITELIST}")
		if [[ -n "${BRANCH_WHITELIST-}" ]]; then
			BRANCH_WHITELIST=" ${BRANCH_WHITELIST} "
		fi
	fi
	if [[ -z "${BRANCH_BLACKLIST-}" ]]; then
		BRANCH_BLACKLIST=''
	else
		BRANCH_BLACKLIST=$(printf "${BRANCH_BLACKLIST}" | sed -r 's:[ \t\r\n]+: :g')
		BRANCH_BLACKLIST=$(trim "${BRANCH_BLACKLIST}")
		if [[ -n "${BRANCH_BLACKLIST-}" ]]; then
			BRANCH_BLACKLIST=" ${BRANCH_BLACKLIST} "
		fi
	fi
	if [[ -n ${BRANCH_WHITELIST} ]] && [[ -n ${BRANCH_BLACKLIST} ]]; then
		echo 'You can not specify BRANCH_WHITELIST and BRANCH_BLACKLIST variables' >&2
		exit 1
	fi
	SOURCE_REPOSITORY_DIR=${WORK_DIRECTORY}/source-$(md5 "${SOURCE_REPOSITORY_URL}")
	WORKER_REPOSITORY_DIR=${WORK_DIRECTORY}/worker-$(md5 "${SOURCE_REPOSITORY_URL}${DESTINATION_REPOSITORY_URL}")
	mkdir --parents --mode=0770 -- "${WORK_DIRECTORY}"
}

function acquireLock {
	echo '# Checking concurrency'
	local LOCK_FILE=${WORKER_REPOSITORY_DIR}.lock
	local WAITLOCK=1
	local TIMEOUT=3
	exec 9>"${LOCK_FILE}"
	while :; do
		flock --exclusive --timeout ${TIMEOUT} 9 && WAITLOCK=0 || true
		if [[ ${WAITLOCK} -eq 0 ]]; then
			break;
		fi
		echo '... still waiting...'
	done
}

function prepareLocalSourceRepository {
	local CREATE_MIRROR=1
	if [[ -f "${SOURCE_REPOSITORY_DIR}/config" ]]; then
		echo '# Updating source repository'
		git -C "${SOURCE_REPOSITORY_DIR}" remote update --prune && CREATE_MIRROR=0 || true
	fi
	if [[ ${CREATE_MIRROR} -eq 1 ]]; then
		echo '# Cloning source repository'
		rm -rf "${SOURCE_REPOSITORY_DIR}"
		git clone --mirror "${SOURCE_REPOSITORY_URL}" "${SOURCE_REPOSITORY_DIR}"
	fi
}

function getSourceRepositoryBranches {
	echo '# Listing source branches'
	# List all branches and takes only the part after "refs/heads/", and store them in the SOURCE_BRANCHES variable
	SOURCE_BRANCHES=$(git -C "${SOURCE_REPOSITORY_DIR}" show-ref --heads | sed -r 's:^.*?refs/heads/::')
	if [[ -z "${SOURCE_BRANCHES}" ]]; then
		echo 'Failed to retrieve branch list' >&2
		exit 1
	fi
	if [[ -n ${BRANCH_WHITELIST} ]]; then
		local SOURCE_BRANCH
		local MISSING_BRANCHES="${BRANCH_WHITELIST}"
		for SOURCE_BRANCH in ${SOURCE_BRANCHES} ; do
			MISSING_BRANCHES=$(printf "${MISSING_BRANCHES}" | sed -r "s: ${SOURCE_BRANCH} : :g")
		done
		MISSING_BRANCHES=$(trim "${MISSING_BRANCHES}")
		if [[ -n ${MISSING_BRANCHES} ]]; then
			printf "These branches specified in BRANCH_WHITELIST were not found in the source repository:\n${MISSING_BRANCHES}\n" >&2
		fi
	fi
}

function getSourceRepositoryTags {
	echo '# Listing source tags'
	# List all tags and takes only the part after "refs/tags/", and store them in the SOURCE_TAGS variable
	SOURCE_TAGS=$(git -C "${SOURCE_REPOSITORY_DIR}" show-ref --tags | sed -r 's:^.*?refs/tags/::')
}

function prepareWorkerRepository {
	local NEW_CLONE=1
	if [[ -f "${WORKER_REPOSITORY_DIR}/.git/config" ]]; then
		echo '# Checking working repository'
		git -C "${WORKER_REPOSITORY_DIR}" fsck --no-dangling --connectivity-only && NEW_CLONE=0 || true
	fi
	if [[ ${NEW_CLONE} -eq 1 ]]; then
		echo '# Creating working repository'
		rm -rf "${WORKER_REPOSITORY_DIR}"
		echo '# Adding destination to working repository'
		(
			git clone --no-hardlinks --local --origin source "${SOURCE_REPOSITORY_DIR}" "${WORKER_REPOSITORY_DIR}" && \
			git -C "${WORKER_REPOSITORY_DIR}" remote add destination "${DESTINATION_REPOSITORY_URL}" && \
			git -C "${WORKER_REPOSITORY_DIR}" fetch --prune destination \
		) || (rm -rf "${WORKER_REPOSITORY_DIR}" && false)
	fi
}

function shouldSkipBranch {
	local BRANCH="${1}"
	local RESULT=''
	if [[ -n "${BRANCH_WHITELIST}" ]]; then
		if [[ " ${BRANCH_WHITELIST} " != *" ${BRANCH} "* ]]; then
			RESULT='not in whitelist'
		fi
	elif [[ " ${BRANCH_BLACKLIST} " = *" ${BRANCH} "* ]]; then
		RESULT='in blacklist'
	fi
	printf "${RESULT}"
}

function processBranch {
	local BRANCH="${1}"
	local NOT_UPDATED=1
	echo '  - fetch'
	git -C "${WORKER_REPOSITORY_DIR}" fetch --quiet --tags source "${BRANCH}"
	echo '  - checkout'
	git -C "${WORKER_REPOSITORY_DIR}" checkout --quiet --force -B "filter-branch/source/${BRANCH}" "remotes/source/${BRANCH}"
	echo '  - determining delta'
	local RANGE="filter-branch/result/${BRANCH}"
	local LAST=$(git -C "${WORKER_REPOSITORY_DIR}" show-ref -s "refs/heads/filter-branch/filtered/${BRANCH}" || true)
	if [[ -n "${LAST}" ]]; then
		RANGE="${LAST}..${RANGE}"
	fi
	local FETCH_HEAD=$(git -C "${WORKER_REPOSITORY_DIR}" rev-parse FETCH_HEAD)
	if [[ "${LAST}" = "${FETCH_HEAD}" ]]; then
		echo '  - nothing new, skipping'
	else
		echo '  - initializing filter'
		rm -f "${WORKER_REPOSITORY_DIR}/.git/refs/filter-branch/originals/${BRANCH}/refs/heads/filter-branch/result/${BRANCH}"
		git -C "${WORKER_REPOSITORY_DIR}" branch --force "filter-branch/result/${BRANCH}" FETCH_HEAD
		rm -rf "${WORKER_REPOSITORY_DIR}.filter-branch"
		echo "  - filtering commits"
		local FOUND_SOMETHING
		git -C "${WORKER_REPOSITORY_DIR}" filter-branch \
			${FILTER} \
			--tag-name-filter cat \
			--prune-empty \
			-d "${WORKER_REPOSITORY_DIR}.filter-branch" \
			--original "refs/filter-branch/originals/${BRANCH}" \
			--state-branch "refs/filter-branch/states/${BRANCH}" \
			-- ${RANGE} \
			&& FOUND_SOMETHING=1 || FOUND_SOMETHING=0 # May fail with "Found nothing to rewrite"
		echo "  - storing state"
		git -C "${WORKER_REPOSITORY_DIR}" branch -f "filter-branch/filtered/${BRANCH}" FETCH_HEAD
		if [[ ${FOUND_SOMETHING} -eq 1 ]]; then
			NOT_UPDATED=0
		fi
	fi
	return $NOT_UPDATED
}

function processBranches {
	local BRANCH
	local SKIP_REASON
	local PUSH_REFSPEC=''
	for BRANCH in ${SOURCE_BRANCHES} ; do
		echo "# Processing branch ${BRANCH}"
		SKIP_REASON=$(shouldSkipBranch "${BRANCH}")
		if [[ -n "${SKIP_REASON}" ]]; then
			echo "  - not to be processed (${SKIP_REASON})"
		else
			local BRANCH_UPDATED
			processBranch "${BRANCH}" && PUSH_REFSPEC="${PUSH_REFSPEC} filter-branch/result/${BRANCH}:${BRANCH}" || true
		fi
	done
	if [[ -z "${PUSH_REFSPEC}" ]]; then
		echo "# No branch updated"
	else
		echo "# Pushing to destination repository"
		git -C "${WORKER_REPOSITORY_DIR}" push --quiet --force --tags destination ${PUSH_REFSPEC}
	fi
}

function trim {
	local STR="${1}"
	while [[ ${STR} == ' '* ]]; do
		STR="${STR## }"
	done
	while [[ ${STR} == *' ' ]]; do
		STR="${STR%% }"
	done
	printf "${STR}"
}

function md5 {
	printf '%s' "%1" | md5sum | sed -e 's: .*$::'
}

setupEnvironment
acquireLock
prepareLocalSourceRepository
getSourceRepositoryBranches
getSourceRepositoryTags
prepareWorkerRepository
processBranches

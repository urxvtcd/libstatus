#!/usr/bin/env sh

set_foreground_color() (
	# See https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit

	foreground_color_code="${1}"

	# The following line resets all attributes (colors, bold, etc). Comment it
	# out if you're getting weird D's in output. It should mostly work OK, it's
	# there just to be really sure.
	tput sgr 0
	tput setaf "${foreground_color_code}"
)

# Upstream check function result codes:

# The current branch foo tracks a remote branch origin/foo.
UPSTREAM_EXISTS=0

# The current branch doesn't track any remote branch.
UPSTREAM_DOESNT_EXIST=1

# The current branch foo doesn't track any remote branch, but there is a branch
# named origin/foo.
UPSTREAM_UNTRACKED=2

# The current branch foo tracks a remote branch, that is named differently
# than origin/foo. origin/foo doesn't exist.
UPSTREAM_MISTRACKED=3

# The current branch foo tracks a remote branch, that is named differently
# than origin/foo, and additionally origin/foo exists.
UPSTREAM_MISTRACKED_EXISTS=4

# supercharged git log format string
FORMAT_STR=                               # set variable to empty string
FORMAT_STR="${FORMAT_STR}%C(reset)"       # reset color setting
FORMAT_STR="${FORMAT_STR}%s"              # commit message subject
FORMAT_STR="${FORMAT_STR}%n"              # newline
FORMAT_STR="${FORMAT_STR}%C(brightblack)" # set color to gray
FORMAT_STR="${FORMAT_STR}%h "             # abbreviated commit hash
FORMAT_STR="${FORMAT_STR}%an "            # author name
FORMAT_STR="${FORMAT_STR}%cr"             # relative commit date
FORMAT_STR="${FORMAT_STR}%C(auto)"        # set color to auto
FORMAT_STR="${FORMAT_STR}% D"             # branches and tags pointing to this commit
FORMAT_STR="${FORMAT_STR}%C(reset)"       # reset color setting

STASH_FORMAT_STR=                                     # set to empty
STASH_FORMAT_STR="${STASH_FORMAT_STR}%s "             # subject
STASH_FORMAT_STR="${STASH_FORMAT_STR}%C(brightblack)" # set color to gray
STASH_FORMAT_STR="${STASH_FORMAT_STR}%cr"             # relative creation date
STASH_FORMAT_STR="${STASH_FORMAT_STR}%C(reset)"       # reset color setting

# The number of commits printed by git log graphs. Export a different value to override.
GRAPH_LENGTH_LIMIT="${GRAPH_LENGTH_LIMIT:-10}"

init() {
	# Initialization function. The rest of the code will assume it was run.

	# Enable ANSI color escape sequences if stdout is a terminal, or if user forces
	# color with 'git -c color.ui=always'.
	if git config --get-colorbool color.ui; then
		COLOR=always
		RED="$(set_foreground_color 1)"
		GREEN="$(set_foreground_color 2)"
		YELLOW="$(set_foreground_color 3)"
		BLUE="$(set_foreground_color 4)"
		PURPLE="$(set_foreground_color 5)"
		TEAL="$(set_foreground_color 6)"
		GRAY="$(set_foreground_color 8)" # bright black to be exact
		WHITE="$(set_foreground_color 15)"

		COLOR_LOCAL_BRANCH="$(git config --get color.decorate.branch)"
		if test -z "${COLOR_LOCAL_BRANCH}"; then
			COLOR_LOCAL_BRANCH="${GREEN}"
		fi

		COLOR_REMOTE_BRANCH="$(git config --get color.decorate.remoteBranch)"
		if test -z "${COLOR_REMOTE_BRANCH}"; then
			COLOR_REMOTE_BRANCH="${RED}"
		fi

		COLOR_STASH="$(git config --get color.decorate.stash)"
		if test -z "${COLOR_STASH}"; then
			COLOR_STASH="${PURPLE}"
		fi

		COLOR_HEAD="$(git config --get color.decorate.HEAD)"
		if test -z "${COLOR_HEAD}"; then
			COLOR_HEAD="${TEAL}"
		fi

		COLOR_ADVICE="$(git config --get color.advice.hint)"
		if test -z "${COLOR_ADVICE}"; then
			COLOR_ADVICE="${YELLOW}"
		fi

	else
		COLOR=never
		RED=""
		GREEN=""
		YELLOW=""
		BLUE=""
		PURPLE=""
		TEAL=""
		GRAY=""
		WHITE=""

		COLOR_LOCAL_BRANCH=
		COLOR_REMOTE_BRANCH=
		COLOR_STASH=
		COLOR_HEAD=
		COLOR_ADVICE=
	fi

	# Seeing this variable, git will not try to use less to page the output of
	# some commands when it gets too long to fit on the screen.
	export GIT_PAGER=

	# These would get called many times, so let's just save them to globals.

	if test -z "${REMOTE}"; then
		REMOTE="$(get_remote)"
	fi

	CURRENT="$(git branch --show-current)"
	EXPECTED_UPSTREAM="${REMOTE:-origin}/${CURRENT}"

	upstream_check_result_file="$(mktemp)"
	get_upstream >"${upstream_check_result_file}"
	read -r UPSTREAM_CHECK_RESULT UPSTREAM <"${upstream_check_result_file}"
	rm "${upstream_check_result_file}"

	readonly REMOTE CURRENT EXPECTED_UPSTREAM UPSTREAM_CHECK_RESULT UPSTREAM
}

get_remote() (
	# Guess the remote to be used by other functions.

	number_of_remotes="$(git remote | wc -l)"

	case "${number_of_remotes}" in
	"0")
		# No remotes, nothing to return.
		;;
	"1")
		# If there's only a single remote, use that.
		git remote
		;;
	*)
		# If there are many, return origin if it's among them,
		# otherwise nothing.
		if git remote | grep -qx origin; then
			echo origin
		fi
		;;
	esac
)

pretty_log() (
	git -c color.ui="${COLOR}" log --graph --format="${FORMAT_STR}" "$@"
)

is_head_a_commit() (
	# Check whether the HEAD points to a commit. This is not a case when we are
	# about to make a root commit. The check is useful to avoid errors in
	# output from other commands.
	# In particular git reflog will return an error when about to make a root
	# commit, even if other root commits exist. This might happen when running
	#   git checkout --orphan
	# this probably is a small bug in git.

	git rev-parse --verify --quiet @ >/dev/null 2>/dev/null
)

is_head_detached() {
	test -z "${CURRENT}"
}

print_tree_status() (
	# Prints status of the files in the working directory using
	# `git status --short` format.

	tree_status="$(git -c color.status="${COLOR}" status --short)"

	if test -z "${tree_status}"; then
		return
	fi

	printf "## %sworking tree status%s\n" "${YELLOW}" "${WHITE}"
	printf "%s\n\n" "${tree_status}"
)

print_current_and_upstream() (
	# Prints graph of commits on both local and remote versions of the current
	# branch. Unless head is detached, it always prints something: local and
	# tracking branch names, even if there are no commits to show on graph.

	if is_head_detached; then
		return
	fi

	printf "## %s..." "${COLOR_LOCAL_BRANCH}${CURRENT}${WHITE}"

	case "${UPSTREAM_CHECK_RESULT}" in
	"${UPSTREAM_EXISTS}")
		divergence="$(print_divergence @ "${UPSTREAM}")"
		printf "%s %s\n" "${COLOR_REMOTE_BRANCH}${UPSTREAM}${WHITE}" "${divergence}"
		;;
	"${UPSTREAM_DOESNT_EXIST}")
		if test -z "${REMOTE}"; then
			printf "%s(no upstream; no remote)%s\n\n" "${GRAY}" "${WHITE}"
		else
			printf "%s(no upstream)%s\n\n" "${GRAY}" "${WHITE}"
		fi
		return
		;;
	"${UPSTREAM_UNTRACKED}")
		divergence="$(print_divergence @ "${UPSTREAM}")"
		printf "%s %s\n" "${GRAY}${UPSTREAM}${WHITE}" "${divergence}"
		;;
	"${UPSTREAM_MISTRACKED}")
		printf "%s(upstream mistracked)%s\n" "${YELLOW}" "${WHITE}"
		;;
	"${UPSTREAM_MISTRACKED_EXISTS}")
		divergence="$(print_divergence @ "${UPSTREAM}")"
		printf "%s %s\n" "${GRAY}${UPSTREAM}${WHITE}" "${divergence}"
		;;
	*)
		printf "## Got unexpected get_upstream() result: %s\n\n" "${UPSTREAM_CHECK_RESULT}"
		return
		;;
	esac

	pretty_log --left-right --boundary -"${GRAPH_LENGTH_LIMIT}" "...${UPSTREAM}"
	echo
)

print_current_and_target() (
	# Prints graph of commits on both the current branch and the branch we'll
	# (probably) be merged to. If target is not explicitly given as an
	# argument, remote/HEAD will be used.

	target="${1}"

	if ! is_head_a_commit; then
		return
	fi

	if is_head_detached; then
		# TODO: maybe not necessary; might be useful in rebase?
		return
	fi

	if test -z "${target}"; then
		if test -z "${REMOTE}"; then
			# No remotes in this repository, so no remote/HEAD to try. We could
			# try local master, develop, or main, but that seems too clever.
			return
		fi

		target_ref_file="$(git rev-parse --git-path refs/remotes/"${REMOTE}"/HEAD)"
		if ! test -e "${target_ref_file}"; then
			printf "%s" "${COLOR_ADVICE}"
			printf "hint: file %s not found.\n" "${target_ref_file}"
			printf "hint: This file is used to guess the branch on a remote repository this branch will\n"
			printf "hint: be merged to. The file can be missing if the remote was added to the repository\n"
			printf "hint: that already existed locally, as opposed to creating a local repository by\n"
			printf "hint: cloning from a remote. If the main branch of the remote is called master, you\n"
			printf "hint: can fix the issue by running this command:\n"
			printf "hint:   echo 'ref: refs/remotes/%s/master' > .git/refs/remotes/%s/HEAD\n" "${REMOTE}" "${REMOTE}"
			printf "hint: This is merely a hindrance to libstatus merge target guessing. It doesn't\n"
			printf "hint: impact any other git operations.\n"
			printf "%s\n" "${WHITE}"
			return
		fi
		target=$(sed -e "s|ref: refs/remotes/||" "${target_ref_file}")

		if test "${target}" = "${UPSTREAM}"; then
			# Don't print anything if the default target was used and it's the
			# same as current branch's upstream. It's not our target then.
			return
		fi
	fi

	if test -z "${target}"; then
		# Target not supplied by user, and not found on our own.
		return
	fi

	divergence="$(print_divergence @ "${target}")"
	printf \
		"## %s...%s %s\n" \
		"${COLOR_LOCAL_BRANCH}${CURRENT}${WHITE}" \
		"${COLOR_REMOTE_BRANCH}${target}${WHITE}" \
		"${divergence}"
	pretty_log --left-right --boundary -"${GRAPH_LENGTH_LIMIT}" "@...${target}"
	echo
)

print_divergence() (
	# Pretty-prints a string like (2/10) to show how much far ahead two
	# branches are relative to their last common ancestor.

	left="$1"
	right="$2"
	left_color="${3:-${COLOR_LOCAL_BRANCH}}"
	right_color="${4:-${COLOR_REMOTE_BRANCH}}"

	tmp="$(mktemp)"
	git rev-list --count --left-right "${left}"..."${right}" >"${tmp}"
	read -r left_ahead right_ahead <"${tmp}"

	printf \
		"(%s/%s)" \
		"${left_color}${left_ahead}${WHITE}" \
		"${right_color}${right_ahead}${WHITE}"
)

print_stash() (
	counter="0"

	if ! git rev-parse --verify --quiet "stash@{${counter}}" >/dev/null; then
		return
	fi

	printf "## %sstashes%s\n" "${YELLOW}" "${WHITE}"

	while git rev-parse --verify --quiet "stash@{${counter}}" >/dev/null; do
		git show \
			--no-patch \
			--format="${COLOR_STASH}${counter}${WHITE}: ${STASH_FORMAT_STR}" \
			"stash@{${counter}}"
		print_numstat "stash@{${counter}}"
		counter=$((counter + 1))
	done

	echo
)

print_numstat() (
	# Pretty-print a file listing for given reference in a style of numstat
	# (see git show --numstat).

	reference="${1}"

	git show --format="" --numstat "${reference}" \
		| while IFS=$(printf '\t') read -r added deleted path; do
			printf \
				"%s%4s %s%4s %s\n" \
				"${GREEN}" \
				"${added}" \
				"${RED}" \
				"${deleted}" \
				"${GRAY}${path}${WHITE}"
		done
)

print_worktree_list() (
	worktree_path="$(git rev-parse --git-path worktrees)"
	if test ! -e "${worktree_path}"; then
		# No worktrees.
		return
	fi

	printf "## %sworktree list%s\n" "${YELLOW}" "${WHITE}"
	git worktree list | sed -e "s|${HOME}|~|" -e "s|\[\(.*\)\]|[${BLUE}\1${WHITE}]|"
	echo
)

are_there_submodules() (
	if ! is_head_a_commit; then
		return
	fi

	git ls-tree -r @ | grep -q " commit "
)

print_submodule_status() (
	status=$(git submodule status | grep -v "^ ")

	if test -n "${status}"; then
		printf "## %ssubmodule status%s\n" "${YELLOW}" "${WHITE}"
		printf "%s\n\n" "${status}" \
			| sed \
				-e "s/^+\(.......\)[^ ]*/[mismatch] \1/" \
				-e "s/^-\(.......\)[^ ]*/[not-init] \1/" \
				-e "s/^U\(.......\)[^ ]*/[conflict] \1/"
	else
		return
	fi
)

print_submodule_summary() (
	summary="$(git submodule summary)"

	if test -n "${summary}"; then
		printf "## %ssubmodule summary%s\n" "${YELLOW}" "${WHITE}"
		printf "%s\n\n" "${summary}" \
			| sed -e "s|^.*<.*$|${RED}&${WHITE}|g" \
			| sed -e "s|^.*>.*$|${GREEN}&${WHITE}|g"
	else
		return
	fi
)

there_is_rebase_in_progress() (
	rebase_merge_dir="$(git rev-parse --git-path rebase-merge)"
	rebase_apply_dir="$(git rev-parse --git-path rebase-apply)"

	test -d "${rebase_merge_dir}" || test -d "${rebase_apply_dir}"
)

there_are_conflicts() (
	number_of_conflicting_files="$(git ls-files --unmerged | wc -l)"
	test "${number_of_conflicting_files}" != 0
)

print_rebase_summary() (
	if ! there_is_rebase_in_progress; then
		return
	fi

	current_marker="→"
	if there_are_conflicts; then
		current_marker="✗"
	fi

	printf "## %srebase summary%s\n" "${YELLOW}" "${WHITE}"

	rebase_dir="$(git rev-parse --git-path rebase-merge)"

	print_rebase_entries "${GREEN}" <"${rebase_dir}/done" \
		| sed -ne '$! s/^/ ✓ /p'
	print_rebase_entries "${YELLOW}" <"${rebase_dir}/done" \
		| sed -ne "$ s/^/ ${current_marker} /p"
	print_rebase_entries "${GRAY}" <"${rebase_dir}/git-rebase-todo" \
		| sed -e 's/^/ · /'

	echo
)

print_rebase_entries() (
	# Pretty-print commit entries found in git's rebase directory files.

	cmd_color="$1"

	while read -r cmd hash msg; do
		printf "%s %.7s %s\n" "${cmd_color}${cmd}${TEAL}" "${hash}" "${WHITE}${msg}"
	done
)

print_untracked_hint() (
	if test "${UPSTREAM_CHECK_RESULT}" = "${UPSTREAM_UNTRACKED}"; then
		printf "%s" "${COLOR_ADVICE}"
		printf "hint: %s branch exists, but isn't marked as upstream.\n" "${UPSTREAM}"
		printf "hint: It is recommended to run:\n"
		printf "hint:\n"
		printf "hint:   git branch --set-upstream-to %s\n" "${UPSTREAM}"
		printf "hint:\n"
		printf "hint: So you can run shorter versions of commands:\n"
		printf "hint:\n"
		printf "hint:   git push %s <branch>   → git push\n" "${REMOTE}"
		printf "hint:   git rebase %s/<branch> → git rebase\n" "${REMOTE}"
		printf "hint:   git merge %s/<branch>  → git merge\n" "${REMOTE}"
		printf "%s\n" "${WHITE}"
	fi
)

print_intent_to_add_hint() (
	if ! is_head_a_commit; then
		return
	fi

	if ! git rev-parse --verify --quiet "@{1}" >/dev/null; then
		# Quit if there was no previous HEAD. In particular, newly created
		# worktrees have reset in their last reflog entry, but @{1} is not
		# defined.
		return
	fi

	if ! git reflog show -1 --format="%gs" | grep -q "^reset: "; then
		# Quit if the last reflog entry isn't a reset.
		return
	fi

	untracked_now="$(mktemp)"
	git ls-files --other --exclude-standard | sort >"${untracked_now}"

	tracked_previousy="$(mktemp)"
	git ls-tree --name-only "@{1}" | sort >"${tracked_previousy}"

	lost_files="$(comm -12 "${untracked_now}" "${tracked_previousy}")"

	rm "${untracked_now}" "${tracked_previousy}"

	if test -n "${lost_files}"; then
		printf "%s" "${COLOR_ADVICE}"
		printf "hint: Your last reset moved HEAD from a revision that tracked these paths:\n"
		# shellcheck disable=SC2001
		printf "%s\n" "${lost_files}" | sed -e "s/^/hint:    /"
		printf "hint: to a revision that doesn't. If you wish to keep tracking them, run\n"
		printf "hint:     git add [<path>...]\n"
		printf "hint: You can avoid this issue by adding --intent-to-add or -N flag to your\n"
		printf "hint: reset invocations.\n"
		printf "%s\n" "${WHITE}"
	fi
)

get_upstream() (
	if test -z "${REMOTE}"; then
		echo "${UPSTREAM_DOESNT_EXIST}"
		return
	fi

	expected_upstream_exists=false
	if git rev-parse --abbrev-ref "${EXPECTED_UPSTREAM}" >/dev/null 2>/dev/null; then
		expected_upstream_exists=true
	fi

	if upstream="$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null)"; then
		if test "${upstream}" != "${EXPECTED_UPSTREAM}"; then
			if test "${expected_upstream_exists}" = true; then
				echo "${UPSTREAM_MISTRACKED_EXISTS}" "${EXPECTED_UPSTREAM}"
				return
			fi
			echo "${UPSTREAM_MISTRACKED}" "${upstream}"
			return
		fi

		echo "${UPSTREAM_EXISTS}" "${upstream}"
		return
	fi

	if test "${expected_upstream_exists}" = true; then
		echo "${UPSTREAM_UNTRACKED}" "${EXPECTED_UPSTREAM}"
		return
	fi

	echo "${UPSTREAM_DOESNT_EXIST}"
)

print_mistracking_hint() {
	if test "${UPSTREAM_CHECK_RESULT}" = "${UPSTREAM_MISTRACKED}"; then
		upstream="$(git rev-parse --abbrev-ref '@{upstream}')"
		printf "%s" "${COLOR_ADVICE}"
		printf "hint: current '%s' branch tracks '%s', and probably shouldn't.\n" "${CURRENT}" "${upstream}"
		printf "hint: you probably should remove the tracking with the following command:\n"
		printf "hint:   git branch --unset-upstream\n"
		printf "hint: or create a matching branch on a remote and track it:\n"
		printf "hint:   git push --set-upstream %s %s" "${REMOTE}" "${EXPECTED_UPSTREAM}"
		printf "%s\n\n" "${WHITE}"

	elif test "${UPSTREAM_CHECK_RESULT}" = "${UPSTREAM_MISTRACKED_EXISTS}"; then
		upstream="$(git rev-parse --abbrev-ref '@{upstream}')"
		printf "%s" "${COLOR_ADVICE}"
		printf "hint: current '%s' branch tracks '%s',\n" "${CURRENT}" "${upstream}"
		printf "hint: but probably should track '%s' instead.\n" "${EXPECTED_UPSTREAM}"
		printf "hint: run this command to fix this:\n"
		printf "hint:   git branch --set-upstream-to %s" "${EXPECTED_UPSTREAM}"
		printf "%s\n\n" "${WHITE}"
	fi
}

print_rebase_lost_merges_hint() (
	if ! is_head_a_commit; then
		return
	fi

	if ! git reflog -1 | grep -q "rebase (finish)"; then
		# The hint applies only if the last reflog entry is an end of a rebase.
		return
	fi

	old_tip="$(git reflog | sed -ne '/rebase (start)/ {n;s/ .*//;p;q}')"
	new_tip="@"
	new_base=$(git reflog | sed -ne "/rebase (start)/ {s/ .*//;p;q}")

	merges_old="$(git log --oneline --merges "${new_base}..${old_tip}" | wc -l)"
	merges_new="$(git log --oneline --merges "${new_base}..${new_tip}" | wc -l)"

	if test "${merges_new}" = 0 && test "${merges_old}" != 0; then
		printf "%s" "${COLOR_ADVICE}"
		printf "hint: the branch before the rebase contained these merge commits:\n"
		git log --oneline --merges "${new_base}..${old_tip}" | sed -e "s/^/hint:   /"
		printf "hint: but the branch after the rebase contains no merge commits. this might be\n"
		printf "hint: intentional, but can also mean that merge commits were lost during the\n"
		printf "hint: rebase because you didn't pass the --rebase-merges flag. if this was not\n"
		printf "hint: intentional, you can run\n"
		printf "hint:   git reset --hard ORIG_HEAD\n"
		printf "hint: to reset the branch to the state before the rebase, and attempt the rebase\n"
		printf "hint: again.\n"
		printf "hint: If this was intentional and you wish this hint went away,\n"
		printf "hint: perform a git commit --amend or a no-op git reset."
		printf "%s\n\n" "${WHITE}"
	fi
)

max_line_length() (
	# Prints the length of the longest line in a file.

	sed \
		-e "s/\x1B\[[0-9;]*[JKmsu]//g" \
		-e "s/\x1B(B//g" \
		| awk '
			{
				if (max_len < length($0)) {
					max_len = length($0);
				}
			}

			END {
				printf max_len
			}
		'
)

columnize() (
	# Prints files passed as arguments in columns.

	column_widths=""
	for file in "$@"; do
		column_widths="${column_widths} $(max_line_length <"${file}")"
	done

	paste "$@" | awk \
		--field-separator '\t' \
		--assign column_widths="${column_widths}" \
		'
		BEGIN {
			split(column_widths, widths, " ")
		}
		{
			for (i = 1; i <= NF; i++) {
				line_without_colors = $i
				gsub("\x1B[[0-9;]*[JKmsu]", "", line_without_colors);
				gsub("\x1B\\(B", "", line_without_colors);
				length_withouth_colors = length(line_without_colors)

				printf $i
				spaces_fs = sprintf("%%-%ds", widths[i] - length_withouth_colors + 1)
				printf spaces_fs, " "
			}
			printf "\n"
		}
		'
)

errtee() (
	# Pipeline debugging helper.

	while read -r line; do
		echo "${line}"
		echo "${line}" >/dev/stderr
	done
)

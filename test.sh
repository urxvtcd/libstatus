#!/usr/bin/env sh

commit() (
	repo="${1}"
	message="${2}"

	GIT_COMMITTER_DATE="@1 +0000" \
		git \
		-C "${repo}" \
		commit \
		--quiet \
		--allow-empty \
		--date="@0 +0000" \
		--message "${message}"
)

merge() (
	repo="${1}"
	branch="${2}"

	GIT_AUTHOR_DATE="@1 +0000" \
		GIT_COMMITTER_DATE="@1 +0000" \
		git \
		-C "${repo}" \
		merge \
		--no-log \
		--quiet \
		--no-edit \
		"${branch}"
)

new_repo() (
	repo_dir="$(mktemp -d)"

	git -C "${repo_dir}" init --quiet "$@"
	git -C "${repo_dir}" config user.name 'David Plowie'
	git -C "${repo_dir}" config user.email 'dplowie@gritte.rs'

	echo "${repo_dir}"
)

test_after_init() (
	expected="$(
		cat <<-EOF
			## master...(no upstream; no remote)
		EOF
	)"

	repo="$(new_repo)"
	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "%s\n\nwas different from\n\n%s" "${actual}" "${expected}"
		printf "repo: %s\n\n" "${repo}"
	}
)

test_after_first_commit() (
	expected="$(
		cat <<-EOF
			## master...(no upstream; no remote)
		EOF
	)"

	repo="$(new_repo)"
	commit "${repo}" "Initial commit"

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "repo: %s\n\n" "${repo}"
	}
)

test_hint_untracked_upstream() (
	expected="$(
		cat <<-EOF
			## master...origin/master (0/0)

			hint: origin/master branch exists, but isn't marked as upstream.
			hint: It is recommended to run:
			hint:
			hint:   git branch --set-upstream-to origin/master
			hint:
			hint: So you can run shorter versions of commands:
			hint:
			hint:   git push origin <branch>   → git push
			hint:   git rebase origin/<branch> → git rebase
			hint:   git merge origin/<branch>  → git merge
		EOF
	)"

	origin="$(new_repo --bare)"
	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	git -C "${repo}" remote add origin "${origin}"
	git -C "${repo}" push --quiet origin master
	echo 'ref: refs/remotes/origin/master' >"${repo}/.git/refs/remotes/origin/HEAD"

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "origin: %s\nrepo: %s\n\n" "${origin}" "${repo}"
	}
)

test_hint_mistracked_upstream() (
	expected="$(
		cat <<-EOF
			## master...origin/master (0/0)

			hint: current 'master' branch tracks 'origin/other',
			hint: but probably should track 'origin/master' instead.
			hint: run this command to fix this:
			hint:   git branch --set-upstream-to origin/master
		EOF
	)"

	origin="$(new_repo --bare)"
	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	git -C "${repo}" remote add origin "${origin}"
	git -C "${repo}" push --quiet origin master
	git -C "${repo}" push --quiet --set-upstream origin master:other
	echo 'ref: refs/remotes/origin/master' >"${repo}/.git/refs/remotes/origin/HEAD"

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "origin: %s\nrepo: %s\n\n" "${origin}" "${repo}"
	}
)

test_correct_upstream() (
	expected="$(
		cat <<-EOF
			## master...origin/master (0/0)
		EOF
	)"

	origin="$(new_repo --bare)"
	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	git -C "${repo}" remote add origin "${origin}"
	git -C "${repo}" push --quiet --set-upstream origin master
	echo 'ref: refs/remotes/origin/master' >"${repo}/.git/refs/remotes/origin/HEAD"

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "origin: %s\nrepo: %s\n\n" "${origin}" "${repo}"
	}
)

test_ahead_of_upstream() (
	expected="$(
		cat <<-EOF
			## master...origin/master (1/0)
			< Second commit
			| c6193d9 David Plowie 54 years ago HEAD -> master
			o Initial commit
			  6a103bc David Plowie 54 years ago origin/master, origin/HEAD
		EOF
	)"

	origin="$(new_repo --bare)"
	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	git -C "${repo}" remote add origin "${origin}"
	git -C "${repo}" push --quiet --set-upstream origin master
	commit "${repo}" "Second commit"
	echo 'ref: refs/remotes/origin/master' >"${repo}/.git/refs/remotes/origin/HEAD"

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "origin: %s\nrepo: %s\n\n" "${origin}" "${repo}"
	}
)

test_rebase_lost_merges_hint() (
	expected="$(
		cat <<-EOF
			## topic...(no upstream; no remote)

			hint: the branch before the rebase contained these merge commits:
			hint:   853f411 Merge branch 'other' into topic
			hint: but the branch after the rebase contains no merge commits. this might be
			hint: intentional, but can also mean that merge commits were lost during the
			hint: rebase because you didn't pass the --rebase-merges flag. if this was not
			hint: intentional, you can run
			hint:   git reset --hard ORIG_HEAD
			hint: to reset the branch to the state before the rebase, and attempt the rebase
			hint: again.
			hint: If this was intentional and you wish this hint went away,
			hint: perform a git commit --amend or a no-op git reset.
		EOF
	)"

	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	git -C "${repo}" checkout --quiet -b topic
	commit "${repo}" "Second commit"
	git -C "${repo}" checkout --quiet -b other master
	commit "${repo}" "Third commit"
	git -C "${repo}" checkout --quiet -
	merge "${repo}" other

	GIT_AUTHOR_DATE="@1 +0000" \
		GIT_COMMITTER_DATE="@1 +0000" \
		git -C "${repo}" rebase --quiet master

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "repo: %s\n\n" "${repo}"
	}
)

test_intent_to_add_hint() (
	expected="$(
		cat <<-EOF
			## working tree status
			?? some-file

			## master...(no upstream; no remote)

			hint: Your last reset moved HEAD from a revision that tracked these paths:
			hint:    some-file
			hint: to a revision that doesn't. If you wish to keep tracking them, run
			hint:     git add [<path>...]
			hint: You can avoid this issue by adding --intent-to-add or -N flag to your
			hint: reset invocations.
		EOF
	)"

	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	echo some-content >"${repo}/some-file"
	git -C "${repo}" add some-file
	commit "${repo}" "Second commit"
	git -C "${repo}" reset @^

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "repo: %s\n\n" "${repo}"
	}
)

test_rebase_status() (
	expected="$(
		cat <<-EOF
			## rebase summary
			 ✓ pick 6a103bc Initial commit # empty
			 → edit c6193d9 Second commit # empty
			 · pick 4af4e41 Third commit # empty
		EOF
	)"

	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	commit "${repo}" "Second commit"
	commit "${repo}" "Third commit"

	# ed is the standard text editor
	GIT_SEQUENCE_EDITOR="printf '2s/pick/edit/\nw\nq\n' | ed >/dev/null 2>/dev/null" \
		GIT_COMMITTER_DATE="@1 +0000" \
		GIT_AUTHOR_DATE="@1 +0000" \
		git -C "${repo}" rebase -i --root --quiet 2>/dev/null

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "repo: %s\n\n" "${repo}"
	}
)

test_remote_head_file_missing_hint() (
	expected="$(
		cat <<-EOF
			## master...(no upstream)

			hint: file .git/refs/remotes/origin/HEAD not found.
			hint: This file is used to guess the branch on a remote repository this branch will
			hint: be merged to. The file can be missing if the remote was added to the repository
			hint: that already existed locally, as opposed to creating a local repository by
			hint: cloning from a remote. If the main branch of the remote is called master, you
			hint: can fix the issue by running this command:
			hint:   echo 'ref: refs/remotes/origin/master' > .git/refs/remotes/origin/HEAD
			hint: This is merely a hindrance to libstatus merge target guessing. It doesn't
			hint: impact any other git operations.
		EOF
	)"

	origin="$(new_repo --bare)"
	repo="$(new_repo)"
	commit "${repo}" "Initial commit"
	git -C "${repo}" remote add origin "${origin}"

	actual="$(git -C "${repo}" repo-status)"

	test "${actual}" = "${expected}" || {
		printf "\noutput\n\n%s\n\nwas different from\n\n%s\n\n" "${actual}" "${expected}"
		printf "origin: %s\nrepo: %s\n\n" "${origin}" "${repo}"
	}
)

if test -z "${1}"; then
	# Run all the tests.
	sed -ne 's|^\(test_[A-Za-z0-9_]*\).*|\1|p' "${0}" \
		| while read -r testcase; do
			echo "${testcase}" && "${testcase}"
		done
else
	# Run the test given as argument.
	"${1}"
fi

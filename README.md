# libstatus

libstatus is (a toolkit for building) a supercharged, POSIX-compliant
replacement of `git status`.

The functionality is implemented in the `libstatus.sh` file, which serves as
a library intended to be sourced by some other script.

Two example scripts (`git-s` and `git-ss`) using the library are provided. To
use them, you need to make sure they are available in your `$PATH`. Configuring
the `$PATH` variable is out of scope of this README, but there's plenty
information online.

Currently implemented features:
  - working directory status (using `git status --short` condensed output; see `git help status` for more info),
    <img src="./img/working-tree-status.png" alt="Render of working tree status" />
  - graph of commits on your branch and its tracked remote counterpart,
    <img src="./img/current-and-upstream-graph.png" alt="Render of current branch and upstream graph" />
  - graph of commits on your branch and the branch it'll be merged to (using `<remote>/HEAD` to guess, can be overridden),
    <img src="./img/current-and-target-graph.png" alt="Render of current branch and merge target graph" />
  - list of stashes along with listing of their changes,
    <img src="./img/stashes.png" alt="Render of stash list" />
  - worktree summary,
    <img src="./img/worktrees.png" alt="Render of worktree list" />
  - submodule status and summary,
  - rebase progress status,
    <img src="./img/rebase-summary.png" alt="Render of rebase summary" />
  - hints about remote branch tracking, merges lost when rebasing without `--rebase-merges`,
    and about files lost from tracking due to reset without `--intent-to-add`.
    <img src="./img/untracked-hint.png" alt="Render of hint about untracked remote branch" />
    <img src="./img/intent-to-add-hint.png" alt="Render of hint about files lost due to reset" />

perl-git-prompt
===============

Perl script to show current Git branch and changeset status in the prompt.

## Usage

Put the following in your `~/.bashrc`

~~~bash
# Add git status to the existing bash prompt
GIT_PROMPT_PATH="$HOME/github/perl-git-prompt/git-prompt.pl"
if [[ ! "$PS1" =~ "$GIT_PROMPT_PATH" ]]; then
    export PS1="\$($GIT_PROMPT_PATH)"$PS1
fi
~~~

Requires git 2.15 or newer (the script uses `status --porcelain=v2` and
`--no-optional-locks`).

Output:
-------
The prompt looks like `Git Branch: (branch) [position dirty ⇄conflicts]`:

* **(branch)** is the current branch. It turns green when clean, red when
  there are uncommitted changes, and orange during a merge conflict or rebase.
  `DETACHED_HEAD` is shown when HEAD is not on a branch.
* **[+2 -3]** is the position relative to the upstream: `+N` commits ahead
  (cyan) and `-N` commits behind (red). A diverged branch shows both.
* **5** is the count of changed files (staged, unstaged, and untracked).
  Its color shows how much is staged: all staged is green, none staged is
  red, and partly staged is yellow.
* **⇄2** is the number of files with merge conflicts.

Examples:
---------
![Example Prompt](http://www.perturb.org/images/git-prompt-1.png)

* You are on the **vader** branch.
* Your local repo is **+1** commit ahead of the remote
* There are **5** files in the staging area

![Example Prompt](http://www.perturb.org/images/git-prompt-2.png)

* You are on the **vader** branch.
* Your local repo is on the same commit as the remote
* There are no files in the staging area

Options:
--------
* `--json` prints the git status as JSON instead of the prompt, for use in
  scripts.
* `--no-color` disables color.
* `NO_COLOR` (set to any non-empty value) also disables color, following
  [no-color.org](https://no-color.org).

Color is turned off automatically when the output is not a terminal, such
as when it is piped or captured.

Note:
-----
This script assumes you have 256 color terminal support. If you still have
a 16 color terminal no guarantees how this will look.

The prompt is printed on two lines: the branch line, then a line break
before the color reset. This keeps the prompt intact when `$()` strips
trailing newlines.

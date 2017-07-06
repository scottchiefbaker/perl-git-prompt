perl-git-prompt
===============

Perl script to show current Git branch and changeset status in the prompt.

## Usage

Put the following in your `~/.bashrc`

~~~bash
# Add git status to the existing bash prompt
GIT_PROMPT_PATH="$HOME/github/perl-git-prompt/git-prompt.pl"
if [[ -f $GIT_PROMPT_PATH ]] && [[ -z $GIT_PROMPT ]]; then
    export GIT_PROMPT=$GIT_PROMPT_PATH
    export PS1="\$($GIT_PROMPT_PATH)"$PS1
fi
~~~

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

Note:
-----
This script assumes you have 256 color terminal support. It's 2013, you
should have a 256 color terminal. If you still have a 16 color terminal
no guarantees how this will look.

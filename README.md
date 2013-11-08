perl-git-prompt
===============

Git extension to show your git branch and changeset status in your the prompt.

Put the following in your `~/.bashrc`

~~~bash
# Add the git status to the existing bash prompt
export PS1="\$(/dir/to/git-prompt.pl)"$PS1
~~~

Example:
--------
~~~
Git Branch: (master) [+1 5]
bash$ 
~~~

* You are on the **master** branch.
* Your local repo is **+1** commit ahead of the remote
* There are **5** files in the staging area

Note:
-----
This script assumes you have 256 color terminal support. It's 2013, you 
should have a 256 color terminal. If you still have a 16 color terminal
no guarantees how this will look.

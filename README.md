perl-git-prompt
===============

Git extension to show your branch and changeset status in the prompt.

Put the following in your `~/.bashrc`

~~~
# Append my git script to the bash prompt
export PS1="\$(/dir/to/git-prompt.pl)"$PS1
~~~

#!/usr/bin/perl

use strict;
use warnings;
use v5.16;
use Cwd qw(getcwd);
use Encode qw(decode);

binmode(STDOUT, ":utf8");

################################################################
# Git status in your bash prompt
# https://github.com/scottchiefbaker/perl-git-prompt.git
#
# Version 0.2
#
# Put this in your ~/.bashrc to show git status in your prompt:
#
# GIT_PROMPT_PATH="$HOME/github/perl-git-prompt/git-prompt.pl"
# if [[ -f $GIT_PROMPT_PATH ]] && [[ -z $GIT_PROMPT ]]; then
#     export GIT_PROMPT=$GIT_PROMPT_PATH
#     export PS1="\$($GIT_PROMPT_PATH)"$PS1
# fi
################################################################

#      1      2  3   2 4 5 6 4
# Git Branch: (master) [+2 14]

# Color codes found in utils/term-colors.pl
my $PROMPT_COLOR  = color(45);  # Color of the header prompt                     #1
my $PAREN_COLOR   = color(15);  # Color of the parenthesis                       #2
my $DIRTY_COLOR   = color(203); # Color when the branch is dirty                 #3
my $CLEAN_COLOR   = color(83);  # Color when the branch is clean                 #3
my $MERGE_COLOR   = color(214); # Color when the branch has merge conflict       #3
my $BRACE_COLOR   = color(15);  # Color of the file count braces                 #4
my $AHEAD_COLOR   = color(117); # Color when the branch is ahead of the remote   #5
my $BEHIND_COLOR  = color(196); # Color when the branch is behind the remote     #5
my $PENDING_COLOR = color(228); # Color of the uncommitted file count            #6
my $RESET_COLOR   = color();    # Reset the color

###################################################################

# Get the state of git in the current dir
my $i = get_git_info();

# A string of all the args passed in
my $args = argv(@ARGV);

# If the user requests debug dump out the data structure
if ($args->{debug}) {
	kd($i);
}

# If they request JSON spit that out
if ($args->{json}) {
	require JSON::PP;
	# Character-mode encode: encode_json() returns UTF-8 *bytes*, which the
	# :utf8 layer on STDOUT would encode a second time. This returns characters
	# and the layer encodes them exactly once.
	print JSON::PP->new->encode($i) . "\n";
	exit;
}

# If we're on a git enabled dir
if ($i && $i->{'branch'}) {
	print $PROMPT_COLOR . "Git Branch: ";

	my $branch_color = '';
	if ($i->{'merge_conflict'} || $i->{rebasing}) {
		$branch_color = $MERGE_COLOR;
	} elsif ($i->{'dirty'}) {
		$branch_color = $DIRTY_COLOR;
	} else {
		$branch_color = $CLEAN_COLOR;
	}

	# Print out the name of the branch we're currently on
	my $branch_name = $i->{'branch'};
	print $PAREN_COLOR . "(" . $branch_color . $branch_name . $PAREN_COLOR . ") ";

	# If we're ahead/behind of the remote OR there are pending files or conflicts.
	# Conflicts have to be listed here too: unmerged entries do not count toward
	# dirty, and without an upstream there is no position either.
	if ($i->{'position'} || $i->{'dirty'} || $i->{'merge_conflict'}) {
		# Open paren
		print $BRACE_COLOR . "[";

		# Ahead/Behind of the remote server. A diverged branch shows both
		# counts, each in its own color: +2 in the ahead color, -3 in the
		# behind color.
		if ($i->{'position'}) {
			if ($i->{'ahead'}) {
				print $AHEAD_COLOR . "+" . $i->{'ahead'};
			}

			if ($i->{'behind'}) {
				print $BEHIND_COLOR . ($i->{'ahead'} ? " " : "") . "-" . $i->{'behind'};
			}
		}

		# If the repo is dirty AND we're ahead/behind put a space between the numbers
		if ($i->{'dirty'} && $i->{'position'}) {
			print " ";
		}

		# If there are pending files to be committed
		#
		# If none of the files are staged
		if (($i->{'dirty'} >= 1) && ($i->{'staged'} == 0)) {
			print $DIRTY_COLOR;
		# If all the files are staged (and none have further unstaged edits)
		} elsif ($i->{dirty} && ($i->{dirty} == $i->{staged}) && !$i->{unstaged}) {
			print $CLEAN_COLOR;
		# If some of the files are staged (but not all)
		} elsif ($i->{dirty}) {
			print $PENDING_COLOR;
		}

		# Print out the number of dirty files
		if ($i->{dirty}) {
			print $i->{'dirty'};
		}

		if ($i->{merge_conflict}) {
			my $count = $i->{merge_conflict};

			#my $merge_symbol = "\N{ALMOST EQUAL TO}";
			my $merge_symbol = "\x{21C4}";

			# Space it away from any numbers, unless it's alone in the bracket
			my $sep = ($i->{'dirty'} || $i->{'position'}) ? " " : "";

			print $MERGE_COLOR . $sep . $merge_symbol . $count;
		}

		# Close paren
		print $BRACE_COLOR . "]";
	}

	print "\n" . $RESET_COLOR;
}

# Set the foreground color. Each escape is wrapped in \x01/\x02 (readline's
# start/end-of-ignore markers, what bash itself turns \[ and \] into). Our
# output reaches the prompt through $() command substitution in PS1, and bash
# does not re-scan substitution output for prompt escapes, so literal \[ \]
# would print as garbage and STILL miscount the line length. Raw control
# bytes pass through untouched; readline drops them and excludes the escapes
# from its width math, so wrapping and history/backspace stay correct.
sub color {
	my $c = shift;

	# No color given: reset
	if (!defined($c)) {
		return "\x01\e[0m\x02";
	}

	return "\x01\e[0m\x02\x01\e[38;5;${c}m\x02";
}

###################################################

sub get_git_info {
	my $ret = {};
	# Init some variables
	$ret->{staged}   = 0;
	$ret->{unstaged} = 0;
	$ret->{dirty}    = 0;

	# Porcelain v2 is stable and locale independent, unlike human readable status.
	# This single call doubles as the repo check: git status exits nonzero when
	# we're outside a work tree (no repo, or inside .git itself), so we fork git
	# once per prompt instead of separately probing with rev-parse. Stderr is
	# merged into the capture instead of discarded so a REAL failure (git too
	# old, dubious ownership, corrupt index) can be told apart from the ordinary
	# no-repo cases below; on success stderr is empty, so the parse is unaffected.
	my $out = `LC_ALL=C git --no-optional-locks status --porcelain=v2 --branch 2>&1`;

	# Not in a git enabled dir
	if ($? != 0) {
		# Expected "no repo" cases, silent exactly like the old 2>/dev/null
		# check: git couldn't be executed at all (missing binary: $? == -1,
		# or the shell's command-not-found 127), or git's own no-repo /
		# no-work-tree fatal (exit 128).
		return 0 if $? == -1;
		return 0 if ($? >> 8) == 127;
		return 0 if $out =~ /not a git repository|must be run in a work tree/i;

		# Anything else (git too old for --porcelain=v2 / --no-optional-locks,
		# dubious ownership, corrupt index) used to look identical to "no
		# repo" and the prompt silently vanished. Surface git's first error
		# line so the user knows why (first line only: an unknown option
		# dumps a usage screenful).
		my ($err) = split(/\n/, $out);
		$err = "git status failed (exit " . ($? >> 8) . ")" unless defined($err) && length($err);
		warn "git-prompt: $err\n";
		return 0;
	}

	# Git hands us raw bytes (branch names are stored as bytes in the ref, usually
	# UTF-8). Decode once so the :utf8 layer on STDOUT encodes them exactly once;
	# without this every high byte gets double-encoded. Malformed bytes become
	# U+FFFD instead of dying, so a weird ref name can't break the prompt.
	$out = decode('UTF-8', $out);

	foreach my $line (split(/\n/, $out)) {
		# Branch header lines
		if ($line =~ /^# branch\.head (.+)$/) {
			my $head = $1;

			if ($head eq '(detached)') {
				$ret->{'branch'} = "DETACHED_HEAD";
			} else {
				$ret->{'branch'} = $head;
			}
		} elsif ($line =~ /^# branch\.ab \+(\d+) -(\d+)$/) {
			my ($ahead, $behind) = ($1, $2);

			# Record both counts independently. Nonzero ahead AND behind
			# means the branch is diverged from the upstream, and the user
			# needs to see BOTH numbers: the old if/elsif showed only the
			# ahead count, so a diverged branch looked pushable when a
			# push would actually be rejected. The + 0 forces a numeric
			# value so JSON encodes a number, not a string.
			if ($ahead) {
				$ret->{'ahead'} = $ahead + 0;
			}

			if ($behind) {
				$ret->{'behind'} = $behind + 0;
			}

			# Build the position string from the nonzero parts
			if ($ahead || $behind) {
				my @pos;
				push @pos, "+$ahead"  if $ahead;
				push @pos, "-$behind" if $behind;
				$ret->{'position'} = join(" ", @pos);
			}
		# Ordinary changed (1) and rename/copy (2) entries: "XY" is index + worktree status
		} elsif ($line =~ /^[12] (.)(.) /) {
			my ($x, $y) = ($1, $2);

			if ($x ne '.') {
				$ret->{'staged'}++;
			}

			if ($y ne '.') {
				$ret->{'unstaged'}++;
			}

			$ret->{'dirty'}++;
		# Unmerged entries
		} elsif ($line =~ /^u /) {
			$ret->{'merge_conflict'}++;
		# Untracked entries count toward dirty: a branch with new files is not
		# clean. They do not touch staged/unstaged, so the "all staged" color
		# still requires every dirty file to be staged.
		} elsif ($line =~ /^\? /) {
			$ret->{'dirty'}++;
		}
	}

	# If there is nothing to commit don't keep looking there is nothing there
	if ($ret->{'dirty'} == 0 && !$ret->{'merge_conflict'}) {
		$ret->{'clean'} = 1;
	}

	# Porcelain v2 does not report rebases, so check the rebase state dirs directly
	# (no extra git call). Those dirs live in the repo's git dir, which is only
	# "./.git" at the top of a plain repo: from a subdirectory there is no .git in
	# the CWD at all, and in linked worktrees/submodules .git is a *file* naming
	# the real git dir. find_gitdir() resolves it in every one of those cases.
	my $gitdir = find_gitdir();

	if ($gitdir && (-d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply")) {
		$ret->{'rebasing'} = 1;
	}

	# During a rebase porcelain v2 reports a detached HEAD. The rebase-merge
	# backend records the branch being rebased in head-name, so use that instead.
	if ($gitdir && $ret->{'rebasing'} && $ret->{'branch'} eq 'DETACHED_HEAD' && -f "$gitdir/rebase-merge/head-name") {
		if (open(my $fh, '<', "$gitdir/rebase-merge/head-name")) {
			my $head_name = <$fh>;
			close($fh);

			chomp($head_name);
			$head_name =~ s{^refs/heads/}{};
			# Same raw-byte situation as the status output above
			$head_name = decode('UTF-8', $head_name);
			$ret->{'branch'} = $head_name;
		}
	}

	return $ret;
}

# Locate the git dir for the repo we're standing in, without forking git: the
# rebase state dirs live there, and they are not always at "./.git". From a
# subdirectory there is no .git in the CWD at all, and in linked worktrees and
# submodules .git is a *file* containing "gitdir: <path>". If GIT_DIR is set in
# the environment we honor it (git itself does); otherwise walk up from the
# CWD until we find a .git, following the file indirection if it is one.
sub find_gitdir {
	my $dir = getcwd();

	return undef unless defined($dir);

	# If GIT_DIR is set, git itself is using it, so it is the real git dir
	if (defined($ENV{GIT_DIR}) && length($ENV{GIT_DIR})) {
		my $gitdir = $ENV{GIT_DIR};
		return ($gitdir =~ m{^/}) ? $gitdir : "$dir/$gitdir";
	}

	while (1) {
		my $dot_git = "$dir/.git";

		# Plain repo: .git is a directory right here
		if (-d $dot_git) {
			return $dot_git;
		}

		# Linked worktree or submodule: .git is a file with "gitdir: <path>"
		if (-f $dot_git) {
			open(my $fh, '<', $dot_git) or return undef;
			my $line = <$fh>;
			close($fh);

			return undef unless defined($line);
			chomp($line);

			if ($line =~ /^gitdir:\s*(.+)$/) {
				my $gitdir = $1;
				# Absolute in linked worktrees, relative in submodules
				return ($gitdir =~ m{^/}) ? $gitdir : "$dir/$gitdir";
			}
			return undef;
		}

		# No .git here: walk up one level
		last if $dir eq '/';
		$dir =~ s{/[^/]+$}{} or last;
		$dir = '/' if $dir eq '';
	}

	return undef;
}

sub argv {
	my @args = @_;
	my $ret  = {};

	for (my $i = 0; $i < scalar(@args); $i++) {
		# If the item starts with "-" it's a key
		if (my ($key) = $args[$i] =~ /^--?(\S+)/) {
			# If the next item does not start with "--" it's the value for this item
			if (defined($args[$i + 1]) && ($args[$i + 1] !~ /^--?/)) {
				$ret->{$key} = $args[$i + 1];
				# Bareword like --verbose with no options
			} else {
				$ret->{$key}++;
			}
		}
	}

	return $ret;
}

# Add debug print krumo style
# Borrowed from: https://www.perturb.org/display/1097_Perl_detect_if_a_module_is_installed_before_using_it.html
BEGIN {
	if (eval { require Dump::Krumo }) {
		Dump::Krumo->import(qw/k kd/);
	} else {
		require Data::Dumper;
		*k  = sub { print Data::Dumper::Dumper(\@_) };
		*kd = sub { print Data::Dumper::Dumper(\@_); die; };
	}
}

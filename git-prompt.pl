#!/usr/bin/perl

use strict;
use warnings;
use v5.16;
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
	require JSON;
	# Character-mode encode: encode_json() returns UTF-8 *bytes*, which the
	# :utf8 layer on STDOUT would encode a second time. This returns characters
	# and the layer encodes them exactly once.
	print JSON->new->encode($i) . "\n";
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

	# If we're ahead/behind of the remote OR there are pending files
	if ($i->{'position'} || $i->{'dirty'}) {
		# Open paren
		print $BRACE_COLOR . "[";

		# Ahead/Behind of the remote server
		if ($i->{'position'}) {
			if ($i->{'ahead'}) {
				print $AHEAD_COLOR;
			} elsif ($i->{'behind'}) {
				print $BEHIND_COLOR;
			}
			print $i->{'position'};
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

			print $MERGE_COLOR . " " . $merge_symbol . $count;
		}

		# Close paren
		print $BRACE_COLOR . "]";
	}

	print "\n" . $RESET_COLOR;
}

# Set the foreground color
sub color {
	my $c = shift;

	# No color given: reset
	if (!defined($c)) {
		return "\e[0m";
	}

	return "\e[0m\e[38;5;${c}m";
}

###################################################

sub is_git_dir {
	# If the exit code is 0 we're in a git enabled dir
	my $ok = system("git rev-parse --is-inside-work-tree >/dev/null 2>&1");

	if ($ok == 0) {
		return 1;
	} else {
		return 0;
	}
}

sub get_git_info {
	# See if we're in a git enabled dir
	if (!is_git_dir()) {
		return 0;
	}

	my $ret = {};
	# Init some variables
	$ret->{staged}   = 0;
	$ret->{unstaged} = 0;
	$ret->{dirty}    = 0;

	# Porcelain v2 is stable and locale independent, unlike human readable status
	my $out = `LC_ALL=C git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null`;

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

			if ($ahead) {
				$ret->{'ahead'}    = 1;
				$ret->{'position'} = "+$ahead";
			} elsif ($behind) {
				$ret->{'behind'}   = 1;
				$ret->{'position'} = "-$behind";
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
		}
	}

	# If there is nothing to commit don't keep looking there is nothing there
	if ($ret->{'dirty'} == 0 && !$ret->{'merge_conflict'}) {
		$ret->{'clean'} = 1;
	}

	# Porcelain v2 does not report rebases, so check the rebase state dirs directly
	# (no extra git call). Only works when .git is a directory, not a worktree file.
	if (-d ".git/rebase-merge" || -d ".git/rebase-apply") {
		$ret->{'rebasing'} = 1;
	}

	# During a rebase porcelain v2 reports a detached HEAD. The rebase-merge
	# backend records the branch being rebased in head-name, so use that instead.
	if ($ret->{'rebasing'} && $ret->{'branch'} eq 'DETACHED_HEAD' && -f ".git/rebase-merge/head-name") {
		if (open(my $fh, '<', ".git/rebase-merge/head-name")) {
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

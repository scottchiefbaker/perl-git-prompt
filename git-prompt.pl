#!/usr/bin/perl

use warnings;
use v5.16;

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
my $BRACE_COLOR   = color(15);  # Color of the file count braces                 #4
my $AHEAD_COLOR   = color(117); # Color when the branch is ahead of the remote   #5
my $BEHIND_COLOR  = color(196); # Color when the branch is behind the remote     #5
my $PENDING_COLOR = color(11);  # Color of the uncommitted file count            #6
my $RESET_COLOR   = color();    # Reset the color

###################################################################

# Get the state of git in the current dir
my $i = get_git_info();

# A string of all the args passed in
my $args = argv();

# If the user requests debug dump out the data structure
if ($args->{debug}) {
	kd($i);
}

# If they request JSON spit that out
if ($args->{json}) {
	require JSON;
	print JSON::encode_json($i) . "\n";
	exit;
}

# If we're on a git enabled dir
if ($i && $i->{'branch'}) {
	print $PROMPT_COLOR . "Git Branch: ";

	my $branch_color = '';
	if ($i->{'dirty'}) {
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
		# If all the files are staged
		} elsif ($i->{'dirty'} == $i->{'staged'}) {
			print $CLEAN_COLOR;
		# If some of the files are staged (but not all)
		} elsif (($i->{'dirty'} >= 0) && ($i->{'staged'} >= 0)) {
			print $PENDING_COLOR;
		}

		# Print out the number of dirty files
		print $i->{'dirty'};

		# Close paren
		print $BRACE_COLOR . "]";
	}

	print "\n" . $RESET_COLOR;
}

# Set the foreground color
sub color {
	my $c    = shift() || "";
	my $bold = shift() || "";

	my $ret = '';

	if ($bold eq 'bold') {
		$ret = "\e[1m";
	} else {
		$ret = "\e[0m";
	}

	# Reset the color
	if (!defined($c)) {
		$ret = "\e[0m";
	} else {
		$ret .= "\e[38;5;${c}m";
	}

	return $ret;
}

###################################################

sub is_git_dir {
	# git branch is the fastest way to see if we're in a git dir or not
	my $cmd = "git branch 2>&1 > /dev/null";
	`$cmd`;

	# If the exit code is 0 we're in a git enabled dir
	if ($? == 0) {
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

	# Git status has all the data we'll need to get the parts
	my $cmd = "2>/dev/null git status";
	my $out = `$cmd`;

	# Find the branch we're on
	if ($out =~ /On branch (.+?)\n/) {
		$ret->{'branch'} = $1;
	} elsif ($out =~ /Not currently on any branch|HEAD detached (at|from)/) {
		$ret->{'branch'} = "DETACHED_HEAD";
	}

	#Your branch is behind 'origin/vader' by 2 commits
	if ($out =~ /Your branch is (ahead|behind).*'(.+?)' by (\d+) commit/) {
		my $sigil = "?";
		if ($1 eq 'ahead') {
			$sigil = "+";
			$ret->{'ahead'} = 1;
		} elsif ($1 eq 'behind') {
			$sigil = "-";
			$ret->{'behind'} = 1;
		}

		my $str = "${sigil}$3";
		$ret->{'position'} = $str;
	}

	# If there is nothing to commit don't keep looking there is nothing there
	if ($out =~ /^nothing to commit/m) {
		$ret->{'clean'} = 1;
		return $ret;
	}

	# Init some variables
	$ret->{staged}   = 0;
	$ret->{unstaged} = 0;
	$ret->{dirty}    = 0;

	# Find the number of files in each given state
	my $state;
	foreach my $line (split(/\n/,$out)) {
		# Files staged to be committed
		if ($line =~ /Changes to be committed:/) {
			$state = "staged";
		# Files git is aware of but aren't going to be committed
		} elsif ($line =~ /Changes not staged for commit:/) {
			$state = "unstaged";
		# Files gits sees but isn't tracking
		} elsif ($line =~ /Untracked files:/) {
			$state = "untracked";
		} elsif ($line =~ /Unmerged paths:/) {
			$state = "unmerged";
		# If the line has a \t in it, it's a file name
		} elsif ($line =~ /\t/) {
			$ret->{$state}++;
			$ret->{'dirty'}++;
		}
	}

	return $ret;
}

sub argv {
	my @args = @_ || @ARGV;
	my $ret = {};

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
sub AUTOLOAD {
	our $AUTOLOAD; # keep 'use strict' happy

	if ($AUTOLOAD eq 'main::k' || $AUTOLOAD eq 'main::kd') {
		if (eval { require Data::Dump::Color }) {
			*k = sub { Data::Dump::Color::dd(@_) };
		} else {
			require Data::Dumper;
			*k = sub { print Data::Dumper::Dumper(@_) };
		}

		sub kd {
			k(@_);

			printf("Died at %2\$s line #%3\$s\n",caller());
			exit(15);
		}

		eval($AUTOLOAD . '(@_)');
	}
}

#!/usr/bin/perl

use strict;

my $PAREN_COLOR   = color(15);  # Color of the parenthesis
my $DIRTY_COLOR   = color(203); # Color when the branch is dirty
my $CLEAN_COLOR   = color(83);  # Color when the branch is clean
my $PROMPT_COLOR  = color(45);  # Color of the header prompt
my $AHEAD_COLOR   = color(117);  # Color when the branch is ahead of the remote
my $BEHIND_COLOR  = color(196); # Color when the branch is behind of the remote
my $PENDING_COLOR = color(11);  # Color of the uncommitted file count
my $RESET_COLOR   = color();    # Reset the color

###################################################################

# A string of all the args passed in
my $args = join(" ",@ARGV);

# Get the state of git in the current dir
my $i = get_git_info();

# If the user requests debug dump out the data structure
if ($args =~ /--debug/) {
	require Data::Dump::Color;
	Data::Dump::Color->import();
	dd($i);
	exit;
}

# If they request JSON spit that out
if ($args =~ /--json/) {
	require JSON;
	JSON->import();
	print encode_json($i) . "\n";
	exit;
}

# If we're on a git enabled dir
if ($i) {
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
		print $PAREN_COLOR . "[";

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
		if ($i->{'dirty'} == $i->{'staged'}) {
			print $CLEAN_COLOR . $i->{'dirty'};
		} elsif ($i->{'dirty'}) {
			print $PENDING_COLOR . $i->{'dirty'};
		}

		# Close paren
		print $PAREN_COLOR . "]";
	}

	print "\n" . $RESET_COLOR;
}

# Set the foreground color
sub color {
	my $c = shift();

	my $ret = '';
	if (!defined($c)) { $ret = "\e[0m"; } # Reset the color
	else { $ret = "\e[38;5;${c}m"; }

	return $ret;
}

###################################################

sub is_git_dir {
	# git branch is the fastest way to see if we're in a git dir or not
	my $cmd = "git branch 2>&1 > /dev/null";
	`$cmd`;

	# Check the exit status to see if we're in a git dir
	if ($? != 0) { return 0; }
	else { return 1; }
}

sub get_git_info {
	# See if we're in a git enabled dir
	if (!is_git_dir()) { return 0; }

	my $ret = {};

	# Git status has all the data we'll need to get the parts
	my $cmd = "git status";
	my $out = `$cmd`;

	# Find the branch we're on
	if ($out =~ /On branch (.+?)\n/) {
		$ret->{'branch'} = $1;
	} elsif ($out =~ /Not currently on any branch/) {
		$ret->{'branch'} = "DETACHED_HEAD";
	}

	#Your branch is behind 'origin/vader' by 2 commits
	if ($out =~ /Your branch is (ahead|behind).*'(.+?)' by (\d+) commit/) {
		my $arrow = "?";
		if ($1 eq 'ahead') {
			$arrow = "+";
			$ret->{'ahead'} = 1;
		} elsif ($1 eq 'behind') {
			$arrow = "-";
			$ret->{'behind'} = 1;
		}

		my $str = "${arrow}$3";
		$ret->{'position'} = $str;
	}

	# If there is nothing to commit don't keep looking there is nothing there
	if ($out =~ /^nothing to commit/m) {
		$ret->{'clean'} = 1;
		return $ret;
	}

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
		# If the line has a \t in it, it's a file name
		} elsif ($line =~ /\t/) {
			$ret->{$state}++;
			$ret->{'dirty'}++;
		}
	}

	return $ret;
}

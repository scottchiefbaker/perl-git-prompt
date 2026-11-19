#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd abs_path);
use File::Spec;
use File::Path qw(make_path);

my $script = abs_path(File::Spec->catfile(
	(File::Spec->splitpath(abs_path(__FILE__)))[1], '..', 'git-prompt.pl'
));

# Load the script without running main()
require $script;

my $orig_cwd = getcwd();
my $perl     = $^X;

sub git {
	my ($dir, @args) = @_;
	my $cmd = join(" ", map { "'$_'" } @args);
	my $out = `cd '$dir' && git -c user.name=test -c user.email=test\@test -c init.defaultBranch=master $cmd 2>&1`;
	die "git $cmd failed: $out" if $? != 0;
	return $out;
}

sub new_repo {
	my $dir = tempdir(CLEANUP => 1);
	git($dir, 'init', '-q');
	git($dir, 'commit', '-q', '--allow-empty', '-m', 'init');
	return $dir;
}

sub in_dir {
	my ($dir, $code) = @_;
	chdir($dir) or die "chdir $dir: $!";
	my @ret = $code->();
	chdir($orig_cwd);
	return wantarray ? @ret : $ret[0];
}

# Run the script as a subprocess inside a directory
sub run_script {
	my ($dir, @args) = @_;
	my $argstr = join(" ", @args);
	my $out = `cd '$dir' && '$perl' '$script' $argstr 2>&1`;
	return $out;
}

###################################################################
# argv
###################################################################

{
	is_deeply(argv(), {}, 'argv: no args gives empty hash');

	is_deeply(argv('--no-color'), { 'no-color' => 1 }, 'argv: bareword flag');

	is_deeply(argv('-debug'), { debug => 1 }, 'argv: single-dash flag');

	is_deeply(argv('--json', '--no-color'), { json => 1, 'no-color' => 1 }, 'argv: two flags');

	is_deeply(argv('--foo', 'bar'), { foo => 'bar' }, 'argv: key with value');

	is_deeply(argv('--foo', 'bar', '--baz'), { foo => 'bar', baz => 1 }, 'argv: value then flag');

	is_deeply(argv('stray', '--json'), { json => 1 }, 'argv: non-flag tokens are ignored');
}

###################################################################
# color
###################################################################

{
	local $ENV{NO_COLOR};
	delete $ENV{NO_COLOR};

	is(color(45), "\x01\e[0m\x02\x01\e[38;5;45m\x02", 'color: 256-color escape wrapped in ignore markers');
	is(color(), "\x01\e[0m\x02", 'color: undef gives reset escape');
}

###################################################################
# find_gitdir
###################################################################

{
	local $ENV{GIT_DIR};
	delete $ENV{GIT_DIR};

	my $repo = new_repo();

	my $found = in_dir($repo, sub { find_gitdir() });
	is(abs_path($found), abs_path("$repo/.git"), 'find_gitdir: plain repo root');

	make_path("$repo/a/b");
	$found = in_dir("$repo/a/b", sub { find_gitdir() });
	is(abs_path($found), abs_path("$repo/.git"), 'find_gitdir: from a subdirectory walks up');

	my $wt = tempdir(CLEANUP => 1) . "/wt";
	git($repo, 'worktree', 'add', '-q', $wt);
	$found = in_dir($wt, sub { find_gitdir() });
	like($found, qr{/\.git/worktrees/wt$}, 'find_gitdir: linked worktree follows .git file');

	my $nogit = tempdir(CLEANUP => 1);
	my $none = in_dir($nogit, sub { find_gitdir() });
	ok(!defined($none) || $none !~ /\.git/, 'find_gitdir: no repo returns no git dir');

	{
		local $ENV{GIT_DIR} = "$repo/.git";
		$found = in_dir($nogit, sub { find_gitdir() });
		is($found, "$repo/.git", 'find_gitdir: honors absolute GIT_DIR');
	}
}

###################################################################
# get_git_info
###################################################################

{
	local $ENV{GIT_DIR};
	delete $ENV{GIT_DIR};

	# Outside any repo
	my $nogit = tempdir(CLEANUP => 1);
	my $none = in_dir($nogit, sub { get_git_info() });
	is($none, 0, 'get_git_info: outside a repo returns 0');

	# Clean repo
	my $repo = new_repo();
	my $i = in_dir($repo, sub { get_git_info() });
	is($i->{branch}, 'master', 'get_git_info: branch name');
	is($i->{dirty}, 0, 'get_git_info: clean repo has no dirty files');
	is($i->{clean}, 1, 'get_git_info: clean flag set');
	ok(!exists $i->{position}, 'get_git_info: no upstream means no position');

	# Untracked file counts as dirty
	open my $fh, '>', "$repo/new.txt" or die; close $fh;
	$i = in_dir($repo, sub { get_git_info() });
	is($i->{dirty}, 1, 'get_git_info: untracked file is dirty');
	is($i->{staged}, 0, 'get_git_info: untracked file is not staged');
	is($i->{unstaged}, 0, 'get_git_info: untracked file is not counted as unstaged');
	ok(!exists $i->{clean}, 'get_git_info: clean flag absent when dirty');

	# Staged file
	git($repo, 'add', 'new.txt');
	$i = in_dir($repo, sub { get_git_info() });
	is($i->{dirty}, 1, 'get_git_info: staged file counts as dirty');
	is($i->{staged}, 1, 'get_git_info: staged file counted');
	is($i->{unstaged}, 0, 'get_git_info: fully staged file has no unstaged count');

	# Staged plus further unstaged edits
	open $fh, '>>', "$repo/new.txt" or die; print $fh "more\n"; close $fh;
	$i = in_dir($repo, sub { get_git_info() });
	is($i->{staged}, 1, 'get_git_info: partially staged file still counts as staged');
	is($i->{unstaged}, 1, 'get_git_info: partially staged file counts as unstaged');

	# Detached HEAD
	git($repo, 'checkout', '-q', '--detach');
	$i = in_dir($repo, sub { get_git_info() });
	is($i->{branch}, 'DETACHED_HEAD', 'get_git_info: detached HEAD sentinel');
	git($repo, 'checkout', '-q', 'master');

	# Merge conflict
	my $conf = new_repo();
	open $fh, '>', "$conf/f.txt" or die; print $fh "base\n"; close $fh;
	git($conf, 'add', 'f.txt');
	git($conf, 'commit', '-q', '-m', 'base');
	git($conf, 'checkout', '-q', '-b', 'other');
	open $fh, '>', "$conf/f.txt" or die; print $fh "other\n"; close $fh;
	git($conf, 'commit', '-q', '-am', 'other');
	git($conf, 'checkout', '-q', 'master');
	open $fh, '>', "$conf/f.txt" or die; print $fh "master\n"; close $fh;
	git($conf, 'commit', '-q', '-am', 'master');
	`cd '$conf' && git -c user.name=t -c user.email=t\@t merge other >/dev/null 2>&1`;
	$i = in_dir($conf, sub { get_git_info() });
	is($i->{merge_conflict}, 1, 'get_git_info: unmerged entry counted as merge_conflict');
	is($i->{dirty}, 0, 'get_git_info: unmerged entries do not count toward dirty');

	# Ahead and behind of upstream, including diverged
	my $up = tempdir(CLEANUP => 1) . "/up.git";
	git(tempdir(CLEANUP => 1), 'init', '-q', '--bare', $up);
	my $ahead = new_repo();
	git($ahead, 'remote', 'add', 'origin', $up);
	git($ahead, 'push', '-q', '-u', 'origin', 'master');

	git($ahead, 'commit', '-q', '--allow-empty', '-m', 'local');
	$i = in_dir($ahead, sub { get_git_info() });
	is($i->{ahead}, 1, 'get_git_info: ahead count');
	ok(!exists $i->{behind}, 'get_git_info: behind absent when zero');
	is($i->{position}, '+1', 'get_git_info: position string when only ahead');

	# Make the remote diverge
	my $other = tempdir(CLEANUP => 1) . "/other";
	git(tempdir(CLEANUP => 1), 'clone', '-q', $up, $other);
	git($other, 'commit', '-q', '--allow-empty', '-m', 'remote');
	git($other, 'push', '-q', 'origin', 'master');
	git($ahead, 'fetch', '-q', 'origin');
	$i = in_dir($ahead, sub { get_git_info() });
	is($i->{ahead}, 1, 'get_git_info: diverged ahead count kept');
	is($i->{behind}, 1, 'get_git_info: diverged behind count kept');
	is($i->{position}, '+1 -1', 'get_git_info: position shows both counts when diverged');
}

###################################################################
# Full script output (subprocess)
###################################################################

{
	local $ENV{NO_COLOR};
	delete $ENV{NO_COLOR};

	my $nogit = tempdir(CLEANUP => 1);
	is(run_script($nogit, '--no-color'), '', 'script: prints nothing outside a repo');

	my $repo = new_repo();
	is(run_script($repo, '--no-color'), "Git Branch: (master) \n", 'script: clean repo output');

	open my $fh, '>', "$repo/x.txt" or die; close $fh;
	is(run_script($repo, '--no-color'), "Git Branch: (master) [1]\n", 'script: dirty count in brackets');

	my $json = run_script($repo, '--json');
	like($json, qr/"branch":"master"/, 'script: --json includes branch');
	like($json, qr/"dirty":1/, 'script: --json includes dirty count');

	my $color = run_script($repo);
	like($color, qr/\e\[38;5;45m/, 'script: color on by default');

	my $nocolor_env = do {
		local $ENV{NO_COLOR} = '1';
		run_script($repo);
	};
	unlike($nocolor_env, qr/\e\[/, 'script: NO_COLOR env disables color');

	my $empty_env = do {
		local $ENV{NO_COLOR} = '';
		run_script($repo);
	};
	like($empty_env, qr/\e\[/, 'script: empty NO_COLOR does not disable color');
}

chdir($orig_cwd);
done_testing();

#!/usr/bin/perl

use strict;
#use Term::ReadKey;
#my ($cols,$rows) = GetTerminalSize();

my $cols = 120;
my $rows = 24;
if (-f '/bin/stty') {
	($rows,$cols) = split(/ /,`/bin/stty size`);
}

for (my $i=0;$i<256;$i++) {

	print set_bcolor($i); # Set the background color

	print set_fcolor(15); # White
	printf("  %03d",$i); # Ouput the color number in white
	print set_fcolor(0); # Black
	printf(" %03d  ",$i); # Ouput the color number in black

	print set_fcolor(); # Reset both colors
	print " "; # Seperators

	if (($i + 1) % int($cols / 12) == 0) { 
		print set_bcolor(); # Reset
		print "\n"; 
	}
}

END {
	print set_fcolor(); # Reset the colors
	print "\n";
}

#print highlight_string('for','Thanks for viewing');

#################################################################################

sub set_fcolor {
	my $c = shift();

	my $ret = '';
	if (!defined($c)) { $ret = "\e[0m"; } # Reset the color
	else { $ret = "\e[38;5;${c}m"; }

	return $ret;
}

sub set_bcolor {
	my $c = shift();

	my $ret = '';
	if (!defined($c)) { $ret = "\e[0m"; } # Reset the color
	else { $ret .= "\e[48;5;${c}m"; }

	return $ret;
}

sub highlight_string {
	my $needle = shift();
	my $haystack = shift();
	my $color = shift() || 2; # Green if they don't pass in a color

	my $fc = set_fcolor($color);
	my $reset = set_fcolor();

	$haystack =~ s/$needle/$fc.$needle.$reset/e;

	return $haystack;
}

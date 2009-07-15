#!/usr/bin/perl

use DBI;
use strict;
use warnings;

our $dbi = get_dbi();

require 'grabhooks.pl';

while(1) {
	if (!deal_with_entry($dbi)) {
		sleep 5;
		if (!$dbi->ping) {
			$dbi = get_dbi();
		}
	}
}

sub get_dbi {
	open MYCNF, "$ENV{HOME}/.my.cnf";
	local $/;
	my $contents = <MYCNF>;
	close MYCNF;
	my ($user, $database, $password);
	$user = $1 if $contents =~ /user = (.*)/;
	$database = $1 if $contents =~ /database = (.*)/;
	$password = $1 if $contents =~ /password = (.*)/;

	if (!$user || !$database || !$password) {
		die("Sorry, the .my.cnf file appears to be corrupt");
	}

	return DBI->connect("dbi:mysql:database=$database", $user, $password);
}

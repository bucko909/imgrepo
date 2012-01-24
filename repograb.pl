#!/usr/bin/perl

use DBI;
use strict;
use warnings;

our $dbi = get_dbi();

require 'grabhooks.pl';

while(1) {
	if (!deal_with_entry($dbi)) {
		$dbi->rollback;
		sleep 5;
		if (!$dbi->ping) {
			$dbi = get_dbi();
		}
	} else {
		exit
	}
}

sub get_dbi {
	my $database = 'repo';

	my $dbh = DBI->connect("dbi:Pg:dbname=repo", '', '', {AutoCommit => 0});
	return $dbh;
}

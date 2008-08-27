package Stuff;

use DBI;

sub get_dbi {
	$ENV{HOME} ||= '/home/repo';
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

1;

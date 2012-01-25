package Stuff;

use strict;
use warnings;

use DBI;

sub get_dbi {
	my $database = 'repo';

	my $dbh = DBI->connect("dbi:Pg:dbname=repo", '', '', {AutoCommit => 1});
	return $dbh;
}

package MyCGI;
use strict;
use warnings;

use CGI;

our @ISA = qw/CGI/;

sub new {
	my ($this, $dbi, @rest) = @_;
	my $ret = CGI::new($this, @rest);
	$ret->{bucko_dbi} = $dbi;
	return $ret;
}

sub header {
	my ($this, @rest) = @_;
	if ($this->{bucko_sess}) {
		my $cookie = $this->cookie(-name => 'session', -value=> $this->{bucko_sess}, -expires => '+6h');
		return CGI::header($this, @rest, -cookie => $cookie);
	} else {
		return CGI::header($this, @rest);
	}
}

sub is_admin {
	return $_[0]->{admin};
}

sub get_session {
	my ($this, $generate_new) = @_;
	my $sess_id;
	if ($sess_id = $this->cookie('session')) {
		# Session appears to exist. Check it's valid.
		my $start_time = $this->{bucko_dbi}->selectall_arrayref("SELECT start_time, admin FROM sessions WHERE id = ?", {}, $sess_id);
		if ($start_time && @$start_time) {
			if ($start_time->[0][0] + 3600*6 < time()) {
				# Expire votes etc.
				$this->{bucko_dbi}->do("DELETE FROM rating_raters WHERE sess_id = ?", {}, $sess_id);
				$this->{bucko_dbi}->do("UPDATE sessions SET start_time = ? WHERE id = ?", {}, time(), $sess_id);
				# Expire any other old sessions
				$this->{bucko_dbi}->do("DELETE FROM sessions WHERE start_time < ?", {}, time() - 3600*8);
			}
			$this->{bucko_sess} = $sess_id;
			$this->{admin} = $start_time->[0][1];
			return $sess_id;
		}
	}

	if (!$generate_new) {
		# We're not allowed to generate new sessions.
		return;
	}

	# Must generate a new session.
	$sess_id = int(rand(1000000));
	while(1) {
		my $res = $this->{bucko_dbi}->selectall_arrayref("SELECT id FROM sessions WHERE id = ?", {}, $sess_id);
		if ($res && @$res) {
			print STDERR "Session collision; generating new: $sess_id\n";
			$sess_id = int(rand(1000000));
		} else {
			last;
		}
	}

	my $ip = $ENV{REMOTE_ADDR} || 'local';

	$this->{bucko_dbi}->do("INSERT INTO sessions (id, start_time, ip) VALUES (?, ?, ?)", {}, $sess_id, time(), $ip);
	$this->{bucko_sess} = $sess_id;
	return $sess_id;
}


1;

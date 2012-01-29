package Repo::Hooks;

use POE;
use POE::Component::IRC;
use DBI;
use strict;
use warnings;
use utf8;

# The bot has successfully connected to a server.  Join a channel.
sub on_001 {
	my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	my $irc = $heap->{IRC};
	$heap->{DBI} ||= get_dbi();
	$heap->{DBI} or die "Could not connect";

	my $channels = $heap->{CHANNELS};
	$irc->yield( join => $channels );
	if (my $ping_id = $heap->{ping_id}) {
		$irc->delay_remove($ping_id);
		delete $heap->{ping_id};
	}
	$heap->{ping_id} = $irc->delay( [ ping => 'keepalive' ], 30 );
}

sub on_pong {
	my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	my $irc = $heap->{IRC};
	if ($_[ARG0]) {
		print "PONG :$_[ARG0]\n";
	} else {
		print "PONG\n";
	}
	if (my $ping_id = $heap->{ping_id}) {
		$irc->delay_remove($ping_id);
		delete $heap->{ping_id};
	}
	$heap->{ping_id} = $irc->delay( [ ping => 'keepalive' ], 150 );
}

sub register {
	my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	my $irc = $heap->{IRC};
	my %events = (
		irc_001    => sub { goto &{'Repo::Hooks::on_001'} },
		irc_433    => sub { goto &{'Repo::Hooks::on_nickinuse'} },
		irc_public => sub { goto &{'Repo::Hooks::on_public'} },
		irc_ctcp_action => sub { goto &{'Repo::Hooks::on_public'} },
		irc_msg => sub { goto &{'Repo::Hooks::on_private'} },
		irc_disconnected => sub { goto &{'Repo::Hooks::on_disconnect'} },
		irc_pong => sub { goto &{'Repo::Hooks::on_pong'} },
		irc_raw  => sub { goto &{'Repo::Hooks::on_raw'} },
		irc_socketerr  => sub { goto &{'Repo::Hooks::on_socketerr'} },
		reconnect => sub { goto &{'Repo::Hooks::reconnect'} },
		register_events => sub { goto &{'Repo::Hooks::register'} },
	);
	for(keys %events) {
		$kernel->state($_, $events{$_});
	}
	if ($_[ARG0]) {
		$kernel->yield('reconnect');
	}
}

sub on_socketerr {
	my ($kernel, $heap, $session, $arg) = @_[ KERNEL, HEAP, SESSION, ARG0 ];
	print "Socket error: $arg\n";
	goto &on_disconnect;
}

sub on_raw {
	my ($kernel, $heap, $session, $arg) = @_[ KERNEL, HEAP, SESSION, ARG0 ];
	print "Raw: $arg\n";
}

sub on_nickinuse {
	my ($kernel, $heap, $session, @arg) = @_[ KERNEL, HEAP, SESSION, ARG0, ARG1, ARG2 ];
	my $irc = $heap->{IRC};
	my $nick = $arg[1];
	$nick =~ s/\s.*//;
	$nick .= '0' if $nick !~ /\d$/;
	$nick =~ /(\d+)$/;
	my $num = $1;
	$num++;
	$nick =~ s/\d+$/$num/;
	print "Nick in use; trying $nick.\n";
	$irc->yield(nick => $nick);
}

sub on_disconnect {
	my ($kernel, $heap, $session) = @_[ KERNEL, HEAP, SESSION ];
	my $irc = $heap->{IRC};

	print "Disconnected; trying again in 5 secs.\n";
	sleep 5;
	
	$kernel->post( $session, 'reconnect' );
}

sub reconnect {
	my ($kernel, $heap) = @_[ KERNEL, HEAP ];
	my $irc = $heap->{IRC};

	$irc->yield( connect =>
		{
			Nick => 'BuckoRepo',
			Username => 'repo',
			Ircname  => 'Repository Grabber',
			Server   => $heap->{SERVER},
			Port     => '6667',
			Raw      => 1,
		}
	);
}



sub get_dbi {
	my $database = 'repo';

	my $dbh = DBI->connect("dbi:Pg:dbname=repo", '', '', {AutoCommit => 1});
	return $dbh;
}

# The bot has received a public message.  Parse it for commands, and
# respond to interesting things.
sub on_public {
	my ( $kernel, $heap, $who, $where, $msg ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	my $irc = $heap->{IRC};
	my $dbi = $heap->{DBI};
	my ($nick, $mask) = split /!/, $who;
	my $channel = $where->[0];

	my $ts = scalar localtime;

	if (!utf8::valid($msg)) {
		print "COCKSOADFASDFSADJ\n";
		return;
	}

	print " [$ts] <$nick:$channel> $msg\n";
	my $sth = $dbi->prepare("INSERT INTO irc_lines (time, nick, mask, channel, text) VALUES(?, ?, ?, ?, ?) returning id;");
	if (!$sth->execute(time(), $nick, $mask, $channel, $msg)) {
		print "DB error: $!";
	}
	my $id = $sth->fetchall_arrayref()->[0][0];
	process_public($dbi, $irc, $nick, $mask, $where, $msg, $id);
}

sub on_private {
	my ( $kernel, $heap, $who, $where, $msg ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	my $irc = $heap->{IRC};
	my $dbi = $heap->{DBI};
	my ($nick, $mask) = split /!/, $who;

	my $ts = scalar localtime;
	print " [$ts] <$nick> $msg\n";
	my $sth = $dbi->prepare("INSERT INTO irc_lines (time, nick, mask, text) VALUES(?, ?, ?, ?) returning id;");
	$sth->execute(time(), $nick, $mask, $msg) or die "DB error: $!";
	my $id = $sth->fetchall_arrayref()->[0][0];

	if ($nick =~ /^bucko/ && $msg =~ /^!reload kjdhf2$/) {
		$irc->yield( privmsg => $nick, "Trying..." );
		my $r = do 'hooks.pl';
		my $session = $_[SESSION];
		my $rep = "Done. (Ret=$r, \$!=$!, \$@=$@)";
		$rep =~ s/\n/\\n/g;
		$kernel->yield($session, 'register');
		$irc->yield( privmsg => $nick, $rep );
	} elsif ($nick =~ /^bucko/ && $msg =~ /^!quit kjdhf2$/) {
		$irc->yield( quit => "Message" );
	} else {
		process_public($dbi, $irc, $nick, $mask, $nick, $msg, $id);
	}
}

sub process_public {
	my ($dbi, $irc, $nick, $mask, $where, $msg, $line_id) = @_;
	if (lc $nick eq 'badgerbot') {
		return;
	}
	if ($msg =~ /^!(.*)/) {
		my ($f, @params) = split /\s+/, $1;
		print "To: $where; Command: $f; Params: @params\n";
		$f = lc $f;
		if ($f eq 'search' || $f eq 'reposearch') {
			my $results = $dbi->selectall_arrayref("SELECT image_id FROM image_postings WHERE url = ?", {}, $params[0]);
			if (@$results) {
				my $result_out = join(' ', map { "http://abhor.co.uk/image?i=$_->[0]" } @$results);
				$irc->yield( privmsg => $where, "$nick: $result_out" );
				print "Results: $result_out\n";
			} else {
				$irc->yield( privmsg => $where, "$nick: Nothing found." );
			}
		}
		return;
	}
	while ($msg =~ m#(https?://\S+)#cg) {
		print "URL: $1\n";
		$dbi->do("INSERT INTO upload_queue(url, line_id) VALUES(?, ?)", {}, $1, $line_id);
	}
}

1;

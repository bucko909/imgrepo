package Repo::Hooks;

use POE;
use POE::Component::IRC;
use DBI;
use strict;
use warnings;

# The bot has successfully connected to a server.  Join a channel.
sub on_001 {
	my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	my $irc = $heap->{IRC};
	$heap->{DBI} ||= get_dbi();
	$heap->{DBI} or die "Could not connect";

	my $channels = $heap->{CHANNELS};
	$irc->yield( join => $channels );
}

sub register {
	my $kernel = $_[KERNEL];
	my %events = (
		irc_001    => sub { goto &{'Repo::Hooks::on_001'} },
		irc_433    => sub { goto &{'Repo::Hooks::on_nickinuse'} },
		irc_public => sub { goto &{'Repo::Hooks::on_public'} },
		irc_msg => sub { goto &{'Repo::Hooks::on_private'} },
		irc_disconnected => sub { goto &{'Repo::Hooks::on_disconnect'} },
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
		}
	);
}



sub get_dbi {
	return $_[0]->{dbi} if exists $_[0]->{dbi};

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

# The bot has received a public message.  Parse it for commands, and
# respond to interesting things.
sub on_public {
	my ( $kernel, $heap, $who, $where, $msg ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	my $irc = $heap->{IRC};
	my $dbi = $heap->{DBI};
	my ($nick, $mask) = split /!/, $who;
	my $channel = $where->[0];

	my $ts = scalar localtime;

	print " [$ts] <$nick:$channel> $msg\n";
	$dbi->do("INSERT INTO irc_lines (time, nick, mask, channel, text) VALUES(?, ?, ?, ?, ?);", {}, time(), $nick, $mask, $channel, $msg);
	my $id = $dbi->last_insert_id(undef, undef, undef, undef);
	process_public($dbi, $irc, $nick, $mask, $where, $msg, $id);
}

sub on_private {
	my ( $kernel, $heap, $who, $where, $msg ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	my $irc = $heap->{IRC};
	my $dbi = $heap->{DBI};
	my ($nick, $mask) = split /!/, $who;

	my $ts = scalar localtime;
	print " [$ts] <$nick> $msg\n";
	$dbi->do("INSERT INTO irc_lines (time, nick, mask, text) VALUES(?, ?, ?, ?);", {}, time(), $nick, $mask, $msg);
	my $id = $dbi->last_insert_id(undef, undef, undef, undef);

	if ($nick =~ /^bucko/ && $msg =~ /^!reload kjdhf$/) {
		$irc->yield( privmsg => $nick, "Trying..." );
		my $r = do 'hooks.pl';
		my $session = $_[SESSION];
		my $rep = "Done. (Ret=$r, \$!=$!, \$@=$@)";
		$rep =~ s/\n/\\n/g;
		$kernel->yield($session, 'register');
		$irc->yield( privmsg => $nick, $rep );
	} elsif ($nick =~ /^bucko/ && $msg =~ /^!quit kjdhf$/) {
		$irc->yield( quit => "Message" );
	} else {
		process_public($dbi, $irc, $nick, $mask, $nick, $msg, $id);
	}
}

sub process_public {
	my ($dbi, $irc, $nick, $mask, $where, $msg, $line_id) = @_;
	if (lc $nick eq 'ender' || lc $nick eq 'badgerbot') {
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
	while ($msg =~ m#(http://\S+/\S*)#cg) {
		print "URL: $1\n";
		$dbi->do("INSERT INTO upload_queue(url, line_id) VALUES(?, ?)", {}, $1, $line_id);
	}
}

1;

#!/usr/bin/perl

# This is a simple IRC bot that just rot13 encrypts public messages.
# It responds to "rot13 <text to encrypt>".

use warnings;
use strict;

use POE;
use POE::Component::IRC;

# Create the component that will represent an IRC network.
my $irc1 = POE::Component::IRC->spawn();
my $irc2 = POE::Component::IRC->spawn();

require 'hooks.pl';

# Create the bot session.  The new() call specifies the events the bot
# knows about and the functions that will handle those events.
POE::Session->create(
	inline_states => {
		_start     => \&bot_start,
		register_events => sub { goto &{'Repo::Hooks::register'} },
	},
	heap => {
		IRC => $irc1,
		SERVER => 'irc.uwcs.co.uk',
		CHANNELS => '#compsoc,#goatse,#anime',
	},
);

POE::Session->create(
	inline_states => {
		_start     => \&bot_start,
		register_events => sub { goto &{'Repo::Hooks::register'} },
	},
	heap => {
		IRC => $irc2,
		SERVER => 'irc.rizon.net',
		CHANNELS => '#clone-army',
	},
);

# The bot session has started.  Register this bot with the "magnet"
# IRC component.  Select a nickname.  Connect to a server.
sub bot_start {
	my $kernel  = $_[KERNEL];
	my $heap    = $_[HEAP];
	my $session = $_[SESSION];

	$heap->{IRC}->yield( register => "all" );

	$kernel->post($session, 'register_events', 1);
}

# Run the bot until it is done.
$poe_kernel->run();
exit 0;

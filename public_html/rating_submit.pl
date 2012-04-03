#!/usr/bin/perl

use Stuff;
use CGI;
use strict;
use warnings;

print "Content-Type: text/plain; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $dbi = Stuff->get_dbi;
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session();
if (!$sess_id) {
	print "nosess";
	exit;
}
my $rating = $q->param('rating');
if (!$rating) {
	print "error";
	exit;
}
my $image_id = $q->param('img');
my $results = $dbi->selectall_arrayref("SELECT sess_id FROM rating_raters WHERE sess_id = ? AND image_id = ?", {}, $sess_id, $image_id);
if (!$results) {
	print "error";
} elsif (@$results) {
	print "already_rated";
} else {
	my $image_result = $dbi->selectall_arrayref("SELECT id FROM images WHERE id=?", {}, $image_id);
	if (!@$image_result) {
		print "error";
		exit;
	}
	my $ret = $dbi->do("INSERT INTO rating_raters (image_id, sess_id) VALUES (?, ?)", {}, $image_id, $sess_id);
	my $change = $rating eq 'up' ? 1 : -1;
	$dbi->do("UPDATE images SET rating = rating + ? WHERE id = ?", {}, $change, $image_id);
	$dbi->do("INSERT INTO rating_ratings (image_id, ip, rating) VALUES (?, ?, ?)", {}, $image_id, $ENV{REMOTE_ADDR}, $change);
	# Can vote.
	print "rated";
}

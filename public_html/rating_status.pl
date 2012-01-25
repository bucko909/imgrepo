#!/usr/bin/perl

use Stuff;
use strict;
use warnings;

print "Content-Type: text/plain; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $dbi = Stuff->get_dbi;
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session();
my $image_id = $q->param('img');
my $results_rating = $dbi->selectall_arrayref("SELECT rating FROM images WHERE id = ?", {}, $image_id);
if (!$sess_id) {
	print "nosess";
	exit;
} else {
	my $results = $dbi->selectall_arrayref("SELECT sess_id FROM rating_raters WHERE sess_id = ? AND image_id = ?", {}, $sess_id, $image_id);
	if (!$results) {
		print "error";
	} elsif (@$results) {
		print "rated";
	} else {
		print "rateable";
	}
}
if ($results_rating && @$results_rating) {
	print "\n$results_rating->[0][0]";
}

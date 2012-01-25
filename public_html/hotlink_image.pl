#!/usr/bin/perl

use Stuff;
use strict;
use warnings;

my $dbi = Stuff->get_dbi;
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session();
my $img = $q->param('img');
my $referer = $ENV{HTTP_REFERER};
my $accept = $ENV{HTTP_ACCEPT};
my $file = $ENV{REDIRECT_URL};
$file =~ s/^\///;

if (!$file || ! -e $file) {
	print "Status: 500 ISE\nContent-type: text/plain\n\nYou fail.";
	exit 0;
}

my $happy_link;

for (split /,/, $accept) {
	next if /;/;
	if (/text|xml|html/) {
#		print STDERR "lolol: $_\n";
		$happy_link = 1;
	} else {
#		print STDERR "fail: $_\n";
	}
}

my $image_id;
my $r = $dbi->selectall_arrayref("SELECT id FROM images WHERE local_filename = ? OR local_thumbname = ?", {}, $img, $img);
if ($r && @$r) {
	$image_id = $r->[0][0];
} else {
#	print STDERR "gone $img\n";
	print "Status: 404 Not found\nContent-type: text/html\n\n<html><head><title>Image not found</title></head><body><h1>Image not found</h1><a href=\"/\">Go to the index</a></body>";
	exit 0;
}

if ($happy_link) {
#	print STDERR "happy\n";
	print "Status: 302 Found\nLocation: /image?i=$r->[0][0]\nContent-type: text/plain\n\nRedirecting to image";
	exit 0;
}

my $goatse;
if ($referer) {
	$r = $dbi->selectall_arrayref("SELECT hotlink_count, hotlink_limit, initial_hotlink_time FROM hotlink_stats WHERE image_id = ? AND referrer_url = ?", {}, $image_id, $referer);
	if ($r && @$r) {
		if ((defined $r->[0][1]) && ($r->[0][0] >= $r->[0][1]) && ($r->[0][2] < time() - 600)) {
			$goatse = 1;
			$dbi->do("UPDATE hotlink_stats SET hotlink_count = hotlink_count + 1, goatse_count = goatse_count + 1 WHERE image_id = ? AND referrer_url = ?", {}, $image_id, $referer);
		} else {
			$dbi->do("UPDATE hotlink_stats SET hotlink_count = hotlink_count + 1 WHERE image_id = ? AND referrer_url = ?", {}, $image_id, $referer);
		}
	} else {
		$dbi->do("INSERT INTO hotlink_stats SET hotlink_count = 1, hotlink_limit = 10, initial_hotlink_time = ?, image_id = ?, referrer_url = ?", {}, time(), $image_id, $referer);
	}
}

if ($goatse) {
#	print STDERR "goat\n";
	print "Content-type: image/jpeg\n";
	print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";
	open GOAT, "media/refererfail.jpg";
	local $/;
	print <GOAT>;
	close GOAT;
	exit 0;
}

if ($image_id) {
#	print STDERR "img\n";
	if ($file =~ /jpe?g$/) {
		print "Content-type: image/jpeg\n";
	} elsif ($file =~ /png$/) {
		print "Content-type: image/png\n";
	} elsif ($file =~ /gif$/) {
		print "Content-type: image/gif\n";
	} else {
		$file =~ /\.(.*)$/;
		print "Content-type: image/$1\n";
	}
	print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";
	$file =~ s/imgtest/images/;
	open IMAGE, $file or print STDERR "fail: $file / $!\n";
	local $/;
	print <IMAGE>;
	close IMAGE;
	exit 0;
}

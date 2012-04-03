#!/usr/bin/perl

use Stuff;
use strict;
use warnings;

print "Content-Type: text/plain; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $dbi = Stuff->get_dbi;
my $q = MyCGI->new($dbi);
$q->get_session(1);
my $ad = $q->is_admin;
my @tags = $q->param('tag');
my $image = $q->param('img');
my $image_result = $dbi->selectall_arrayref("SELECT id FROM images WHERE id=?", {}, $image);
if (!@$image_result) {
	print "\nImage $image did not exist: @tags";
	exit;
}
my $image_id = $image_result->[0][0];
my @success;
my %failures;
my %types = (
	name => 1,
	series => 1,
	meme => 1,
	content => 1,
	artist => 1,
	other => 1,
	private => 1,
);
if ($ad) {
	my @res = grep { $_ eq 'delete_me' || $_ eq 'delete_me:private' || $_ eq 'approved' || $_ eq 'approved:private' } @tags;
	if (!@res) {
		my $image_tagged = $dbi->selectall_arrayref("SELECT tag_id FROM image_tags WHERE image_id = ? AND (tag_id = 4 OR tag_id = 840)", {}, $image_id);
		if (!@$image_tagged) {
			push @tags, 'approved:private';
		}
	}
}
for my $tag (@tags) {
	my ($name, $type) = split /:/, lc $tag;
	if ($type && !$types{$type}) {
		$failures{type_unknown} ||= [];
		push @{$failures{type_unknown}}, $tag;
		next;
	}
	if (!$type) {
		my $results = $dbi->selectall_arrayref("SELECT tags.type FROM tags WHERE tags.name = ?;", {}, $name);
		if (@$results == 0) {
			$failures{new_ambiguous} ||= [];
			push @{$failures{new_ambiguous}}, $tag;
			next;
		} elsif (@$results > 1) {
			$failures{ambiguous} ||= [];
			push @{$failures{ambiguous}}, $tag;
			next;
		}
		$type = $results->[0][0];
	}
	if ($type eq 'private' && !$ad) {
		$failures{private} ||= [];
		push @{$failures{private}}, $tag;
		next;
	} elsif ($type eq 'private') {
		if ($name eq 'delete_me') {
			if (!$dbi->do('INSERT INTO upload_queue (url) values(CONCAT(\'delete \', ?::text))', {}, $image_id)) {
				$failures{sql} ||= [];
				push @{$failures{sql}}, $tag;
				next;
			}
		}
	}
	my $existing = $dbi->selectall_arrayref("SELECT tags.id FROM tags WHERE tags.name = ? AND tags.type = ?", {}, $name, $type);
	my $tag_id;
	if (@$existing) {
		$tag_id = $existing->[0][0];
	} else {
		my $other = $dbi->selectall_arrayref("SELECT tags.id FROM tags WHERE tags.name = ?", {}, $name);
		if (!$dbi->do("INSERT INTO tags (name, type) VALUES(?, ?)", {}, $name, $type)) {
			$failures{couldnt_create} ||= [];
			push @{$failures{couldnt_create}}, "$name:$type (".$dbi->errstr.")";
			next;
		}
		$existing = $dbi->selectall_arrayref("SELECT tags.id FROM tags WHERE tags.name = ? AND tags.type = ?", {}, $name, $type);
		if (!@$existing) {
			$failures{couldnt_create} ||= [];
			push @{$failures{couldnt_create}}, "$name:$type (no id)";
			next;
		}
		$tag_id = $existing->[0][0];
		if (@$other) {
			$dbi->do("UPDATE tags SET has_other_type=1 WHERE name=?", {}, $name);
		}
	}
	my $image_tagged = $dbi->selectall_arrayref("SELECT tag_id FROM image_tags WHERE image_id = ? AND tag_id = ?", {}, $image_id, $tag_id);
	if (@$image_tagged) {
		$failures{existed} ||= [];
		push @{$failures{existed}}, "$name:$type";
		next;
	} else {
		$dbi->do("INSERT INTO image_tags (image_id, tag_id, ip, tag_time) VALUES (?,?,?,?)", {}, $image_id, $tag_id, $ENV{REMOTE_ADDR}, time());
	}
	push @success, "$name:$type";
}
if (@success) {
	print "Success:";
	for(@success) {
		print " $_";
	}
}
if (%failures) {
	for(keys %failures) {
		print "\n";
		if ($_ eq 'type_unknown') {
			print "Invalid tag type (name/series/meme/content/other/artist):";
		} elsif ($_ eq 'new_ambiguous') {
			print "New tag with no type (name/series/meme/content/other/artist):";
		} elsif ($_ eq 'ambiguous') {
			print "Tag with ambiguous type:";
		} elsif ($_ eq 'existed') {
			print "Tags which the image already had:";
		} elsif ($_ eq 'private') {
			print "Tags which can only be added by admin:";
		} elsif ($_ eq 'couldnt_create') {
			print "Tags which failed to create:";
		}
		for(@{$failures{$_}}) {
			print " $_";
		}
	}
}

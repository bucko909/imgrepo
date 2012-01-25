#!/usr/bin/perl

use Stuff;
use CGI;
use strict;
use warnings;

print "Content-Type: text/plain; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $q = CGI->new;
my $dbi = Stuff->get_dbi;
my @tags = $q->param('tag');
my @tag_ids = $q->param('tag_id');
my $results;
if (@tags || @tag_ids) {
	my ($query, @bind) = ('0');
	if (@tags) {
		for(@tags) {
			if (/(.*):(.*)/) {
				$query .= " OR (exist_tags.name = ? AND exist_tags.type = ?)";
				push @bind, ($1, $2);
			} else {
				$query .= " OR exist_tags.name = ?";
				push @bind, $_;
			}
		}
	}
	if (@tag_ids) {
		$query .= " OR exist_tagd.tag_id IN (".join(',', ('?') x @tag_ids).")";
		push @bind, @tag_ids;
	}
	$results = $dbi->selectall_arrayref("SELECT new_tags.id, new_tags.name, new_tags.type, new_tags.has_other_type, COUNT(new_tagd.image_id) AS use_count FROM image_tags new_tagd INNER JOIN image_tags exist_tagd ON new_tagd.image_id = exist_tagd.image_id AND new_tagd.tag_id != exist_tagd.tag_id INNER JOIN tags exist_tags  ON exist_tags.id = exist_tagd.tag_id INNER JOIN tags new_tags ON new_tags.id = new_tagd.tag_id AND new_tags.id != 840 WHERE $query GROUP BY new_tagd.tag_id ORDER BY use_count DESC LIMIT 10;", {}, @bind);
} else {
	$results = $dbi->selectall_arrayref("SELECT new_tags.id, new_tags.name, new_tags.type, new_tags.has_other_type, COUNT(new_tagd.image_id) AS use_count FROM image_tags new_tagd INNER JOIN tags new_tags ON new_tags.id = new_tagd.tag_id AND new_tags.id != 840 GROUP BY new_tagd.tag_id ORDER BY use_count DESC LIMIT 10;");
}
print join("\n", map { "$_->[0] $_->[1] $_->[2]" } @$results);

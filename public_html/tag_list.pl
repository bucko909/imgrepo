#!/usr/bin/perl

use Stuff;
use CGI;
use strict;
use warnings;

print "Content-Type: text/plain; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $q = CGI->new;
my $dbi = Stuff->get_dbi;
my $image_id = $q->param('img');
my $results1 = $dbi->selectall_arrayref("SELECT tags.id, tags.name, tags.type, tags.has_other_type FROM tags INNER JOIN image_tags ON image_tags.tag_id = tags.id WHERE image_tags.image_id = ?;", {}, $image_id);
print join("\n", map { "$_->[0] $_->[1] $_->[2] $_->[3]" } @$results1);

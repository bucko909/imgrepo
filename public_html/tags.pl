#!/usr/bin/perl

use Stuff;
use CGI;
use strict;
use warnings;

print "Content-Type: text/html; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $q = CGI->new;
print <<END;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta name="Content-Type" value="application/xhtml+xml"/><title>Index</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>
END
print $q->h1("Tags");
my $dbi = Stuff->get_dbi;
my $results1 = $dbi->selectall_arrayref("SELECT tags.id, tags.name, tags.type, tags.has_other_type, COUNT(image_id) AS tag_count FROM tags LEFT OUTER JOIN image_tags ON image_tags.tag_id = tags.id GROUP BY tags.id ORDER BY tag_count DESC;");
print "<p>";
print join("\n", map { qq|<a href="index.pl?tag=$_->[1]%3A$_->[2]">$_->[1]|.($_->[3]?" ($_->[2])":"").qq|</a>| } @$results1);
print "</p>";
print $q->end_html;

#!/usr/bin/perl

use DBI;
use Stuff;
use POSIX qw/strftime/;
use strict;
use warnings;

my $dbi = Stuff->get_dbi();
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session(1);

my $upload_queue = $q->param('i');

my $res= $dbi->selectall_arrayref("SELECT upload_queue.url, irc_lines.nick, irc_lines.channel, irc_lines.text, irc_lines.time, upload_queue.attempted, upload_queue.success, upload_queue.fail_reason FROM upload_queue INNER JOIN irc_lines ON irc_lines.id = upload_queue.line_id WHERE upload_queue.id = ?;", {}, $upload_queue);

if (!@$res) {
	print "Status: 404 Not Found\nContent-Type: text/html\n\n";
	print $q->start_html("Not Found");
	print $q->h1("Not Found");
	print $q->p("The image posting ($upload_queue) you requested does not exist.");
	print $q->end_html;
	exit;
}
$res = $res->[0];


if (grep { lc $_ eq 'application/xhtml+xml' } split /\s*[,;]\s*/, $ENV{HTTP_ACCEPT}) {
	my $s = $q->header('application/xhtml+xml');
	$s =~ s/^Status:\s*-cookie\s*\n//;
	print $s;
} else {
	print $q->header;
#	print $q->start_html("Your browser!");
#	print $q->h1("Sorry, XHTML only");
#	print $q->p("Sorry, this page requires an XHTML-equipped browser. You may wish to try Opera or Firefox.");
#	print $q->end_html;
#	exit;
}

print <<END;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head><meta name="Content-Type" value="application/xhtml+xml"/><title>Upload log for $upload_queue</title><link rel="stylesheet" type="text/css" href="style.css"/><link rel="icon" type="image/png" href="media/favicon.png"/></head><body id="body">
END
print qq|<div class="m" id="main">|;
print qq|<h1>Upload log for $upload_queue</h1>|;
my $qline = '<code>&lt;'.$q->escapeHTML($res->[1]).($res->[2] ? '/'.$q->escapeHTML($res->[2]) : '').'&gt; '.$q->escapeHTML($res->[3]).'</code>';
my $qurl = '<a href="'.$q->escapeHTML($res->[0]).'">'.$q->escapeHTML($res->[0]).'</a>';
my $qattempted = defined $res->[5] ? ($res->[5] ? 'True' : 'False') : 'Undefined';
my $qsuccess = defined $res->[6] ? ($res->[6] ? 'True' : 'False') : 'Undefined';
my $qfail = $res->[7] ? '<li><b>Error</b>: '.$q->escapeHTML($res->[7]).'</li>' : '';
print qq|<p style="text-align: left;"><ul><li><b>IRC contents</b>: $qline</li><li><b>URL</b>: $qurl</li><li><b>Attempted</b>: $qattempted</li><li><b>Success</b>: $qsuccess</li>$qfail</ul></p>|;
print "</div>";
print $q->end_html;

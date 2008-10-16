#!/usr/bin/perl

use DBI;
use Stuff;
use POSIX qw/strftime/;
use strict;
use warnings;

my $dbi = get_dbi();
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session(1);

my ($extra, $join, @bind) = ("1", "");
if (my $chan = $q->param('chan')) {
	$extra .= " AND channel = ?";
	push @bind, $chan;
}
if (my $nick = $q->param('nick')) {
	$extra .= " AND nick = ?";
	push @bind, $nick;
}
if (my $type = $q->param('type')) {
	$extra .= " AND images.image_type = ?";
	push @bind, $type;
}
if (my @tags = $q->param('tag')) {
	$extra .= " AND (0";
	$join .= " INNER JOIN image_tags ON image_tags.image_id = images.id INNER JOIN tags ON tags.id = image_tags.tag_id";
	for(@tags) {
		if (/(.*):(.*)/) {
			$extra .= " OR (tags.name = ? AND tags.type = ?)";
			push @bind, ($1, $2);
		} else {
			$extra .= " OR tags.name = ?";
			push @bind, $_;
		}
	}
	$extra .= ")";
}
my $count = 50;
my $start = 0;
if (my $skip = $q->param('skip')) {
	if ($skip !~ /[^0-9]/) {
		$start = $skip;
	}
}

my $res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, url, irc_lines.nick, irc_lines.channel, irc_lines.time, image_type FROM images INNER JOIN image_postings ON images.id = image_postings.image_id INNER JOIN irc_lines ON irc_lines.id = image_postings.line_id$join WHERE $extra ORDER BY irc_lines.time DESC LIMIT ?, ?;", {}, @bind, $start, $count+1);

my $nav = '';
my @p = $q->param();
my %params;
for($q->param) {
	next if $_ eq 'skip';
	$params{$_} = $q->param($_);
}
my $qs = join '&amp;', map { "$_=$params{$_}" } keys %params;
$qs =~ s/#/%23/g;
if ($start != 0) {
	my $ns  = $start - $count;
	$ns = 0 if $ns < 0;
	$nav .= qq#<p><a href="?$qs">Top</a> | <a href="?$qs&amp;skip=$ns">Newer</a>#;
}
if ($start != 0) {
	$nav .= " | ";
} else {
	$nav .= "<p>";
}
if ($count < @$res) {
	my $ns  = $start + $count;
	$nav .= qq#<a href="?$qs&amp;skip=$ns">Older</a> #;
}
$nav .= qq|<a href="tags">Tags</a></p>|;

if (grep { lc $_ eq 'application/xhtml+xml' } split /\s*[,;]\s*/, $ENV{HTTP_ACCEPT}) {
	print $q->header('application/xhtml+xml');
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
<head><meta name="Content-Type" value="application/xhtml+xml"/><title>Index</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>
END
print $nav;
print qq|<div class="g">|;
my $number = $count > @$res ? @$res : $count;
for(@$res[0..$number-1]) {
	my $d = $_->[1];
	$d =~ s#^(.)(.).*#$1/$2#;
	my $style = "";
	if ($_->[3]) {
		$style = qq| style="width:$_->[3]px;height:$_->[4]px;"|;
	}
	my $uchan = $_->[7] || '';
	$uchan =~ s/#/%23/g;
	my $chan = $_->[7] ? qq|<a href="?chan=$uchan">$_->[7]</a>| : 'privmsg';
	my $extra = '';
	my $local_url = "image?i=$_->[0]";
	if ($_->[9] eq 'animated') {
		$extra = qq|<img src="media/trans.gif" style="width:12px;height:$_->[4]px;background:url(media/moviereel.png);"/>|;
	} elsif ($_->[9] eq 'nicovideo') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->[4]px;background:url(media/niconico.png);"/>|;
	} elsif ($_->[9] eq 'youtube') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->[4]px;background:url(media/youtube.png);"/>|;
	} elsif ($_->[9] eq 'html') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->[4]px;background:url(media/firefox.png);"/>|;
	}
	my $qurl = $q->escapeHTML($_->[5]);
	my $qdispurl = length $qurl > 25 ? substr($qurl,0,22)."..." : $qurl;
	print qq|<div><div><a href="$local_url"><div><div>$extra<img$style src="thumbs/$d/$_->[2]"/>$extra</div></div></a><div><div><a href="?nick=$_->[6]">$_->[6]</a> / $chan<br/><a href="$qurl">$qdispurl</a></div></div></div></div> |;
}
print qq|<div><img src="media/trans.gif" style="width:100%;height:1px;"/></div>|;
print "</div>";
print $nav;
print $q->end_html;


sub get_dbi {
	return $_[0]->{dbi} if exists $_[0]->{dbi};

	$ENV{HOME} ||= '/home/repo';
	open MYCNF, "$ENV{HOME}/.my.cnf";
	local $/;
	my $contents = <MYCNF>;
	close MYCNF;
	my ($user, $database, $password);
	$user = $1 if $contents =~ /user = (.*)/;
	$database = $1 if $contents =~ /database = (.*)/;
	$password = $1 if $contents =~ /password = (.*)/;

	if (!$user || !$database || !$password) {
		die("Sorry, the .my.cnf file appears to be corrupt");
	}

	return DBI->connect("dbi:mysql:database=$database", $user, $password);
}

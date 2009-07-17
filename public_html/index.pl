#!/usr/bin/perl

use DBI;
use Stuff;
use POSIX qw/strftime/;
use strict;
use warnings;

my $dbi = Stuff::get_dbi();
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session(1);

my ($extra, $join, @joinbind, @bind) = ("1", "");
my $order = "MAX(irc_lines.time) DESC, images.id DESC";
my @flags;
my $by_image = 0;
if (my $chan = $q->param('chan')) {
	$extra .= " AND channel = ?";
	push @bind, $chan;
} elsif ($ENV{SERVER_NAME} =~ /disillusionment/) {
	$extra .= " AND channel = ?";
	push @bind, "#compsoc";
}
if (my $nick = $q->param('nick')) {
	$extra .= " AND nick = ?";
	push @bind, $nick;
}
if (my $url = $q->param('url')) {
	$extra .= " AND url LIKE CONCAT('%', ?, '%')";
	push @bind, $url;
}
if (my $type = $q->param('type')) {
	$extra .= " AND images.image_type = ?";
	push @bind, $type;
}
if (my $val = $q->param('plus_rated')) {
	$extra .= " AND images.rating > 0";
}
if (my $area = $q->param('min_area')) {
	$extra .= " AND images.image_width * images.image_height >= ?";
	push @bind, $area;
}
if (my $has_tag = $q->param('has_tag')) {
	$join .= " INNER JOIN image_tags t1 ON t1.image_id = images.id AND t1.tag_id != 4";
}
if (my $by_img  = $q->param('by_image')) {
	$by_image = 1;
	$order = "images.id DESC";
} elsif (my $to_approve = $q->param('approveq')) {
	$join .= " LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND (tdt.tag_id = 840 OR tdt.tag_id = 4) LEFT OUTER JOIN image_tags tdt2 ON tdt2.image_id = images.id";
	$extra .= " AND tdt.tag_id IS NULL AND tdt2.tag_id IS NOT NULL";
	$order = "(images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)";
	$by_image = 1;
} elsif (my $to_delete = $q->param('delq')) {
	$join .= " LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND tdt.tag_id = 840";
	$extra .= " AND tdt.tag_id IS NULL AND images.rating <= 0";
	$order = "(images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)";
	push @flags, "deletion_info";
	$by_image = 1;
#SELECT images.*, IF(image_tags.tag_id IS NULL,0,1) AS tagtot FROM images LEFT OUTER JOIN image_tags ON images.id = image_tags.image_id AND image_tags.tag_id != 4 WHERE rating <= 0 AND image_tags.tag_id IS NULL GROUP BY images.id ORDER BY (images.id + fullviews*1000)/(thumbnail_size + size);
}
if (my @tags = $q->param('tag')) {
	$extra .= " AND (1";
	my $c = 0;
	for(@tags) {
		my $not = s/^-//;
		my $cond;
		my @b;
		if (/(.*):(.*)/) {
			$cond = "tt$c.name = ? AND tt$c.type = ?";
			@b = ($1, $2);
		} else {
			$cond = "tt$c.name = ?";
			@b = ($_);
		}
		if ($not) {
			$join .= " INNER JOIN tags tt$c ON $cond LEFT OUTER JOIN image_tags it$c ON it$c.image_id = images.id AND tt$c.id = it$c.tag_id";
			$extra .= " AND it$c.tag_id IS NULL";
			push @joinbind, @b;
		} else {
			$join .= " INNER JOIN image_tags it$c ON it$c.image_id = images.id INNER JOIN tags tt$c ON tt$c.id = it$c.tag_id";
			$extra .= " AND $cond";
			push @bind, @b;
		}
		$c++;
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

my $res;
$res = $dbi->selectall_arrayref("SELECT AVG(size), AVG(image_width)*AVG(image_height) FROM images WHERE image_type != 'html' && image_width < 3000 && image_height < 3000;");
our ($avgsize, $avgarea) = @{$res->[0]};
if ($by_image) {
	$res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, image_type, image_height * image_width, size FROM images$join WHERE $extra GROUP BY images.id ORDER BY $order LIMIT ?, ?;", {}, @joinbind, @bind, $start, $count+1);
} else {
	$res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, url, irc_lines.nick, irc_lines.channel, irc_lines.time, image_type, image_height * image_width, size FROM images INNER JOIN image_postings ON images.id = image_postings.image_id INNER JOIN irc_lines ON irc_lines.id = image_postings.line_id$join WHERE $extra GROUP BY irc_lines.id, images.id ORDER BY $order LIMIT ?, ?;", {}, @joinbind, @bind, $start, $count+1);
}

my $nav = '<p>';
if ($q->is_admin) {
	$nav .= "(Id) | ";
}

$nav .= '<a href="/">Top</a>';
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
	$nav .= qq# | <a href="?$qs">Newest</a> | <a href="?$qs&amp;skip=$ns">Newer</a>#;
}
$nav .= " | ";
if ($count < @$res) {
	my $ns  = $start + $count;
	$nav .= qq#<a href="?$qs&amp;skip=$ns">Older</a> #;
}
$nav .= qq| \| <a href="tags">Tags</a>|;
if ($start == 0) {
	$nav .= " | ";
	$nav .= qq|[<a href="?delq=1">Deletion queue</a>]|;
	$nav .= " | ";
	$nav .= qq|[<a href="?has_tag=1">Tagged</a>]|;
	$nav .= " | ";
	$nav .= qq|[<a href="?min_area=1000000">Huge</a>]|;
}
$nav .= "</p>";

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
<head><meta name="Content-Type" value="application/xhtml+xml"/><title>Index</title><link rel="stylesheet" type="text/css" href="style.css"/><link rel="icon" type="image/png" href="media/favicon.png"/></head><body>
END

print $nav;
print qq|<form method="post"><p>Search URL: <input type="text" name="url"/> \| [bar on left measures file size; right is area]</p></form>|;
for(@flags) {
	if ($_ eq 'deletion_info') {
		my $inf = $dbi->selectall_arrayref("SELECT SUM(thumbnail_size) + SUM(size), COUNT(*) FROM images");
		my $saved = $dbi->selectall_arrayref("SELECT SUM(size) + SUM(thumbnail_size), COUNT(*) FROM images INNER JOIN image_tags ON images.id = image_tags.image_id AND image_tags.tag_id = 840");
		#print "<p>Repo status: ".sprintf("%0.2f",5*1024*1024*1024-$inf->[0][0]/1024/1024/1024)."GiB of 5GiB used; ".sprintf("%0.1f",100*$inf->[0][0]/1024/1024/1024/5)."% full. +ve rated and tagged images will not be automatically deleted. Viewing an image moves it further from deletion, so if you view it and it sucks, downrate it.</p>";
		print "<p>Repo status: ".sprintf("%0.2f",(5*1024*1024*1024-$inf->[0][0])/1024/1024)."MiB of 5GiB free (".sprintf("%0.2f",($saved->[0][0])/1024/1024/1024)."GiB of which is saved - that's $saved->[0][1]/$inf->[0][1] images). +ve rated and approved images will not be automatically deleted. Viewing an image moves it further from deletion, so if you view it and it sucks, downrate it. Recent (top 1000 or so) images are never deleted.</p>";
	}
}
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
	my $type = $by_image ? $_->[5] : $_->[9];
	my $area = $by_image ? $_->[6] : $_->[10];
	my $size = $by_image ? $_->[7] : $_->[11];
	my $relarea = 1 - (1 / sqrt($area/$avgarea+1));
	my $relsize = 1 - (1 / sqrt($size/$avgsize+1));
	$relarea = 0.1 if $relarea < 0.1;
	$relsize = 0.1 if $relsize < 0.1;
	$relarea = int($relarea*$_->[4]);
	$relsize = int($relsize*$_->[4]);
	my $areaind = qq|<img src="media/trans.gif" class="areaind" style="height:${relarea}px;"/>|;
	my $sizeind = qq|<img src="media/trans.gif" class="areaind" style="height:${relsize}px;"/>|;
	if ($type eq 'animated') {
		$extra = qq|<img src="media/trans.gif" style="width:12px;height:$_->[4]px;background:url(media/moviereel.png);"/>|;
	} elsif ($type eq 'nicovideo') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->[4]px;background:url(media/niconico.png);"/>|;
	} elsif ($type eq 'youtube') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->[4]px;background:url(media/youtube.png);"/>|;
	} elsif ($type eq 'html') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->[4]px;background:url(media/firefox.png);"/>|;
	}
	my $qurl = $q->escapeHTML($_->[5]||'');
	my $dispurl = $_->[5] ? (length $_->[5] > 25 ? substr($_->[5],0,22)."..." : $_->[5]) : '';
	my $qdispurl = $q->escapeHTML($dispurl);
	print qq|<div><div><a href="$local_url"><div><div>$sizeind$extra<img$style src="thumbs/$d/$_->[2]"/>$extra$areaind</div></div></a>|;
	print qq|<div><div><a href="?nick=$_->[6]">$_->[6]</a> / $chan<br/><a href="$qurl">$qdispurl</a></div></div>| if !$by_image;
	print qq|</div></div> |;
}
print qq|<div><img src="media/trans.gif" style="width:100%;height:1px;"/></div>|;
print "</div>";
print $nav;
print $q->end_html;

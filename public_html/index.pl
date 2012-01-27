#!/usr/bin/perl

use DBI;
use Stuff;
use POSIX qw/strftime/;
use Time::HiRes qw/time/;
use strict;
use warnings;

my $start = time();

my $dbi = Stuff::get_dbi();
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session(1);

my ($extra, $join, @joinbind, @bind) = ("TRUE", "");
my @order = qw/-image_postings.id/;
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
	$join .= " INNER JOIN image_tags t1 ON t1.image_id = images.id AND t1.tag_id = 840";
}
if (my $by_img  = $q->param('by_image')) {
	$by_image = 1;
	@order = qw/-images.id/;
} elsif (my $to_approve = $q->param('approveq')) {
	$join .= " LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND (tdt.tag_id = 840 OR tdt.tag_id = 4) LEFT OUTER JOIN image_tags tdt2 ON tdt2.image_id = images.id";
	$extra .= " AND tdt.tag_id IS NULL AND tdt2.tag_id IS NOT NULL";
	@order = ("(images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)");
	$by_image = 1;
} elsif (my $to_delete = $q->param('delq')) {
	$join .= " LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND tdt.tag_id = 840";
	$extra .= " AND tdt.tag_id IS NULL AND images.rating <= 0";
	@order = ("(images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)");
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
		my $res;
		if (/(.*):(.*)/) {
			$res = $dbi->selectall_arrayref("SELECT id FROM tags WHERE name=? AND type=?", {}, $1, $2);
		} else {
			$res = $dbi->selectall_arrayref("SELECT id FROM tags WHERE name=?", {}, $_);
		}
		if (!$res || !@$res) {
			print $q->header('text/plain');
			print "No such tag: $_";
			exit 0;
		} elsif (@$res > 1) {
			print $q->header('text/plain');
			print "Ambiguous tag: $_";
			exit 0;
		}
		my $tag_id = $res->[0][0];
		$join .= " LEFT OUTER JOIN image_tags it$c ON it$c.image_id = images.id AND it$c.tag_id = $tag_id";
		if ($not) {
			$extra .= " AND it$c.tag_id IS NULL";
		} else {
			$extra .= " AND it$c.tag_id IS NOT NULL";
		}
		$c++;
	}
	$extra .= ")";
}
my $count = 50;
$count = $q->param('count') if $q->param('count') && $q->is_admin;

my $limit = $count+1;
my $reverse;
my $gofurther;
if ($q->param('skip') && $q->param('skip') =~ /^[0-9]+$/) {
	my $start = 0;
	my $skip = int $q->param('skip');
	$limit = "? OFFSET ?";
	push @bind, $count+2, $q->param('skip')-1;
} elsif ($q->param('from')) {	
	$extra .= " AND image_postings.id >= ? - 1";
	$gofurther = int $q->param('from') - 1;
	push @bind, $q->param('from');
	$limit += 2;
	$reverse = 1;
} elsif ($q->param('to')) {
	$extra .= " AND image_postings.id <= ? + 1";
	$gofurther = int $q->param('to') + 1;
	push @bind, $q->param('to');
	$limit += 2;
}

my @desc = $reverse ? (" DESC", "") : ("", " DESC"); 
my $order = join ", ", map { my $a = s/^-//; $a ? "$_$desc[1]" : "$_$desc[0]" } @order;

my $res;
$res = $dbi->selectall_arrayref("SELECT AVG(size), AVG(image_width)*AVG(image_height) FROM images WHERE image_type != 'html' AND image_width < 3000 AND image_height < 3000;");
our ($avgsize, $avgarea) = @{$res->[0]};

if ($by_image) {
	$res = $dbi->selectall_arrayref("SELECT MAX(images.id) FROM images LEFT OUTER JOIN image_tags approved_tag ON approved_tag.image_id = images.id AND approved_tag.tag_id = 840$join WHERE $extra LIMIT $limit;", {}, @joinbind, @bind);
} else {
	$res = $dbi->selectall_arrayref("SELECT MAX(image_postings.id) FROM image_postings INNER JOIN images ON images.id = image_postings.image_id INNER JOIN irc_lines ON irc_lines.id = image_postings.line_id LEFT OUTER JOIN image_tags approved_tag ON approved_tag.image_id = images.id AND approved_tag.tag_id = 840$join WHERE $extra LIMIT $limit;", {}, @joinbind, @bind);
}
my $max_id = $res->[0][0];

my $sth;
if ($by_image) {
	$sth = $dbi->prepare("SELECT images.id AS id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, image_type, image_height * image_width AS area, size, approved_tag.tag_id AS approved FROM images LEFT OUTER JOIN image_tags approved_tag ON approved_tag.image_id = images.id AND approved_tag.tag_id = 840$join WHERE $extra ORDER BY $order LIMIT $limit;");
} else {
	$sth = $dbi->prepare("SELECT images.id AS id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, url, irc_lines.nick AS nick, irc_lines.channel AS chan, irc_lines.time AS time, image_type, image_height * image_width AS area, size, approved_tag.tag_id AS approved, image_postings.id AS post_id FROM image_postings INNER JOIN images ON images.id = image_postings.image_id INNER JOIN irc_lines ON irc_lines.id = image_postings.line_id LEFT OUTER JOIN image_tags approved_tag ON approved_tag.image_id = images.id AND approved_tag.tag_id = 840$join WHERE $extra ORDER BY $order LIMIT $limit;");
}

if (!$sth) {
	print $q->header('text/plain');
	print "SQL Error fetching images.";
	exit 0;
}
$sth->execute(@joinbind, @bind);

$res = [];
while(my $ref = $sth->fetchrow_hashref) {
	push @$res, $ref;
}

# Sort out the resulting data
my ($ismore_old, $ismore_new);
if ($gofurther && $res->[0]{post_id} == $gofurther) {
	shift @$res;
	$ismore_new = 1;
}
if (@$res > $count) {
	$res = [ @{$res}[0..$count] ];
	$ismore_old = 1;
}
if ($reverse) {
	$res = [ reverse @$res ];
	($ismore_old, $ismore_new) = ($ismore_new, $ismore_old);
}
if ($by_image) {
	$ismore_new = 1 unless $res->[0]{id} == $max_id;
} else {
	$ismore_new = 1 unless $res->[0]{post_id} == $max_id;
}

my $nav = '<p class="nav">';
if ($q->is_admin) {
	$nav .= "(Id) | ";
}

$nav .= '<a href="/">Top</a>';
my @p = $q->param();
my %params;
for($q->param) {
	next if $_ eq 'skip' || $_ eq 'from' || $_ eq 'to';
	$params{$_} = $q->param($_);
}
my $qs = join '&amp;', map { "$_=$params{$_}" } keys %params;
$qs =~ s/#/%23/g;
my $qqs = $q->escapeHTML($qs);
if ($ismore_new) {
	my $ns  = $res->[0]{post_id} + 1;
	$nav .= qq# | <a href="?$qqs">Newest</a> | <a href="?$qqs&amp;from=$ns">Newer</a>#;
}
$nav .= " | ";
if ($ismore_old) {
	my $ns  = $res->[$#$res]{post_id} - 1;
	$nav .= qq#<a href="?$qqs&amp;to=$ns">Older</a> #;
}
$nav .= qq| \| <a href="tags">Tags</a>|;
if (!%params) {
	$nav .= " | ";
	$nav .= qq|[<a href="?delq=1">Deletion queue</a>]|;
	$nav .= " | ";
	$nav .= qq|[<a href="?has_tag=1">Tagged</a>]|;
	$nav .= " | ";
	$nav .= qq|[<a href="?min_area=1000000">Huge</a>]|;
}
$nav .= "</p>";

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
<head><meta name="Content-Type" value="application/xhtml+xml"/><title>Index</title><link rel="stylesheet" type="text/css" href="style.css"/><link rel="icon" type="image/png" href="media/favicon.png"/><script language="javascript" src="media/tagedit.js"/></head><body>
END

my $grey_id;
print $nav;
print qq|<form method="post"><p>Search URL: <input type="text" name="url"/> \| [bar on left measures file size; right is area]</p></form>|;
for(@flags) {
	if ($_ eq 'deletion_info') {
		my $inf = $dbi->selectall_arrayref("SELECT SUM(thumbnail_size) + SUM(size), COUNT(*) FROM images");
		my $saved = $dbi->selectall_arrayref("SELECT SUM(size) + SUM(thumbnail_size), COUNT(*) FROM images INNER JOIN image_tags ON images.id = image_tags.image_id AND image_tags.tag_id = 840");
		$grey_id = $dbi->selectall_arrayref("SELECT MAX(image_id) FROM image_tags INNER JOIN tags ON tags.id = image_tags.tag_id WHERE tags.name = 'approved';")->[0][0];
		#print "<p>Repo status: ".sprintf("%0.2f",5*1024*1024*1024-$inf->[0][0]/1024/1024/1024)."GiB of 5GiB used; ".sprintf("%0.1f",100*$inf->[0][0]/1024/1024/1024/5)."% full. +ve rated and tagged images will not be automatically deleted. Viewing an image moves it further from deletion, so if you view it and it sucks, downrate it.</p>";
		print "<p>Repo status: ".sprintf("%0.2f",(5*1024*1024*1024-$inf->[0][0])/1024/1024)."MiB of 5GiB free (".sprintf("%0.2f",($saved->[0][0])/1024/1024/1024)."GiB of which is saved - that's $saved->[0][1]/$inf->[0][1] images). +ve rated and approved images will not be automatically deleted. Viewing an image moves it further from deletion, so if you view it and it sucks, downrate it. Recent (top 1000 or so) images are never deleted. Grey images are too recent to be deleted.</p>";
	}
}
print qq|<div class="g" id="g">|;
for(@$res) {
	my $d = $_->{local_thumbname};
	$d =~ s#^(.)(.).*#$1/$2#;
	my $style = "";
	if ($_->{thumbnail_width}) {
		$style = qq| style="width:$_->{thumbnail_width}px;height:$_->{thumbnail_height}px;"|;
	}
	my $uchan = $_->{chan} || '';
	$uchan =~ s/#/%23/g;
	my $chan = $_->{chan} ? qq|<a href="?chan=$uchan">$_->{chan}</a>| : 'privmsg';
	my $extra = '';
	my $local_url = "image.pl?i=$_->{id}";
	my $type = $_->{image_type};
	my $area = $_->{area};
	my $size = $_->{size};
	my $relarea = 1 - (1 / sqrt($area/$avgarea+1));
	my $relsize = 1 - (1 / sqrt($size/$avgsize+1));
	$relarea = 0.1 if $relarea < 0.1;
	$relsize = 0.1 if $relsize < 0.1;
	$relarea = int($relarea*$_->{thumbnail_height});
	$relsize = int($relsize*$_->{thumbnail_height});
	my $areaind = qq|<img src="media/trans.gif" class="areaind" style="height:${relarea}px;"/>|;
	my $sizeind = qq|<img src="media/trans.gif" class="areaind" style="height:${relsize}px;"/>|;
	if ($type eq 'animated') {
		$extra = qq|<img src="media/trans.gif" style="width:12px;height:$_->{thumbnail_height}px;background:url(media/moviereel.png);"/>|;
	} elsif ($type eq 'nicovideo') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->{thumbnail_height}px;background:url(media/niconico.png);"/>|;
	} elsif ($type eq 'youtube') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->{thumbnail_height}px;background:url(media/youtube.png);"/>|;
	} elsif ($type eq 'html') {
		$extra = qq|<img src="media/trans.gif" style="width:16px;height:$_->{thumbnail_height}px;background:url(media/firefox.png);"/>|;
	}
	my $qurl = $q->escapeHTML($_->{url}||'');
	my $dispurl = $_->{url} ? (length $_->{url} > 25 ? substr($_->{url},0,22)."..." : $_->{url}) : '';
	my $qdispurl = $q->escapeHTML($dispurl);
	my $boxs = defined $grey_id && $grey_id < $_->{id} ? " style=\"background:gray!important;\"" : "";
	print qq|<div><a href="$local_url"><div$boxs>$sizeind$extra<img$style src="thumbs/$d/$_->{local_thumbname}"/>$extra$areaind</div></a>|;
	my $link = $_->{url} =~ /^http/ ? qq|<a href="$qurl">$qdispurl</a>| : "$qdispurl";
	my $approved = $_->{approved} ? qq| ✓| : "";
	my $delete = $q->is_admin() ? qq| <a href="#" id="delete$_->{id}">✗</a>| : "";
	print qq|<div><a href="?nick=$_->{nick}">$_->{nick}</a> / $chan<br/>$link$approved$delete</div>| if !$by_image;
	print qq|</div> |;
}
print "</div>";
$qs =~ s/"/\\"/g;
$qqs = $q->escapeHTML($qs);
my $new = $ismore_new ? 0 : $res->[0]{post_id};
print qq|<script language="javascript">delete_initialise();scrolldetect_initialise($res->[$#$res]{post_id},$new,$avgarea,$avgsize,"$qqs",$sess_id);</script>|;
print $nav;
my $t = time() - $start;
printf "<p>%0.3fsecs</p>", $t;
print qq|<div id="scrolly_bit" style="display:none;"/>|;
print $q->end_html;

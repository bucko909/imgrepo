#!/usr/bin/perl

use DBI;
use Stuff;
use POSIX qw/strftime/;
use strict;
use warnings;

my $dbi = Stuff->get_dbi();
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session(1);

my $image_id = $q->param('i');

my $res = $dbi->selectall_arrayref("SELECT id, local_filename, local_thumbname, image_width, image_height, image_type, fullviews FROM images WHERE id = ?;", {}, $image_id);

if (!@$res) {
	print "Status: 404 Not Found\nContent-Type: text/html\n\n";
	print $q->start_html("Not Found");
	print $q->h1("Not Found");
	print $q->p("The image you requested does not exist.");
	print $q->end_html;
	exit;
}

my $visit_time = $dbi->selectall_arrayref("SELECT time FROM image_visits WHERE visit_key = ? AND image_id = ?", {}, $ENV{REMOTE_ADDR}, $res->[0][0]);
if (@$visit_time) {
	if ($visit_time->[0][0] < time() - 60 * 60) {
		$visit_time = [];
		$dbi->do("DELETE FROM image_visits WHERE time < ?", {}, time() - 60 * 60);
	}
}
if (!@$visit_time) {
	$dbi->do("UPDATE images SET fullviews = fullviews + 1 WHERE id = ?;", {}, $image_id);
	$dbi->do("INSERT INTO image_visits SET image_id = ?, time = ?, visit_key = ?", {}, $res->[0][0], time(), $ENV{REMOTE_ADDR});
	$res->[0][6]++;
}

my $posts = $dbi->selectall_arrayref("SELECT url, line_id FROM image_postings WHERE image_id = ?;", {}, $image_id);

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
<head><meta name="Content-Type" value="application/xhtml+xml"/><title>Image $image_id</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body id="body">
END
print qq|<div class="m" id="main">|;
if ($res->[0][5] eq 'youtube') {
	my $vid = $posts->[0][0];
	$vid =~ s/.*v=([^&]*).*/$1/;
#<object width="425" height="344"><param name="movie" value="http://www.youtube.com/v/$vid&amp;hl=en&amp;fs=1"></param><param name="allowFullScreen" value="true"></param><embed src="http://www.youtube.com/v/$vid&amp;hl=en&amp;fs=1" type="application/x-shockwave-flash" allowfullscreen="true" width="425" height="344"></embed></object>
	print <<END;
<p><object width="800" height="630"><param name="movie" value="http://www.youtube.com/v/$vid&amp;hl=en&amp;fs=1"></param><param name="allowFullScreen" value="true"></param><embed src="http://www.youtube.com/v/$vid&amp;hl=en&amp;fs=1" type="application/x-shockwave-flash" allowfullscreen="true" width="800" height="630"></embed></object></p>
END
} elsif ($res->[0][5] eq 'nicovideo') {
	my $vid = $posts->[0][0];
	$vid =~ s/.*\b(\w\w\d+).*/$1/;
#<p><iframe width="312" height="176" src="http://ext.nicovideo.jp/thumb/nm$vid" scrolling="no" style="border:solid 1px #CCC;" frameborder="0"><a href="http://ext.nicovideo.jp/watch/nm$vid">Watch</a></iframe></p>
	print <<END;
<p><div id="nvcontent" style="display:inline-block;width:1000px;height:660px;overflow:scroll;"><iframe width="950" height="2000" src="http://www.nicovideo.jp/watch/$vid" scrolling="no" style="border:solid 1px #CCC;" frameborder="0"><a href="http://www.nicovideo.jp/watch/$vid">Watch</a></iframe></div></p>
<script lang="javascript">
var nicodiv = document.getElementById("nvcontent");
nicodiv.scrollTop = 500;
</script>
END
} else {
	my $imgurl = $res->[0][1];
	$imgurl =~ s#^(.)(.)#$1/$2/$1$2#;
	print <<END;
<p><a id="mylink" href="images/$imgurl"><img src="images/$imgurl" style="width: $res->[0][3]px; height: $res->[0][4]px;" id="myimg"/></a></p>
<script lang="javascript">
var maindiv = document.getElementById("main");
var pagebody = document.getElementById("body");
var elt = document.getElementById("myimg");
var mylink = document.getElementById("mylink");
var origheight = elt.style.height;
var origwidth = elt.style.width;
function resize() {
	var ratio1 = parseInt(elt.style.height) / (document.body.parentNode.clientHeight - 50);
	var ratio2 = parseInt(elt.style.width) / (document.body.parentNode.clientWidth - 50);
	var ratio = ratio1 > ratio2 ? ratio1 : ratio2;
	if (ratio > 1) {
		elt.style.height = (parseInt(elt.style.height) / ratio) + "px";
		elt.style.width = (parseInt(elt.style.width) / ratio) + "px";
	} else {
		elt.style.height = origheight;
		elt.style.width = origwidth;
	}
}
function origsize(e) {
	if (elt.style.height != origheight) {
		window.removeEventListener('resize',resize,true);
		elt.removeEventListener('click',origsize,false);
		elt.style.height = origheight;
		elt.style.width = origwidth;
		e.preventDefault();
	}
}
window.addEventListener('resize',resize,true);
elt.addEventListener('click',origsize,false);
resize();
</script>
END
}
print qq|<div class="i">|;
print qq|<p>Viewed $res->[0][6] times. <span id="rating"></span></p>|;
print qq|<p>Tags: <span id="tags"></span></p>|;
print qq|<div id="editlink"><a href="#" id="editlinklink">Edit</a></div>|;
print qq|<div id="editor" style="display: none;"><p><form id="tagform"><input type="text" id="tagbox" size="80" autocomplete="off"/> <input type="submit" id="tagsubmitbutton" value="Add Tags"/><input type="hidden" id="imageid" value="$res->[0][0]"/></form></p><div id="statmsg"/><div id="autocomplete"/></div>|;
print qq|<script language="javascript" src="media/tagedit.js"/>|;
print "</div><br/>";
print qq|<div class="i">|;
for my $post (@$posts) {
	my $postline = $dbi->selectall_arrayref("SELECT id, time, nick, channel, text FROM irc_lines WHERE id = ?", {}, $post->[1]);
	my $postprev = $postline->[0][3] ? $dbi->selectall_arrayref("SELECT id, time, nick, channel, text FROM irc_lines WHERE time < ? AND channel = ? ORDER BY time DESC LIMIT 2", {}, $postline->[0][1], $postline->[0][3]) : [];
	my $postnext = $postline->[0][3] ? $dbi->selectall_arrayref("SELECT id, time, nick, channel, text FROM irc_lines WHERE time > ? AND channel = ? ORDER BY time ASC LIMIT 2", {}, $postline->[0][1], $postline->[0][3]) : [];
	my @lines = (reverse(@$postprev), @$postline, @$postnext);

	my $uchan = $postline->[0][3] || '';
	$uchan =~ s/#/%23/g;
	my @ltext = (qq|In |.($postline->[0][3] ? qq|<a href="?chan=$uchan">$postline->[0][3]</a>| : "private message").qq| on |.strftime("%a %b %d %Y", localtime $lines[0][1]).qq|:|);
	for (@lines) {
		my $qurl = quotemeta $post->[0];
		my $text = $q->escapeHTML($_->[4]);
		$text =~ s#[^ -~]#?#g;
		$text =~ s#(http://\S+)#<a href="$1">$1</a>#g;
		$text =~ s#(href="$qurl")#class="me" $1#g;
		push @ltext, strftime("[%H:%M:%S] ", localtime $_->[1]).qq|&lt;<a href="/?nick=$_->[2]">$_->[2]</a>&gt; $text|;
	}
	print qq|<p>|.join("<br/>", @ltext)."</p>";
}
print "</div>";
print "</div>";
print $q->end_html;

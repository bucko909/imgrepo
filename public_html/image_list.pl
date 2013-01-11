#!/usr/bin/perl


use Stuff;
use CGI;
use strict;
use warnings;

print "Content-Type: text/plain; charset=ISO-8859-1\n";
print "Expires: Thu, 01 Jan 1970 00:00:00 GMT\n\n";

my $dbi = Stuff->get_dbi;
my $q = MyCGI->new($dbi);
my $sess_id = $q->get_session();
if (!$sess_id) {
#	print "nosess";
#	exit;
}

my ($extra, $join, @joinbind, @bind) = ("TRUE", "");
my @order = qw/-upload_queue.id/;
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
	$extra .= " AND upload_queue.id >= ? - 1";
	$gofurther = int $q->param('from') - 1;
	push @bind, $q->param('from');
	$limit += 2;
	$reverse = 1;
} elsif ($q->param('to')) {
	$extra .= " AND upload_queue.id <= ? + 1";
	$gofurther = int $q->param('to') + 1;
	push @bind, $q->param('to');
	$limit += 2;
}

my @desc = $reverse ? (" DESC", "") : ("", " DESC"); 
my $order = join ", ", map { my $a = s/^-//; $a ? "$_$desc[1]" : "$_$desc[0]" } @order;

my $res;
$res = $dbi->selectall_arrayref("SELECT AVG(size), AVG(image_width)*AVG(image_height) FROM images WHERE image_type != 'html' AND image_width < 3000 AND image_height < 3000;");
our ($avgsize, $avgarea) = @{$res->[0]};

my $sth;
if ($by_image) {
	$sth = $dbi->prepare("SELECT images.id AS id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, image_type, image_height * image_width AS area, size, approved_tag.tag_id AS approved FROM images LEFT OUTER JOIN image_tags approved_tag ON approved_tag.image_id = images.id AND approved_tag.tag_id = 840$join WHERE $extra ORDER BY $order LIMIT $limit;");
} else {
	$sth = $dbi->prepare("SELECT images.id AS id, local_filename, local_thumbname, thumbnail_width, thumbnail_height, upload_queue.url, irc_lines.nick AS nick, irc_lines.channel AS chan, irc_lines.time AS time, image_type, image_height * image_width AS area, size, approved_tag.tag_id AS approved, upload_queue.id AS post_id FROM upload_queue LEFT OUTER JOIN image_postings ON image_postings.id = image_posting_id LEFT OUTER JOIN images ON images.id = image_postings.image_id INNER JOIN irc_lines ON irc_lines.id = upload_queue.line_id LEFT OUTER JOIN image_tags approved_tag ON approved_tag.image_id = images.id AND approved_tag.tag_id = 840$join WHERE attempted AND $extra ORDER BY $order LIMIT $limit;");
}

if (!$sth) {
	exit 0;
}
$sth->execute(@joinbind, @bind);

$res = [];
while(my $ref = $sth->fetchrow_hashref) {
	push @$res, $ref;
}

# Sort out the resulting data
my ($ismore_new, $ismore_old);
if ($gofurther && $res->[0]{post_id} == $gofurther) {
	shift @$res;
	$ismore_old = 1;
}
if (@$res > $count) {
	$res = [ @{$res}[0..$count] ];
	$ismore_new = 1;
}

do {
	no warnings;
	print join "\n", map { "$_->{post_id}\t$_->{id}\t$_->{image_type}\t$_->{local_thumbname}\t$_->{thumbnail_width}\t$_->{thumbnail_height}\t$_->{nick}\t".($_->{chan}?$_->{chan}:"privmsg")."\t$_->{url}\t".($_->{approved}?'approved':'')."\t$_->{area}\t$_->{size}" } @$res;
}

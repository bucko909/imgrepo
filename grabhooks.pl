use LWP::UserAgent;
use File::Temp qw/tempfile/;
use Image::Magick;
use strict;
use warnings;

our $images = "/home/repo/public_html/images";
our $thumbs = "/home/repo/public_html/thumbs";

sub deal_with_entry {
	my ($dbi) = shift;
	my $res = $dbi->selectall_arrayref("SELECT id, url, line_id FROM upload_queue ORDER BY id ASC LIMIT 1");
	if (!$res || !@$res) {
		return 0;
	}
	my ($id, $url, $line_id) = @{$res->[0]};
	$dbi->do("DELETE FROM upload_queue WHERE id = ?", {}, $id);

	my ($fh, $temp_file) = tempfile( DIR => "$ENV{HOME}/tempstor" );
	close $fh;
	my $ua = LWP::UserAgent->new(
		agent => "Bucko Repository Agent",
	);
	$ua->timeout(15);
	my $imgurl;
	my $referer_url;
	my $image_type = 'image';
	my $old_id;
	if ($url =~ m/^reget (\d+)(?::(\d+))?$/) {
		$old_id = $1;
		my $bits;
		if ($2) {
			$bits = $dbi->selectall_arrayref("SELECT url FROM image_postings WHERE image_id = ? AND line_id = ?", {}, $old_id, $2);
		} else {
			$bits = $dbi->selectall_arrayref("SELECT url FROM image_postings WHERE image_id = ?", {}, $old_id);
		}
		if (!@$bits) {
			print "Image did not exist/missing URL: $url\n";
			return 1;
		}
		print "Regetting ($url)\n";
		$url = $bits->[0][0];
	}
	if ($url eq 'reload') {
		print "Reloading.\n";
		do 'grabhooks.pl';
		return 1;
	} elsif ($url =~ m/^delete (\d+)$/) {
		my $image_id = $1;
		my $res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname FROM images WHERE images.id = ?", {}, $image_id);
		if (!$res || !@$res) {
			print "Bad image number $image_id.\n";
		} else {
			print "Deleting image number $image_id.\n";
			remove_image($dbi, @{$res->[0]});
			print "Done.\n";
			return 1;
		}
	} elsif ($url =~ m#^http://[^/]*abhor\.co\.uk/#i) {
		print "Ignoring self-referential URL $url.\n";
		return 1;
	} elsif ($url =~ m#^http://(?:www.)nicovideo.jp/watch/..(\d+)#) {
		$image_type = "nicovideo";
		$imgurl = "http://tn-skr2.smilevideo.jp/smile?i=$1";
	} elsif ($url =~ m#^http://(?:\w+.)?youtube.com/.*\bv=([^&]+)#) {
		$image_type = "youtube";
		my $vidid = $1;
		print "Mangling youtube for $url.\n";
		my $resp = $ua->get("http://www.youtube.com/results?search_query=$vidid",
			Referer => 'http://www.youtube.com/',
		);
		$referer_url = "http://www.youtube.com/results?search_query=$vidid";
		my $qvidid = quotemeta $vidid;
		if ($resp->content =~ m#(http://[^/]*.ytimg.com/vi/$qvidid/[^"]*)#) {
			$imgurl = $1;
			print "Youtube: Preview image seems to be at $imgurl\n";
		} else {
			print "Youtube: Failed to find preview for $url\n";
			return 1;
		}
	} elsif ($url =~ m#^http://rule34.paheal.net/#) {
		print "Mangling rule34 URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://rule34.paheal.net/',
		);
		$referer_url = $url;
		if ($resp->content =~ m#<img id='main_image' src='(.*?)'>#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			print $resp->content;
			return 1;
		}
	} elsif ($url =~ m#^http://img\.eternallybored\.org/img#) {
		print "Mangling eternallybored URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://img.eternallybored.org/',
		);
		$referer_url = $url;
		if ($resp->content =~ m#src='imgs/(.*?)'#) {
			$imgurl = "http://img.eternallybored.org/imgs/$1";
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			return 1;
		}
	} elsif ($url =~ m#^http://danbooru\.donmai\.us/post/show/#) {
		print "Mangling danbooru URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://danbooru.donmai.us/',
		);
		$referer_url = $url;
		if ($resp->content =~ m#src="(http://danbooru.donmai.us/data/sample/.*?)"# || $resp->content =~ m#src="(http://danbooru.donmai.us/data/(?!=preview).*?)"#) {
			$imgurl = $1;
			$imgurl =~ s|sample/sample-||;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www\.)?gelbooru.com/index.php.*page=post#) {
		print "Mangling gelbooru URL $url.\n";
		my $resp = $ua->get($url,
			Referer => "http://www.gelbooru.com/",
		);
		$referer_url = $url;
		if ($resp->content =~ m#src="(http://(?:.*?)gelbooru\.com/images/.*?)"#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			return 1;
		}
	} elsif ($url =~ m#^http://\S+\.pixiv.net/img/\S+/\d+\.\w+$#) {
		print "Setting pixiv referer for URL $url\n";
		$referer_url = "http://www.pixiv.net/member_illust.php";
		$imgurl = $url;
	} elsif ($url =~ m#http://www.pixiv.net/(?:member_illust|index).php\?mode=(?:medium|big)&illust_id=(\d+)#) {
		print "Mangling pixiv URL $url\n";
		my $resp = $ua->get($url,
			Referer => 'http://www.pixiv.net/',
		);
		$referer_url = $url;
		if ($resp->content =~ m#src="(http://\S+\.pixiv.net/img/\S+/\d+(?:_\w)?\.\w+)"#) {
			$imgurl = $1;
			$imgurl =~ s/_\w\././;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www.)motivatedphotos.com/#) {
		print "Mangling motivatedphotos URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://www.motivatedphotos.com/',
		);
		$referer_url = $url;
		if ($resp->content =~ m#src="(http://yarp\d*.motivatedphotos.com/autocdn/[^"]*(?<!-t2)\.jpg)"#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			return 1;
		}
	} else {
		$imgurl = $url;
		$referer_url = $url;
		$referer_url =~ s#/[^/]*$#/#;
	}
	# Image (we hope)

	$ua->max_size(25*1024*1024*1024); # 25 megs max size for now.

	my $resp;
	my $tries = 0;
	while ($tries++ < 5) {
		print "Get $imgurl.\n";
		$resp = $ua->get($imgurl,
			Referer => $referer_url,
			':content_file' => $temp_file,
		);
		if (!$resp->is_success) {
			print "$url failed to fetch: ".$resp->code.": ".$resp->message.".\n";
			if ($tries < 5) {
				print "Retrying in 5 secs.\n";
				sleep 5;
			}
		} else {
			last;
		}
	}
	if ($resp->is_success) {
		chmod 0644, $temp_file;
		open(SUM, "md5sum $temp_file|");
		my $sum = <SUM>;
		$sum =~ s/\s.*//s;
		close SUM;
		$res = $dbi->selectall_arrayref("SELECT id, local_filename FROM images WHERE md5sum=?", {}, $sum);
		my $count = @$res;
		if ($count) {
			# image may be duplicate; let's check.
			for (@$res) {
				my $img_oid = $_->[0];
				my $ofn = $_->[1];
				$ofn =~ s#^(.)(.)#$1/$2/$1$2#;

				# Ensure we don't stupidly collide when images are deleted.
				$_->[1] =~ /-(\d+)/;
				$count = $1 if $1 > $count;

				if (!system("diff", $temp_file, "$images/$ofn")) {
					print "$url is a duplicate of $ofn; skipping.\n";
					$dbi->do("INSERT INTO image_postings (image_id, line_id, url) VALUES (?, ?, ?)", {}, $img_oid, $line_id, $url);
					unlink($temp_file);
					return 1;
				}
			}
		}

		$count++;

		my $type = lc $resp->header('Content-Type');
		if ($imgurl =~ m#^http://.*/_images/.*\.(\w+)# && $type eq 'text/plain') {
			# HACK. Fuck you, R34.
			my $ext = lc $1;
			$ext = 'jpeg' if $ext eq 'jpg';
			$type = 'image/'.$ext;
		} else {
			print "$imgurl\n";
		}
		$type =~ s/;.*//;
		my $ext;
		if ($type !~ m#^image/#) {
			unless ($type =~ m#^text/(?:plain|html)# || $type =~ m#^application/xhtml\+xml#) {
				print "$url pointed to unknown MIME type $type.\n";
				unlink($temp_file);
				return 1;
			}
			# Not an image!
			unlink($temp_file);
			print "$url did not point to an image. Trying a capture.\n";
			system("rm", "-rf", "/home/repo/Desktop/");
			mkdir("/home/repo/Desktop");
			if (!fork) {
				$dbi->{InactiveDestroy} = 1;
				system("/home/repo/xvfb-ffcap", "firefox", "-saveimage", $url);
				exit;
			}
			my $fn;
			my $timer = 30;
			while(!$fn && $timer-- > 0) {
				sleep 1;
				$fn = </home/repo/Desktop/*.png>;
			}
			print "It's time for a killin'.\n";
			print "Image: $fn\n" if $fn;
			system("killall", "Xvfb");
			if ($fn) {
				# Success
				rename($fn,$temp_file);
				$ext = 'png';
			} else {
				return 1;
			}
			$image_type = "html";
		} elsif ($type eq 'image/bmp') {
			$ext = 'bmp';
		} elsif ($type eq 'image/gif') {
			$ext = 'gif';
		} elsif ($type eq 'image/jpeg') {
			$ext = 'jpeg';
		} elsif ($type eq 'image/svg+xml') {
			$ext = 'svg';
		} elsif ($type eq 'image/png') {
			$ext = 'png';
		} else {
			unlink($temp_file);
			print "$url pointed to unknown image type $type.\n";
			return 1;
		}

		my $fn = "$sum-$count.$ext";
		my $thumbfn = "$sum-$count.jpg";
		$fn =~ /^(.)(.)/;
		my ($d1, $d2) = ($1, $2);
		mkdir("$images/$d1");
		mkdir("$images/$d1/$d2");
		my $imagefile = "$images/$d1/$d2/$fn";
		rename($temp_file, $imagefile);

		my $image = Image::Magick->new;
		my ($width, $height, $size, $format) = $image->Ping($imagefile);
		if (!$width) {
			unlink($imagefile);
			print "$url pointed to badly formatted image.\n";
			return 1;
		}
		my ($pwidth, $pheight);
		mkdir("$thumbs/$d1");
		mkdir("$thumbs/$d1/$d2");
		if ($width <= $height / 1.5) {

			$pheight = $height < 150 ? $height : 150;
			$pwidth = $width < 150 ? $width : 150;
			# TODO upgrade PerlMagick so it can do this.
			system("convert", $imagefile.'[0]', "-thumbnail", $pwidth."x".$pheight."^", "-gravity", "North", "-extent", $pwidth."x".$pheight, "$thumbs/$d1/$d2/$thumbfn");
		} else {
			if ($width <= $height * 1.5) {
				$pheight = $height < 150 ? $height : 150;
				$pwidth = $width * ($pheight / $height);
			} else {
				$pwidth = $width < 225 ? $width : 225;
				$pheight = $height * ($pwidth / $width);
			}
			$image->Set('Size' => $pwidth.'x'.$pheight);
			if ($image->Read($imagefile)) {
				unlink($imagefile);
				print "$url\'s local filename could not be read.\n";
				return 1;
			}
			print "Length: ".scalar(@$image)."\n";
			if (@$image > 1) {
				print "Is animated (".@$image." frames).\n";
				$image = $image->[0];
				$image_type = 'animated';
			}
			if ($image->Thumbnail(width => $pwidth, height => $pheight)) {
				unlink($imagefile);
				print "$url could not be thumbnailed.\n";
				return 1;
			}
			$image->Write(filename => "$thumbs/$d1/$d2/$thumbfn", compress => 'JPEG');
		}
		my @s = stat("$thumbs/$d1/$d2/$thumbfn");
		my $thumbsize = $s[7];
		@s = stat($imagefile);
		my $imagesize = $s[7];
		$dbi->do("INSERT INTO images (local_filename, local_thumbname, md5sum, image_width, image_height, size, thumbnail_width, thumbnail_height, thumbnail_size, image_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", {}, $fn, $thumbfn, $sum, $width, $height, $imagesize, $pwidth, $pheight, $thumbsize, $image_type);
		my $image_id = $dbi->last_insert_id(undef, undef, undef, undef);
		if (!$old_id) {
			$dbi->do("INSERT INTO image_postings (image_id, line_id, url) VALUES (?, ?, ?)", {}, $image_id, $line_id, $url);
			print "$url successful (image number $image_id).\n";
			cull_images($dbi);
		} else {
			$dbi->do("INSERT INTO image_postings (image_id, line_id, url) SELECT ?, line_id, url FROM image_postings WHERE image_id = ?", {}, $image_id, $old_id);
			my $res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname FROM images WHERE images.id = ?", {}, $old_id);
			if (!$res || !@$res) {
				print "Bad image number $old_id (replaced with $image_id).\n";
			} else {
				print "Deleting image number $old_id (replaced with $image_id).\n";
				remove_image($dbi, @{$res->[0]});
			}
		}
		return 1;
	} else {
		unlink($temp_file);
		print "$url failed to fetch: ".$resp->code.": ".$resp->message."\n";
		return 1;
	}
}

sub cull_images {
	my ($dbi) = @_;
	my $total = $dbi->selectall_arrayref("SELECT SUM(thumbnail_size) + SUM(size) FROM images")->[0][0];
	printf("Total space used: %0.2fGiB\n", $total/1024/1024/1024);
	if ($total > 5 * 1024 * 1024 * 1024) {
		my $first_id = $dbi->selectall_arrayref("SELECT MAX(id) FROM images")->[0][0] - 2000;
		my $remain = $total - 5 * 1024*1024*1024;
		print "It's cullin' time ($remain bytes to go).\n";
		#my $sth = $dbi->prepare("SELECT images.id, size + thumbnail_size, local_filename, local_thumbname FROM images INNER JOIN image_tags ON images.id = image_tags.image_id INNER JOIN tags ON tags.id = image_tags.tag_id WHERE tags.name = 'delete_me' AND images.rating < 0");
		my $sth = $dbi->prepare("SELECT images.id, size + thumbnail_size, local_filename, local_thumbname FROM images LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND tdt.tag_id != 4 WHERE images.id < ? AND tdt.tag_id IS NULL AND images.rating <= 0 GROUP BY images.id ORDER BY (images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)");
		$sth->execute($first_id);
		my $row;
		my $removed = 0;
		while($remain > 0 && ($row = $sth->fetchrow_arrayref)) {
			$remain -= $row->[1];
			print "Cull $row->[0] ($row->[2]); $row->[1] bytes ($remain left).\n";
			remove_image($dbi, $row->[0], $row->[2], $row->[3]);
			$removed++;
		}
		print "Total images culled: $removed.\n";
		$sth->finish;
	}
}

sub remove_image {
	my ($dbi, $id, $if, $tf) = @_;
	$if =~ s[^(.)(.)][$1/$2/$1$2];
	$tf =~ s[^(.)(.)][$1/$2/$1$2];
	my $doit = 1;
	my $debug = 0;
	print qq|unlink("$images/$if");\n| if $debug;
	unlink("$images/$if") if $doit;
	print qq|unlink("$thumbs/$tf");\n| if $debug;
	unlink("$thumbs/$tf") if $doit;
	print qq|$dbi->do("DELETE FROM image_tags WHERE image_id = ?", {}, $id);\n| if $debug;
	$dbi->do("DELETE FROM image_tags WHERE image_id = ?", {}, $id) if $doit;
	print qq|$dbi->do("DELETE FROM image_postings WHERE image_id = ?", {}, $id);\n| if $debug;
	$dbi->do("DELETE FROM image_postings WHERE image_id = ?", {}, $id) if $doit;
	print qq|$dbi->do("DELETE FROM image_visits WHERE image_id = ?", {}, $id);\n| if $debug;
	$dbi->do("DELETE FROM image_visits WHERE image_id = ?", {}, $id) if $doit;
	print qq|$dbi->do("DELETE FROM rating_raters WHERE image_id = ?", {}, $id);\n| if $debug;
	$dbi->do("DELETE FROM rating_raters WHERE image_id = ?", {}, $id) if $doit;
	print qq|$dbi->do("DELETE FROM rating_ratings WHERE image_id = ?", {}, $id);\n| if $debug;
	$dbi->do("DELETE FROM rating_ratings WHERE image_id = ?", {}, $id) if $doit;
	print qq|$dbi->do("DELETE FROM images WHERE id = ?", {}, $id);\n| if $debug;
	$dbi->do("DELETE FROM images WHERE id = ?", {}, $id) if $doit;
}

1;

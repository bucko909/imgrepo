use LWP::UserAgent;
use File::Temp qw/tempfile/;
use Image::Magick;
use strict;
use warnings;

our $images = "/home/repo/public_html/images";
our $thumbs = "/home/repo/public_html/thumbs";

sub done {
	my ($dbi, $id, $ipid) = @_;
	print "DONE: My posting ID is $ipid.\n";
	$dbi->do("UPDATE upload_queue SET success = TRUE, image_posting_id = ? WHERE id = ?", {}, $ipid, $id);
	$dbi->commit or die "DB error: $!";
}

sub err {
	my ($dbi, $id, $reason) = @_;
	$dbi->do("UPDATE upload_queue SET success = FALSE, fail_reason = ? WHERE id = ?", {}, $reason, $id);
	$dbi->commit or die "DB error: $!";
}

sub deal_with_entry {
	my ($dbi) = shift;
	my $res = $dbi->selectall_arrayref("SELECT id, url, line_id FROM upload_queue WHERE NOT attempted ORDER BY id ASC LIMIT 1");
	if (!$res || !@$res) {
		return 0;
	}
	my ($upload_id, $url, $line_id) = @{$res->[0]};
	my $time = time();
	$dbi->do("UPDATE upload_queue SET attempted = TRUE WHERE id = ?", {}, $upload_id);
	$dbi->commit or die "DB error: $!";

	my ($fh, $temp_file) = tempfile( DIR => "$ENV{HOME}/tempstor" );
	close $fh;
	my $can_accept = 'identity'; #HTTP::Message::decodable;
	my $ua = LWP::UserAgent->new(
		agent => "Abhor Repository Agent",
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
			err($dbi, $upload_id, "Image did not exist");
			return 1;
		}
		print "Regetting ($url)\n";
		$url = $bits->[0][0];
	}
	if ($url eq 'reload') {
		print "Reloading.\n";
		do 'grabhooks.pl';
		done($dbi, $upload_id);
		return 1;
	} elsif ($url eq 'cull') {
		print "Culling.\n";
		&cull_images($dbi);
		done($dbi, $upload_id);
		return 1;
	} elsif ($url =~ m/^delete (\d+)$/) {
		my $image_id = $1;
		my $res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname FROM images WHERE images.id = ?", {}, $image_id);
		if (!$res || !@$res) {
			print "Bad image number $image_id.\n";
			err($dbi, $upload_id, "Bad image number");
		} else {
			print "Deleting image number $image_id.\n";
			remove_image($dbi, @{$res->[0]});
			print "Done.\n";
			done($dbi, $upload_id);
		}
		return 1;
	} elsif ($url =~ m/^local_move_in (.*?) (.*)/) {
		$url = $2;
		rename($1, $temp_file);
		print "Local upload of $2; renamed $1 -> $temp_file\n";
		$image_type = 'local';
	} elsif ($url =~ m#^http://[^/]*(?:abhor|disillusionment)\.co\.uk/.*i=(\d+)#i) {
		print "Self-referential URL $url to image $1.\n";
		$old_id = $1;
		my $res = $dbi->selectall_arrayref("SELECT id FROM images WHERE images.id = ?", {}, $old_id);
		if (!$res || !@$res) {
			print "Image doesn't exist.\n";
			err($dbi, $upload_id, "Image did not exist");
		} else {
			$res = $dbi->selectall_arrayref("INSERT INTO image_postings (image_id, line_id, url, time) VALUES (?, ?, ?, ?) RETURNING id", {}, $old_id, $line_id, $url, $time);
			done($dbi, $upload_id, $res->[0][0]);
		}
		return 1;
	} elsif ($url =~ m#^http://[^/]*(?:abhor|disillusionment)\.co\.uk/images/.*/([^/]*)#i) {
		print "Self-referential URL $url to image $1.\n";
		my $res = $dbi->selectall_arrayref("SELECT id FROM images WHERE local_filename = ?", {}, $1);
		if (!$res || !@$res) {
			print "Image doesn't exist.\n";
			err($dbi, $upload_id, "Image did not exist");
		} else {
			$res = $dbi->selectall_arrayref("INSERT INTO image_postings (image_id, line_id, url, time) VALUES (?, ?, ?, ?) RETURNING id", {}, $res->[0][0], $line_id, $url, $time);
			done($dbi, $upload_id, $res->[0][0]);
		}
		return 1;
	} elsif ($url =~ m#^http://[^/]*(?:abhor|disillusionment)\.co\.uk#i) {
		print "Unparseable self-referential URL $url.\n";
		err($dbi, $upload_id, "Could not parse");
		return 1;
	} elsif ($url =~ m#http://imgur.com/(?:r/(?:[^/]+/)?)?([^./]+)$#) {
		my $id = $1;
		print "Mangling imgur URL $url.\n";
		my $resp = $ua->get($url, 'Accept-Encoding' => $can_accept);
		if ($resp->decoded_content =~ m#<link rel="image_src" href="(http://i.imgur.com/$id\.[^./]+)" ?/># || $resp->decoded_content =~ m#<img src="(http://i.imgur.com/$id\.[^./]+)" /># || $resp->decoded_content =~ m#<link rel="image_src" href="(http://i.imgur.com/[^./]{4,}\.[^./]{2,4})" />#) {
			$referer_url = $url;
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			print $resp->decoded_content;
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www.)nicovideo.jp/watch/..(\d+)#) {
		$image_type = "nicovideo";
		$imgurl = "http://tn-skr2.smilevideo.jp/smile?i=$1";
	} elsif ($url =~ m#^https?://(?:(?:\w+\.)?youtube.com/.*\bv=|(?:w+\.)?youtu.be/)([^&]+)#) {
		$image_type = "youtube";
		my $vidid = $1;
		print "Mangling youtube for $url.\n";
		my $resp = $ua->get("http://www.youtube.com/results?search_query=\"$vidid\"",
			Referer => 'http://www.youtube.com/',
			'Accept-Encoding' => $can_accept
		);
		$referer_url = "http://www.youtube.com/results?search_query=\"$vidid\"";
		my $qvidid = quotemeta $vidid;
		if ($resp->decoded_content =~ m#((?:http:)?//[^/]*.ytimg.com/vi/$qvidid/[^"]*)#) {
			$imgurl = $1;
			if ($imgurl !~ /^http:/) {
				$imgurl ="http:$imgurl";
			}
			print "Youtube: Preview image seems to be at $imgurl\n";
		} else {
			print $resp->decoded_content;
			print "Youtube: Failed to find preview for $url\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://rule34.paheal.net/#) {
		print "Mangling rule34 URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://rule34.paheal.net/',
			'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#<img id='main_image' src='(.*?)'>#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			print $resp->decoded_content;
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://img\.eternallybored\.org/img#) {
		print "Mangling eternallybored URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://img.eternallybored.org/', 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#src='imgs/(.*?)'#) {
			$imgurl = "http://img.eternallybored.org/imgs/$1";
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://danbooru\.donmai\.us/post/show/#) {
		print "Mangling danbooru URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://danbooru.donmai.us/', 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#<a href="(http://[^/.]+.donmai.us/data/[^/]*)" id="highres"# || $resp->decoded_content =~ m#src="(http://(?:danbooru|hijiribe).donmai.us/data/sample/.*?)"# || $resp->decoded_content =~ m#src="(http://danbooru.donmai.us/data/(?!=preview).*?)"#) {
			$imgurl = $1;
			$imgurl =~ s|sample/sample-||;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			print $resp->decoded_content;
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www\.)?fukung.net/#) {
		print "Mangling fukung URL $url.\n";
		my $resp = $ua->get($url,
			Referer => "http://fukung.net/", 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#src="(http://media.fukung.net/images/[^"]+)"#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www\.)?moid.org/banme#) {
		print "Fail url $url.\n";
		err($dbi, $upload_id, "Moid just didn't work for some reason");
		return 1;
	} elsif ($url =~ m#^http://(?:www\.)?moid.org/ed/#) {
		print "Mangling moid URL $url.\n";
		my $resp = $ua->get($url,
			Referer => "http://www.moid.org/", 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#src="(/ed/images/.*?)"#) {
			$imgurl = "http://www.moid.org$1";
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www\.)?gelbooru.com/index.php.*page=post#) {
		print "Mangling gelbooru URL $url.\n";
		my $resp = $ua->get($url,
			Referer => "http://www.gelbooru.com/", 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#src="(http://(?:.*?)gelbooru\.com/+images/+.*?)"#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://\S+\.pixiv.net/img/\S+/\d+\.\w+$#) {
		print "Setting pixiv referer for URL $url\n";
		$referer_url = "http://www.pixiv.net/member_illust.php";
		$imgurl = $url;
	} elsif ($url =~ m#http://www.pixiv.net/(?:member_illust|index).php\?mode=(?:medium|big)&illust_id=(\d+)#) {
		print "Mangling pixiv URL $url\n";
		my $resp = $ua->get($url,
			Referer => 'http://www.pixiv.net/', 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#src="(http://\S+\.pixiv.net/img/\S+/\d+(?:_\w)?\.\w+)"#) {
			$imgurl = $1;
			$imgurl =~ s/_\w\././;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} elsif ($url =~ m#^http://(?:www.)motivatedphotos.com/#) {
		print "Mangling motivatedphotos URL $url.\n";
		my $resp = $ua->get($url,
			Referer => 'http://www.motivatedphotos.com/', 'Accept-Encoding' => $can_accept
		);
		$referer_url = $url;
		if ($resp->decoded_content =~ m#src="(http://yarp\d*.motivatedphotos.com/autocdn/[^"]*(?<!-t2)\.jpg)"#) {
			$imgurl = $1;
			print "OK; I think I need $imgurl.\n";
		} else {
			print "Parse failure.\n";
			err($dbi, $upload_id, "Could not parse");
			return 1;
		}
	} else {
		$imgurl = $url;
		$referer_url = $url;
		$referer_url =~ s/\/[^\/]*$/\//;
	}
	# Image (we hope)

	my $resp;
	if ($image_type ne 'local') {
		$ua->max_size(25*1024*1024*1024); # 25 megs max size for now.

		my $tries = 0;
		while ($tries++ < 5) {
			print "Get $imgurl.\n";
			$resp = $ua->get($imgurl,
				Referer => $referer_url,
				':content_file' => $temp_file, 'Accept-Encoding' => $can_accept
			);
			if (!$resp->is_success && (!$resp->header('Content-Length') || $resp->header('Content-Length') == (stat($temp_file))[7])) {
				print "$url failed to fetch: ".$resp->code.": ".$resp->message.".\n";
				if ($tries < 5) {
					print "Retrying in 5 secs.\n";
					sleep 5;
				}
			} else {
				if ($resp->header('Content-Encoding') eq 'gzip') {
					print "gzip encoded; trying to decompress\n";
					if (!rename($temp_file, "$temp_file.gz")) {
						print "Failed! $!\n";
						next
					}
					if (system(gunzip => "$temp_file.gz")) {
						system(ls => -l => $temp_file => "$temp_file.gz");
						next;
					}
				}
				last;
			}
		}
		print "Size: ".$resp->header('Content-Length')."\n";
	} else {
		print "Local upload; skipping fetch phase.\n";
	}
	if ($image_type eq 'local' || $resp->is_success) {
		chmod 0644, $temp_file;
		open(SUM, "md5sum $temp_file|");
		my $sum = <SUM>;
		$sum =~ s/\s.*//s;
		close SUM;
		$res = $dbi->selectall_arrayref("SELECT id, local_filename, local_thumbname FROM images WHERE md5sum=?", {}, $sum);
		my $count = @$res;
		if ($count) {
			# image may be duplicate; let's check.
			for (@$res) {
				my $img_oid = $_->[0];
				my $ofn = $_->[1];
				my $tfb = $_->[2];
				$ofn =~ s#^(.)(.)#$1/$2/$1$2#;

				# Ensure we don't stupidly collide when images are deleted.
				$_->[1] =~ /-(\d+)/;
				$count = $1 if $1 > $count;

				# Assuming missing files match, for now.
				if ((! -e "$images/$ofn") || !system("diff", $temp_file, "$images/$ofn")) {
					if ($img_oid == 72350) {
						print "$url is imgur broken link.\n";
						err($dbi, $upload_id, "Imgur broken link");
						return 1;
					}
					print "$url is a duplicate of $ofn ($img_oid).\n";
					if ($old_id) {
						if ($old_id != $img_oid) {
							print "Massaging database.\n";
							$dbi->do("UPDATE image_postings SET image_id = ? WHERE image_id = ?", {}, $img_oid, $old_id);
							$dbi->do("UPDATE image_tags SET image_id = ? WHERE image_id = ?", {}, $img_oid, $old_id);
							$dbi->do("UPDATE image_visits SET image_id = ? WHERE image_id = ?", {}, $img_oid, $old_id);
							$dbi->do("UPDATE rating_raters SET image_id = ? WHERE image_id = ?", {}, $img_oid, $old_id);
							$dbi->do("UPDATE rating_ratings SET image_id = ? WHERE image_id = ?", {}, $img_oid, $old_id);;
							$res = $dbi->selectall_arrayref("SELECT local_filename, local_thumbname FROM images WHERE id=?", {}, $old_id);
							my ($img_file, $thumb_file) = @{$res->[0]};
							remove_image($dbi, $old_id, $img_file, $thumb_file);
						}
					} else {
						$res = $dbi->selectall_arrayref("INSERT INTO image_postings (image_id, line_id, url, time) VALUES (?, ?, ?, ?) RETURNING id", {}, $img_oid, $line_id, $url, $time);
					}
					$dbi->commit or die "DB error: $!";
					unlink($temp_file);
					print "New ID is $res->[0][0]\n";
					done($dbi, $upload_id, $res->[0][0]);
					return 1;
				}
			}
		}

		$count++;

		my $type;
		if ($image_type eq 'local') {
			if ($url =~ /jpe?g(?:_.*)?$/i) {
				$type = 'image/jpeg';
			} elsif ($url =~ /bmp$/) {
				$type = 'image/bmp';
			} elsif ($url =~ /gif$/) {
				$type = 'image/gif';
			} elsif ($url =~ /svg$/) {
				$type = 'image/svg+xml';
			} elsif ($url =~ /png$/) {
				$type = 'image/png';
			} else {
				$type = ''; # ???
			}
		} else {
			$type = lc $resp->header('Content-Type');
		}
		if ($type eq 'text/plain' && $imgurl =~ m#^http://.*/_images/.*\.(\w+)#) {
			# HACK. Fuck you, R34.
			my $ext = lc $1;
			$ext = 'jpeg' if $ext eq 'jpg';
			$type = 'image/'.$ext;
		} elsif ($url =~ /imgur.*\.(jpg|png|gif)/ and $type eq 'binary/octet-stream') {
			my $ext = lc $1;
			$ext = 'jpeg' if $ext eq 'jpg';
			$type = 'image/'.$ext;
		} elsif ($imgurl) {
			print "$imgurl\n";
		}
		$type =~ s/;.*//;
		my $ext;
		if ($type !~ m#^image/# && $type ne 'video/webm') {
			unless ($type =~ m#^text/(?:plain|html)# || $type =~ m#^application/xhtml\+xml#) {
				print "$url pointed to unknown MIME type $type.\n";
				unlink($temp_file);
				err($dbi, $upload_id, "Unknown MIME type");
				return 1;
			}
			# Not an image!
			unlink($temp_file);
			print "$url did not point to an image. Trying a capture.\n";
			mkdir("/home/repo/Desktop");
			system('grab-url' => $url);
			my $fn = '/tmp/repo-out.png';
			if(-e $fn) {
				# Success
				if (system(mv => -f => $fn => $temp_file)) {
					err($dbi, $upload_id, "Couldn't rename temp file: $!");
					return 1;
				}
				$ext = 'png';
			} else {
				err($dbi, $upload_id, "Grab failed to produce any output image");
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
		} elsif ($type eq 'video/webm') {
			$image_type = 'webm';
			$ext = 'webm';
		} else {
			unlink($temp_file);
			print "$url pointed to unknown image type $type.\n";
			err($dbi, $upload_id, "Unknown type");
			return 1;
		}

		my $fn = "$sum-$count.$ext";
		my $thumbfn = "$sum-$count.jpg";
		$fn =~ /^(.)(.)/;
		my ($d1, $d2) = ($1, $2);
		mkdir("$images/$d1");
		mkdir("$images/$d1/$d2");
		my $imagefile = "$images/$d1/$d2/$fn";
		if (!rename($temp_file, $imagefile)) {
			print "Failed to rename $temp_file -> $imagefile: $!\n";
			err($dbi, $upload_id, "Failed to rename: $!");
			unlink($temp_file);
			unlink($imagefile);
			return 1;
		}

		my $image = Image::Magick->new;
		$image->Set('disk-limit' => '0MiB');
		$image->Set('memory-limit' => '100MiB');
		$image->Set('map-limit' => '10MiB');
		my $previewfile;
		if ($image_type eq 'webm') {
			print "webm preview via mplayer...\n";
			if (system("mplayer",
				-frames => 1,
				-vo => "jpeg",
				$imagefile)) {
				print "mplayer failed to start.\n";
				err($dbi, $upload_id, "No mplayer?");
				return 1;
			}
			if (! -e "00000001.jpg") {
				print "mplayer preview fail.\n";
				err($dbi, $upload_id, "No mplayer frame preview");
				return 1;
			}
			$previewfile = "00000001.jpg";
		} else {
			$previewfile = $imagefile;
		}
		my ($width, $height, $size, $format) = $image->Ping($previewfile);
		if (!$width) {
			unlink($imagefile);
			print "$url pointed to badly formatted image.\n";
			err($dbi, $upload_id, "Dodgy image");
			return 1;
		}
		print "Dimensions: $width*$height\n";
		if ($width > 15000 || $height > 50000) {
			unlink($imagefile);
			print "$url pointed to huge image.\n";
			err($dbi, $upload_id, "Huge image");
			return 1;
		}
		my ($pwidth, $pheight);
		mkdir("$thumbs/$d1");
		mkdir("$thumbs/$d1/$d2");
		if ($width <= $height / 1.5) {
			$pheight = $height < 150 ? $height : 150;
			$pwidth = $width < 150 ? $width : 150;
			# TODO upgrade PerlMagick so it can do this.
			system("convert",
				$previewfile.'[0]',
				-limit => disk => '200MiB',
				-limit => memory => '200MiB',
				-limit => map => '100MiB',
				-cache => 1000000,
				-depth => 16,
				-gamma => 0.4545454545,
				-thumbnail => $pwidth."x".$pheight."^",
				-gravity => "North",
				-extent => $pwidth."x".$pheight,
				-gamma => 2.2,
				-depth => 8,
				"$thumbs/$d1/$d2/$thumbfn");
		} else {
			if ($width <= $height * 1.5) {
				$pheight = $height < 150 ? $height : 150;
				$pwidth = int($width * ($pheight / $height));
			} else {
				$pwidth = $width < 225 ? $width : 225;
				$pheight = int($height * ($pwidth / $width));
			}
			$image->Set('Size' => $pwidth.'x'.$pheight);
			my $err;
			if ($err = $image->Read($previewfile)) {
				unlink($imagefile);
				print "$url\'s local filename $imagefile could not be read: $err\n";
				err($dbi, $upload_id, "Read error ($err)");
				return 1;
			}
			$image->Gamma('gamma' => 0.4545454545);
			print "Length: ".scalar(@$image)."\n";
			if (@$image > 1) {
				print "Is animated (".@$image." frames).\n";
				$image = $image->[0];
				$image_type = 'animated';
			}
			if ($image->Thumbnail(width => $pwidth, height => $pheight)) {
				unlink($imagefile);
				print "$url could not be thumbnailed.\n";
				err($dbi, $upload_id, "Could not thumbnail");
				return 1;
			}
			$image->Gamma('gamma' => 2.2);
			$image->Set('Depth' => 8);
			$image->Write(filename => "$thumbs/$d1/$d2/$thumbfn", compress => 'JPEG');
		}
		my @s = stat("$thumbs/$d1/$d2/$thumbfn");
		my $thumbsize = $s[7];
		@s = stat($imagefile);
		my $imagesize = $s[7];
		my $sth = $dbi->prepare("INSERT INTO images (local_filename, local_thumbname, md5sum, image_width, image_height, size, thumbnail_width, thumbnail_height, thumbnail_size, image_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) returning id");
		$sth->execute($fn, $thumbfn, $sum, $width, $height, $imagesize, $pwidth, $pheight, $thumbsize, $image_type);
		my $image_id = $sth->fetchall_arrayref()->[0][0];
		if (!$old_id) {
			$res = $dbi->selectall_arrayref("INSERT INTO image_postings (image_id, line_id, url, time) VALUES (?, ?, ?, ?) RETURNING id", {}, $image_id, $line_id, $url, $time);
			print "$url successful (image number $image_id).\n";
			cull_images($dbi);
		} else {
			my $res = $dbi->selectall_arrayref("SELECT images.id, local_filename, local_thumbname FROM images WHERE images.id = ?", {}, $old_id);
			if (!$res || !@$res) {
				print "Bad image number $old_id (replaced with $image_id).\n";
			} else {
				$dbi->do("UPDATE image_postings SET image_id = ? WHERE image_id = ?", {}, $image_id, $old_id);
				$dbi->do("UPDATE image_tags SET image_id = ? WHERE image_id = ?", {}, $image_id, $old_id);
				$dbi->do("UPDATE image_visits SET image_id = ? WHERE image_id = ?", {}, $image_id, $old_id);
				$dbi->do("UPDATE rating_raters SET image_id = ? WHERE image_id = ?", {}, $image_id, $old_id);
				$dbi->do("UPDATE rating_ratings SET image_id = ? WHERE image_id = ?", {}, $image_id, $old_id);;
				print "Deleting image number $old_id (replaced with $image_id).\n";
				remove_image($dbi, @{$res->[0]});
			}
		}
		done($dbi, $upload_id, $res->[0][0]);
		return 1;
	} else {
		unlink($temp_file);
		print "$url failed to fetch: ".$resp->code.": ".$resp->message."\n";
		err($dbi, $upload_id, "Could not fetch: ".$resp->code.": ".$resp->message);
		return 1;
	}
}

sub cull_images {
	my ($dbi) = @_;
	my $total = $dbi->selectall_arrayref("SELECT SUM(thumbnail_size) + SUM(size) FROM images WHERE NOT on_s3")->[0][0];
	printf("Total space used: %0.2fGiB\n", $total/1024/1024/1024);
	if ($total > 50 * 1024 * 1024 * 1024) {
		my $first_id = $dbi->selectall_arrayref("SELECT MAX(id) FROM images")->[0][0];
		#my $first_id = $dbi->selectall_arrayref("SELECT MAX(image_id) FROM image_tags INNER JOIN tags ON tags.id = image_tags.tag_id WHERE tags.name = 'approved'")->[0][0];
		my $remain = $total - 5 * 1024*1024*1024;
		print "It's cullin' time ($remain bytes to go).\n";
		print "Tag cutoff is $first_id.\n";
		#my $sth = $dbi->prepare("SELECT images.id, size + thumbnail_size, local_filename, local_thumbname FROM images INNER JOIN image_tags ON images.id = image_tags.image_id INNER JOIN tags ON tags.id = image_tags.tag_id WHERE tags.name = 'delete_me' AND images.rating < 0");
		my $sth = $dbi->prepare("SELECT images.id, size, thumbnail_size, local_filename, local_thumbname FROM images LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND tdt.tag_id != 4 WHERE images.id < ? AND tdt.tag_id IS NULL AND images.rating <= 0 AND NOT on_s3 GROUP BY images.id ORDER BY (images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)");
		#my $sth = $dbi->prepare("SELECT images.id, size, thumbnail_size, local_filename, local_thumbname FROM images LEFT OUTER JOIN image_tags tdt ON tdt.image_id = images.id AND tdt.tag_id != 4 WHERE images.id < ? AND tdt.tag_id IS NULL AND images.rating <= 0 AND NOT on_s3 GROUP BY images.id ORDER BY (images.id + images.rating*10000 + images.fullviews*1000)/(images.thumbnail_size + images.size)");
		$sth->execute($first_id);
		my $row;
		my $removed = 0;
		while($remain > 0 && ($row = $sth->fetchrow_arrayref)) {
			print "Cull $row->[0] ($row->[3]); $row->[1] bytes ($remain left).\n";
			if (system(to_s3 => $row->[0]) == 0) {
				print "Sent to S3\n";
				$remain -= $row->[1];
			} else {
				print "S3 sync failed\n";
				die "S3 failed";
				#remove_image($dbi, $row->[0], $row->[3], $row->[4]);
				#$remain -= $row->[1];
			}
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

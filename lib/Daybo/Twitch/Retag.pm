#!/usr/bin/perl
#
# This program will walk through the directory structure from the current working
# directory and it will write out ID3 tags into any MPEG II layer III files which
# are found in both ID3v1 and ID3v2 formats.
#
# The names are based on a directory structure which looks like this:
# ./artist/album/track.mp3
#
# If you use any other classification, do not use this program or make adjustments
# to the code first.  I shall attempt to be ignorant to all files which do not
# meet this exact criteria.  I shall not modify them.  The files which I do find
# will have their existing tags completely _REPLACED_.  Please back up your music
# before running this script.  As I have limited information on which to base
# my tag data, some information may be inaccurate.  Garbage in, garbage out.
# ... and with that... good luck >=)
#
# Written by Palmer of XXXXXXXX.com Ltd
#

package Daybo::Twitch::Retag;
use Moose;
use MP3::Tag;
#----------------------------------------------------------------------------
sub run {
	my ($self, $dirname) = @_;
	my $filename;
	local *dirHandle;

	if (!opendir(dirHandle, $dirname)) {
		print "Can\'t open $dirname, ignoring\n";
		return 0;
	}

	while ($filename = readdir(dirHandle)) {
		next if ($filename eq '.' || $filename eq '..');
		if (-d ($dirname . '/' . $filename)) {
			print "chdir $dirname/$filename\n";
			$self->run($dirname . '/' . $filename);
		} else {
			if (open(FILEHANDLE, '<' . $dirname . '/' . $filename)) {
				my $ext;

				$ext = GetExt($filename);
				close(FILEHANDLE);

				if (IsMp3($ext)) {
					if (CountPath($dirname) == 3) {
						print "Tagging $dirname/$filename\n";
						Tag(
							"$dirname/$filename",
							GetArtist($dirname),
							GetAlbum($dirname),
							GetTrack($filename)
						);
						print "\n";
					}
				}
			}
		}
	}

	closedir(dirHandle);
	return 0;
}
#----------------------------------------------------------------------------
sub usage {
	print("twitch-tag-mp3.pl <base_dir>\n\n");
	print("See README for more information, or https://hg.sr.ht/~m6kvm/twitch-tag-mp3\n");
	return 1;
}
#----------------------------------------------------------------------------
sub IsMp3 {
	my $ext = $_[0];
	return 1 if (lc($ext) eq 'mp3');
	return 0;
}
#----------------------------------------------------------------------------
sub GetExt {
	my $fn = $_[0];
	my @arr;
	my $ext;

	@arr = split(m/\./, $fn);
	$ext = $arr[scalar(@arr)-1];
	return undef if ($fn eq $ext);
	return $ext;
}
#----------------------------------------------------------------------------
sub CountPath {
	my $pathstr = $_[0];
	my @comps;
	my $count = 0;

	@comps = split('/', $pathstr);
	foreach ( @comps ) {
		$count++;
	}

	return $count;
}
#----------------------------------------------------------------------------
sub Tag {
	my $file = $_[0];
	my $artist = $_[1];
	my $album = $_[2];
	my $track = $_[3];
	my $mp3;

	$mp3 = MP3::Tag->new($file);
	$mp3->get_tags();
	$mp3->{ID3v1}->remove_tag() if ( exists $mp3->{ID3v1} );
	$mp3->{ID3v2}->remove_tag() if ( exists $mp3->{ID3v2} );
	$mp3->new_tag("ID3v1");
	$mp3->new_tag("ID3v2");
	$mp3->{ID3v1}->all(
		$track,
		$artist,
		$album,
		"2007",
		"Restored music information",
		0,
		0
	);

	$mp3->{ID3v1}->write_tag();
	$mp3->{ID3v2}->add_frame("TIT2", 0, $track);
	$mp3->{ID3v2}->add_frame("TALB", 0, $album);
	$mp3->{ID3v2}->add_frame("TPE1", 0, $artist);

	$mp3->{ID3v2}->add_frame(
		"COMM",
		"ENG",
		"Short text",
		"Restored music information (may be inaccurate)"
	);

	if ( !$mp3->{ID3v1}->write_tag() ) {
		#print "Error tagging $filename (ID3v1): $!";
	}
	if ( !$mp3->{ID3v2}->write_tag() ) {
		#print "Error tagging $filename (ID3v2): $!";
	}
}
#----------------------------------------------------------------------------
sub GetArtist($)
{
	$_ = $_[0];
	s:^\./::;
	s/\/.*$//;
	return $_;
}
#----------------------------------------------------------------------------
sub GetAlbum($)
{
	$_ = $_[0];
	s/^.*\///;
	return $_;
}
#----------------------------------------------------------------------------
sub GetTrack($)
{
	$_ = $_[0];
	s/.mp3$//;
	return $_;
}
#----------------------------------------------------------------------------
1;

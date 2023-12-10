#!/usr/bin/perl
# Twitch MP3 tagger.
# Copyright (c) 2023, Rev. Duncan Ross Palmer (2E0EOL)
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
#     * Neither the name of the the maintainer, nor the names of its contributors
#       may be used to endorse or promote products derived from this software
#       without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package Daybo::Twitch::Retag;
use Moose;
use MP3::Tag;

our $VERSION = '0.2.0';
our $URL = 'https://hg.sr.ht/~m6kvm/twitch-tag-mp3';
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
		my $relPath = $dirname . '/' . $filename;
		if (-d $relPath) {
			if (acceptableDirName($filename)) {
				print "chdir $relPath\n";
				$self->run($relPath);
			}
		} else {
			if (open(FILEHANDLE, '<' . $relPath)) {
				my $ext;

				$ext = GetExt($filename);
				close(FILEHANDLE);

				if (IsMp3($ext)) {
					print "Tagging $relPath\n";
					Tag(
						$relPath,
						parseFileName($filename),
					);
				}
			}
		}
	}

	closedir(dirHandle);
	return 0;
}
#----------------------------------------------------------------------------
sub usage {
	printf("twitch-tag-mp3 %s usage:\n", $VERSION);
	print("twitch-tag-mp3.pl <base_dir>\n\n");
	print("See README for more information, or $URL\n");
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
sub Tag {
	my ($file, $artist, $album, $track, $year) = @_;

	my $mp3 = MP3::Tag->new($file);
	$mp3->get_tags();
	$mp3->{ID3v1}->remove_tag() if (exists $mp3->{ID3v1});
	$mp3->{ID3v2}->remove_tag() if (exists $mp3->{ID3v2});
	$mp3->new_tag("ID3v1");
	$mp3->new_tag("ID3v2");
	warn "artist: $artist, album: $album, track: $track, year: $year"; # TODO: Proper logger, at trace level or debug
	$mp3->{ID3v1}->all(
		$track,
		$artist,
		$album,
		$year,
		'Generated by twitch-tag-mp3',
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
		"Generated by twitch-tag-mp3 $VERSION - $URL",
	);

	if ( !$mp3->{ID3v1}->write_tag() ) {
		print "Error tagging $file (ID3v1): $!";
	}
	if ( !$mp3->{ID3v2}->write_tag() ) {
		print "Error tagging $file (ID3v2): $!";
	}

	return;
}
#----------------------------------------------------------------------------
sub parseFileName {
	# Example: '1stdegreeproductions (live) 2021-10-18 11_05-40110166187.mp3'
	my ($filename) = @_;
	if ($filename =~ m/^(\w+)\s\(\w+\)\s(\d{4})-\d{2}-\d{2}.*/) {
		my ($artist, $album, $track, $year) = ($1, undef, undef, $2);

		$track = $filename;
		$track =~ s/\.mp3$//;
		$track =~ s/-trim//;
		$track =~ s/-tempo//;
		$track =~ s/-untempo//;

		$artist =~ s/Official//gi;
		$artist =~ s/Music//gi;
		$artist = 'Raymond Doyle' if ($artist eq 'CarteBlanche88');
		$artist = 'Taucher' if (lc($artist) eq 'taucher66');
		$artist = 'Kristina Sky' if ($artist eq 'TheRealKristinaSky');
		$artist = 'Edit' if ($artist eq 'The_Real_DJ_Edit' || $artist eq 'TheReal_DJEdit');
		$artist = 'Vlastimil' if ($artist eq 'VlastimilVibes');
		$artist =~ s/dj//i;
		$artist =~ s/_/ /g;
		$artist =~ s/\s*$//;
		$artist =~ s/^\s*//;

		$album = "${artist} on Twitch";

		return ($artist, $album, $track, $year);
	}

	die("Cannot parse filename structure: '$filename'");
}
#----------------------------------------------------------------------------
sub acceptableDirName {
	my ($dirName) = @_;
	return 0 if ($dirName eq '@eaDir');
	return 1;
}
#----------------------------------------------------------------------------
1;

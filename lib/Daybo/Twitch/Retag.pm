#!/usr/bin/perl

# Twitch MP3 tagger.
# Copyright (c) 2022, Duncan Ross Palmer (M6KVM)
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

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
sub Tag {
	my $file = $_[0];
	my $artist = $_[1];
	my $album = $_[2];
	my $track = $_[3];
	my $mp3;

	$mp3 = MP3::Tag->new($file);
	$mp3->get_tags();
	$mp3->{ID3v1}->remove_tag() if (exists $mp3->{ID3v1});
	$mp3->{ID3v2}->remove_tag() if (exists $mp3->{ID3v2});
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
		print "Error tagging $file (ID3v1): $!";
	}
	if ( !$mp3->{ID3v2}->write_tag() ) {
		print "Error tagging $file (ID3v2): $!";
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

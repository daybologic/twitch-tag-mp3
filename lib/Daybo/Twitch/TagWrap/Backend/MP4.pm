# Twitch MP3 tagger.
# Copyright (c) 2023-2026, Rev. Duncan Ross Palmer (2E0EOL)
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

package Daybo::Twitch::TagWrap::Backend::MP4;
use Moose;

extends 'Daybo::Twitch::TagWrap::Backend';

use English qw(-no_match_vars);
use File::Basename qw(dirname);
use File::Copy qw(move);
use File::Temp qw(tempfile);
use JSON::PP qw(decode_json);

=item C<readTags($file)>

Given C<$file>, runs C<ffprobe> over it and returns the tags as a hash ref,
or C<undef> if no tags are present.  The C<date> key is normalised to
C<year> and C<title> to C<track> to match the common tag interface.

=cut

sub readTags {
	my ($self, $file) = @_;

	my $json;
	{
		my @cmd = ('ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', '-show_streams', $file);
		open(my $fh, '-|', @cmd) or return;
		local $INPUT_RECORD_SEPARATOR = undef;
		$json = <$fh>;
		close($fh) or die("close failed: $ERRNO");
	}

	my $data = decode_json($json);
	my $tags = $data->{format}{tags} || {};

	if ($tags->{date}) {
		$tags->{year} = delete($tags->{date});
	}

	if ($tags->{title}) {
		$tags->{track} = delete($tags->{title});
	}

	return ($tags && scalar(keys(%$tags)) > 0) ? $tags : undef;
}

=item C<deleteTags($file)>

No-op for MP4 files; tag removal is handled implicitly by C<writeTags>
via C<ffmpeg>'s metadata overwrite behaviour.

=cut

sub deleteTags {
	# no-op
}

=item C<writeTags($file, $artist, $album, $track, $year, $comment)>

Write metadata tags to the given MP4 file using C<ffmpeg>.  A temporary
file is created in the same directory as C<$file> and atomically moved
over it on success.  Dies if C<ffmpeg> exits non-zero or the move fails.
No return value.

=cut

sub writeTags {
	my ($self, $file, $artist, $album, $track, $year, $comment) = @_;

	my $dir = dirname($file);

	# Create temp file in same directory
	my ($fh, $temp) = tempfile(
		'.twitch-tag-ffmpeg.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
		SUFFIX => '.mp4.tmp',
		DIR    => $dir,
		UNLINK => 0,   # we’ll manage cleanup
	);
	close($fh);

	my $exitCode = $self->_system('ffmpeg',
		'-nostdin',
		'-y',
		'-i', $file,
		'-c', 'copy',
		'-movflags', '+faststart',
		'-f', 'mp4',
		'-metadata', "artist=$artist",
		'-metadata', "album=$album",
		'-metadata', "date=$year",
		'-metadata', "title=$track",
		'-metadata', "comment=$comment",
		$temp,
	);

	if ($exitCode != 0) {
		unlink($temp);
		die("ffmpeg failed for '$file'");
	}

	# Atomic replace
	move($temp, $file)
	    or die("Failed to move '$temp' to '$file': $ERRNO");

	return;
}

1;

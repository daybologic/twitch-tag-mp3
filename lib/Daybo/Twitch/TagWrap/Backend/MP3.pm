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

package Daybo::Twitch::TagWrap::Backend::MP3;
use Moose;

extends 'Daybo::Twitch::TagWrap::Backend';

use English qw(-no_match_vars);
use File::Spec;

=item C<readTags($file)>

Given C<$file>, we will run C<id3v2> over it and collect the tags.
We might return C<undef>.  There may be no tags.  Only recognized tags are
returned.  These are the tags:

=over

=item *

artist

=item *

album

=item *

track

=item *

year

=item *

comment

=back

=cut

sub readTags {
	my ($self, $file) = @_;

	return unless (open(my $fh, '-|', 'id3v2', '-l', $file));

	my %tags;
	while (my $line = <$fh>) {
		chomp($line);
		__parseTag(\%tags, $line);
	}
	$fh->close();

	return %tags ? \%tags : undef;
}

=item C<deleteTags($file)>

Call this method to remove all of the ID3 tags in an MP3 file.
There is no return value.

=cut

sub deleteTags {
	my ($self, $file) = @_;
	$self->_system('id3v2', '--delete-all', $file);
	return;
}

=item C<writeTags($file, $artist, $album, $track, $year, $comment)>

Write the ID3 tags to the given filename.
No return value.

=cut

sub writeTags {
	my ($self, $file, $artist, $album, $track, $year, $comment) = @_;
	$self->_system(
		'id3v2',
		'--artist', $artist,
		'--album',  $album,
		'--song',   $track,
		'--year',   $year,
		'--comment', $comment,
		$file,
	);
	return;
}

=item C<__parseTag($tags, $line)>

Given a hash ref C<$tags> and a single line of C<id3v2 -l> output,
attempts to match the line against each known field parser and, on a
match, populates C<$tags> with the extracted value.  No return value.

=cut

my %__parsers = ( );
sub __parseTag {
	my ($tags, $line) = @_;

	__initParsers() if (0 == scalar(keys(%__parsers)));

	while (my ($fieldName, $rx) = each(%__parsers)) {
		next if ($line !~ $rx);
		$tags->{$fieldName} = $1;
		last;
	}

	return;
}

=item C<__initParsers()>

Populates C<%__parsers> with the per-field regular expressions used by
C<__parseTag>.  Called lazily the first time C<__parseTag> is invoked.
No return value.

=cut

sub __initParsers {
	%__parsers = (
		artist => qr/^TPE1[^:]+:\s*(.+)$/,
		album => qr/^TALB[^:]+:\s*(.+)$/,
		track => qr/^TIT2[^:]+:\s*(.+)$/,
		year => qr/^TYER[^:]+:\s*(.+)$/,
		comment => qr/^COMM[^:]+:\s*(?:\([^)]*\)\[[^\]]*\]:\s*)?(.+)$/,
	);

	return;
}

1;

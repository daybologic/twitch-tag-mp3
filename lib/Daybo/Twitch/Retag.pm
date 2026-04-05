#!/usr/bin/perl
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

package Daybo::Twitch::Retag;
use English qw(-no_match_vars);
use IO::Dir;
use IO::File;
use JSON::PP qw(encode_json);
use Time::HiRes qw(time);
use Moose;
use POSIX qw(EXIT_FAILURE EXIT_SUCCESS);
use Daybo::Twitch::TagWrap;

our $VERSION = '0.7.0';

our $URL = 'github.com/daybologic/twitch-tag-mp3';

has jobs => (is => 'ro', isa => 'Int',  default => 1);

has [qw(force json noop recursive verbose)]
    => (is => 'ro', isa => 'Bool', default => 0);

has _stats => (is => 'rw', isa => 'HashRef', default => sub { return {}; });

has __originalProgramName => (is => 'rw', isa => 'Str');

has _tagWrap => (is => 'ro', isa => 'Daybo::Twitch::TagWrap', default => sub { Daybo::Twitch::TagWrap->new() });

my @pids;

=item C<__acceptableDirName($dirName)>

Returns true unless C<$dirName> is C<@eaDir> (a Synology metadata
directory that should never be walked).

=cut

sub __acceptableDirName {
	my ($dirName) = @_;
	return ($dirName ne '@eaDir');
}

=item C<__collect($dirname)>

Recursively walks C<$dirname>, returning an array ref of tuples
C<[$relPath, $filename, $size, $ext]> for every file whose extension is
supported by the tag backend.  Updates C<_stats> with C<seen_files>,
C<seen_bytes>, C<unqualified_files>, and C<unqualified_bytes> as it goes.
Returns C<-1> (not a ref) if the directory cannot be opened.

=cut

sub __collect {
	my ($self, $dirname) = @_;
	my @files;

	my $dir = IO::Dir->new($dirname);
	unless ($dir) {
		$self->__log("Cannot open '$dirname': $ERRNO");
		return -1;
	}

	while (defined(my $filename = $dir->read())) {
		next if ($filename eq '.' || $filename eq '..');

		my $relPath = $dirname . '/' . $filename;

		if (-d $relPath) {
			if ($self->recursive && __acceptableDirName($filename)) {
				my $sub = $self->__collect($relPath);
				push(@files, @{$sub}) if (ref($sub));
			}
		} elsif (my $fh = IO::File->new($relPath, '<')) {
			my $ext = __getExt($filename);
			my $size = -s $relPath;
			$fh->close();
			$self->_stats->{seen_files}++;
			$self->_stats->{seen_bytes} += $size;

			if ($self->_tagWrap->isExtSupported($ext)) {
				__parseFileName($filename);
				push(@files, [ $relPath, $filename, $size, $ext ]);
			} else {
				$self->_stats->{unqualified_bytes} += $size;
				$self->_stats->{unqualified_files}++;
			}
		}
	}

	$dir->close();
	return \@files;
}

=item C<__fixConjunctions($artist)>

Lowercases C<on>, C<and>, and C<or> when they appear as interior words
(not first or last) in C<$artist>.  Returns the artist string unchanged
if it contains two words or less.

=cut

sub __fixConjunctions {
	my ($artist) = @_;
	my @words = split(/\s+/, $artist);
	return $artist if (@words <= 2);
	foreach my $i (1 .. $#words - 1) {
		$words[$i] = lc($words[$i]) if ($words[$i] =~ /^(?:on|and|or)$/i);
	}
	return join(' ', @words);
}

=item C<__fixWorldSuffix($artist)>

Ensures a trailing C<world> token is separated from the preceding word by
a space, and normalizes a trailing C< Uk> suffix to C< UK>.

=cut

sub __fixWorldSuffix {
	my ($artist) = @_;
	$artist =~ s/(\S)(world)$/$1 $2/i;
	$artist =~ s/ Uk$/ UK/i;
	return $artist;
}

=item C<__fmtBytes($bytes)>

Formats a byte count as a human-readable string with the appropriate
binary unit (TiB, GiB, MiB, KiB, or bytes).  Checks from largest to
smallest unit.

=cut

sub __fmtBytes {
	my ($bytes) = @_;
	return sprintf('%.3f TiB (%d bytes)', $bytes / (1024 * 1024 * 1024 * 1024), $bytes) if ($bytes >= 1000 * 1024 * 1024 * 1024);
	return sprintf('%.3f GiB (%d bytes)', $bytes / (1024 * 1024 * 1024), $bytes) if ($bytes >= 1024 * 1024 * 1024);
	return sprintf('%.2f MiB (%d bytes)', $bytes / (1024 * 1024), $bytes) if ($bytes >= 1024 * 1024);
	return sprintf('%.1f KiB (%d bytes)', $bytes / 1024, $bytes) if ($bytes >= 1024);
	return sprintf('%d bytes', $bytes);
}

=item C<__getExt($fn)>

Returns the lower-case file extension of C<$fn> (the part after the last
C<.>), or an empty string if the filename has no extension.

=cut

sub __getExt {
	my ($fn) = @_;
	my @arr = split(m/\./, $fn);
	my $ext = $arr[ scalar(@arr) - 1 ];
	return '' if ($fn eq $ext);
	return lc($ext);
}

=item C<__log($msg)>

Prints C<$msg> to stdout when C<--verbose> is active.  If C<$msg> is a
hash ref it is emitted as JSON regardless of the C<--json> flag; a plain
string is wrapped in a JSON object when C<--json> is set.  No return
value.

=cut

sub __log {
	my ($self, $msg) = @_;
	if ($self->verbose) {
		if (ref($msg) eq 'HASH') {
			print encode_json($msg) . "\n";
		} elsif ($self->json) {
			print encode_json({message => $msg}) . "\n";
		} else {
			print "$msg\n";
		}
	}
	return;
}

=item C<__logTagChanges($file, $pct, $existing, $artist, $album, $track, $year, $comment)>

Compares each proposed tag field against C<$existing> and logs the
differences (or a "Tags unchanged, forced rewrite" message when nothing
changed).  Returns the number of fields that differ.

=cut

sub __logTagChanges {
	my ($self, $file, $pct, $existing, $artist, $album, $track, $year, $comment) = @_;

	my (%JSON_changeLog, $plain_changeLog);
	my $changeCount = 0;

	if ($self->json) {
		%JSON_changeLog = (
			file => $file,
			process => {
				type => 'changelog',
				pct => $pct,
				pid => $PID,
			},
			changes => [ ],
		);
	} else {
		$plain_changeLog = sprintf('[%d%%]: ', $pct);
	}

	foreach my $f (
		['artist',  $existing->{artist},  $artist],
		['album',   $existing->{album},   $album],
		['track',   $existing->{track},   $track],
		['year',    $existing->{year},    $year],
		['comment', $existing->{comment}, $comment],
	) {
		my ($name, $old, $new) = @{$f};
		$old //= '';
		if ($old ne $new) {
			$changeCount++;
			if ($self->json) {
				push(@{ $JSON_changeLog{changes} }, {
					field => $name,
					old => $old,
					new => $new,
				});
			} else {
				$plain_changeLog .= "$name: \"$old\" -> \"$new\", ";
			}
		}
	}

	if ($self->json) {
		$JSON_changeLog{process}{message} = 'Tags unchanged, forced rewrite'
		    if ($changeCount == 0);
		$self->__log(\%JSON_changeLog);
	} else {
		$plain_changeLog = sprintf('[%d%%] Tags unchanged, forcing rewrite for %s', $pct, $file)
		    if ($changeCount == 0);
		$self->__log($plain_changeLog);
	}

	return $changeCount;
}

=item C<__normalizeArtist($artistRaw)>

Converts a raw yt-dlp artist handle into a display name.  Strips
C<Official>, C<Music>, and C<dj> tokens; replaces underscores with
spaces; splits camelCase runs into words; applies title-case; fixes
conjunctions via L<__fixConjunctions> and world-suffix via
L<__fixWorldSuffix>; and applies a table of hardcoded handle-to-name
overrides.

=cut

sub __normalizeArtist {
	my ($artistRaw) = @_;
	my $artist = $artistRaw;

	$artist =~ s/Official//gi;
	$artist =~ s/Music//gi;
	$artist = 'Raymond Doyle' if ($artist eq 'CarteBlanche88');
	$artist = 'Taucher' if ($artist =~ m/^taucher66$/i);
	$artist = 'Kristina Sky' if ($artist eq 'TheRealKristinaSky');
	$artist = 'Edit' if ($artist eq 'The_Real_DJ_Edit' || $artist eq 'TheReal_DJEdit');
	$artist = 'Vlastimil' if ($artist =~ m/^vlastimilvibes$/i);
	$artist =~ s/dj//i;
	$artist =~ s/_/ /g;
	$artist =~ s/\s*$//;
	$artist =~ s/^\s*//;

	if ($artist =~ /^[A-Z]{3,}/ || $artist =~ /[a-z][A-Z]/) {
		my @words = ($artist =~ /([A-Z][a-z]+|[A-Z]+|[a-z]+|[0-9]+)/g);
		$artist = join(' ', map { ucfirst(lc($_)) } @words);
	}

	$artist = __fixWorldSuffix($artist);
	$artist =~ s/\b([a-z])/uc($1)/ge;
	$artist = __fixConjunctions($artist);

	$artist = 'DJ Chopper' if ($artistRaw eq 'djChopper');
	$artist = 'DJ DNA' if ($artist eq 'Dna');
	$artist = 'DJ Edit' if ($artist eq 'Edit');
	$artist = 'DJ Paulo' if ($artist eq 'Paulo');
	$artist = 'DJ Baedine' if ($artist eq 'Baedine');
	$artist = 'HANAWINS' if ($artist eq 'Hanawins');
	$artist = 'A D A M S K I' if ($artistRaw eq 'A_D_A_M_S_K_I');
	$artist = 'Bugi' if ($artistRaw eq 'xX_Bugi_Xx');
	$artist = 'ReOrder' if ($artistRaw eq 'ReOrderDJ');
	$artist = 'Rob Kidd' if ($artist =~ m/^robkidd/i);
	$artist = 'Ryan Moon' if ($artist =~ m/^ryanmoon/i);
	$artist = 'Mark Sherry' if ($artistRaw =~ m/^marksherrydj$/i);
	$artist = 'Markus Schulz' if ($artistRaw =~ m/^markusschulz$/i);
	$artist = 'Ferry Corsten' if ($artist =~ m/^ferrycorsten/i);
	$artist = 'Noemi Black' if ($artist =~ m/^noemiblack/i);
	$artist = 'Fraser Binnie' if ($artist =~ m/^fraserbinnie/i);
	$artist = 'Stoneface & Terminal' if ($artist eq 'Stoneface Terminal');
	$artist = 'XiJaro & Pitch' if ($artistRaw eq 'XiJaroAndPitch');
	$artist = 'FaBiESto' if ($artistRaw eq 'FaBiESto');
	$artist = $artistRaw if ($artistRaw eq 'Music4ThaMasses');
	$artist = $artistRaw if ($artistRaw eq 'RaZoR368');
	$artist = lc($artistRaw) if ($artistRaw =~ m/^tkkttony$/i);
	$artist = $artistRaw if ($artistRaw =~ /TV$/);

	return $artist;
}

=item C<__parseFileName($filename)>

Parses a yt-dlp-style filename and returns a four-element array ref
C<[$artist, $album, $track, $year]>.  Results are memoized by filename.
Three filename formats are recognised:

=over

=item *

C<ArtistHandle (type) YYYY-MM-DD HH_MM[-StreamID].mp3>

=item *

C<YYYY-MM-DD-HH-MM-SS-ArtistHandle.ext>

=item *

C<ArtistHandle-YYYY-MM-DD.ext>

=back

Dies if none of the patterns match.

=cut

my %__filenameParserContext = ( );
sub __parseFileName {
	# Example: '1stdegreeproductions (live) 2021-10-18 11_05-40110166187.mp3'
	# Example: '2022-05-30-15-20-01-vlastimilvibes.mp3'
	my ($filename) = @_;

	if (my $cached = $__filenameParserContext{$filename}) {
		return $cached;
	}

	if ($filename =~ m/^(\w+)\s\(\w+\)\s((\d{4})-\d{2}-\d{2})(?:\s(\d{2})_(\d{2})(?:\s\[(\d+)\]|-(\d+))?)?/) {
		my ($date, $year, $hh, $mm) = ($2, $3, $4 // '00', $5 // '00');
		my $streamId = $6 // $7;
		my $artistRaw = $1;
		my $artist = __normalizeArtist($artistRaw);

		my $track = "$artist $date ${hh}:${mm}:00";
		$track .= " $streamId" if (defined($streamId));
		my $album = "${artist} on Twitch";

		return $__filenameParserContext{$filename} = [ $artist, $album, $track, $year ];
	} elsif ($filename =~ m/^(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\w+)\.\w+$/) {
		my ($year, $mon, $day, $hh, $mm, $ss, $artistRaw) = ($1, $2, $3, $4, $5, $6, $7);
		my $date = "$year-$mon-$day";
		my $artist = __normalizeArtist($artistRaw);
		my $track = "$artist $date ${hh}:${mm}:${ss}";
		my $album = "${artist} on Twitch";

		return $__filenameParserContext{$filename} = [ $artist, $album, $track, $year ];
	} elsif ($filename =~ m/^(\w+)-(\d{4})-(\d{2})-(\d{2})\.\w+$/) {
		my ($artistRaw, $year, $mon, $day) = ($1, $2, $3, $4);
		my $date = "$year-$mon-$day";
		my $artist = __normalizeArtist($artistRaw);
		my $album = "${artist} on Twitch";
		my $track = "${artist} ${date} 00:00:00";

		return $__filenameParserContext{$filename} = [ $artist, $album, $track, $year ];
	}

	die("Cannot parse filename structure: '$filename'");
}

=item C<__printStats()>

Emits a run summary via C<__log> after all files have been processed.
In JSON mode, outputs a single C<stats> event object; otherwise prints a
human-readable multi-line summary.  No return value.

=cut

sub __printStats {
	my ($self) = @_;

	my $s = $self->_stats;
	my $elapsed = $s->{end_time} - $s->{start_time};
	my $total_mib = $s->{total_bytes} / (1024 * 1024);

	if ($self->json) {
		$self->__log({
			process => { type => 'stats' },
			stats => {
				total_files         => $s->{total_files} + 0,
				modified_files      => $s->{modified_files} + 0,
				skipped_files       => $s->{skipped_files} + 0,
				total_bytes         => $s->{total_bytes} + 0,
				modified_bytes      => $s->{modified_bytes} + 0,
				change_count        => $s->{change_count} + 0,
				unqualified_bytes   => $s->{unqualified_bytes} + 0,
				unqualified_files   => $s->{unqualified_files} + 0,
				seen_files          => $s->{seen_files} + 0,
				seen_bytes          => $s->{seen_bytes} + 0,
				elapsed_s           => $elapsed + 0,
				avg_time_per_file_s => $s->{total_files} > 0 ? $elapsed / $s->{total_files} : 0,
				avg_time_per_mib_s  => $total_mib > 0 ? $elapsed / $total_mib : 0,
			},
		});
		return;
	}

	my $plain = sprintf("Summary:\n");
	$plain .= sprintf("  Files seen:       %d\n",   $s->{seen_files});
	$plain .= sprintf("  Bytes seen:       %s\n",   __fmtBytes($s->{seen_bytes}));
	$plain .= sprintf("  Files processed:  %d\n",   $s->{total_files});
	$plain .= sprintf("  Files modified:   %d\n",   $s->{modified_files});
	$plain .= sprintf("  Files skipped:    %d\n",   $s->{skipped_files});
	$plain .= sprintf("  Total bytes:      %s\n",   __fmtBytes($s->{total_bytes}));
	$plain .= sprintf("  Modified bytes:   %s\n",   __fmtBytes($s->{modified_bytes}));
	$plain .= sprintf("  Tag changes:      %d\n",   $s->{change_count});
	$plain .= sprintf("  Unqualified files: %d\n",  $s->{unqualified_files});
	$plain .= sprintf("  Unqualified bytes: %s\n",  __fmtBytes($s->{unqualified_bytes}));
	$plain .= sprintf("  Total time:       %.3fs\n", $elapsed);
	$plain .= sprintf("  Avg time/file:    %.3fs\n", $elapsed / $s->{total_files})
	    if ($s->{total_files} > 0);
	$plain .= sprintf("  Avg time/MiB:     %.3fs\n", $elapsed / $total_mib)
	    if ($total_mib > 0);
	$self->__log($plain);

	return;
}

=item C<__reapChild($done_pid)>

Reads the result line written by a finished child process, updates
C<_stats> with its file and byte totals, then removes its entry from
C<@pids>.  No return value.

=cut

sub __reapChild {
	my ($self, $done_pid) = @_;

	my ($entry) = grep { $_->{pid} == $done_pid } @pids;
	if ($entry) {
		my $line = readline($entry->{rfh});
		close($entry->{rfh});
		if (defined($line)) {
			chomp($line);
			my ($modified, $changeCount) = split(/ /, $line);
			$modified //= 0;
			$changeCount //= 0;
			$self->_stats->{total_files}++;
			$self->_stats->{total_bytes} += $entry->{size};
			if ($modified) {
				$self->_stats->{modified_files}++;
				$self->_stats->{modified_bytes} += $entry->{size};
			} else {
				$self->_stats->{skipped_files}++;
			}
			$self->_stats->{change_count} += $changeCount;
		}
	}

	@pids = grep { $_->{pid} != $done_pid } @pids;
	return;
}

=item C<run($dirname)>

Public entry point.  Initializes stats, walks C<$dirname> via
C<__collect>, dispatches each qualifying file to C<__tag>, waits for all
child processes to finish, then prints the run summary.  Returns
C<EXIT_SUCCESS> or C<EXIT_FAILURE>.

=cut

sub run {
	my ($self, $dirname) = @_;

	$self->__originalProgramName($PROGRAM_NAME);
	local $PROGRAM_NAME = sprintf('%s: main loop', $self->__originalProgramName);

	$self->_stats({
		total_files    => 0,
		modified_files => 0,
		skipped_files  => 0,
		total_bytes    => 0,
		modified_bytes => 0,
		change_count      => 0,
		unqualified_bytes => 0,
		unqualified_files => 0,
		seen_files        => 0,
		seen_bytes        => 0,
		start_time        => time(),
		end_time       => 0,
	});

	$self->__log("Walking file tree '$dirname'");
	my $files = $self->__collect($dirname);
	if (!ref($files) && $files == -1) {
		return EXIT_FAILURE;
	}

	my $total = scalar(@$files);
	if ($total == 0) {
		$self->__log('Nothing to do!');
		return EXIT_SUCCESS;
	}

	my $weighted = $ENV{EXPERIMENTAL_PROGRESS};
	my ($totalBytes, $doneBytes);
	if ($weighted) {
		$totalBytes += $_->[2] for @$files;
		$doneBytes = 0;
	}

	for (my $i = 0; $i < scalar(@$files); $i++) {
		my ($relPath, $filename, $size, $ext) = @{ $files->[$i] };
		my $pct;
		if ($weighted) {
			$doneBytes += $size;
			$pct = $totalBytes > 0 ? int($doneBytes / $totalBytes * 100) : 100;
		} else {
			$pct = $total > 0 ? int(($i + 1) / $total * 100) : 100;
		}
		$self->__log("Tagging $relPath");
		$self->__tag(
			$relPath,
			$pct,
			$size,
			$ext,
			@{ __parseFileName($filename) },
		);
	}

	while (@pids) {
		local $PROGRAM_NAME = sprintf('%s: no more files, waitpid', $self->__originalProgramName);
		my $done = waitpid(-1, 0);
		$self->__reapChild($done);
	}

	$self->_stats->{end_time} = time();
	$self->__printStats();

	return EXIT_SUCCESS;
}

=item C<__tag($file, $pct, $size, $ext, $artist, $album, $track, $year)>

Enforces the C<--jobs> concurrency limit (blocking on C<waitpid> if
needed), then forks a child.  The parent records the child's PID and pipe
handle; the child calls C<__tagPerProcess>, writes its result to the
pipe, and exits.  No return value.

=cut

sub __tag {
	my ($self, $file, $pct, $size, $ext, $artist, $album, $track, $year) = @_;

	if (scalar(@pids) >= $self->jobs) {
		local $PROGRAM_NAME = sprintf('%s: reached %d concurrent jobs, waitpid', $self->__originalProgramName, $self->jobs);
		my $done = waitpid(-1, 0);
		$self->__reapChild($done);
	}

	pipe(my $rfh, my $wfh) or die("Cannot create pipe: $ERRNO");

	my $pid = fork();
	die("Cannot fork! $ERRNO") unless (defined($pid));

	if ($pid) { # parent
		close($wfh);
		push(@pids, { pid => $pid, rfh => $rfh, size => $size });
	} else { # child
		close($rfh);
		my ($modified, $changeCount) = $self->__tagPerProcess($file, $ext, $pct, $artist, $album, $track, $year);
		$modified //= 0;
		$changeCount //= 0;
		print $wfh "$modified $changeCount\n";
		close($wfh);
		exit(EXIT_SUCCESS);
	}

	return;
}

=item C<__tagPerProcess($file, $ext, $pct, $artist, $album, $track, $year)>

Runs inside a forked child.  Reads existing tags, skips the file if all
fields are already up to date (unless C<--force>), otherwise deletes and
rewrites tags via the appropriate backend and restores the original GID.
Returns a two-element list C<($modified, $changeCount)>.

=cut

sub __tagPerProcess {
	my ($self, $file, $ext, $pct, $artist, $album, $track, $year) = @_;
	my $comment = "Generated by $URL";

	if ($self->json) {
		$self->__log({
			process => {
				type => 'tag',
				pct => $pct,
				pid => $PID,
			},
			fields => {
				artist => $artist,
				album => $album,
				track => $track,
				year => $year,
				comment => $comment,
			},
		});
	} else {
		$self->__log(sprintf('[%d%%] artist: %s, album: %s, track: %s, year: %s',
		    $pct, $artist, $album, $track, $year));
	}

	local $PROGRAM_NAME = sprintf('%s: reading "%s"', $self->__originalProgramName, $file);
	my $backendForExt = $self->_tagWrap->getBackendForExt($ext);
	my $existing = $backendForExt->readTags($file);

	if (!$self->force
	    && $existing
	    && ($existing->{artist}  // '') eq $artist
	    && ($existing->{album}   // '') eq $album
	    && ($existing->{track}   // '') eq $track
	    && ($existing->{year}    // '') eq $year
	    && ($existing->{comment} // '') eq $comment
	) {
		$self->__log(sprintf('[%d%%] Tags unchanged, skipping %s', $pct, $file));
		return (0, 0);
	}

	my $changeCount = 0;
	$changeCount = $self->__logTagChanges($file, $pct, $existing, $artist, $album, $track, $year, $comment)
	    if ($existing);

	my @stat = stat($file)
	    or die("Cannot stat '$file': $ERRNO");

	my $gid = $stat[5];

	if ($self->noop) {
		return (0, $changeCount);
	}

	local $PROGRAM_NAME = sprintf('%s: retagging "%s"', $self->__originalProgramName, $file);
	$backendForExt->deleteTags($file);
	$backendForExt->writeTags($file, $artist, $album, $track, $year, $comment);

	chown(-1, $gid, $file) == 1
	    or die("Cannot restore GID $gid on '$file': $ERRNO");

	return (1, $changeCount);
}

=item C<usage()>

Prints a usage summary to stdout and returns 1.

=cut

sub usage {
	printf("twitch-tag-mp3 %s usage:\n", $VERSION);
	print("twitch-tag-mp3 --directory <DIR> [--force] [--help] [--jobs <N>] [--json] [--noop] [--recursive] [--verbose] [--version]\n");
	print("twitch-tag-mp3 -d <DIR> [-f] [-h] [-j <N>] [-J] [-n] [-r] [-v] [-V]\n\n");
	printf("See https://%s for more information.\n", $URL);
	return 1;
}

1;

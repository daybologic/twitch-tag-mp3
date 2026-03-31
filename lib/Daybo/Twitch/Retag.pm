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
use File::Spec;
use IO::Dir;
use IO::File;
use IPC::Run3;
use JSON::PP qw(encode_json);
use Time::HiRes qw(time);
use Moose;
use POSIX qw(EXIT_FAILURE EXIT_SUCCESS);

our $VERSION = '0.6.0';

our $URL = 'github.com/daybologic/twitch-tag-mp3';

has jobs => (is => 'ro', isa => 'Int',  default => 1);

has [qw(force json noop recursive verbose)]
    => (is => 'ro', isa => 'Bool', default => 0);

has _stats => (is => 'rw', isa => 'HashRef', default => sub { return {}; });

has __originalProgramName => (is => 'rw', isa => 'Str');

my @pids;

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

	$self->log("Walking file tree '$dirname'");
	my $files = $self->_collect($dirname);
	if (!ref($files) && $files == -1) {
		return EXIT_FAILURE;
	}

	my $total = scalar(@$files);
	if ($total == 0) {
		$self->log('Nothing to do!');
		return EXIT_SUCCESS;
	}

	my $weighted = $ENV{EXPERIMENTAL_PROGRESS};
	my ($total_bytes, $done_bytes);
	if ($weighted) {
		$total_bytes += $_->[2] for @$files;
		$done_bytes = 0;
	}

	for (my $i = 0; $i < scalar(@$files); $i++) {
		my ($relPath, $filename, $size) = @{ $files->[$i] };
		my $pct;
		if ($weighted) {
			$done_bytes += $size;
			$pct = $total_bytes > 0 ? int($done_bytes / $total_bytes * 100) : 100;
		} else {
			$pct = $total > 0 ? int(($i + 1) / $total * 100) : 100;
		}
		$self->log("Tagging $relPath");
		$self->tag(
			$relPath,
			$pct,
			$size,
			@{ parseFileName($filename) },
		);
	}

	while (@pids) {
		local $PROGRAM_NAME = sprintf('%s: no more files, waitpid', $self->__originalProgramName);
		my $done = waitpid(-1, 0);
		$self->_reapChild($done);
	}

	$self->_stats->{end_time} = time();
	$self->_printStats();

	return EXIT_SUCCESS;
}

sub _collect {
	my ($self, $dirname) = @_;
	my @files;

	my $dir = IO::Dir->new($dirname);
	unless ($dir) {
		$self->log("Cannot open '$dirname': $ERRNO");
		return -1;
	}

	while (defined(my $filename = $dir->read())) {
		next if ($filename eq '.' || $filename eq '..');

		my $relPath = $dirname . '/' . $filename;

		if (-d $relPath) {
			if ($self->recursive && acceptableDirName($filename)) {
				my $sub = $self->_collect($relPath);
				push(@files, @{$sub}) if (ref($sub));
			}
		} elsif (my $fh = IO::File->new($relPath, '<')) {
			my $ext = getExt($filename);
			my $size = -s $relPath;
			$fh->close();
			$self->_stats->{seen_files}++;
			$self->_stats->{seen_bytes} += $size;

			if (isMp3($ext)) {
				parseFileName($filename);
				push(@files, [ $relPath, $filename, $size ]);
			} else {
				$self->_stats->{unqualified_bytes} += $size;
				$self->_stats->{unqualified_files}++;
			}
		}
	}

	$dir->close();
	return \@files;
}

sub log { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
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

sub usage {
	printf("twitch-tag-mp3 %s usage:\n", $VERSION);
	print("twitch-tag-mp3 --directory <DIR> [--force] [--help] [--jobs <N>] [--json] [--noop] [--recursive] [--verbose] [--version]\n");
	print("twitch-tag-mp3 -d <DIR> [-f] [-h] [-j <N>] [-J] [-n] [-r] [-v] [-V]\n\n");
	printf("See https://%s for more information.\n", $URL);
	return 1;
}

sub isMp3 {
	my ($ext) = @_;
	return (defined($ext) && lc($ext) eq 'mp3');
}

sub getExt {
	my ($fn) = @_;
	my @arr = split(m/\./, $fn);
	my $ext = $arr[ scalar(@arr) - 1 ];
	return if ($fn eq $ext);
	return $ext;
}

sub tag {
	my ($self, $file, $pct, $size, $artist, $album, $track, $year) = @_;

	if (scalar(@pids) >= $self->jobs) {
		local $PROGRAM_NAME = sprintf('%s: reached %d limit, waitpid', $self->__originalProgramName, $self->jobs);
		my $done = waitpid(-1, 0);
		$self->_reapChild($done);
	}

	pipe(my $rfh, my $wfh) or die("Cannot create pipe: $ERRNO");

	my $pid = fork();
	die("Cannot fork! $ERRNO") unless (defined($pid));

	if ($pid) { # parent
		close($wfh);
		push(@pids, { pid => $pid, rfh => $rfh, size => $size });
	} else { # child
		close($rfh);
		my ($modified, $change_count) = $self->tagPerProcess($file, $pct, $artist, $album, $track, $year);
		$modified //= 0;
		$change_count //= 0;
		print $wfh "$modified $change_count\n";
		close($wfh);
		exit(EXIT_SUCCESS);
	}

	return;
}

sub _reapChild {
	my ($self, $done_pid) = @_;

	my ($entry) = grep { $_->{pid} == $done_pid } @pids;
	if ($entry) {
		my $line = readline($entry->{rfh});
		close($entry->{rfh});
		if (defined($line)) {
			chomp($line);
			my ($modified, $change_count) = split(/ /, $line);
			$modified //= 0;
			$change_count //= 0;
			$self->_stats->{total_files}++;
			$self->_stats->{total_bytes} += $entry->{size};
			if ($modified) {
				$self->_stats->{modified_files}++;
				$self->_stats->{modified_bytes} += $entry->{size};
			} else {
				$self->_stats->{skipped_files}++;
			}
			$self->_stats->{change_count} += $change_count;
		}
	}

	@pids = grep { $_->{pid} != $done_pid } @pids;
	return;
}

sub readTags {
	my ($file) = @_;

	return unless (open(my $fh, '-|', 'id3v2', '-l', $file));

	my %tags;
	while (my $line = <$fh>) {
		chomp($line);
		parseTag(\%tags, $line);
	}
	$fh->close();

	return %tags ? \%tags : undef;
}

my %__parsers = ( );
sub parseTag {
	my ($tags, $line) = @_;

	if (0 == scalar(keys(%__parsers))) {
		%__parsers = (
			artist => qr/^TPE1[^:]+:\s*(.+)$/,
			album => qr/^TALB[^:]+:\s*(.+)$/,
			track => qr/^TIT2[^:]+:\s*(.+)$/,
			year => qr/^TYER[^:]+:\s*(.+)$/,
			comment => qr/^COMM[^:]+:\s*(?:\([^)]*\)\[[^\]]*\]:\s*)?(.+)$/,
		);
	}

	while (my ($fieldName, $rx) = each(%__parsers)) {
		next if ($line !~ $rx);
		$tags->{$fieldName} = $1;
		last;
	}

	return;
}

sub logTagChanges {
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
		$self->log(\%JSON_changeLog);
	} else {
		$plain_changeLog = sprintf('[%d%%] Tags unchanged, forcing rewrite for %s', $pct, $file)
		    if ($changeCount == 0);
		$self->log($plain_changeLog);
	}

	return $changeCount;
}

sub tagPerProcess {
	my ($self, $file, $pct, $artist, $album, $track, $year) = @_;
	my $comment = "Generated by $URL";

	if ($self->json) {
		$self->log({
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
		$self->log(sprintf('[%d%%] artist: %s, album: %s, track: %s, year: %s',
		    $pct, $artist, $album, $track, $year));
	}

	local $PROGRAM_NAME = sprintf('%s: reading "%s"', $self->__originalProgramName, $file);
	my $existing = readTags($file);

	if (!$self->force
	    && $existing
	    && ($existing->{artist}  // '') eq $artist
	    && ($existing->{album}   // '') eq $album
	    && ($existing->{track}   // '') eq $track
	    && ($existing->{year}    // '') eq $year
	    && ($existing->{comment} // '') eq $comment
	) {
		$self->log(sprintf('[%d%%] Tags unchanged, skipping %s', $pct, $file));
		return (0, 0);
	}

	my $change_count = 0;
	$change_count = $self->logTagChanges($file, $pct, $existing, $artist, $album, $track, $year, $comment)
	    if ($existing);

	my @stat = stat($file)
	    or die("Cannot stat '$file': $ERRNO");

	my $gid = $stat[5];

	if ($self->noop) {
		return (0, $change_count);
	}

	local $PROGRAM_NAME = sprintf('%s: retagging "%s"', $self->__originalProgramName, $file);
	__system('id3v2', '--delete-all', $file);
	__system(
		'id3v2',
		'--artist', $artist,
		'--album',  $album,
		'--song',   $track,
		'--year',   $year,
		'--comment', $comment,
		$file,
	);

	chown(-1, $gid, $file) == 1
	    or die("Cannot restore GID $gid on '$file': $ERRNO");

	return (1, $change_count);
}

sub __system {
	my (@args) = @_;

	run3(
		\@args,
		undef,
		File::Spec->devnull(),
		File::Spec->devnull(),
	);

	my $exitCode = $CHILD_ERROR;
	if ($exitCode == -1) {
		die("Failed to run id3v2: $ERRNO");
	} elsif ($exitCode & 127) {
		die(sprintf(
			'id3v2 died with signal %d%s',
			($exitCode & 127),
			($exitCode & 128) ? ' (core dumped)' : q{}
		));
	} elsif (($exitCode >> 8) != 0) {
		die(sprintf('id3v2 exited with status %d', $exitCode >> 8));
	}

	return $exitCode;
}

sub _normalizeArtist {
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

	$artist = fixWorldSuffix($artist);
	$artist =~ s/\b([a-z])/uc($1)/ge;
	$artist = fixConjunctions($artist);

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

my %__filenameParserContext = ( );
sub parseFileName {
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
		my $artist = _normalizeArtist($artistRaw);

		my $track = "$artist $date ${hh}:${mm}:00";
		$track .= " $streamId" if (defined($streamId));
		my $album = "${artist} on Twitch";

		return $__filenameParserContext{$filename} = [ $artist, $album, $track, $year ];
	} elsif ($filename =~ m/^(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\w+)\.\w+$/) {
		my ($year, $mon, $day, $hh, $mm, $ss, $artistRaw) = ($1, $2, $3, $4, $5, $6, $7);
		my $date = "$year-$mon-$day";
		my $artist = _normalizeArtist($artistRaw);
		my $track = "$artist $date ${hh}:${mm}:${ss}";
		my $album = "${artist} on Twitch";

		return $__filenameParserContext{$filename} = [ $artist, $album, $track, $year ];
	}

	die("Cannot parse filename structure: '$filename'");
}

sub fixWorldSuffix {
	my ($artist) = @_;
	$artist =~ s/(\S)(world)$/$1 $2/i;
	$artist =~ s/ Uk$/ UK/i;
	return $artist;
}

sub fixConjunctions {
	my ($artist) = @_;
	my @words = split(/\s+/, $artist);
	return $artist if (@words <= 2);
	foreach my $i (1 .. $#words - 1) {
		$words[$i] = lc($words[$i]) if ($words[$i] =~ /^(?:on|and|or)$/i);
	}
	return join(' ', @words);
}

sub acceptableDirName {
	my ($dirName) = @_;
	return ($dirName ne '@eaDir');
}

sub _fmtBytes {
	my ($bytes) = @_;
	return sprintf('%.3f TiB (%d bytes)', $bytes / (1024 * 1024 * 1024 * 1024), $bytes) if ($bytes >= 1000 * 1024 * 1024 * 1024);
	return sprintf('%.3f GiB (%d bytes)', $bytes / (1024 * 1024 * 1024), $bytes) if ($bytes >= 1024 * 1024 * 1024);
	return sprintf('%.2f MiB (%d bytes)', $bytes / (1024 * 1024), $bytes) if ($bytes >= 1024 * 1024);
	return sprintf('%.1f KiB (%d bytes)', $bytes / 1024, $bytes) if ($bytes >= 1024);
	return sprintf('%d bytes', $bytes);
}

sub _printStats {
	my ($self) = @_;

	my $s = $self->_stats;
	my $elapsed = $s->{end_time} - $s->{start_time};
	my $total_mib = $s->{total_bytes} / (1024 * 1024);

	if ($self->json) {
		$self->log({
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
	$plain .= sprintf("  Bytes seen:       %s\n",   _fmtBytes($s->{seen_bytes}));
	$plain .= sprintf("  Files processed:  %d\n",   $s->{total_files});
	$plain .= sprintf("  Files modified:   %d\n",   $s->{modified_files});
	$plain .= sprintf("  Files skipped:    %d\n",   $s->{skipped_files});
	$plain .= sprintf("  Total bytes:      %s\n",   _fmtBytes($s->{total_bytes}));
	$plain .= sprintf("  Modified bytes:   %s\n",   _fmtBytes($s->{modified_bytes}));
	$plain .= sprintf("  Tag changes:      %d\n",   $s->{change_count});
	$plain .= sprintf("  Unqualified files: %d\n",  $s->{unqualified_files});
	$plain .= sprintf("  Unqualified bytes: %s\n",  _fmtBytes($s->{unqualified_bytes}));
	$plain .= sprintf("  Total time:       %.3fs\n", $elapsed);
	$plain .= sprintf("  Avg time/file:    %.3fs\n", $elapsed / $s->{total_files})
	    if ($s->{total_files} > 0);
	$plain .= sprintf("  Avg time/MiB:     %.3fs\n", $elapsed / $total_mib)
	    if ($total_mib > 0);
	$self->log($plain);

	return;
}

1;

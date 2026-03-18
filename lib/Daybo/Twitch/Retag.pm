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
use Moose;
use POSIX qw(EXIT_SUCCESS);

our $VERSION = '0.4.0';

our $URL = 'github.com/daybologic/twitch-tag-mp3';

has jobs => (is => 'ro', isa => 'Int',  default => 1);

has [qw(json noop recursive verbose)]
    => (is => 'ro', isa => 'Bool', default => 0);

my @pids;

sub run {
	my ($self, $dirname) = @_;

	$self->log("Walking file tree '$dirname'");
	my @files = $self->_collect($dirname);
	my $total  = scalar(@files);

	foreach my $i (0 .. $#files) {
		my ($relPath, $filename) = @{ $files[$i] };
		my $pct = $total > 0 ? int(($i + 1) / $total * 100) : 100;
		$self->log("Tagging $relPath");
		$self->tag(
			$relPath,
			$pct,
			@{ parseFileName($filename) },
		);
	}

	foreach my $pid (@pids) {
		waitpid($pid, 0);
	}

	@pids = ();

	return EXIT_SUCCESS;
}

sub _collect {
	my ($self, $dirname) = @_;
	my @files;

	my $dir = IO::Dir->new($dirname);
	return () unless ($dir);

	while (defined(my $filename = $dir->read())) {
		next if ($filename eq '.' || $filename eq '..');

		my $relPath = $dirname . '/' . $filename;

		if (-d $relPath) {
			if ($self->recursive && acceptableDirName($filename)) {
				push(@files, $self->_collect($relPath))
			}
		} elsif (my $fh = IO::File->new($relPath, '<')) {
			my $ext = getExt($filename);
			$fh->close();

			if (isMp3($ext)) {
				parseFileName($filename);
				push(@files, [ $relPath, $filename ]);
			}
		}
	}

	$dir->close();
	return @files;
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
	print("twitch-tag-mp3.pl -d <base_dir>\n\n");
	print("See README for more information, or https://$URL\n");
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
	my ($self, $file, $pct, $artist, $album, $track, $year) = @_;

	if (scalar(@pids) >= $self->jobs) {
		my $done = waitpid(-1, 0);
		@pids = grep { $_ != $done } @pids;
	}

	my $pid = fork();
	die("Cannot fork! $ERRNO") unless (defined($pid));

	if ($pid) { # parent
		push(@pids, $pid);
	} else { # child
		local $PROGRAM_NAME = sprintf("tagging '%s'", $file);
		$self->tagPerProcess($file, $pct, $artist, $album, $track, $year);
		exit(EXIT_SUCCESS);
	}

	return;
}

sub readTags {
	my ($file) = @_;

	return unless (open(my $fh, '-|', 'id3v2', '-l', $file));

	my %tags;
	while (my $line = <$fh>) {
		parseTag(\%tags, $line);
	}
	$fh->close();

	return %tags ? \%tags : undef;
}

sub parseTag {
	my ($tags, $line) = @_;

	chomp($line);

	# TODO: can we re-write this as a key -> rx map?
	if ($line =~ /^TPE1[^:]+:\s*(.+)$/) {
		return $tags->{artist} = $1;
	} elsif ($line =~ /^TALB[^:]+:\s*(.+)$/) {
		return $tags->{album} = $1;
	} elsif ($line =~ /^TIT2[^:]+:\s*(.+)$/) {
		return $tags->{track} = $1;
	} elsif ($line =~ /^TYER[^:]+:\s*(.+)$/) {
		return $tags->{year} = $1;
	} elsif ($line =~ /^COMM[^:]+:\s*(?:\([^)]*\)\[[^\]]*\]:\s*)?(.+)$/) {
		return $tags->{comment} = $1;
	}

	return;
}

sub logTagChanges {
	my ($self, $pct, $existing, $artist, $album, $track, $year, $comment) = @_;

	my (%JSON_changeLog, $plain_changeLog);

	if ($self->json) {
		%JSON_changeLog = (
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
		$self->log(\%JSON_changeLog);
	} else {
		$self->log($plain_changeLog);
	}

	return;
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

	my $existing = readTags($file);
	if ($existing
	    && ($existing->{artist}  // '') eq $artist
	    && ($existing->{album}   // '') eq $album
	    && ($existing->{track}   // '') eq $track
	    && ($existing->{year}    // '') eq $year
	    && ($existing->{comment} // '') eq $comment
	) {
		$self->log(sprintf('[%d%%] Tags unchanged, skipping %s', $pct, $file));
		return;
	}

	$self->logTagChanges($pct, $existing, $artist, $album, $track, $year, $comment)
	    if ($existing);

	my @stat = stat($file)
	    or die("Cannot stat '$file': $ERRNO");

	my $gid = $stat[5];

	return if ($self->noop);

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

	return;
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

	$artist = 'DJ DNA' if ($artist eq 'Dna');
	$artist = 'DJ Edit' if ($artist eq 'Edit');
	$artist = 'DJ Paulo' if ($artist eq 'Paulo');
	$artist = 'DJ Baedine' if ($artist eq 'Baedine');
	$artist = 'HANAWINS' if ($artist eq 'Hanawins');
	$artist = 'A_D_A_M_S_K_I' if ($artistRaw eq 'A_D_A_M_S_K_I');
	$artist = 'Bugi' if ($artistRaw eq 'xX_Bugi_Xx');
	$artist = 'Ferry Corsten' if ($artist =~ m/^ferrycorsten/i);
	$artist = 'Noemi Black' if ($artist =~ m/^noemiblack/i);
	$artist = 'Fraser Binnie' if ($artist =~ m/^fraserbinnie/i);
	$artist = 'Stoneface & Terminal' if ($artist eq 'Stoneface Terminal');
	$artist = 'XiJaro & Pitch' if ($artistRaw eq 'XiJaroAndPitch');
	$artist = 'FaBiESto' if ($artistRaw eq 'FaBiESto');
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

1;

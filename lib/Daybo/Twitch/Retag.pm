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
use IPC::Run3;
use Moose;

our $VERSION = '0.3.0';

our $URL = 'https://git.sr.ht/~m6kvm/twitch-tag-mp3';

has 'jobs'      => (is => 'ro', isa => 'Int',  default => 1);
has 'noop'      => (is => 'ro', isa => 'Bool', default => 0);
has 'recursive' => (is => 'ro', isa => 'Bool', default => 0);
has 'verbose'   => (is => 'ro', isa => 'Bool', default => 0);

my @pids;

sub run {
	my ($self, $dirname) = @_;

	$self->log("Walking file tree '$dirname'");
	my @files = $self->_collect($dirname);
	my $total  = scalar(@files);

	for my $i (0 .. $#files) {
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

	return 0;
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
			push(@files, $self->_collect($relPath))
				if ($self->recursive && acceptableDirName($filename));
		} elsif (open(my $fh, '<', $relPath)) {
			my $ext = getExt($filename);
			close($fh);

			if (isMp3($ext)) {
				parseFileName($filename);
				push(@files, [$relPath, $filename]);
			}
		}
	}

	$dir->close();
	return @files;
}

sub log { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
	my ($self, $msg) = @_;
	print "$msg\n" if ($self->verbose);
	return;
}

sub usage {
	printf("twitch-tag-mp3 %s usage:\n", $VERSION);
	print("twitch-tag-mp3.pl <base_dir>\n\n");
	print("See README for more information, or $URL\n");
	return 1;
}

sub isMp3 {
	my ($ext) = @_;
	return (defined($ext) && lc($ext) eq 'mp3');
}

sub getExt {
	my ($fn) = @_;
	my @arr;
	my $ext;

	@arr = split(m/\./, $fn);
	$ext = $arr[scalar(@arr)-1];
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
		local $0 = sprintf("tagging '%s'", $file);
		$self->tagPerProcess($file, $pct, $artist, $album, $track, $year);
		exit(0);
	}

	return;
}

sub readTags {
	my ($file) = @_;
	my %tags;

	open(my $fh, '-|', 'id3v2', '-l', $file) or return;
	while (my $line = <$fh>) {
		chomp $line;
		if    ($line =~ /^TPE1[^:]+:\s*(.+)$/) { $tags{artist} = $1 }
		elsif ($line =~ /^TALB[^:]+:\s*(.+)$/) { $tags{album}  = $1 }
		elsif ($line =~ /^TIT2[^:]+:\s*(.+)$/) { $tags{track}  = $1 }
		elsif ($line =~ /^TYER[^:]+:\s*(.+)$/) { $tags{year}    = $1 }
		elsif ($line =~ /^COMM[^:]+:\s*(?:\([^)]*\)\[[^\]]*\]:\s*)?(.+)$/) { $tags{comment} = $1 }
	}
	close($fh);

	return %tags ? \%tags : undef;
}

sub logTagChanges {
	my ($self, $pct, $existing, $artist, $album, $track, $year, $comment) = @_;

	for my $f (['artist',  $existing->{artist},  $artist],
	           ['album',   $existing->{album},   $album],
	           ['track',   $existing->{track},   $track],
	           ['year',    $existing->{year},    $year],
	           ['comment', $existing->{comment}, $comment])
	{
		my ($name, $old, $new) = @{$f};
		$old //= '';
		$self->log(sprintf('[%d%%] %s: "%s" -> "%s"', $pct, $name, $old, $new))
		    if ($old ne $new);
	}

	return;
}

sub tagPerProcess {
	my ($self, $file, $pct, $artist, $album, $track, $year) = @_;
	my $comment = "Generated by twitch-tag-mp3 $VERSION";

	$self->log(sprintf('[%d%%] artist: %s, album: %s, track: %s, year: %s',
	    $pct, $artist, $album, $track, $year));

	my $existing = readTags($file);
	if ($existing
	    && ($existing->{artist}  // '') eq $artist
	    && ($existing->{album}   // '') eq $album
	    && ($existing->{track}   // '') eq $track
	    && ($existing->{year}    // '') eq $year
	    && ($existing->{comment} // '') eq $comment)
	{
		$self->log(sprintf('[%d%%] Tags unchanged, skipping %s', $pct, $file));
		return;
	}

	$self->logTagChanges($pct, $existing, $artist, $album, $track, $year, $comment)
	    if ($existing);

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

my %__filenameParserContext = ( );
sub parseFileName {
	# Example: '1stdegreeproductions (live) 2021-10-18 11_05-40110166187.mp3'
	my ($filename) = @_;

	if (my $cached = $__filenameParserContext{$filename}) {
		return $cached;
	}

	if ($filename =~ m/^(\w+)\s\(\w+\)\s((\d{4})-\d{2}-\d{2})(?:\s(\d{2})_(\d{2})(?:\s\[(\d+)\]|-(\d+))?)?/) {
		my ($date, $year, $hh, $mm) = ($2, $3, $4 // '00', $5 // '00');
		my $streamId = $6 // $7;
		my ($artist, $album, $track) = ($1, undef, undef);
		my $artistRaw = $artist;

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

		if ($artist =~ /^[A-Z]{2,}/ || $artist =~ /[a-z][A-Z]/) {
			my @words = ($artist =~ /([A-Z][a-z]+|[A-Z]+|[a-z]+|[0-9]+)/g);
			$artist = join(' ', map { ucfirst(lc($_)) } @words);
		}

		$artist = fixWorldSuffix($artist);
		$artist =~ s/\b([a-z])/uc($1)/ge;
		$artist = fixConjunctions($artist);

		$artist = 'DJ Edit' if ($artist eq 'Edit');
		$artist = 'DJ Paulo' if ($artist eq 'Paulo');
		$artist = 'DJ Baedine' if ($artist eq 'Baedine');
		$artist = 'HANAWINS' if ($artist eq 'Hanawins');
		$artist = 'A_D_A_M_S_K_I' if ($artistRaw eq 'A_D_A_M_S_K_I');
		$artist = 'Bugi' if ($artistRaw eq 'xX_Bugi_Xx');
		$artist = 'Ferry Corsten' if (lc($artistRaw) eq 'ferrycorstenofficial');
		$artist = 'Noemi Black' if (lc($artistRaw) eq 'noemiblackdj');
		$artist = 'Fraser Binnie' if (lc($artistRaw) eq 'fraserbinnie');
		$artist = 'XiJaro & Pitch' if ($artistRaw eq 'XiJaroAndPitch');
		$artist = 'FaBiESto' if ($artistRaw eq 'FaBiESto');
		$artist = $artistRaw if ($artistRaw =~ /TV$/);

		$track = "$artist $date ${hh}:${mm}:00";
		$track .= " $streamId" if (defined($streamId));
		$album = "${artist} on Twitch";

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
	for my $i (1 .. $#words - 1) {
		$words[$i] = lc($words[$i]) if ($words[$i] =~ /^(?:on|and|or)$/i);
	}
	return join(' ', @words);
}

sub acceptableDirName {
	my ($dirName) = @_;
	return ($dirName ne '@eaDir');
}

1;

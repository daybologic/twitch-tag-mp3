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

package Daybo::Twitch::TagWrap::Backend;
use Moose;
use Data::Dumper;
use English qw(-no_match_vars);
use File::Basename;
use IPC::Run3;
use UNIVERSAL::require;

has __backends   => (
	is       => 'ro',
	isa      => 'HashRef',
	lazy     => 1,
	required => 0,
	init_arg => undef,
	builder  => '__initBackends',
);

sub list {
	my ($self) = @_;
	return [ sort(keys(%{ $self->__backends })) ];
}

sub getBackendForExt {
	my ($self, $ext) = @_;

	my $module = $self->__backends->{ uc($ext) };

	die("Cannot find module which deals with extension '$ext': " . Dumper $self->__backends)
	    unless ($module);

	return $module;
}

sub __initBackends {
	my ($self) = @_;
	my %backends;
 	my $pattern = 'lib/Daybo/Twitch/TagWrap/Backend/*.pm';

	while (my $pm = glob($pattern)) {
		my ($module, @patterns);
		$pm = basename($pm);
		$pm =~ s/\.pm$//;
		$module = sprintf('Daybo::Twitch::TagWrap::Backend::%s', $pm);
		unless ($module->use) {
			warn('Could not import package: ' . $@);
			next;
		}
		$module = $module->new(owner => $self);
		$backends{$pm} = $module;
	}
	return \%backends;
}

sub _system {
	my ($self, @args) = @_;

	run3(
		\@args,
		undef,
		File::Spec->devnull(),
		File::Spec->devnull(),
	);

	my $exitCode = $CHILD_ERROR;
	if ($exitCode == -1) {
		die("Failed to run $args[0]: $ERRNO");
	} elsif ($exitCode & 127) {
		die(sprintf(
			'%s died with signal %d%s',
			$args[0],
			($exitCode & 127),
			($exitCode & 128) ? ' (core dumped)' : q{}
		));
	} elsif (($exitCode >> 8) != 0) {
		die(sprintf('%s exited with status %d', $args[0], $exitCode >> 8));
	}

	return $exitCode;
}

1;

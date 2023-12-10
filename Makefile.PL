#!/usr/bin/perl

# Twitch MP3 tagger.
# Copyright (c) 2023, Rev. Duncan Ross Palmer (2E0EOL)
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

package main;
use strict;
use warnings;

eval {
	import Sys::CPU;
};

use ExtUtils::MakeMaker;

WriteMakefile(
	ABSTRACT     => 'Perl program for ID3 tagging Twitch MP3 files which were downloaded with YouTube-DL',
	AUTHOR       => 'Duncan Ross Palmer, M6KVM (palmer@overchat.org)',

	EXE_FILES    => [glob q('bin/*')],
	NAME         => 'Daybo::Twitch::Retag',

        PREREQ_PM => {
                'Moose'    => 0,
		'MP3::Tag' => 0,
	}, BUILD_REQUIRES => {
		'Sys::CPU' => 0,
		#'Moose'           => 0,
		#'Test::More'      => 0,
	},

	VERSION_FROM => 'lib/Daybo/Twitch/Retag.pm',
);

package MY;
use strict;
use warnings;

sub test {
	my $inherited = shift;

	my $njobs;
	eval {
		$njobs = 2 * Sys::CPU::cpu_count();
	};
	if ($@) {
		$njobs = 2;
	}

	$inherited = sprintf('export HARNESS_OPTIONS=$(shell if echo $$PERL5OPT | grep -qe "-MDevel::Cover"; then echo ""; else echo j%u; fi)', $njobs) . "\n" . $inherited;

	return $inherited;
}

1;

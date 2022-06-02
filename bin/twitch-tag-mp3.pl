#!/usr/bin/env perl

package main;
use strict;
use warnings;

use lib './lib';
use Daybo::Twitch::Retag;

sub main {
	my $retagger = Daybo::Twitch::Retag->new();
	my $startDir = $ARGV[0];
	return $retagger->usage() if (!defined($startDir));
	return $retagger->run($startDir);
}


exit(main()) unless (caller());

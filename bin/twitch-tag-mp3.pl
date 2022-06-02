#!/usr/bin/env perl

package main;
use strict;
use warnings;

use lib './lib';
use Daybo::Twitch::Retag;

sub main {
	my $retagger = Daybo::Twitch::Retag->new();
	return $retagger->run('.');
}


exit(main()) unless (caller());

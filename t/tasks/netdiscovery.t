#!/usr/bin/perl

use strict;
use warnings;
use lib 't/lib';
use UNIVERSAL::require;
use Config;

use Test::Exception;
use Test::More;
use Test::Deep qw(cmp_deeply);

use FusionInventory::Agent::Logger;

# check thread support availability
if (!$Config{usethreads} || $Config{usethreads} ne 'define') {
    plan skip_all => 'thread support required';
}

FusionInventory::Agent::Task::NetDiscovery->use();

# Setup a target with a Test logger and debug
my $logger = FusionInventory::Agent::Logger->new(
    logger  => [ 'Test' ],
    debug   => 1
);

my %arp_test = (
    'linux' => {
        ip      => "192.168.0.3",
        device  => {
            DNSHOSTNAME => "hostname.test",
            MAC         => "00:8d:b9:37:4a:c2"
        }
    },
    'win32' => {
        ip      => "192.168.0.1",
        device  => {
            MAC         => "00:80:0c:07:ae:d3"
        }
    },
    'none' => {
        ip      => "192.168.0.1",
        device  => {}
    },
    # No file needed to simulate a wrong API call
    'noip' => {
        device  => {}
    },
    # No file behind to simulate a command exec failure
    'nothing' => {
        ip      => "192.168.0.1",
        device  => {}
    },
);

plan tests => scalar keys %arp_test ;

foreach my $arp_case (keys(%arp_test)) {

    my $self = {
        logger => $logger
    };
    bless $self, "FusionInventory::Agent::Task::NetDiscovery";

    my %device = $self->_scanAddressByArp(
        ip      => $arp_test{$arp_case}->{ip},
        logger  => $logger,
        file    => "resources/generic/arp/$arp_case"
    );

    cmp_deeply(
        $arp_test{$arp_case}->{device}, \%device,
        "$arp_case: arp test"
    );

}

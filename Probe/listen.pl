#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;

$| = 1;
my $socket = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1', LocalPort => 44334, Proto => 'udp', ReuseAddr => 0
) or die "bind failed: $!\n";
print "listening on 127.0.0.1:44334\n";
local $SIG{ALRM} = sub { die "listener timeout\n" };
alarm 35;
for (1 .. 20) {
    my $sender = $socket->recv(my $message, 1024);
    die "recv failed: $!\n" unless defined $sender;
    print "$message\n";
}

#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;

my $socket = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1', PeerPort => 44333, Proto => 'udp'
) or die "socket failed: $!\n";
my $session = time() * 1000 + $$;
my $sequence = 0;
for (1 .. 4) {
    my $request = pack('a4 v v Q< Q< Q< V v v',
        'MSH2', 1, 8, $session, 0, ++$sequence, 3, 60, 0);
    $socket->send($request) or die "send failed: $!\n";
    print "subscribe sent seq=$sequence\n";
    local $SIG{ALRM} = sub { die "no feature packet within 3 seconds\n" };
    eval {
        alarm 3;
        my $sender = $socket->recv(my $response, 1024);
        alarm 0;
        die "recv failed: $!\n" unless defined $sender;
        my ($magic, $type, $length) = unpack('a4 v v', $response);
        print "packet magic=$magic type=$type payload=$length bytes=" . length($response) . "\n";
    };
    alarm 0;
    print $@ if $@;
    sleep 2;
}


use strict;
use Socket;
use IO::Socket;
use IO::Select;

my $port = 12345;
my $server = 'localhost';

my $sock = new IO::Socket::INET(PeerAddr => $server, PeerPort => $port, Proto => 'tcp');
my $sock_set = new IO::Select->new();

send($sock, "hello server \n", 0);

if ($sock) {
    my $ping_count = 10;
    $sock_set->add($sock);
    while (1) {
        my $line;
        while ($sock_set->can_read(0.02)) {
            $line = $sock->getline;
            print " $ping_count : $line " if $line;
            last if (!$line or $line =~ /done/);
        }
        last if ($line =~ /done/);
        if ($ping_count > 0) {
            send($sock, "ping $ping_count \n", 0);
        }
        $ping_count = $ping_count - 1;
        if ($ping_count == 0) {
            send($sock, "done \n", 0);
            print "done sent\n";
        }
    }

    $sock_set->remove($sock);
    close $sock;
}
else {
    print "failed to connect to $server \n";
}


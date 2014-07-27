
use strict;
use Socket;
use IO::Socket;
use IO::Select;

my $port = 12345;
my $proto = getprotobyname('tcp');
my $server = 'localhost';

my ($listen_sock, $sock_set);

$listen_sock = new IO::Socket::INET(LocalHost=>$server, 
                                    LocalPort=>$port, 
                                    Proto=>'tcp', 
                                    Listen=>1, 
                                    Reuse=>1);
print "SERVER started on port $port \n";

$sock_set = IO::Select->new();
$sock_set->add($listen_sock);

while (1) {
    my $so;
    my @ready = $sock_set->can_read(0);
    foreach $so(@ready) {
        if ($so == $listen_sock) {
            my ($client);
            my $addrinfo = accept($client, $listen_sock);

            my ($port, $iaddr) = sockaddr_in($addrinfo);
            my $name = gethostbyaddr($iaddr, AF_INET);

            print "connection accepted from $name : $port \n";

            send($client, "Hello from server\n", 0);
            $sock_set->add($client);
        }
        else {
            my $inp;
            chop($inp = $so->getline);
            chop($inp);
            print "received -- $inp \n";
            send($so, "OK: $inp\n", 0);

            if ( $inp =~ /^done/ or !$inp ) {
                print "close clien\n";
                $sock_set->remove($so);
                close $so;
            }
        }
    }
    sleep(0.1);
}



use strict;
use Socket;
use IO::Socket;

my $port = 12345;
my $proto = getprotobyname('tcp');
my $server = 'localhost';

my ($listen_sock, $sock_set);
socket($listen_sock, PF_INET, SOCK_STREAM, $proto) or die "failed to open socket $!\n";
setsockopt($listen_sock, SOL_SOCKET, SO_REUSEADDR, 1);
bind($listen_sock, pack_sockaddr_in($port, inet_aton($server))) or die "failed to bind port $port \n";
listen($listen_sock, 5);

my $client_addr;
while ($client_addr = accept($clnt_sock, $listen_sock)) {
    my $name = gethostbyaddr($client_addr, AF_INET);
    print $clnt_sock "smile from server";
    print "connection received from $name\n";
    close $clnt_sock;
}


# my $sock;
# socket($sock, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2]) or die "failed to create socket $!\n";
# connect($sock, pack_sockaddr_in($port, inet_aton($server))) or die "failed to connect to port $port \n";


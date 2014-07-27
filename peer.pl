
use strict;
use warnings;
use Socket;
use IO::Socket;
use IO::Select;
use IO::Pipe;
use IO::Handle;

my %peer0 = ( name => "peerA", server => "localhost", port =>"12345", init_role => "master" );
my %peer1 = ( name => "peerB", server => "localhost", port =>"12346", init_role => "slave" );
my %peer2 = ( name => "peerC", server => "localhost", port =>"12347", init_role => "slave" );
my @peer_list = ( \%peer0, \%peer1, \%peer2 );
my %env = ( peer_list => \@peer_list, 
            conn_retry_time => 10,
            lease_timeout => 10,
            state => "Uninitialized",
          );


sub initialize_peer
{
    my ($env_ref, $peer_id) = @_;
    my ($id, $self, $listen_sock, $io_set) = 0;

    foreach my $peer (@{$env_ref->{"peer_list"}}) {
        $env_ref->{"peers"}->{$id} = $peer;
        $peer->{"id"} = $id;
        $peer->{"state"} = "DISCONNECTED";
        $peer->{"last_conn_time"} = 0;
        $id = $id + 1;
    }
    $env_ref->{"self_id"} = $peer_id;
    $env_ref->{"group_size"} = 3;
    $env_ref->{"group_quorum"} = 2;
    $env_ref->{"connected_peer"} = 0;

    $self = $env_ref{"peers"}->{$peer_id};
    $listen_sock = new IO::Socket::INET(LocalHost => $self->{"server"}, 
                                        LocalPort => $self->{"port"},
                                        Proto => 'tcp', 
                                        Listen => 1,
                                        Reuse => 1
                                       );
    return 1 if (! $listen_sock);
    $env_ref->{"listen_sock"} = $listen_sock;

    $io_set = IO::Select->new();
    $env_ref->{"io_set"} = $io_set;
    $io_set->add($listen_sock);

    $env_ref->{"state"} = "INITIALIZED";
    $env_ref->{"connected_peer"} = 1;
    return 0;
}

sub try_connect_peer
{
    my ($env_ref, $peer, $timeout) = @_;
    my ($peer_sock, $rc);

    $rc = 1;
    $peer_sock = new IO::Socket::INET(PeerAddr => $peer->{"server"},
                                      PeerPort => $peer->{"port"},
                                      Proto => 'tcp', 
                                      Timeout => $timeout,
                                     );
    if ($peer_sock) {
        $peer->{"state"} = "CONNECTED";
        $peer->{"sock"} = $peer_sock;
        $env_ref->{"io_set"}->add($peer_sock);
        $rc = 0;
    }

    return $rc;
}

sub start_peer_process
{
    my ($env_ref, $peer) = @_;
    my ($peer_name, $req_pipe1, $req_pipe2, $peer_pid);

    $peer_name = $peer->{"name"};
    $req_pipe1 = IO::Pipe->new();
    $req_pipe2 = IO::Pipe->new();
    $env_ref->{$peer_name}->{"writer"} = $req_pipe1;
    $env_ref->{$peer_name}->{"reader"} = $req_pipe2;
    if ($peer_pid = fork()) {
        $env_ref->{$peer_name}->{"pid"} = $req_pid;
        $env_ref->{$peer_name}->{"writer_fh"} = $req_pipe1->writer();
        $req_pipe1->autoflush();
        $env_ref->{$peer_name}->{"reader_fh"} = $req_pipe2->reader();
        $env_ref->{"io_set"}->add($env_ref->{$peer_name}->{"reader_fh"});
    }
    else {
        $env_ref->{$peer_name}->{"reader_fh"} = $req_pipe1->reader();
        $env_ref->{$peer_name}->{"writer_fh"} = $req_pipe2->writer();
        $req_pipe2->autoflush();
        peer_process($env_ref, $peer);
    }
}

sub start_master_request_process
{
    my ($env_ref) = @_;
    my ($req_pipe1, $req_pipe2, $req_pid);

    $req_pipe1 = IO::Pipe->new();
    $req_pipe2 = IO::Pipe->new();
    $env_ref->{"req"}->{"writer"} = $req_pipe1;
    $env_ref->{"req"}->{"reader"} = $req_pipe2;
    if ($req_pid = fork()) {
        $env_ref->{"req"}->{"pid"} = $req_pid;
        $env_ref->{"req"}->{"writer_fh"} = $req_pipe1->writer();
        $req_pipe1->autoflush();
        $env_ref->{"req"}->{"reader_fh"} = $req_pipe2->reader();
        $env_ref->{"io_set"}->add($env_ref->{"req"}->{"reader_fh"});
    }
    else {
        $env_ref->{"req"}->{"reader_fh"} = $req_pipe1->reader();
        $env_ref->{"req"}->{"writer_fh"} = $req_pipe2->writer();
        $req_pipe2->autoflush();
        master_request_process($env_ref);
    }
}

sub start_master_voting_process
{
}

sub main_loop
{
    my ($env_ref) = @_;
    my ($peer, $rc);
    while (1) {
        # check peer connection
        foreach $peer (@{$env_ref->{"peer_list"}}) {
            next if ($peer->{"id"} eq $env_ref->{"id"});
            next if ($peer->{"state"} eq "CONNECTED");
            next if (time > $peer->{"last_conn_time"} + $env_ref->{"conn_retry_time"});
            $rc = try_connect_peer($env_ref, $peer);
            $peer->{"last_conn_time"} = time;
            if ($rc) {
                print "retry connect " . $peer->{"name"} . " failed.\n";
            } else {
                print "connected with " . $peer->{"name"} . " \n";
            }
        }

        # get req
        sleep(0.1);
    }
}

sub main 
{
    my ($env_ref, $peer_id) = @_;

    my ($rc) ;

    $rc = initialize_peer($env_ref, $peer_id);
    if ($rc) {
        print "Failed to peer (id=$peer_id). \n";
        exit ($rc);
    }

    foreach $peer (@{$env_ref->{"peer_list"}}) {
        next if ($peer->{"id"} eq $env_ref->{"id"});
        start_peer_process($env_ref, $peer);
    }
    start_master_request_process($env_ref);
    start_master_voting_process($env_ref);

    print "to start ", $env_ref->{"peers"}->{$peer_id}->{"name"}, "\n";
    main_loop($env_ref);
}

if ($#ARGV < 0) {
    print "Usage: \n";
    print "\t peer.pl <peer_id> \n";
    print "peer_id : 0 - 2 \n";
    exit(0);
}
my $peer_id = $ARGV[0];
main (\%env, $peer_id) ;


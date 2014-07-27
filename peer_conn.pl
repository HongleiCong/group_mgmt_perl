
use strict;
use warnings;
use Socket;
use IO::Socket;
use IO::Select;
use IO::Pipe;
use IO::Handle;

sub add_timer_func
{
    my ($env_ref, $next_time, $func) = @_;
    my $timer_list = $env_ref->{"timer_list"};
    my %timer_func = { time => $next_time,
                       func => $func,
                     };
    $timer_list->push(\%timer_func);
}

sub add_io_func
{
    my ($env_ref, $fh, $func) = @_;
    my $io_list = $env_ref->{"io_list"};
    my %io_func = { fh => $fh,
                    func => $func,
                  };
    $io_list->push(\%io_func);
}

sub connect_peer
{
    my ($env_ref, $peer) = @_;
    my ($sock, $curr_time);

    my $next_time = time + $env_ref->{"conn_retry_time"};
    $sock = new IO::Socket::INET(PeerAddr => $peer->{"server"}, 
                                 PeerPort => $peer->{"port"},
                                 Proto => 'tcp',
                                 Timeout => 3);
    if ($sock) {
        # send connected to main
        # add io_func to io_list
        add_io_func($env_ref, $sock, \&on_request_from_peer);
    }
    else {
        add_timer_func($env_ref, $next_time, \&connect_peer);
    }
}


sub on_request_from_main
{
    my ($env_ref, $peer, $fh) = @_;
    my ($req, $sock);

    $req = $fh->getline;
    if (uc $req =~ /^CONNECT/) {
        connect_peer($env_ref, $peer);
    }
    elsif (uc $req =~ /^SEND/) {
    }
    elsif (uc $req =~ /^STATUS/) {
    }
}

sub on_request_from_peer
{
    my ($env_ref, $peer, $fh) = @_;
}

sub peer_process 
{
    my ($env_ref, $peer) = @_;
    my ($reader_fh, $writer_fh, $peer_name, $req, $rsp);
    my ($io_set, @io_list, @timer_list);

    @io_list = ();
    @timer_list = ();

    $peer_name = $peer->{"name"};
    $reader_fh = $env_ref->{}->{"reader_fh"};
    $writer_fh = $env_ref->{"req"}->{"writer_fh"};
    $io_set = IO::Select->new();
    $env_ref->{"io_set"} = $io_set;
    $env_ref->{"io_list"} = \@io_list;
    $env_ref->{"time_list"} = \@timer_list;

    $io_set->add($reader_fh);
    add_io_func($env_ref, $reader_fh, \&on_request_from_main);


    while (1) {
        my @ready = $io_set->can_read(0);
        foreach my $fh (@ready) {
            foreach my $fh_func (@io_list) {
                if ($fh == $fh_func->{"fh"}) {
                    my $func = $fh_func->{"func"};
                    $func->($env_ref, $peer, $fh);
                    last;
                }
            }
        }

        foreach my $timer_fn (@timer_list) {
            last if ($timer_fn->{"time"} > time);
            my $func = $timer_fn->{"func"};
            $func->($env_ref, $peer);
            shift @timer_list;
        }

        sleep(0.5);
    }

    while ($req = $reader_fh->getline()) {
        print $writer_fh "ACK: $req";
        if ($req =~ /^CONNECT/) {
            on_start($env_ref);
        }
        else {
            # unknown request
        }
    }

    exit(0);
}


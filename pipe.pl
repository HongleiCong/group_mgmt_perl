
use strict;
use warnings;
use IO::Pipe;
use IO::Handle;

my $req_pipe = IO::Pipe->new();
my $rsp_pipe = IO::Pipe->new();

if (my $pid = fork()) {
    my $req_fh = $req_pipe->writer();
    $req_pipe->autoflush();
    my $rsp_fh = $rsp_pipe->reader();

    my $time = localtime;
    print "parent $time\n";

    for (my $i = 0; $i < 1000; $i++) {
        print $req_fh "request $i\n";
        sleep (0);
        my $rsp = $rsp_fh->getline();
        print "rsp: $rsp \n";
    }
    print $req_fh "done\n";

    while (my $rsp = $rsp_fh->getline()) {
        last if ($rsp =~ /^quit/);
        print "rsp: $rsp \n";
    }

    waitpid($pid, 0);
    $time = localtime;
    print "$time \n";
}
else {
    print "child \n";
    my $req_fh = $req_pipe->reader();
    my $rsp_fh = $rsp_pipe->writer();
    $rsp_pipe->autoflush();

    while (my $req = $req_fh->getline()) {
        print $rsp_fh "processed $req";
        last if ($req =~ /^done/);
    }
    print $rsp_fh "quit\n";
    exit(0);
}

1;




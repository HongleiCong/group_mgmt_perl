
#!/usr/bin/perl -w

use strict;

use IO::Select;
use IO::Pipe;
use IO::Handle;

my $debug = 1;

my @connect = ("3","2","1");

my %msgs;
@msgs{@connect} = qw/hooray hip hip/;

my $select_ch = IO::Select->new();

foreach my $msg (@connect) {
    # for each write, fork a child
    if ($msg) {
        # fork and open child for reading
        my $pipe = IO::Pipe->new();

        if (my $pid = fork() ) {
            #parent
            my $fh = $pipe->reader();
            $debug && print "parent $$ forked $pid\n";
            $fh->blocking(0);    # set non-blocking I/O
            $debug && print "parent adding readable filehandle ($fh)\n";
            $select_ch->add($fh);
        } else {
            #child
            my $childhandle = $pipe->writer();
            my $mt = $msgs{$msg};
            sleep $msg;
            print STDERR "$$ child $msg writing to pipe $msg, response $mt
+\n";
            print $childhandle "child $msg, response $mt";
            exit 0;        #kill the child process
        }
    }
}                # done with processing this read

# here we read for responses from the filehandles
my @readyfiles;            #array for select to populate
while ( @readyfiles = $select_ch->can_read() ) {
    foreach my $rh (@readyfiles) {
        # read from filehandle, send back string

        print "$$ calling IO::Handle::getline\n";

        my $child_resp_string = $rh->getline();

        $debug && print "$$ read |$child_resp_string|\n";

        # only one read per handle, so close
        $debug && print "$$ removing @{[ref $rh]}\n";
        $select_ch->remove($rh);
        $rh->close;

        $debug && print "$$ @{[$select_ch->count()]} handles left to read\n";    
    }
}
print "exiting...\n";
exit 0;


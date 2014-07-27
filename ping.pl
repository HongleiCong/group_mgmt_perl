
package ping;

use strict;
use Fcntl qw( F_GETFL F_SETFL O_NONBLOCK );
use Socket qw( SOCK_DGRA SOCK_STREAM SOCK_RAW PF_INET SOL_SOCKET SO_ERROR
               AF_INET inet_aton inet_ntoa sockaddr_in );
use Socket6 qw ( AF_INET6 PF_INET6 inet_pton sockaddr_in6 );
use POSIX qw( ENOTCONN ECONNREFUSED ECONNRESET EINPROGRESS EWOULDBLOCK EAGAIN WNOHANG );
use FileHandle;
use Net::Ping;

# default consts
my $def_timeout = 3;
my $def_proto = "icmp";
my $def_datasize = 32;
my $max_datasize = 256;


sub new
{
    my ($this,
        $proto,
        $timeout,
        $data_size,
        ) = @_;

    my $class = ref($this) || $this;
    my $self = {};
    bless($self, $class);

    my $pf_type = PF_INET;
    $proto = $def_proto unless $proto;
    $timeout = $def_timeout unless $timeout;
    $data_size = $def_datasize unless $data_size;
    $data_size = $max_datasize if ($data_size > $max_datasize);
    $pf_type = PF_INET6 if ($proto eq "ipv6-icmp");

    $self->{"proto"} = $proto;
    $self->{"timeout"} = $timeout;
    $self->{"data_size"} = $data_size;
    for (my $cnt = 0; $cnt < $data_size; $cnt++) {
        $self->{"data"} .= chr($cnt % 256);
    }

    $self->{"seq"} = 0;
    $self->{"proto_num"} = (getprotobyname($self->{"proto"}))[2] 
                           || print ("Failed to get proto by name \n");
    $self->{"pid"} = $$ & 0xffff;
    $self->{"fh"} = FileHandle->new();
    socket($self->{"fh"}, $pf_type, SOCK_RAW, $self->{"proto_num"}) 
                           || print ("socket error - $! \n");

    return ($self);
}
 
sub ping 
{
    my ($self, $host) = @_;
    my ($ip, $ret);

    $ip = inet_aton($host) if ($self->{"proto"} eq "icmp");
    $ip = inet_pton(AF_INET6, $host) if ($self->{"proto"} eq "ipv6-icmp");
    return () unless defined($ip);

    if (($self->{"proto"} eq 'icmp')) {
        $ret = $self->ping_icmp($ip);
    }
    elsif (($self->{"proto"} eq 'ipv6-icmp')) {
        $ret = $self->ping_icmp6($ip);
    }
    else {
        print ("Unknown protocol \"$self->{proto}\" in afm_ping() \n");
    }

    return $ret;
}

use constant ICP_ECHOREPLY    => 0;
use constant ICP_UNREACHABLE  => 3;
use constant ICP_ECHO         => 8;
use constant ICP_SUBCODE      => 0;

use constant ICP6_ECHOREPLY   => 129;
use constant ICP6_UNREACHABLE => 1;
use constant ICP6_ECHO        => 128;
use constant ICP6_SUBCODE     => 0;

use constant ICP_STRUCT       => "C2 n3 A";
use constant ICP_FLAGS        => 0;
use constant ICP_PORT         => 0;

sub ping_icmp
{
    my ($self, $ip) = @_;
    my ($checksum, $msg, $len_msg, $saddr);

    $self->{"seq"} = ($self->{"seq"} + 1) % 65536;
    $checksum = 0;
    $msg = pack(ICP_STRUCT . $self->{"data_size"}, ICMP_ECHO, ICMP_SUBCODE,
                $checksum, $self->{"pid"}, $self->{"seq"}, $self->{"data"});
    $checksum = Net::Ping->checksum($msg);
    $msg = pack(ICP_STRUCT . $self->{"data_size"}, ICMP_ECHO, ICMP_SUBCODE,
                $checksum, $self->{"pid"}, $self->{"seq"}, $self->{"data"});
    $len_msg = length($msg);
    $saddr = sockaddr_in(ICP_PORT, $ip);
    $self->{"ping_time"} = time();
    $self->{"from_ip"} = undef;
    $self->{"from_type"} = undef;
    $self->{"from_subcode"} = undef;
    send($self->{"fh"}, $msg, ICP_FLAGS, $saddr);

    return 0;
}

sub ping_icmp6
{
    my ($self, $ip) = @_;
    my ($checksum, $msg, $len_msg, $saddr);

    $self->{"seq"} = ($self->{"seq"} + 1) % 65536;
    $checksum = 0;
    $msg = pack(ICP_STRUCT . $self->{"data_size"}, ICMP6_ECHO, ICMP6_SUBCODE,
                $checksum, $self->{"pid"}, $self->{"seq"}, $self->{"data"});
    $checksum = Net::Ping->checksum($msg);
    $msg = pack(ICP_STRUCT . $self->{"data_size"}, ICMP6_ECHO, ICMP6_SUBCODE,
                $checksum, $self->{"pid"}, $self->{"seq"}, $self->{"data"});
    $len_msg = length($msg);
    $saddr = sockaddr_in6(ICP_PORT, $ip);
    $self->{"ping_time"} = time();
    $self->{"from_ip"} = undef;
    $self->{"from_type"} = undef;
    $self->{"from_subcode"} = undef;
    send($self->{"fh"}, $msg, ICP_FLAGS, $saddr);

    return 0;
}

sub ack
{
    my ($self, $ip, $timeout) = @_;
    my $ret;
    $timeout = $self->{"timeout"} unless $timeout;
    $timeout = 0.1 if ($self->{"ping_time"} + $timeout < time());

    if (($self->{"proto"} eq 'icmp')) {
        $ret = $self->ack_icmp($ip, $timeout);
    }
    elsif (($self->{"proto"} eq 'ipv6-icmp')) {
        $ret = $self->ack_icmp($ip, $timeout);
    }
    else {
        print ("Unknown protocol \"$self->{proto}\" in afm_ping() \n");
    }

    return $ret;
}

sub ack_icmp
{
    my ($self, $ip, $timeout) = @_;
    my ($rbits, $ret, $done, $finish_time, $nfound);
    $ret = 0;
    $done = 0;

    $rbits = "";
    vec($rbits, $self->{"fh"}->fileno(), 1) = 1;
    $finish_time = time() + $timeout;
    while (!$done && $timeout > 0)
    {
        $nfound = mselect((my $rout=$rbits), undef, undef, $timeout);
        $timeout = $finish_time - time();
        if (!defined($nfound))
        {
            $ret = undef;
            $done = 1;
        }
        elsif ($nfound) 
        {
            if (($self->{"proto"} eq 'icmp')) {
                ($ret, $done) = $self->process_icmp_reply($ip);
            }
            elsif (($self->{"proto"} eq 'ipv6-icmp')) {
                ($ret, $done) = $self->process_icmp6_reply($ip);
            }
            else {
                $done = 1;
            }
        } else {
          $done = 1;
        }
    }

    return $ret;
}

sub process_icmp_reply
{
    my ($self, $ip) = @_;

    my ($ret, $done, $recv_msg, $from_pid, $from_seq, $from_saddr, $from_port, $from_ip, 
        $from_type, $from_subcode, $from_msg);

    $done = 0;
    $recv_msg = "";
    $from_pid = -1;
    $from_seq = -1;
    $from_saddr = recv($self->{"fh"}, $recv_msg, 1500, ICP_FLAGS);
    ($from_port, $from_ip) = sockaddr_in($from_saddr);
    ($from_type, $from_subcode) = unpack("C2", substr($recv_msg, 20, 2));
    if ($from_type == ICP_ECHOREPLY) {
      ($from_pid, $from_seq) = unpack("n3", substr($recv_msg, 24, 4)) if length $recv_msg >= 28;
    } else {
      ($from_pid, $from_seq) = unpack("n3", substr($recv_msg, 52, 4)) if length $recv_msg >= 56;
    }
    $self->{"from_ip"} = $from_ip;
    $self->{"from_type"} = $from_type;
    $self->{"from_subcode"} = $from_subcode;
    if (($from_pid == $self->{"pid"}) && ($from_seq == $self->{"seq"})) {
        if ($from_type == ICP_ECHOREPLY) {
            $ret = 1;
            $done = 1;
        } elsif ($from_type == ICP_UNREACHABLE) {
            $done = 1;
        }
    }

    return ($ret, $done);
}

sub process_icmp6_reply
{
    my ($self, $ip) = @_;

    my ($ret, $done, $recv_msg, $from_pid, $from_seq, $from_saddr, $from_port, $from_ip, 
        $from_type, $from_subcode, $from_msg);

    $done = 0;
    $recv_msg = "";
    $from_pid = -1;
    $from_seq = -1;
    $from_saddr = recv($self->{"fh"}, $recv_msg, 1500, ICP_FLAGS);
    ($from_port, $from_ip) = sockaddr_in6($from_saddr);
    ($from_type, $from_subcode) = unpack("C2", substr($recv_msg, 0, 2));
    if ($from_type == ICP6_ECHOREPLY) {
      ($from_pid, $from_seq) = unpack("n3", substr($recv_msg, 4, 4)) if length $recv_msg >= 28;
    } else {
      ($from_pid, $from_seq) = unpack("n3", substr($recv_msg, 32, 4)) if length $recv_msg >= 56;
    }
    $self->{"from_ip"} = $from_ip;
    $self->{"from_type"} = $from_type;
    $self->{"from_subcode"} = $from_subcode;
    if (($from_pid == $self->{"pid"}) && ($from_seq == $self->{"seq"})) {
        if ($from_type == ICP6_ECHOREPLY) {
            $ret = 1;
            $done = 1;
        } elsif ($from_type == ICP6_UNREACHABLE) {
            $done = 1;
        }
    }

    return ($ret, $done);
}

sub mselect
{
    if ($_[3] > 0 and $^O eq 'SWin32') {
        my $t = $_[3];
        my $gran = 0.5;
        my @args = @_;
        while (1) {
            $gran = $t if $gran > $t;
            my $nfound = select($_[0], $_[1], $_[2], $gran);
            undef $nfound if $nfound == -1;
            $t -= $gran;
            return $nfound if $nfound or !defined($nfound) or $t <= 0;
        
            sleep(0);
            ($_[0], $_[1], $_[2]) = @args;
        }
    }
    else {
        my $nfound = select($_[0], $_[1], $_[2], $_[3]);
        undef $nfound if $nfound == -1;
        return $nfound;
    }
}

sub close
{
    my ($self) = @_;

    $self->{"fh"}->close();
}

sub add_ping_event
{
    my ($this,
        $env_ref,
        $opt_ref,
        $user_ref,
        $ip,
        $event,
        ) = @_;

}

sub wait_ack
{
    my ($this,
        $env_ref,
        $opt_ref,
        $user_ref,
        $ip_list,
        $timeout,
        ) = @_;

}

sub wait_ack
{
    my ($this,
        $env_ref,
        $opt_ref,
        $user_ref,
        ) = @_;

}



1;

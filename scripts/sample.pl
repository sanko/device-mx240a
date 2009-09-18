#!perl -I../lib
use strict;
use warnings;

# http://cvs.sourceforge.net/viewcvs.py/mx240ad/IMopen/protocol-notes?rev=1.2.2.3&view=markup
# http://cvs.sourceforge.net/viewcvs.py/mx240ad/mx240ad/mx240a-protocol.txt?rev=1.4&view=markup
$|++;
use Device::MX240a::Win32;
my $base = Device::MX240a::Win32->new();

die q[Failed to contact base.] if !$base;


if(0){
$base->write(0xef . 0x01 . 0x01 );
my $s = 230;
for (0..9) {
    $base->write(pack q[C], $_ + $s);
    $base->read;
}
$base->write(pack q[C], 0xca);    # 5445 53e3 0060 6000  TES.....
$base->read;
$base->read;
$base->read;
$base->read;
die;
$base->write(pack q[C], 0xfb); # 5445 53e3 0060 6000  TES.....
$base->write(pack q[C], 0xab); # 5445 53e3 0060 6000  TES.....
$base->write(pack q[C], 0xbb); # 5445 53e3 0060 6000  TES.....
$base->write(pack q[C], 0x3a); # 5253 5349 00fe 6000  RSSI....
$base->write(pack q[C], 0x7a); # 5253 5349 00fe 6000  RSSI....
$base->write(pack q[C], 0xca); # 5253 5349 00fe 6000  RSSI....
$base->read;



}
my $debug_line = 1;
$base->on_im(
    sub {
        my ($self, $handset, $message) = @_;
        warn q[IM > ] . $message;
        $handset->_send_im($handset->window, scalar reverse $message);
        return;
    }
);
$base->on_connect(
    sub {
        my ($self, $handset) = @_;

        # try to keep it under 16 characters...
        # otherwise, you'll lose some and it'll wrap to higher lines
        # So, if we were to send "Sanko Robinson's IMFree123456789",
        # it would show up as
        # Logging into [service]
        #
        #
        # MFre
        #
        # Handheld Name: Sanko Robinson's
        #
        # return name and list of services
        return (q[Blah!],
                {A => q[ AIM],
                 Y => q[Yahoo!],
                 M => q[ MSN]
                }
        );
    }
);
$base->on_login(
    sub {
        my ($self, $handset) = @_;
        warn sprintf q[Login: %s:%s @ %s], $handset->username,
            $handset->password, $handset->service;
        return 1;    # okay
        return 0;    # deny login
    }
);
$base->on_login_complete(
    sub {
        my ($self, $handset) = @_;
        warn q[Sending fake buddies...];
        for my $buddy ({screenname => q[MX240a Agent],
                        group      => q[Internal]
                       },
                       {screenname => q[perl eval],
                        group      => q[Programs],
                        away       => 1
                       },
                       {screenname => q[Sanko],
                        group      => q[Internal],
                        idle       => 1
                       },
                       {screenname => q[system],
                        group      => q[Programs],
                        mobile     => 1
                       },
            )
        {   $handset->_buddy_in($buddy);   }
    }
);
$base->on_window_open(
    sub {
        my ($self, $handset, $buddy, $with_ack) = @_;
        warn sprintf
            q[(H|%d) Open Window with buddy #%d (%s)?%s],
            $handset->id, $handset->window, $buddy->{q[screenname]},
            $with_ack ? qq[\n WITH ACK!!!] : q[];
        return 1;
    }
);
$base->on_window_close(
    sub {
        my ($self, $handset) = @_;
        warn q[Close Window];
        return 1;
    }
);

# General
$base->on_data_in(
    sub {
        my ($self, $data) = @_;
        print_hex(q[<], $data);
    }
);
$base->on_data_out(
    sub {
        my ($self, $data) = @_;
        print_hex(q[>], $data);
    }
);


$base->do_one_loop while 1;
exit;



    sub hexdump {
        my ( $stuff, $forcehex) = @_;
        return '' if !defined $stuff;
        $forcehex = 0 if !defined $forcehex;
        my $retbuff = '';
        my @stuff = split '', $stuff;
        return $stuff
            unless $forcehex
                or grep { $_ lt chr(0x20) or $_ gt chr(0x7E) } @stuff;
        while (@stuff) {
            $retbuff .= qq[\n\t];
            my @currstuff = splice(@stuff, 0, 16);
            {
                my $i = 0;
                foreach my $currstuff (@currstuff) {
                    $retbuff .= ' ' unless $i % 4;
                    $retbuff .= ' ' unless $i % 8;
                    $retbuff .= sprintf "%02X ", ord($currstuff);
                    $i++;
                }
                for my $j ($i .. 16) {
                    $retbuff .= ' ' unless $j % 4;
                    $retbuff .= ' ' unless $j % 8;
                    $retbuff .= '   ';
                }
            }
            $retbuff .= '  ';
            {
                my $i = 0;
                foreach my $currstuff (@currstuff) {
                    $retbuff .= ' ' unless $i % 4;
                    $retbuff .= ' ' unless $i % 8;
                    if ($currstuff ge chr(0x20) and $currstuff le chr(0x7E)) {
                        $retbuff .= $currstuff;
                    }
                    else {
                        $retbuff .= '.';
                    }
                    $i++;
                }
            }
        }
        return $retbuff;
    }


sub print_hex {
    my ($direction, $read) = @_;
    return print hexdump($read, 1);
    $read =~ s|^\0||;
    my $write = q[];
    my (@sets) = $read =~ m[(..)]g;
    for my $set (@sets) {

        #printf q[%04d ], ord($char);
        my ($hi, $lo) = split q[], $set;
        $write
            .= sprintf(q[%.2x%.2x ], ord($hi), ord($lo)); # convert dec to hex
              #print unpack("H*", pack("N",255)); # convert dec to hex
    }
    $read =~ s|[^\w\d\s]|.|g;
    return printf qq[%08d %s %s %s\n], ++$debug_line,
        $direction,
        $write, $read;
}

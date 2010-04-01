{

    package Device::MX240a;
    use strict;
    use warnings;
    use Carp qw[carp confess];
    use Scalar::Util qw[refaddr];
    use lib q[../../lib];
    use Device::MX240a::Handset;

    # Constants
    sub MX240A_VENDOR  { return q[22b8] }
    sub MX240A_PRODUCT { return q[7f01] }
    sub READ_SIZE      {16}
    sub WRITE_SIZE     {16}
    our $VERSION = 1.0.0;
    my @REGISTRY =
        \my (%handle,             %data_in,         %handsets,
             %_on_data_in,        %_on_data_out,    %_on_im,
             %_on_registration,   %_on_connect,     %_on_login,
             %_on_login_complete, %_on_window_open, %_on_window_close,
             %buff_data, %last_sent
        );

    sub new {    # no args... yet.
        my ($class, $args) = @_;
        my $self = bless \$class, $class;
        my $handle = (($^O =~ m[Win32])
                      ? Device::MX240a::Win32->_open($self, $args)
                      : Device::MX240a::libusb->_open($self, $args)
        );
        return if !$handle;
        $handle{refaddr $self}  = $handle;
        $data_in{refaddr $self} = q[];
        return $self->_init_USB ? $self : ();
    }
    sub _handle { return $handle{refaddr +shift} }

    sub ACK {
        my ($self, $expect_NAK) = @_;
        $self->write(pack('C2', 0xad, 0xff), 1) || return;
        if ($expect_NAK) { $self->read() or return; }
        return 1;
    }
    my %id_dispatch;
    %id_dispatch = (
        a => sub {    # IM
            my ($self, $num) = @_;
            my $handset = (defined $handsets{refaddr $self}{$num}
                           ? $handsets{refaddr $self}{$num}
                           : Device::MX240a::Handset->new({id   => $num,
                                                           base => $self
                                                          }
                           )
            );
            $handsets{refaddr $self}{$num} = $handset;
            $self->_read_IM($handset);
        },
        c => sub {
            my ($self, $num) = @_;
            my $handset = (defined $handsets{refaddr $self}{$num}
                           ? $handsets{refaddr $self}{$num}
                           : Device::MX240a::Handset->new({id   => $num,
                                                           base => $self
                                                          }
                           )
            );
            $handsets{refaddr $self}{$num} = $handset;

            # same as d, but for NAK
        },
        d => sub {    # address handset N (recv message, partial)
            my ($self, $num) = @_;
            my $handset = (defined $handsets{refaddr $self}{$num}
                           ? $handsets{refaddr $self}{$num}
                           : Device::MX240a::Handset->new({id   => $num,
                                                           base => $self
                                                          }
                           )
            );
            $handsets{refaddr $self}{$num} = $handset;
            $self->_read_IM($handset);
        },
        e => sub {    # 'administration'/chat/extra functionality
            my ($self, $num, $func) = @_;
            my $handset = (defined $handsets{refaddr $self}{$num}
                           ? $handsets{refaddr $self}{$num}
                           : Device::MX240a::Handset->new({id   => $num,
                                                           base => $self
                                                          }
                           )
            );
            $handsets{refaddr $self}{$num} = $handset;
            if ('f' eq $num) {    # init base ACK?
                $self->ACK(1);
            }
            elsif ($num == 0) {    # someone's trying to register
                $self->write(pack 'C2', 0xee, 0xd3);    # reg: we like you!
                    #$self->write(pack q[C2], 0xee, 0xc5); # reg: ...rejected!
                return 1;
            }
            else {    # same as fN, but for NAK
                &{$id_dispatch{'f'}}($self, $num, $func, 1);
            }
        },
        f => sub {    # address handset N (recv message, complete)
            my ($self, $num, $func, $nak) = @_;
            my $handset = (defined $handsets{refaddr $self}{$num}
                           ? $handsets{refaddr $self}{$num}
                           : Device::MX240a::Handset->new({id   => $num,
                                                           base => $self
                                                          }
                           )
            );
            $handsets{refaddr $self}{$num} = $handset;
            if ('fd' eq $func) {    # ACK?
                #$self->write($last_sent{refaddr $self}) if $nak;
                #warn 'FD!!!!!';
                #warn hex($buff_data{refaddr $self}[0]);
                $self->ACK(0) if hex($buff_data{refaddr $self}[0]) == 2;
            }
            elsif ('69' eq $func) {    # ACK?
                $self->ACK(1);
            }
            elsif ('8c' eq $func) {
                if (!defined $buff_data{refaddr $self}[0])
                {                      # handset couldn't contact base ?
                    $self->ACK(1);
                }
                elsif (hex($buff_data{refaddr $self}[0]) == 0xc1)
                {                      # handset shut down?
                    exit;              # testing
                }
                else {

                    #ACK(1);
                }
            }
            elsif ('8e' eq $func) {
                my ($name, $services)
                    = $_on_connect{refaddr $self}
                    ->($self, $handsets{refaddr $self}{$num})
                    if $_on_connect{refaddr $self};
                $self->_send_name($handsets{refaddr $self}{$num}, $name);
                $self->_send_services($handsets{refaddr $self}{$num},
                                      $services);

                # &send_tones;
            }
            elsif ('91' eq $func) {    # sending AIM username
                $handset->_set_service(q[A]);
                my $user = q[];
                while ($data_in{refaddr $self}
                       =~ m|\0(.\x91)?([^\xff]+)?([^\w]*)?|)
                {   $user .= $2;
                    last if length $3;
                    $self->read();
                }
                $handset->_set_username($user);
            }
            elsif ('92' eq $func) {    # sending AIM password
                my $pass = q[];
                while ($data_in{refaddr $self}
                       =~ m|\0(.\x92)?([^\xff]+)?([^\w]*)?|)
                {   last if not $2;
                    $pass .= $2;
                    last if length $3;
                    $self->read();
                }
                $handset->_set_password($pass);
                my $id = $handset->id;
                if (  $_on_login{refaddr $self}
                    ? $_on_login{refaddr $self}->($self, $handset)
                    : 0
                    )
                {   $self->write(pack q[C4], hex(q[e] . $id), 0xd3, 0xff);
                    $self->ACK;

                    # XXX - ...should this exist?
                    $_on_login_complete{refaddr $self}->($self, $handset)
                        if $_on_login_complete{refaddr $self};
                }
                else {
                    return
                        $self->write(pack q[C4], hex('e' . $id),
                                     0xe5, 0x02, 0xff);
                }
            }
            elsif ("94" eq $func) {    # new/newly selected AIM window
                $self->_read_open_window($handset, $buff_data{refaddr $self});
            }
            elsif ("95" eq $func) {
                $_on_window_close{refaddr $self}->($self, $handset)
                    if $_on_window_close{refaddr $self};
                $handset->_close_window();
                if ((q[f1] eq $func)) {
                }
            }
            elsif ("b1" eq $func) {    # YAHOO! stuff
                $handset->_set_service(q[Y]);
                my $user = q[];
                while ($data_in{refaddr $self}
                       =~ m|\0(.\xb1)?([^\xff]+)?([^\w]*)?|)
                {   $user .= $2;
                    last if length $3;
                    $self->read();
                }
                $handset->_set_username($user);
                warn sprintf
                    qq[\t(H|%d) sending Yahoo! username: %s],
                    $handset->id, $handset->username;
            }
            elsif (("b2" eq $func)) {
                my $pass = q[];
                while ($data_in{refaddr $self}
                       =~ m|\0(.\xb2)?([^\xff]+)?([^\w]*)?|)
                {   $pass .= $2;
                    last if length $3;
                    $self->read();
                }
                $handset->_set_password($pass);
                warn sprintf
                    q[\t(H|%d) sending Yahoo! pass: %s | And we're logging in...],
                    $handset->id,
                    $handset->pass;
                my $id = $handset->id;
                if (  $_on_login{refaddr $self}
                    ? $_on_login{refaddr $self}->($self, $handset)
                    : 0
                    )
                {   print "\t\tLogin Ok :)\n";
                    $self->write(pack q[C4], qq[0xe$id], 0xd3, 0xff);
                }
                else {
                    print "\t\tLogin Not Ok :( Let's figure out why...\n";
                    return $self->write(pack q[C4], qq[0xe$id], 0xe5, 0x02,
                                        0xff);
                }
            }
            else {    # IM
                $self->_read_IM($handset);
            }
        },
        8 => sub {    # address handset N (recv message, complete)
            my ($self, $num) = @_;
            my $handset = (defined $handsets{refaddr $self}{$num}
                           ? $handsets{refaddr $self}{$num}
                           : Device::MX240a::Handset->new({id   => $num,
                                                           base => $self
                                                          }
                           )
            );
            $handsets{refaddr $self}{$num} = $handset;
            return $self->_read_IM($handset);
        }
    );

    sub do_one_loop {
        my ($self) = @_;
        $self->read() or return;
        my @buff = map(sprintf("%04d", ord()),
                       split(q[], $data_in{refaddr $self}));
        my @buff_h = map(sprintf("%#.4x", ord()),
                         split(q[], $data_in{refaddr $self}));
        (my ($null, $byte_1st, $byte_2nd), @{$buff_data{refaddr $self}})
            = @buff_h;
        if ($data_in{refaddr $self}) {
            my (undef, undef, undef, undef, $id, $num) = split q[], $byte_1st;
            my (undef, undef, undef, undef, $func) = split q[], $byte_2nd, 5;

            #print "\t[ID:$id|HH#:$num][Func:$func]\n";
            if (defined $id_dispatch{$id}) {
                &{$id_dispatch{$id}}($self, $num, $func);
            }
        }
        return 1;
    }

    sub _read_IM {
        my ($self, $handset) = @_;
        return if !$handset;

        #94    0x81                 talk? not followed by talk ack
        #94    0x02                 talk?
        #94    0x01                 talk? IMfree Agent (in first group)
        my $IM    = q[];
        my $id    = $handset->id;
        my $loops = 1;
        my $regex = qr[^\0([\xa$id\xf$id\xd$id])([^\xff\xfe]*)];

        #warn $regex;
        while (1) {
            #warn qq[loop [$IM|$loops]];
            #if $buf =~ m|\xfe|;
            if ($data_in{refaddr $self} =~ $regex) {

                #warn "[A|$IM|$1|$2|$data_in{refaddr $self}]";
                $IM .= $2 || q[];
                last if $data_in{refaddr $self} =~ m[\xff\xfe?];
                $self->read();
            }
            elsif ($data_in{refaddr $self} =~ m[^\0(.+)\xff]) {

                #warn "[D|$IM|$1|$data_in{refaddr $self}]";
                $IM .= $1;
                last;
                $self->read();
            }
            elsif ($data_in{refaddr $self} =~ m|[^\xff]\xfe?|) {

                #warn "[M|$IM|$1|$data_in{refaddr $self}]";
                $self->ACK(0);
                $self->read;

                #$self->_read_IM($handset);
            }
            else {
                $data_in{refaddr $self} =~ s[^.][];
                $IM .= substr($data_in{refaddr $self},0,8,'');
                #warn "[?|$IM|$data_in{refaddr $self}]";
                #$self->ACK((($data_in{refaddr $self} =~ m[\xfe]) ? 1: 0));
                $self->ACK(0);
                $self->read();
                last;
            }
            $loops++;
        }

=docs
if no terminator, just end after 3 chunks of 8.
if only room for ff in third chunk, put that.
=cut

        $self->ACK(0);
        $_on_im{refaddr $self}->($self, $handset, $IM)
            if $_on_im{refaddr $self};
        return 1;
    }

    sub _read_open_window {
        my ($self, $handset, $buff_data) = @_;
        if (!defined $handset->service()) {
            carp q[No service];
            $handset->_range_error;
            return;
        }
        my $c_im = $buff_data->[0];
        $c_im =~ s|[^\d]||;
        my $buddy = $handset->_locate_buddy_by_id($c_im);
        return if not $buddy;
        $self->ACK(0);
        $_on_window_open{refaddr $self}
            ->($self, $handset, int($c_im), $buddy, ($buff_data->[2] eq q[fe]))
            if $_on_window_open{refaddr $self};
        return $handset->_set_window(int $c_im);;
    }

    sub _send_buddy_in {
        my ($self, $handset, $args) = @_;
        confess if not defined $args;
        my $id         = $handset->id;
        my $screenname = $args->{q[screenname]};
        my $group      = $args->{q[group]};
        $args->{q[away]}   ||= 0;
        $args->{q[mobile]} ||= 0;
        $args->{q[idle]}   ||= 0;
        $args->{q[id]}     ||= int(rand(0xff));

#
#my $num = $handset->_bl_add($args); # size of the bl is also this new buddy's id
#
        my $status = q[ANN];    # basic
        if    ($args->{q[idle]})   { $status =~ s|A|I| }
        elsif ($args->{q[away]})   { $status =~ s|A|U| }
        elsif ($args->{q[mobile]}) { $status =~ s|N|Y| }
        $self->ACK(1);    # Some action on the pipe first... just in case...

#eNca  >    status 0x01-0x3c     0000  X  set buddy status (status: ANN, AYN, UNN)
#ANN = (no icon)
#AYN = Buddy is online using a mobile device
#UNN = Buddy is away
#UYN = Buddy is away
#INN = Buddy is idle
#IYN = Buddy is idle
#warn pp $args;
        $self->write(
             (pack q[C2A3C], hex(q[e] . $id), 0xca, $status, $args->{q[id]}));

        #$self->ACK(1);    # flush the pipe
        $self->write(

            # cNc9  >    group name           ff00  X  send person data
            pack q[C2a6a*C6], hex(q[c] . $id), 0xc9,
            $args->{q[group]},
            $args->{q[screenname]}
            , 0xff, 0x00,

            # aNc9  >    remaining-data       ff00  X  send more person data ?
            hex(q[a] . $id), 0xc9, 0x01, 0xff
        );

        #000102  ]>  e1ca 414e 4e01 0000  ..ANN... # add person
        #000106  ]>  c1c9 2020 4d65 2020  ..  Me   # send person data
        #000107  ]>  494d 6672 6565 2041  IMfree A
        #000108  ]>  6765 6e74 ff00       gent.. A
        #000122  ]>  a1c9 20ff 00         .. ..    # status modifier?
        # flush the pipe
        return $self->ACK(1);
    }

    sub _send_services {    # XXX - send more than one service...
        my ($self, $handset, $services) = @_;
        for my $chr (qw[A M Y]) {
            $self->write(pack q[C2A6C],
                         hex(q[e] . $handset->id),
                         0xd7, $services->{$chr}, 0xff)
                if $services->{$chr};
        }
        return 1;
    }

    sub _send_name {
        my ($self, $handset, $name) = @_;
        return $self->write(pack q[C2A*C], hex($handset->id), 0xd9, $name,
                            0xff);
    }

    # Event system
    sub on_im {
        my ($self, $method) = @_;
        return $_on_im{refaddr $self} = $method;
    }

    sub on_connect {
        my ($self, $method) = @_;
        return $_on_connect{refaddr $self} = $method;
    }

    sub on_login {
        my ($self, $method) = @_;
        return $_on_login{refaddr $self} = $method;
    }

    # XXX - ...should this exist?
    sub on_login_complete {
        my ($self, $method) = @_;
        return $_on_login_complete{refaddr $self} = $method;
    }

    sub on_registration {
        my ($self, $method) = @_;
        return $_on_registration{refaddr $self} = $method;
    }

    sub on_window_open {
        my ($self, $method) = @_;
        return $_on_window_open{refaddr $self} = $method;
    }

    sub on_window_close {
        my ($self, $method) = @_;
        return $_on_window_close{refaddr $self} = $method;
    }

    sub on_data_in {
        my ($self, $method) = @_;
        return $_on_data_in{refaddr $self} = $method;
    }

    sub on_data_out {
        my ($self, $method) = @_;
        return $_on_data_out{refaddr $self} = $method;
    }

    sub read {
        my ($self) = @_;
        $data_in{refaddr $self} = $self->_read(READ_SIZE) or return;
        $_on_data_in{refaddr $self}->($self, $data_in{refaddr $self})
            if $_on_data_in{refaddr $self};
        return length $data_in{refaddr $self};
    }

    sub write {
        my ($self, $data, $forget) = @_;
        return if !$data;
        #my (undef, undef, $line) = caller;
        $last_sent{refaddr $self} = $data if !$forget;
        my $sent = 0;
        my @data = $data =~ m|\G(.{1,8})|g;
        for my $part (@data) {
            $part .= qq[\0] for length($part) .. 7;
            $part = qq[\0] . $part;
            $sent += $self->_write($part);
            require Time::HiRes;
            Time::HiRes::sleep(0.15);
            $_on_data_out{refaddr $self}->($self, $part)
                if $_on_data_out{refaddr $self};
        }
        return $sent;
    }
    DESTROY {
        my $self = shift;
        if ($handle{refaddr $self}) {
            $self->_init_USB;
            $self->_close();
        }
        for my $hash (@REGISTRY) {
            delete $hash->{refaddr $self};
        }
        return 1;
    }
}
1;

# $Id $

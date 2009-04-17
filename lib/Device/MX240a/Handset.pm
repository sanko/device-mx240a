package Device::MX240a::Handset;
{
    use strict;
    use warnings;
    use Carp qw[confess carp];
    use Data::Dump qw[pp];
    use Scalar::Util qw[refaddr];
    our $VERSION = 0.3;
    my @REGISTRY
        = \my (%id, %base, %service, %username, %password, %blist, %window);
    DESTROY {
        my ($self) = @_;
        for my $hash (@REGISTRY) { delete $hash->{refaddr $self} }
        return 1;
    }

    # Constructor... duh
    sub new {
        my ($class, $args) = @_;
        if (not defined $args->{q[id]}) {
            carp q[Device::MX240a::Handset->new() requires an id number];
            return;
        }
        if ($args->{q[id]} !~ m[^\d+$]) {
            carp
                q[Device::MX240a::Handset->new() requires an integer id number];
            return;
        }
        if (not defined $args->{q[base]}) {
            confess q[Device::MX240a::Handst->new() requires a base];
        }
        my $self = bless \$args->{q[id]}, $class;
        $base{refaddr $self} = $args->{q[base]};
        $id{refaddr $self}   = $args->{q[id]};
        return $self;
    }

    # Accessors
    sub id    { return $id{refaddr +shift} }
    sub blist { return $blist{refaddr +shift} }

    sub _set_service {
        my ($self, $service) = @_;
        confess if not defined $service;
        return $service{refaddr $self} = $service;
    }
    sub service { return $service{refaddr +shift}; }

    sub _set_username {
        my ($self, $username) = @_;
        confess if not defined $username;
        return $username{refaddr $self} = $username;
    }
    sub username { return $username{refaddr +shift}; }

    sub _set_password {
        my ($self, $password) = @_;
        confess if not defined $password;
        return $password{refaddr $self} = $password;
    }
    sub password { return $password{refaddr +shift}; }

    sub _set_window {
        my ($self, $window) = @_;
        confess if not defined $window;
        return $window{refaddr $self} = $window;
    }
    sub window { return $window{refaddr +shift}; }

    # Methods
    sub _buddy_in {
        my ($self, $buddy) = @_;
        if (defined $blist{refaddr $self}{$buddy->{q[screenname]}}) {
            $buddy->{q[id]}
                = $blist{refaddr $self}{$buddy->{q[screenname]}}{q[id]};
        }
        else {
            $buddy->{q[id]} = scalar(keys %{$blist{refaddr $self}}) + 1;
        }
        $blist{refaddr $self}{$buddy->{q[screenname]}} = $buddy;
        return $base{refaddr $self}->_send_buddy_in($self, $buddy);
    }

    sub _locate_buddy_by_id {
        my ($self, $id) = @_;
        return unless defined $id;
        return unless $id =~ m[^\d+$];
        my $buddy;
        for my $b (values %{$blist{refaddr $self}}) {
            if ($b->{q[id]} == $id) {
                $buddy = $b;
                last
            }
        }
        return $buddy;
    }

    sub _close_window {
        my ($self) = @_;
        return delete $window{refaddr $self};
    }

    sub _send_im {
        my ($self, $window, $msg) = @_;
        return $base{refaddr $self}
            ->write((pack q[C3], hex(q[8] . $id{refaddr $self}), $window, 0)
                    . $msg
                        . (pack q[C2], 0xff, 0x00));

=docs
if no terminator, just end after 3 chunks of 8.
if only room for ff in third chunk, put that.
=cut
    }
}
1;

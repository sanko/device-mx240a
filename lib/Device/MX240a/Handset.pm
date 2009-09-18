package Device::MX240a::Handset;
{
    use strict;
    use warnings;
    use Carp qw[confess carp];
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
                last;
            }
        }
        return $buddy;
    }

    sub _locate_id_by_buddy {
        my ($self, $screen_name) = @_;
        return unless defined $screen_name;
        return unless length $screen_name;
        return unless $blist{refaddr $self}{$screen_name};
        return $blist{refaddr $self}{$screen_name}{'id'};
    }

    sub _close_window {
        my ($self) = @_;
        return delete $window{refaddr $self};
    }

    sub _send_im {
        my ($self, $window, $msg) = @_;
        my $bid = pack 'C2', hex('8' . $id{refaddr $self}), $window;
        my $send = chr(0) . $msg . (pack 'C2', 0xff, 0x00);
        $send = $bid . join $bid, grep length, split(m[(.{22})], $send);
        $base{refaddr $self}->write($send) || return;
        $base{refaddr $self}
            ->write(pack 'C3', hex('e' . $id{refaddr $self}), 0xce, $window)
            || return;
        return 1;
    }

    sub _range_error {
        my ($self, $error) = @_;
        return $base{refaddr $self}
            ->write((pack q[C2], hex(q[c] . $id{refaddr $self}), 0xc5));
    }
}
1;

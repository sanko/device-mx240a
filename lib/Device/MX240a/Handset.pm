package Device::MX240a::Handset;
{
    use strict;
    use warnings;
    use Carp qw[confess carp];
    our $VERSION = 0.3;

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
        my $self = bless {base => $args->{q[base]},
                          id   => $args->{q[id]}
        }, $class;
        return $self;
    }

    # Accessors
    sub id    { return +shift->{'id'} }
    sub blist { return +shift->{'blist'} }

    sub _set_service {
        my ($self, $service) = @_;
        confess if not defined $service;
        return $self->{'service'} = $service;
    }
    sub service { return +shift->{'service'}; }

    sub _set_username {
        my ($self, $username) = @_;
        confess if not defined $username;
        return $self->{'username'} = $username;
    }
    sub username { return +shift->{'username'}; }

    sub _set_password {
        my ($self, $password) = @_;
        confess if not defined $password;
        return $self->{'password'} = $password;
    }
    sub password { return +shift->{'password'}; }

    sub _set_window {
        my ($self, $window) = @_;
        confess if not defined $window;
        return $self->{'window'} = $window;
    }
    sub window { return +shift->{'window'}; }

    # Methods
    sub _buddy_in {
        my ($self, $buddy) = @_;
        if (defined $self->{'blist'}{$buddy->{q[screenname]}}) {
            $buddy->{q[id]}
                = $self->{'blist'}{$buddy->{q[screenname]}}{q[id]};
        }
        else {
            $buddy->{q[id]} = scalar(keys %{$self->{'blist'}}) + 1;
        }
        $self->{'blist'}{$buddy->{q[screenname]}} = $buddy;
        return $self->{'base'}->_send_buddy_in($self, $buddy);
    }

    sub _locate_buddy_by_id {
        my ($self, $id) = @_;
        return unless defined $id;
        return unless $id =~ m[^\d+$];
        my $buddy;
        for my $b (values %{$self->{'blist'}}) {
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
        return unless $self->{'blist'}{$screen_name};
        return $self->{'blist'}{$screen_name}{'id'};
    }

    sub _close_window {
        my ($self) = @_;
        return delete $self->{'window'};
    }

    sub _send_im {
        my ($self, $window, $msg) = @_;
        my $bid = pack 'C2', hex('8' . $self->{'id'}), $window;
        my $send = chr(0) . $msg . (pack 'C2', 0xff, 0x00);
        $send = $bid . join $bid, grep length, split(m[(.{22})], $send);
        $self->{'base'}->write($send) || return;
        $self->{'base'}
            ->write(pack 'C3', hex('e' . $self->{'id'}), 0xce, $window)
            || return;
        return 1;
    }

    sub _range_error {
        my ($self, $error) = @_;
        return $self->{'base'}
            ->write((pack q[C2], hex(q[c] . $self->{'id'}), 0xc5));
    }
}
1;

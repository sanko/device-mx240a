#
package Device::MX240a::Win32;
{
    use strict;
    use warnings;
    use Carp qw[confess carp];
    our @ISA;
    our $VERSION = 0.4;

    BEGIN {
        use lib q[../..];
        require Device::MX240a;
        push @ISA, qw[Device::MX240a];
    }

    sub __get_HID {
        my $size = 1024;
        my $all;
        require Win32API::File;
        while (!Win32API::File::QueryDosDevice([], $all, $size)) {
            $size *= 2;
        }
        my $pattern = sprintf q[HID#Vid_%s&Pid_%s.*],
            Device::MX240a::MX240A_VENDOR(), Device::MX240a::MX240A_PRODUCT();
        my @all = split /\0/, $all;
        my %all;
        my $device;
        for my $d (@all) {
            $device = $d;
            if (!Win32API::File::QueryDosDevice($device, $all, 0)) {
                carp sprintf q[Can't get device definition (%s): %s], $device,
                    fileLastError();
            }
            else {
                $all =~ s/\0\0.*//; # Audio devices return some strange items?
                my @list = split /\0/, $all;
                $all{$device} = \@list;
            }
        }
        for (sort { ($all{$a}->[0] || q[]) cmp($all{$b}->[0] || q[]) }
             keys %all)
        {   return $_ if /$pattern/;
        }
        return;
    }

    sub _init_USB {
        my ($self) = @_;
         return $self->write(pack q[C4], 0xad, 0xef, 0x8d, 0xff);
    }

    sub _open {
        my ($self) = @_;
        my $HID = __get_HID();
        return if ! defined $HID;
        require Win32API::File;
        my $device = Win32API::File::createFile(q[//./] . $HID,
                         Win32API::File::GENERIC_READ()  |
                         Win32API::File::GENERIC_WRITE() |
                         Win32API::File::FILE_FLAG_OVERLAPPED());
        tie *device, 'Win32API::File', $device;
        return \*device;
    }

    sub _write {
        my ($self, $data) = @_;
        my $sent = syswrite($self->_handle, $data, length($data), 0);
        #warn sprintf 'Wrote %d bytes', $sent;
        return $sent;
    }

    sub _read {
        my ($self, $amount) = @_;
        my $read = sysread($self->_handle, my($data_in), $amount);
        #warn sprintf 'Read %d bytes', $read;
        return $data_in;
    }

    sub _close {
        my ($self) = @_;
        return if !$self->_handle;
        return close $self->_handle;
    }

    sub DESTROY {
        my ($self) = @_;
        return $self->_close();
    }
}
1;

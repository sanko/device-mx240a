#!/usr/bin/perl -w
use strict;
use warnings;
use File::Find;
use Module::Build;
use 5.008001;
my @tests;

sub find_cb {
    return if -d $_ or -l $_;
    return unless -T $_;
    return unless $_ =~ m[.+\.t$];
    return push @tests, $File::Find::name;
}
find \&find_cb, qw[t/];
my $mb = Module::Build->new(
          module_name       => q[Device::MX240a],
          license           => q[perl],
          dist_author       => q[Sanko Robinson <sanko@cpan.org>],
          dist_abstract     => q[Motorola IMFree (MX240a) Device Interface],
          dist_version_from => q[lib/Device/MX240a.pm],
          build_requires    => {
                             q[Module::Build] => 0.2805,
                             q[Test::More]    => 0.72,
          },
          requires => {q[Module::Build]  => 0.2805,
                       q[perl]           => 5.008001,
                       q[Test::More]     => 0.72,
                       q[Win32]          => 0,
                       q[Win32API::File] => 0
          },
          test_files => \@tests,
          meta_merge => {
              resources => {
                  homepage   => q[http://sanko.googlecode.com/],
                  bugtracker => q[http://code.google.com/p/sanko/issues/list],
                  repository => q[http://sanko.googlecode.com/svn/trunk/],
              },
              keywords     => [qw[MX240a Motorola handset Win32 IMFree]],
              generated_by => q[Sanko Robinson <sanko@cpan.org>]
          }
);
$mb->create_build_script;

# $Id$

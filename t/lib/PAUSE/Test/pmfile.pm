use strict;
use warnings;

package PAUSE::Test::pmfile;

use Test::FITesque::Fixture;
use base qw(Test::FITesque::Fixture);
use Test::More;

use Test::MockObject;
use Test::MockObject::Extends;
use PAUSE::mldistwatch;
use Mock::Dist;
use Module::Faker::Dist;
use Path::Class ();
use Data::Dumper;
use YAML;

#my $PACKAGE = Test::MockObject::Extends->new('PAUSE::package');
my $PACKAGE = Test::MockObject->new;
$PACKAGE->fake_module(
  'PAUSE::package',
  new => sub { shift; %{ $PACKAGE } = @_; return $PACKAGE },
);
$PACKAGE->mock(examine_pkg => sub {});

my ($fake_dist, $fake_dist_dir);
sub fake_dist {
  $fake_dist ||= Module::Faker::Dist->from_file('t/dist/My-Dist.yaml');
}

sub fake_dist_dir {
  $fake_dist_dir ||= Path::Class::dir(shift->fake_dist->make_dist_dir);
}

sub new {
  my ($self) = shift->SUPER::new(@_);
  my $mock = delete $self->{mock} || {};
  $self->{dist} ||= Mock::Dist->new;
  $self->{dist}{DIST} ||= 'My-Dist';
  $self->{pmfile} ||= PAUSE::pmfile->new(
    PMFILE => "fake-pmfile",
    DIO    => $self->{dist},
    USERID => 'FAKE',
    TIME   => time,
    YAML_CONTENT => {},
    VERSION => $self->fake_dist->version,
  );
  $self->{pmfile} = Test::MockObject::Extends->new($self->{pmfile});
  for my $o (keys %$mock) {
    for my $m (keys %{ $mock->{$o} || {} }) {
      my $to_mock = $mock->{$o}{$m};
      if (ref $to_mock eq 'ARRAY') {
        $self->{$o}->$m(@$_) for @$to_mock;
      } else {
        $self->{$o}->$m($to_mock->{$_}) for keys %$to_mock;
      }
    }
  }
  return $self;
}

sub dist_mock_ok {
  my ($self, $method, $args) = @_;
  $self->{pmfile}->$method(@$args);
  $self->{dist}->next_call_ok($method, $args);
}

sub dist_mock :Test :Plan(1) {
  my ($self, $method, @args) = @_;
  $self->dist_mock_ok($method, \@args);
}

my $ppp = 'My::Package';
sub filter_ppps :Test :Plan(3) {
  my ($self, $no_index, $expect) = @_;
  $self->{pmfile}{YAML_CONTENT}{no_index} = $no_index;

  my @res = $self->{pmfile}->filter_ppps($ppp);
  is_deeply(
    \@res,
    $expect->{skip} ? [] : [$ppp],
    "expected result",
  );
  if ($expect->{reason}) {
    my $reason = $expect->{reason};
    if ($no_index) {
      $reason = ($expect->{skip} ? "" : "NOT ")
        . "Skipping ppp[$ppp] $reason";
    }
    $self->{dist}->next_call_ok(verbose => [ 1, $reason ]);
    $self->{dist}->next_call_ok(verbose => [ 1, "Result of filter_ppps: res[@res]" ]);
  } else {
    ok( ! $self->{dist}->called('verbose'), "no verbose() call");
    ok(1, "dummy");
    $self->{dist}->clear;
  }
}

sub simile :Test :Plan(2) {
  my ($self, $file, $package, $ret) = @_;
  my $label = "$file and $package are "
    . ($ret ? "" : "not ") . "similes";
  ok( $self->{pmfile}->simile($file, $package) == $ret, $label );
  $file =~ s/\.pm$//;
  $self->{dist}->verbose_ok(
    1, "Result of simile(): file[$file] package[$package] ret[$ret]\n"
  );
}

sub examine_fio :Test :Plan(3) {
  my ($self) = @_;
  my $pmfile = $self->{pmfile};
  $pmfile->{PMFILE} = $self->fake_dist_dir->file('lib/My/Dist.pm')->stringify;
  $pmfile->examine_fio;
  $self->{dist}->next_call for 1..5; # skip over some irrelevant logging
#  $self->{dist}->next_call_ok(connect => []);
#  $self->{dist}->next_call_ok(version_from_yaml_ok => []);
#  $self->{dist}->verbose_ok(1, "simile: file[Dist] package[My::Dist] ret[1]\n");
#  $self->{dist}->verbose_ok(1, "no keyword 'no_index' or 'private' in YAML_CONTENT");
#  $self->{dist}->verbose_ok(1, "res[My::Dist]");
  $self->{dist}->verbose_ok(1, "Will check keys_ppp[My::Dist]\n");
  is_deeply(
    [ @{$PACKAGE}{ qw(PACKAGE DIST FIO TIME PMFILE USERID YAML_CONTENT) } ],
    [
      'My::Dist', 'My-Dist', $pmfile,
      @{$pmfile}{qw(TIME PMFILE USERID YAML_CONTENT)},
    ],
    "correct package info",
  );
  delete $PACKAGE->{PP}{pause_reg}; # cannot guess
  is_deeply(
    $PACKAGE->{PP},
    {
      parsed => 1,
      filemtime => (stat $pmfile->{PMFILE})[9],
      infile    => $pmfile->{PMFILE},
      simile    => $pmfile->{PMFILE},
    },
    "correct package PP",
  );
}

1;

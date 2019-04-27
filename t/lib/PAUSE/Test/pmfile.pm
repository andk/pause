use strict;
use warnings;

package PAUSE::Test::pmfile;

use Test::FITesque::Fixture;
use base qw(Test::FITesque::Fixture);
use Test::More;
use Test::Deep;

# This one, we don't expect to be used.  In a weird world, we'd mark it fatal
# or something so we could say "nothing should log outside of test code."
# -- rjbs, 2019-04-27
use PAUSE::Logger '$Logger' => { init => {
  ident     => 'TestPAUSE',
  facility  => undef,
  to_self   => 0,
  to_stderr => 0,
} };

use Test::MockObject;
use Test::MockObject::Extends;
use PAUSE::mldistwatch;
use Mock::Dist;
use Module::Faker::Dist;
use Path::Class ();
use Data::Dumper;
use YAML::XS;

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
  $self->{dist}{TIME} = time;
  $self->{dist}{DIST} ||= 'My-Dist';
  $self->{pmfile} ||= PAUSE::pmfile->new(
    PMFILE => "fake-pmfile",
    DIO    => $self->{dist},
    USERID => 'FAKE',
    META_CONTENT => {},
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

sub test_logger {
  return PAUSE::Logger->default_logger_class->new({
    ident     => 'TestPAUSE',
    facility  => undef,
    log_pid   => 0,
    to_self   => 1,
    to_stderr => $ENV{TEST_VERBOSE} ? 1 : 0,
  });
}

my $ppp = 'My::Package';
sub filter_ppps :Test :Plan(2) {
  my ($self, $no_index, $expect) = @_;
  $self->{pmfile}{META_CONTENT}{no_index} = $no_index;

  local $Logger = test_logger;

  my @res = $self->{pmfile}->filter_ppps($ppp);
  cmp_deeply(
    \@res,
    $expect->{skip} ? [] : [$ppp],
    "expected result",
  );

  if ($expect->{skip}) {
    my ($type, $value) = %$no_index;
    $value = $value->[0] if ref $value;
    $value =~ s/::\z// if $type eq 'namespace';

    cmp_deeply(
        $Logger->events,
        [
            superhashof({
              message => re(qr{no_index rule on $type $value; skipping $ppp}) }),
        ]
    );
  } else {
    ok(! @{ $Logger->events }, "no logging");
    $self->{dist}->clear;
  }
}

sub simile :Test :Plan(2) {
  my ($self, $file, $package, $ret) = @_;

  local $Logger = test_logger();

  my $label = "$file and $package are "
    . ($ret ? "" : "not ") . "similes";
  ok( $self->{pmfile}->simile($file, $package) == $ret, $label );
  $file =~ s/\.pm$//;

  cmp_deeply(
      $Logger->events,
      [ superhashof({
          message =>
          qq!result of simile(): {{{"file": "$file", "package": "$package", "ret": $ret}}}!
        })
      ]
  );
}

sub examine_fio :Test :Plan(3) {
  my ($self) = @_;
  my $pmfile = $self->{pmfile};

  local $Logger = test_logger();

  $pmfile->{PMFILE} = $self->fake_dist_dir->file('lib/My/Dist.pm')->stringify;
  $pmfile->examine_fio;

#  $self->{dist}->next_call_ok(connect => []);
#  $self->{dist}->next_call_ok(version_from_meta_ok => []);
#  $self->{dist}->verbose_ok(1, "simile: file[Dist] package[My::Dist] ret[1]\n");
#  $self->{dist}->verbose_ok(1, "no keyword 'no_index' or 'private' in META_CONTENT");
#  $self->{dist}->verbose_ok(1, "res[My::Dist]");

  cmp_deeply(
    $Logger->events,
    [
      ignore(),
      superhashof({ message => re(qr/will examine packages: \Q{{["My::Dist"]}}\E\z/) }),
    ],
    "we see the event log we expected",
  );

  cmp_deeply(
    [ @{$PACKAGE}{ qw(PACKAGE DIST FIO PMFILE USERID META_CONTENT) } ],
    [
      'My::Dist', 'My-Dist', $pmfile,
      @{$pmfile}{qw(PMFILE USERID META_CONTENT)},
    ],
    "correct package info",
  );

  cmp_deeply(
    $PACKAGE->{PP},
    {
      parsed => 1,
      filemtime => (stat $pmfile->{PMFILE})[9],
      infile    => $pmfile->{PMFILE},
      simile    => $pmfile->{PMFILE},
      pause_reg => $self->{dist}{TIME},
    },
    "correct package PP",
  );
}

sub packages_per_pmfile :Test :Plan(3) {
  my ($self,$pkg,$pm_content,$version) = @_;
  # pass("playing around");
  my $selfpmfile = $self->{pmfile};
  my $pmfile = $self->fake_dist_dir->file('lib/My/Dist.pm')->stringify;
  open my $fh, ">", $pmfile or die "Could not open > '$pmfile': $!";
  print $fh $pm_content;
  close $fh or die "Could not close > '$pmfile': $!";
  $selfpmfile->{PMFILE} = $pmfile;
  $selfpmfile->{MTIME} = "42";
  $selfpmfile->{VERSION_FROM_META_OK} = 0;
  # $selfpmfile->{VERSION} = $version;
  my $ppp = $selfpmfile->packages_per_pmfile;
  is ref $ppp, "HASH", "ppp is a HASH";
  is join(" ",keys %$ppp), $pkg, "only key in ppp is '$pkg'";
  delete $ppp->{$pkg}{pause_reg};
  cmp_deeply(
             $ppp->{$pkg},
             { version => $version,
               filemtime => 42,
               infile => $pmfile,
               simile => $pmfile,
               parsed => 1,
             },
             "correct version in packages_per_pmfile: $version",
            );
}

1;

#Local Variables:
#mode: cperl
#cperl-indent-level: 2
#End:

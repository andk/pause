use strict;
use warnings;

package PAUSE::Tester;

use Test::FITesque;
use YAML::XS;
use File::Basename;

sub import {
  my $self = shift;
  return unless @_;
  die "invalid arguments: @_" unless $_[0] eq '-run';
  shift;
  $self->run(@_);
}

sub run {
  my $self = shift;
  my $run_class = shift;
  unless ($run_class) {
    ($run_class = basename((caller)[1], '.t')) =~ s/-/::/g;
    $run_class = "PAUSE::Test::$run_class";
  }

  my $data_dir = 't/data/' . ($run_class =~ /::([^:]+)$/)[0];

  #warn "run_class[$run_class] data_dir[$data_dir]\n";

  run_tests {
    suite {
      map {
        my ($method, $data) = @$_;
        if (ref $data eq 'ARRAY') {
          my $tests = $data;
          $data = {
            tests => $tests,
          }
        }
        test {
          [ $run_class, $data->{args} || {} ],
          map { [ $method, @$_ ] } @{$data->{tests}}
        }
      } 
      map {
        my $method = basename($_, '.yaml');
        map {
          [ $method, $_ ]
        } grep { defined } YAML::XS::LoadFile($_);
      } <$data_dir/*.yaml>
    }
  };
}

1;

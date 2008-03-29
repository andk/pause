use strict;
use warnings;

use lib 't/lib';
use PAUSE::Test::pmfile;

use Test::FITesque;
use YAML::Syck;
use File::Basename;

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
        [ 'PAUSE::Test::pmfile', $data->{args} || {} ],
        map { [ $method, @$_ ] } @{$data->{tests}}
      }
    } 
    map {
      my $method = basename($_, '.yaml');
      map {
        [ $method, $_ ]
      } grep { defined } YAML::Syck::LoadFile($_);
    } <t/data/pmfile/*.yaml>
  }
};

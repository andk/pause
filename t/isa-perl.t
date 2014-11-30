use lib 't/lib';
use TestSetup;
my $tests;
BEGIN { $tests = 0 }
use Test::More;
use lib 't/lib/privatelib'; # Stub PrivatePAUSE
use PAUSE::mldistwatch;

{
    my %p;
    BEGIN {
        %p =
            (
             "C/CB/CBAIL/perl5_003.tar-gz" => 1,
             "A/AN/ANDYD/perl5.003_07.tar.gz" => 1,
             "T/TI/TIMB/perl5.004_04.tar.gz" => 1,
             "I/IN/INGY/perl5-0.02.tar.gz" => 0,
             "D/DA/DAPM/perl-5.10.1.tar.bz2" => 1,
             "N/NW/NWCLARK/perl-5.8.9.tar.gz" => 1,
             "J/JE/JESSE/perl-5.14.0-RC3.tar.gz" => 0,
             "B/BI/BINGOS/perl-5.13.7.tar.gz" => 0,
             "J/JE/JESSE/perl-5.14.0.tar.gz" => 1,
            );
        $tests += keys %p;
    }
    for my $k (sort keys %p) {
        my $expect = $p{$k};
        is(PAUSE::dist->isa_regular_perl($k)||0, $expect, $k);
    }
}

BEGIN { plan tests => $tests }

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

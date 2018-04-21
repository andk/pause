use strict;

use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE
use TestSetup;
use Test::More;
use PAUSE;

my @positive = qw(
    C/CB/CBAIL/perl5_003.tar-gz
    A/AN/ANDYD/perl5.003_07.tar.gz
    T/TI/TIMB/perl5.004_04.tar.gz
    D/DA/DAPM/perl-5.10.1.tar.bz2
    N/NW/NWCLARK/perl-5.8.9.tar.gz
    J/JE/JESSE/perl-5.14.0.tar.gz
);

my @negative = qw(
    I/IN/INGY/perl5-0.02.tar.gz
    J/JE/JESSE/perl-5.14.0-RC3.tar.gz
    B/BI/BINGOS/perl-5.13.7.tar.gz
);

plan tests => @positive + @negative;

ok( PAUSE::isa_regular_perl($_), "$_ isa regular perl") for @positive;
ok(!PAUSE::isa_regular_perl($_), "$_ is not a regular perl") for @negative;

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

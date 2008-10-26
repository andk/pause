use strict;
use warnings;
use File::Spec;
use Test::More;

eval { require Test::Perl::Critic; };

if ( $@ ) {
    my $msg = 'Test::Perl::Critic required to criticise code';
    plan( skip_all => $msg );
}

my $rcfile = File::Spec->catfile( 't', 'perlcriticrc' );
Test::Perl::Critic->import( -profile => $rcfile );
all_critic_ok();



# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

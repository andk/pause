use Test::More tests=>1;
use lib 't/lib';
use PAUSE;
my $rf = File::Rsync::Mirror::Recentfile->new(
                                              canonize => "naive_path_normalize",
                                              localroot => "t",
                                              interval => q(2d),
                                             );
my $recent_events = $rf->recent_events;
is 377, scalar @$recent_events, "length of testfile is 377";

__END__

# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:

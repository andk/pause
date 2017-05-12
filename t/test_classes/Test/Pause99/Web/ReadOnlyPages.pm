package Test::Pause99::Web::ReadOnlyPages;

use strict;
use warnings;
use File::Temp qw/tempdir/;
use Path::Class qw/dir file/;

use Test::More;
use base 'Test::Pause99::Web::Base';

sub test_basic : Tests(4) {
    my $t = shift;
    my ( $env, $author, $m ) = $t->new_andreas();

# File list

    # Create some files in a directory
    my $root_dir = tempdir( CLEANUP => 0 );
    my $dir = dir("$root_dir/A/AN/ANDK");
    $dir->mkpath();

    $dir->file('foo')->spew('0');
    $dir->file('bar')->spew('0123456789');

    my $expected_files = { foo => 1, bar => 10 };

    local $PAUSE::Config->{MLROOT} = $root_dir;

    for my $query (qw/show_files delete_files/) {
        my $data = $m->$query->parse();
        my %files = map { @$_{qw/filename size/} } @{ $data->{'file_list'} };
        is_deeply( \%files, $expected_files,
            "$query: File list finds two author files" );
        is( $data->{'author_directory'},
            'authors/id/A/AN/ANDK',
            "$query: Author directory looks sensible" );
    }
}

1;
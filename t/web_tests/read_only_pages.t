#!perl

use strict;
use warnings;

use Test::More;
use Path::Class;
use File::Temp qw/tempdir tempfile/;

use pause_1999::Test::Environment;
use pause_1999::Test::Fixtures::Author;

my ( $env, $author ) = pause_1999::Test::Environment->new_with_author(
    username  => 'ANDK',
    asciiname => 'Andreas K',
);

my $m = $env->site_model($author);

# File list
{
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

done_testing();

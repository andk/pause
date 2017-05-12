package pause_1999::Test::MySQL;

use Moose;
use Test::mysqld;
use Test::More;
use DBI;
use File::Temp qw/tempfile/;
use Capture::Tiny qw/capture_merged/;

$SIG{INT} = sub { die "caught SIGINT, shutting down mysql\n" };

=head2 SYNOPSIS

 my $db
   = pause_1999::Test::MySQL->new( schemas => ['doc/mod.schema.txt'] );

 my $dbh = $db->dbh;

 # Drop straight in to the mysql console:
 $dbh->debug_console

=cut

# These are the only caller-configurable parts

# SQL to load at instantiation
has 'schemas' => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub {[]},
);

# Location of the mysql client binary
has 'mysql_client' => (
    is => 'ro',
    isa => 'Str',
    default => ($ENV{'PAUSE_MYSQL_CLIENT'} || 'mysql'),
);

# These are the public methods

# DBH
has 'dbh' => (
    is => 'ro',
    isa => 'DBI::db',
    lazy_build => 1,
);

# Drops you in to `mysql` connected to the database
sub debug_console {
    my $self = shift;
    $self->run_mysql();
}

sub dsn {
    my $self = shift;
    return $self->mysqld->dsn( dbname => $self->_db_name );
}

# Private attributes

# Object-specific database name
has '_db_name' => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);

sub _build__db_name {
    my $self = shift;
    return 'db_' . ( $self + 0 ) . int(rand 999_999);
}

# Location of the config file for the mysql client
has '_auth_file' => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

sub _build__auth_file {
    my $self = shift;
    my ($fh, $filename) = tempfile();
    my $args = $self->dsn;
    $args =~ s/DBI:mysql://;

    my %options = map { split /=/ } split( /;/, $args );
    $options{'database'}              = delete $options{'dbname'};
    $options{'socket'}                = delete $options{'mysql_socket'};
    $options{'default-character-set'} = 'utf8';

    my $auth_content = join "\n", "[client]",
        map { "$_=" . $options{$_} } keys %options;

    print $fh $auth_content;
    close $fh;
    return $filename;
}

sub BUILD {
    my $self = shift;
    my $dbh = $self->dbh;

    for my $schema ( @{$self->schemas} ) {
        note("Loading schema: $schema");
        $self->run_mysql( $schema );
    }
}



sub _build_dbh {
    my $self = shift;
    my $dbname = $self->_db_name;

    my $master_dbh = DBI->connect(
        $self->mysqld->dsn(
            dbname                  => 'test',
            'default-character-set' => 'utf8'
        )
    );

    note("Creating new MySQL database: $dbname");
    $master_dbh->do( 'CREATE DATABASE ' . $dbname )
        or die $master_dbh->errstr;

    # Connect to it
    my $dbh = DBI->connect( $self->mysqld->dsn( dbname => $dbname ),
        '', '', { RaiseError => 1 } );

    return $dbh;
}

sub run_mysql {
    my $self = shift;
    my $cmd = shift || '';
    $cmd = "< $cmd" if $cmd;
    my $exe = $self->mysql_client;
    system(sprintf("%s --defaults-extra-file=%s %s", $exe, $self->_auth_file, $cmd));
}

# mysqld singleton. We might have different tests that want to execute in
# seperate DBs, but I can't see why we'd want to be running more than one
# mysqld, so we do a singleton here
our $mysqld;

sub mysqld {
    my $self = shift;
    return $mysqld if $mysqld;

    note("Starting a test mysqld");
    note(
        capture_merged(
            sub {   $mysqld = Test::mysqld->new(
                    my_cnf => { 'skip-networking' => '' }
                );
            }
        )
    );
    die $Test::mysqld::errstr unless $mysqld;
    note("mysqld started");

    return $mysqld;
}

1;

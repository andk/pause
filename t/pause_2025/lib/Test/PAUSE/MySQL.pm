package Test::PAUSE::MySQL;

use Test::Builder ();
use Test::Requires qw(Test::mysqld);
use Test::Requires qw(File::Which);

BEGIN {
  unless (File::Which::which 'mysql') {
    Test::Builder->new->skip_all("no mysql found, needed for this test")
  }
}

use Moose;
use Test::mysqld;
use Test::More;
use DBI;
use File::Temp qw/tempfile/;
use Capture::Tiny qw/capture_merged/;
use SQL::Maker;
use Path::Tiny;

$SIG{INT} = sub { die "caught SIGINT, shutting down mysql\n" };

=head2 SYNOPSIS

 my $db
   = Test::PAUSE::MySQL->new( schemas => ['doc/mod.schema.txt'] );

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

has 'sql_maker' => (
    is => 'ro',
    isa => 'SQL::Maker',
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
        my $body = path($schema)->slurp;
        for (grep $_, split /;\n/s, $body) {
            $dbh->do($_);
        }
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

sub _build_sql_maker {
    my $self = shift;
    SQL::Maker->new(driver => 'mysql');
}

sub run_mysql {
    my $self = shift;
    my $cmd = shift || '';
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

my %DefaultValues = (
    # authen_pause
    # mod
    packages => {
        filemtime => time,
        pause_reg => 'TESTUSER',
        comment => '',
        status => 'index',
    },
    users => {
        fullname => 'test',
        homepage => '',
        isa_list => '',
        introduced => time,
        changed => time,
        changedby => 'TESTADMIN',
    },
);

sub insert {
    my ($self, $table, $values, $opt) = @_;
    if (my $default = $DefaultValues{$table}) {
        for my $key (keys %$default) {
            $values->{$key} //= $default->{$key};
        }
    }
    if ($opt and delete $opt->{replace}) {
        $opt->{prefix} = 'REPLACE';
    }
    my ($sql, @bind) = $self->sql_maker->insert($table, $values, $opt);
    $self->dbh->do($sql, undef, @bind);
}

sub update {
    my ($self, $table, $set, $where) = @_;
    my ($sql, @bind) = $self->sql_maker->update($table, $set, $where);
    $self->dbh->do($sql, undef, @bind);
}

sub delete {
    my ($self, $table, $where) = @_;
    my ($sql, @bind) = $self->sql_maker->delete($table, $where);
    $self->dbh->do($sql, undef, @bind);
}

sub select {
    my ($self, $table, $fields, $where, $opt) = @_;
    my ($sql, @bind) = $self->sql_maker->select($table, $fields, $where, $opt);
    $self->dbh->selectall_arrayref($sql, {Slice => +{}}, @bind);
}

1;

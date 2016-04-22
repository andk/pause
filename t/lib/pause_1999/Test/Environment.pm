package pause_1999::Test::Environment;

use Moose;
use Plack::Util;
use Plack::Test;
use pause_1999::Test::MySQL;
use pause_1999::Test::Config;
use pause_1999::Test::Fixtures::Author;

has 'authen_db' => (
    is         => 'ro',
    isa        => 'pause_1999::Test::MySQL',
    lazy_build => 1,
);
sub authen_dbh {
    my $self = shift;
    $self->authen_db->dbh;
}

sub _build_authen_db {
    my $self = shift;
    my $db   = pause_1999::Test::MySQL->new(
        schemas => ['doc/authen_pause.schema.txt'] );
    pause_1999::Test::Config->set_authen_db($db);
    return $db;
}

has 'mod_db' => (
    is         => 'ro',
    isa        => 'pause_1999::Test::MySQL',
    lazy_build => 1,
);
sub mod_dbh {
    my $self = shift;
    $self->mod_db->dbh;
}

sub _build_mod_db {
    my $self = shift;
    my $db
        = pause_1999::Test::MySQL->new( schemas => ['doc/mod.schema.txt'] );
    pause_1999::Test::Config->set_mod_db($db);
    return $db;
}

has 'plack_test' => (
    is => 'ro',
    lazy_build => 1,
);

sub _build_plack_test {
    my $self = shift;
    my $app  = Plack::Util::load_psgi 'app.psgi';
    return Plack::Test->create($app);
}

sub new_with_author {
    my ( $class, %options ) = @_;
    my $self = $class->new();

    my $author = pause_1999::Test::Fixtures::Author->new(
        environment => $self,
        %options,
    );

    return ( $self, $author );
}


1;

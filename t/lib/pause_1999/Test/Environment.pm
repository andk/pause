package pause_1999::Test::Environment;

use Moose;
use Plack::Util;
use Plack::Test;
use Test::WWW::Mechanize::PSGI;

use Class::MOP::Class;
use Plack::Test::MockHTTP;
use Capture::Tiny qw/capture_stderr/;

=head1 SYNOPSIS

Set up a whole web environment ready to go. Currently supports:

my ( $env, $author ) = pause_1999::Test::Environment->new_with_author(
    username  => 'ANDK',
    asciiname => 'Andreas K',
);

You now have databases:

 $env->authen_db->dbh

A user in C<$author> and in the DB

And a site model:

  $env->site_model( $author )
      ->change_passwd
      ->change_passwd__submit( 'moo', 'moo' );

=cut

use pause_1999::Test::MySQL;
use pause_1999::Test::Config;
use pause_1999::Test::SiteModel;
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

has 'plack_app' => (
    is => 'ro',
    default => sub { Plack::Util::load_psgi 'app.psgi' },
);

has 'plack_test' => (
    is => 'ro',
    lazy_build => 1,
);

sub _build_plack_test {
    my $self      = shift;
    my $metaclass = Class::MOP::Class->create_anon_class(
        superclasses => ['Plack::Test::MockHTTP'] );

    my $plack_test = Plack::Test->create( $self->plack_app );
    $metaclass->rebless_instance($plack_test);

    my $method = $metaclass->add_method(
        'request',
        sub {
            my ( $obj, $req ) = @_;
            my $result;
            my ($stderr) = capture_stderr {
                $result = Plack::Test::MockHTTP::request( $obj, $req );
            };
            $self->_filter_stderr($stderr);
            return $result;

        }
    );

    return $plack_test;
}

has 'mail_mailer' => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub {['testfile']},
);

sub BUILD {
    my $self = shift;
    pause_1999::Test::Config->set_mail_mailer( $self->mail_mailer );
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

sub site_model {
    my ( $self, $author ) = @_;
    my $metaclass = Class::MOP::Class->create_anon_class(
        superclasses => [
            'Test::WWW::Mechanize::PSGI', @Test::WWW::Mechanize::PSGI::ISA
        ]
    );

    my $mech = Test::WWW::Mechanize::PSGI->new( app => $self->plack_app );
    $metaclass->rebless_instance($mech);

    my $method = $metaclass->add_method(
        'simple_request',
        sub {
            my ( $obj, $req ) = @_;
            my $result;
            my ($stderr) = capture_stderr {
                $result = Test::WWW::Mechanize::PSGI::simple_request( $obj,
                    $req );
            };
            $self->_filter_stderr($stderr);
            return $result;

        }
    );

    my $model = pause_1999::Test::SiteModel->new( mech => $mech );
    $model->set_user($author) if $author;
    return $model;
}

sub _filter_stderr {
    my ( $self, $stderr ) = @_;
    Test::More::note($stderr) unless $ENV{'HUSH_PAUSE_STDERR'};
}

1;

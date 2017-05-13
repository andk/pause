package PAUSE::Web::Context;

use Mojo::Base -base;
use Log::Dispatch::Config;
use Encode;
use Sys::Hostname ();
use Email::Sender::Simple;
use Email::MIME;
use Data::Dumper;
use PAUSE::Web::Config;
use PAUSE::Web::Exception;

our $VERSION = "1072";

has root => sub { Carp::confess "requires root" };
has config => sub { PAUSE::Web::Config->new };
has logger => sub { Log::Dispatch::Config->instance };

sub init {
  my $self = shift;

  my $root = $self->root;
  Log::Dispatch::Config->configure("$root/etc/plack_log.conf.".($ENV{PLACK_ENV} // "development"));
}

# pause_1999::main::version
sub version {
  my $self = shift;
  return $self->{VERSION} if defined $self->{VERSION};
  my $version = $VERSION;
  for my $m (grep {! m!/Test/!} grep /pause_2017/, keys %INC) {
    $m =~ s|/|::|g;
    $m =~ s|\.pm$||;
    my $v = $m->VERSION || 0;
    warn "Warning: Strange versioning style in m[$m]v[$v]" if $v < 10;
    $version = $v if $v > $version;
  }
  $version;
}

sub hostname {
  my $self = shift;
  $PAUSE::Config->{SERVER_NAME} || Sys::Hostname::hostname();
}

sub log {
  my ($self, $arg) = @_;
  $self->logger->log(%$arg)
}

### Database

sub connect {
  my $self = shift;
  eval {$self->{DbHandle} ||= DBI->connect(
    $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
    $PAUSE::Config->{MOD_DATA_SOURCE_USER},
    $PAUSE::Config->{MOD_DATA_SOURCE_PW},
    { RaiseError => 1,
      mysql_auto_reconnect => 1,
      # mysql_enable_utf8 => 1,
    }
  )};
  return $self->{DbHandle} if $self->{DbHandle};
  $self->database_alert;
}

sub authen_connect {
  my $self = shift;
  # local($SIG{PIPE}) = 'IGNORE';
  eval {$self->{DbHandle4Authen} ||= DBI->connect(
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
    $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
    { RaiseError => 1,
      mysql_auto_reconnect => 1,
      # mysql_enable_utf8 => 1,
    }
  )};
  return $self->{DbHandle4Authen} if $self->{DbHandle4Authen};
  $self->database_alert;
}

sub database_alert {
  my $self = shift;
  my $mess = Carp::longmess($@);
  my $tsf = "$PAUSE::Config->{RUNDATA}/alert.db.not.available.ts";
  if (! -f $tsf or (time - (stat _)[9]) > 6*60*60) {
    my $server = $self->hostname;
    my $header = {
                  From => "database_alert",
                  To => $PAUSE::Config->{ADMIN},
                  Subject => "PAUSE Database Alert $server",
                 };
    $self->send_mail($header, $mess);
    open my $fh, ">", $tsf or warn "Could not open $tsf: $!";
  }
  die PAUSE::Web::Exception->new(ERROR => <<"ERROR_END");
Sorry, the PAUSE Database currently seems unavailable.<br />
Administration has been notified.<br />
Please try again later.
ERROR_END
}

# A wrapper function for fetchrow_array and fetchrow_hashref
# XXX: Should mysql_enable_utf8 suffice?
sub fetchrow {
  my ($self, $sth, $what) = @_;

  if (wantarray) {
    my @arr = $sth->$what;
    for (@arr) {
      defined && /[^\000-\177]/ && Encode::_utf8_on($_);
    }
    return @arr;
  } else {
    my $ret = $sth->$what;
    if (ref $ret) {
      for my $k (keys %$ret) {
        defined && /[^\000-\177]/ && Encode::_utf8_on($_) for $ret->{$k};
      }
      return $ret;
    } else {
      defined && /[^\000-\177]/ && Encode::_utf8_on($_) for $ret;
      return $ret;
    }
  }
}

### Mailer

sub prepare_sendto {
  my ($self, $active_user, $pause_user, @admin) = @_;

  my %umailset;
  my $name = $active_user->{asciiname} || $active_user->{fullname} || "";
  my $Uname = $pause_user->{asciiname} || $pause_user->{fullname} || "";
  if ($active_user->{secretemail}) {
    $umailset{qq{"$name" <$active_user->{secretemail}>}} = 1;
  } elsif ($active_user->{email}) {
    $umailset{qq{"$name" <$active_user->{email}>}} = 1;
  }
  if ($active_user->{userid} ne $pause_user->{userid}) {
    if ($pause_user->{secretemail}) {
      $umailset{qq{"$Uname" <$pause_user->{secretemail}>}} = 1;
    }elsif ($pause_user->{email}) {
      $umailset{qq{"$Uname" <$pause_user->{email}>}} = 1;
    }
  }
  my @to = keys %umailset;
  push @to, @admin if @admin;
  @to;
}

sub send_mail_multi {
  my ($self, $to, $header, $mailblurb) = @_;
  warn "sending to[@$to]";
  warn "mailblurb[$mailblurb]";
  for my $to2 (@$to) {
    $header->{To} = $to2;
    $self->send_mail($header, "$mailblurb");
  }
}

sub send_mail {
  my ($self, $header, $blurb) = @_;

  my @hdebug = %$header; $self->log({level => "info", message => sprintf("hdebug[%s]", join "|", @hdebug) });
  $header->{From}                        ||= qq{"Perl Authors Upload Server" <$PAUSE::Config->{UPLOAD}>};
  $header->{"Reply-To"}                  ||= join ", ", @{$PAUSE::Config->{ADMINS}};

  my $email = Email::MIME->create(
    header_str => [%$header],
    attributes => {
      charset      => 'utf-8',
      content_type => 'text/plain',
      encoding     => 'quoted-printable',
    },
    body_str => $blurb,
  );

  if ($PAUSE::Config->{TESTHOST}){
    warn "TESTHOST is NOT sending mail";
    warn "Line " . __LINE__ . ", File: " . __FILE__ . "\n" .
        Data::Dumper->new([$header,$blurb],[qw(header blurb)])
              ->Indent(1)->Useqq(1)->Dump;
  }
  Email::Sender::Simple->send($email);
  1;
}

sub DESTROY {
  my $self = shift;
  $self->{DbHandle4Authen}->disconnect if ref $self->{DbHandle4Authen};
  $self->{DbHandle}->disconnect if ref $self->{DbHandle};
}

1;

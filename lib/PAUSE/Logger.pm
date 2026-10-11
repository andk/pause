use strict;
use warnings;
package PAUSE::Logger;
use parent 'Log::Dispatchouli::Global';

use Log::Dispatchouli 2.002;
use Time::HiRes ();

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

sub default_logger_class { 'PAUSE::Logger::_Logger' }

sub default_logger_args {
  return {
    ident     => "PAUSE-unidentified",

    # to turn on syslogging...
    facility  => 'daemon', # where "daemon" is whatever syslog facility you want

    to_stderr => $_[0]->default_logger_class->env_value('STDERR') // 0,
    to_self   => $_[0]->default_logger_class->env_value('TO_SELF') ? 1 : 0,
  }
}

{
  package PAUSE::Logger::_Logger;
  use parent 'Log::Dispatchouli';

  use Carp ();
  use File::Spec ();
  use IO::Handle ();
  use Params::Util qw(_HASH0);

  # Log::Dispatchouli's to_file option is deprecated, but we really want it!
  sub new {
    my ($class, $arg) = @_;
    $arg = { %{ $arg // {} } };

    my $file_format = delete $arg->{file_format} // sub {
      my ($sec, $usec) = Time::HiRes::gettimeofday;
      my @time = localtime $sec;
      sprintf "%4u-%02u-%02u %02u:%02u:%02u.%04u %s\n",
        $time[5]+1900,
        $time[4]+1,
        @time[3,2,1,0],
        int($usec/1000),
        $_[0]
    };

    my $to_file  = delete $arg->{to_file};
    my $log_path = delete $arg->{log_path};
    my $log_file = delete $arg->{log_file};

    my $self = $class->SUPER::new($arg);

    if ($to_file) {
      my $filename = File::Spec->catfile(
        ($log_path || $self->env_value('PATH') || File::Spec->tmpdir),
        $log_file || do {
          my @time = localtime;
          sprintf('%s.%04u%02u%02u',
            $self->ident,
            $time[5] + 1900,
            $time[4] + 1,
            $time[3])
        }
      );

      open my $fh, '>>', $filename
        or Carp::croak("can't open log file $filename for appending: $!");
      $fh->autoflush(1);

      $self->{_pause_file} = {
        fh      => $fh,
        format  => $file_format,
        log_pid => $self->log_pid_for('file'),
      };
    }

    return $self;
  }

  sub _log_to_file {
    my ($self, $message) = @_;
    return unless my $file = $self->{_pause_file};

    $message = "[$$] $message" if $file->{log_pid};
    print { $file->{fh} } $file->{format}->($message)
      or die "can't write to log file: $!";

    return;
  }

  sub log {
    my ($self, @rest) = @_;
    my $arg = _HASH0($rest[0]) ? shift(@rest) : {};

    return $self->SUPER::log($arg, @rest)
      unless $self->{_pause_file} && ($arg->{fatal} || ! $self->get_muted);

    my $message = $self->flog_messages($arg, @rest);
    $self->_log_to_file($message);

    # The message is already flogged and prefixed, so we hand the finished
    # string to the superclass with all prefixes suppressed.  A plain string
    # passes through flogging unchanged, and this way any coderefs in the
    # original message or prefixes are only called once
    local $self->{prefix};
    return $self->SUPER::log({ %$arg, prefix => undef }, $message);
  }

  sub log_event {
    my ($self, $type, $data) = @_;

    $self->_log_to_file($self->fmt_event($type, $data))
      unless $self->get_muted;

    return $self->SUPER::log_event($type, $data);
  }

  sub env_prefix { 'PAUSE_LOG' }
}

1;

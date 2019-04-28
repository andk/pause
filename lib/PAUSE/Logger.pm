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
    ident     => "PAUSE",

    # to turn on syslogging...
    # facility => 'daemon', # where "daemon" is whatever syslog facility you want

    to_stderr => $_[0]->default_logger_class->env_value('STDERR') // 1,
    to_self   => $_[0]->default_logger_class->env_value('TO_SELF') ? 1 : 0,
  }
}

{
  package PAUSE::Logger::_Logger;
  use parent 'Log::Dispatchouli';

  sub new {
    my ($class, $arg) = @_;
    $arg->{file_format} //= sub {
      my ($sec, $usec) = Time::HiRes::gettimeofday;
      my @time = localtime $sec;
      sprintf "%4u-%02u-%02u %02u:%02u:%02u.%04u %s\n",
        $time[5]+1900,
        @time[4,3,2,1,0],
        int($usec/1000),
        $_[0]
    };

    $class->SUPER::new($arg);
  }

  sub env_prefix { 'PAUSE_LOG' }
}

1;

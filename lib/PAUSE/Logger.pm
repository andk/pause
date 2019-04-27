use strict;
use warnings;
package PAUSE::Logger;
use parent 'Log::Dispatchouli::Global';

use Log::Dispatchouli 2.002;

sub logger_globref {
  no warnings 'once';
  \*Logger;
}

sub default_logger_class { 'PAUSE::Logger::_Logger' }

sub default_logger_args {
  return {
    ident     => "PAUSE",
    to_stderr => $_[0]->default_logger_class->env_value('STDERR') // 1,
    to_self   => $_[0]->default_logger_class->env_value('TO_SELF') ? 1 : 0,
  }
}

{
  package PAUSE::Logger::_Logger;
  use parent 'Log::Dispatchouli';

  sub env_prefix { 'PAUSE_LOG' }
}

1;

package PAUSE::Web::Exception;

use Mojo::Base -base;
use overload 
  '""' => sub {$_[0]->{ERROR} ? $_[0]->{ERROR} : $_[0]->{HTTP_STATUS} ? $_[0]->{HTTP_STATUS} : ""},
;


1;

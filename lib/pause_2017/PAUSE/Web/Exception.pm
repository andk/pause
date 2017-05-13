package PAUSE::Web::Exception;

use Mojo::Base -base;
use overload 
  '""' => sub {$_[0]->{ERROR}},
;


1;

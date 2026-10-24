package PAUSE::Indexer::Abort::Dist;
use v5.12.0;
use Moo;

has public => (
  is      => 'ro',
  default => 0,
);

has message => (
  is => 'ro',
  required => 1,
);

no Moo;
1;

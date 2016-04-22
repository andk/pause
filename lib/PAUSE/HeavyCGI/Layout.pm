package PAUSE::HeavyCGI::Layout;
use 5.005;

use strict;
use vars qw($VERSION);

#use fields qw[

### CONTENT
### PREJOINED

#];

$VERSION = sprintf "%d.%03d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/;

sub new {
  my($class,@arr) = @_;
  no strict "refs";
  my $self = bless {}, $class;
  $self->{CONTENT} = [@arr];
  $self;
}

sub content {
  my PAUSE::HeavyCGI::Layout $self = shift;
  @{$self->{CONTENT}};
}

sub prejoin { #make the array shorter
  my PAUSE::HeavyCGI::Layout $self = shift;
  return if $self->{PREJOINED};
  my $a = $self->{CONTENT};
  my($i) = 0;
  while ($i < @$a-2){
    if ( ref($a->[$i]) || ref($a->[$i+1])){
      ++$i;
    } else {
      splice @$a, $i, 2, join("",$a->[$i],$a->[$i+1]);
    }
  }
  $self->{PREJOINED} = 1;
}

sub as_string {
  my PAUSE::HeavyCGI::Layout $self = shift;
  my PAUSE::HeavyCGI $mgr = shift;
  my @m;
  for my $chunk ($self->content) {
    if (ref $chunk and $chunk->can("as_string")) {
      push @m, $chunk->as_string($mgr);
    } else {
      push @m, "$chunk";
      # Carp::cluck("Hey-4. chunk[$chunk]");
    }
  }
  join "", @m;
}

1;

=head1 NAME

PAUSE::HeavyCGI::Layout - Represent a page layout in an array

=head1 SYNOPSIS

 my $layout = PAUSE::HeavyCGI::Layout->new(@array);

 $layout->prejoin;  # make the array more compact

 my @array = $layout->content;
 my $string = $layout->as_string($object);

=head1 DESCRIPTION

The constructor new() takes as an argument an array of elements.
Elements may be strings and objects in any order.

The content() method returns the array of elements.

The prejoin() method joins adjacent string elements, leaving at most
one string element between objects in the array.

The as_string() method takes an object, say $mgr, as an argument and
joins all elements of the array such that all chunks that represent an
object are called with

    $chunk->as_string($mgr)

and all chunks that represent a string are fillers in between. Objects
that do not understand the as_string method are just filled in as
strings, leaving room for debugging or overloading or whatever.

=cut


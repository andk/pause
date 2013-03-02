use strict;
use warnings;

package Mock::Dist;

use base qw(Test::MockObject);
use Test::More ();
use Test::Deep ();

my $null = sub {};

my @NULL = qw(verbose alert connect disconnect mlroot);

my %ALWAYS = (
  version_from_meta_ok => 1,
);

sub new {
  my $self = shift->SUPER::new(@_);

  $self->mock($_ => $null) for @NULL;

  $self->set_always($_ => $ALWAYS{$_}) for keys %ALWAYS;

  return $self;
}

sub next_call_ok {
  my ($self, $method, $args, $label) = @_;
  unless ($label) {
    $label = "$method: " . join ", ", @$args;
    $label =~ s/\n$//;
    $label =~ s/\n.+$/.../s;
  }
  Test::Deep::cmp_deeply(
    [ $self->next_call ],
    [ $method => [ $self, @$args ] ],
    $label,
  );
}

1;

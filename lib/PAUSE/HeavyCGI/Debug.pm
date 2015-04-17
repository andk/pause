package PAUSE::HeavyCGI::Debug;
use base 'Class::Singleton';
use Data::Dumper;
use strict;

sub as_string {
  my PAUSE::HeavyCGI::Debug $self = shift;
  my PAUSE::HeavyCGI $mgr = shift;

  # An AVHV is ugly to look at, so we convert to an HASH

  my(%f,$k,$v);

  while (($k,$v) = each %$mgr){
   next unless defined $v;
   $f{$k} = $v;
  }
  Data::Dumper::Dumper( \%f )
}

1;

=head1 NAME

PAUSE::HeavyCGI::Debug - inspect the Pseudohash as Hash with Data::Dumper

=head1 SYNOPSIS

 push @layout, "<BR><PRE>",
               $self->instance_of("PAUSE::HeavyCGI::Debug"),
               "</PRE><BR>\n";

=head1 DESCRIPTION

Can be used to inspect the application object within an output page.
The Class is just implemented as an illustration.

=cut


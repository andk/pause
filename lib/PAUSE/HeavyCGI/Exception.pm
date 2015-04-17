package PAUSE::HeavyCGI::Exception;
use strict;

sub new {
  my $class = shift;
  bless { @_ }, $class;
}

1;

=head1 NAME

    PAUSE::HeavyCGI::Exception - exception class for PAUSE::HeavyCGI

=head1 SYNOPSIS

 die PAUSE::HeavyCGI::Exception->new(HTTP_STATUS => status);
 die PAUSE::HeavyCGI::Exception->new(ERROR => [error, ...]);

=head1 DESCRIPTION

The execution of the PAUSE::HeavyCGI::prepare method is protected by
an eval. Within that block the above mentioned exceptions can be
thrown. For a discussion of the semantics of these errors, see
L<PAUSE::HeavyCGI>.

You need not C<require> the PAUSE::HeavyCGI::Error module, it is
already required by PAUSE::HeavyCGI.

=cut


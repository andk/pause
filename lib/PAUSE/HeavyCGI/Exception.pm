package Apache::HeavyCGI::Exception;
use strict;

sub new {
  my $class = shift;
  bless { @_ }, $class;
}

1;

=head1 NAME

    Apache::HeavyCGI::Exception - exception class for Apache::HeavyCGI

=head1 SYNOPSIS

 die Apache::HeavyCGI::Exception->new(HTTP_STATUS => status);
 die Apache::HeavyCGI::Exception->new(ERROR => [error, ...]);

=head1 DESCRIPTION

The execution of the Apache::HeavyCGI::prepare method is protected by
an eval. Within that block the above mentioned exceptions can be
thrown. For a discussion of the semantics of these errors, see
L<Apache::HeavyCGI>.

You need not C<require> the Apache::HeavyCGI::Error module, it is
already required by Apache::HeavyCGI.

=cut


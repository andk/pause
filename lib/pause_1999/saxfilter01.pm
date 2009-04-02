=pod

Replace all relative links with links to www.cpan.org.

These documents all live on CPAN and relative links are the correct
way to deal with them in the real documents. But when we offer them on
PAUSE, the links are not correct and we need to do some rewriting.

=cut

package pause_1999::saxfilter01;
use base XML::SAX::Base;
use strict;
our $VERSION = "512";

sub start_element {
  my($self,$prop) = @_;
  if ($prop->{Name} eq "body") {
    $self->{InBody}++;
    return;
  }
  return unless $self->{InBody};
  if ($prop->{Name} eq "a") {
    my $href;

    $href = $prop->{Attributes}{"{}href"}{Value} if
        $prop->{Attributes} &&
            $prop->{Attributes}{"{}href"} &&
                $prop->{Attributes}{"{}href"}{Value};

    if (0) {
    } elsif (!$href) {
      # anchor
    } elsif ($href =~ m{ ^ (?:ftp|http|https) : // }x ) {
      # absolute
    } elsif ($href =~ m{ ^ (?:mailto) : }x ) {
      # absolute
    } elsif ($href =~ m{^\#}) {
      # anchor
    } else {
      $prop->{Attributes}{"{}href"}{Value} =~ s{^}{http://www.cpan.org/modules/};
    }
  }

  $self->SUPER::start_element($prop);
}

sub end_element {
  my($self,$prop) = @_;
  if ($prop->{Name} eq "body") {
    $self->{InBody}--;
    return;
  }
  return unless $self->{InBody};
  $self->SUPER::end_element($prop);
}

sub characters {
  my($self,$prop) = @_;
  return unless $self->{InBody};
  $self->SUPER::characters($prop);
}

sub doctype_decl { return; }

sub processing_instruction { return; }

1;

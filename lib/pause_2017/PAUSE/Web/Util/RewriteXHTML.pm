package PAUSE::Web::Util::RewriteXHTML;

# XXX: Should be rewritten to use HTML5 eventually

use Mojo::Base;
use XML::SAX::ParserFactory;
use XML::SAX::Writer;
use XML::LibXML::SAX;
$XML::SAX::ParserPackage = "XML::LibXML::SAX";

sub rewrite {
  my ($self, $html) = @_;

  my $w = XML::SAX::Writer->new(Output => \@out);
  my $f = PAUSE::Web::Util::RewriteXHTML::Filter->new(Handler => $w);
  my $p = XML::SAX::ParserFactory->parser(Handler => $f);
  $p->parse_string($html);
  while ($out[0] =~ /^<[\?\!]/){ # remove XML Declaration, DOCTYPE
    shift @out;
  }
  join "", @out;
}



package PAUSE::Web::Util::RewriteXHTML::Filter;

use Mojo::Base "XML::SAX::Base";

sub start_element {
  my ($self, $prop) = @_;
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
  my ($self, $prop) = @_;
  if ($prop->{Name} eq "body") {
    $self->{InBody}--;
    return;
  }
  return unless $self->{InBody};
  $self->SUPER::end_element($prop);
}

sub characters {
  my ($self, $prop) = @_;
  return unless $self->{InBody};
  $self->SUPER::characters($prop);
}

sub doctype_decl { return; }

sub processing_instruction { return; }

1;

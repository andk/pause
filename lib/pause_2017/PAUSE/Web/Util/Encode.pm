package PAUSE::Web::Util::Encode;

# XXX: Should be replaced with plain Encode eventually

use Mojo::Base;
use Encode;
use HTML::Entities;
use Unicode::String;

{
  our %entity2char = %HTML::Entities::entity2char;
  while (my($k,$v) = each %entity2char) {
    if ($v =~ /[^\000-\177]/) {
      $entity2char{$k} = Unicode::String::latin1($v)->utf8;
      # warn "CONV k[$k] v[$v]";
    } else {
      delete $entity2char{$k};
      # warn "DEL v[$v]";
    }
  }
}

sub any2utf8 {
  my $s = shift;
  return $s unless defined $s;

  if ($s =~ /[\200-\377]/) {
    # warn "s[$s]";
    my $warn;
    local $^W=1;
    local($SIG{__WARN__}) = sub { $warn = $_[0]; warn "warn[$warn]" };
    my($us) = Unicode::String::utf8($s);
    if ($warn and $warn =~ /utf8|can't/i) {
      warn "DEBUG: was not UTF8, we suppose latin1 (apologies to shift-jis et al): s[$s]";
      $s = Unicode::String::latin1($s)->utf8;
      warn "DEBUG: Now converted to: s[$s]";
    } else {
      warn "seemed to be utf-8";
    }
  }
  $s = _decode_highbit_entities($s); # modifies in-place
  Encode::_utf8_on($s);
  $s;
}

sub _decode_highbit_entities {
  my $s = shift;
  # warn "s[$s]";
  my $c;
  use utf8;
  for ($s) {
    s{ ( & \# (\d+) ;? )
      }{ ($2 > 127) ? chr($2) : $1
      }xeg;

    s{ ( & \# [xX] ([0-9a-fA-F]+) ;? )
      }{$c = hex($2); $c > 127 ? chr($c) : $1
      }xeg;

    s{ ( & (\w+) ;? )
    }{my $r = $entity2char{$2} || $1; warn "r[$r]2[$2]"; $r;
    }xeg;

  }
  # warn "s[$s]";
  $s;
}

1;

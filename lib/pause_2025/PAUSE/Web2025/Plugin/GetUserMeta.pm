package PAUSE::Web2025::Plugin::GetUserMeta;

use Mojo::Base "Mojolicious::Plugin";

sub register {
  my ($self, $app, $conf) = @_;
  $app->helper(user_meta => \&_get);
}

=pod

In user_meta liegt noch der ganze Scheiss herum, mit dem ich die
unglaubliche Langsamkeit analysiert habe, die eintrat, als ich den
alten Algorithmus durch 5.8 habe durchlaufen lassen.

Am Schluss (mit $sort_method="splitted") war 5.8 etwa gleich schnell
wie 5.6, aber die Trickserei ist etwas zu aufwendig fuer meinen
Geschmack.

Also, der Fehler war, dass ich zuerst einen String zusammengebaut
habe, der UTF-8 enthalten konnte und uebermaessig lang war und dann
darueber im Sort-Algorithmus lc laufen liess. Jedes einzelne lc hat
etwas Zeit gekostet, da es im Sort-Algorithmus war, musste es 40000
mal statt 2000 mal laufen. Soweit, so klar auf einen Blick: richtige
Loesung ist es, den String mit Hilfe des "translit" Feldes zo kurz zu
lassen, dass nur ASCII verbleibt, dann ein downgrade, dann lc, und
dann erst Sortieren. In einem zweiten Hash traegt man den
Display-String herum.

Was bis heute ein Mysterium ist, ist die Frage, wieso das Einschalten
der Statistik, also ein hoher *zusaetzlicher* Aufwand, die Zeit auf
ein Sechstel biz Zehntel *gedrueckt* hat. Da muss etwas Schlimmes mit
$a und $b passieren.

=cut

sub _get {
  my $c = shift;
  my $mgr = $c->app->pause;
  my $dbh = $mgr->connect;
  my $sql = qq{SELECT userid, fullname, isa_list, asciiname
               FROM users};
  my $sth = $dbh->prepare($sql);
  $sth->execute;
  my(%u,%labels);
  # my $sort_method = "gogo";
  my $sort_method = "splitted";
  if (0) { # worked mechanically correct but slow with 5.7.3@16103.
           # The slowness is not in the fetchrow but in the sort with
           # lc below. At the time of the test $mgr->fetchrow turned
           # on UTF-8 flag on everything, including pure ASCII.

    while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
      $u{$row[0]} = $row[2] ? "mailinglist $row[0]" : "$row[1] ($row[0])";
    }

  } elsif (0) {

    # here we are measuring where the time is spent and tuning up and
    # down and experiencing strange effects.

    my $start = Time::HiRes::time();
    my %tlc;
    while (my @row = $sth->fetchrow_array) {
      if ($] > 5.007) {
        # apparently it pays to only turn on UTF-8 flag if necessary
        defined && /[^\000-\177]/ && Encode::_utf8_on($_) for @row;
      }
      $u{$row[0]} = $row[2] ? "mailinglist $row[0]" :
          $row[3] ? "$row[3]=$row[1] ($row[0])" : "$row[1] ($row[0])";

      if (0) {
        # measuring lc() alone does not explain the slow sort. We see
        # about 0.4 secs for lc() on all names when they all have the
        # UTF-8 flag on, about 0.07 secs when only selected ones have
        # the flag on.
        next unless $row[1];
        my $tlcstart = Time::HiRes::time();
        $tlc{$row[1]} = lc $row[1];
        $tlc{$row[1]} = Time::HiRes::time() - $tlcstart;
      }
    }
    # warn sprintf "TIME: fetchrow and lc on users: %7.4f", Time::HiRes::time()-$start;
    my $top = 10;
    for my $t (sort { $tlc{$b} <=> $tlc{$a} } keys %tlc) {
      warn sprintf "%-43s: %9.7f\n", $t, $tlc{$t};
      last unless --$top;
    }
  } else { # splitted!
    my $start = Time::HiRes::time();
    while (my @row = $sth->fetchrow_array) {
      if ($] > 5.007) {
        # apparently it pays to only turn on UTF-8 flag if necessary
        defined && /[^\000-\177]/ && Encode::_utf8_on($_) for @row;
      }
      my $disp = $row[2] ?
          "$row[0] (mailinglist)" :
              $row[3] ?
                  "$row[0]:$row[3]=$row[1]" :
                      "$row[0]:$row[1]";
      substr($disp, 52) = "..." if length($disp) > 55;
      my($sort) = $disp =~ /^([\000-\177]+)/;
      utf8::downgrade($sort) if $] > 5.007;
      $u{$row[0]} = lc $sort;
      $labels{$row[0]} = $disp;
    }
    warn sprintf "TIME: fetchrow and split on users: %7.4f", Time::HiRes::time()-$start;
  }
  my $start = Time::HiRes::time();
  our @tlcmark = ();
  our $Collator;
  if ($sort_method eq "U:C") {
    require Unicode::Collate;
    $Collator = Unicode::Collate->new();
  }
  # use sort qw(_mergesort);
  # use sort qw(_quicksort);
  my @sorted = sort {
    if (0) {
      # Mysterium: the worst case was to have all names with UTF-8
      # flag, Sort_method="lc" and running no statistics. Turning on
      # the statistics here reduced runtime from 77-133 to 12 secs.
      # With only selected names having UTF-8 flag on we reach 10 secs
      # without the statistics and 12 with it. BTW, mergesort counts
      # 20885 comparisons, quicksort counts 23201.
      push(
           @tlcmark,
           sprintf("%s -- %s: %9.7f",
                   $u{$a},
                   $u{$b},
                   Time::HiRes::time())
          );
    }
    if (0) {
    } elsif ($sort_method eq "lc") {
      # we reach minimum of 10 secs here, better than 77-133 but still
      # unacceptable. We seem to have to fight against two bugs: slow
      # lc() always is one bug, extremely slow lc() when combined with
      # sort is the other one. We must solve it as we did in metalist:
      # maintain a sortdummy in the database and let the database sort
      # on ascii.
      lc($u{$a}) cmp lc($u{$b});
    } elsif ($sort_method eq "U:C") {
      $Collator->cmp($a,$b);
      # v0.10 completely bogus and 67 secs
    } elsif ($sort_method eq "splitted") {
      $u{$a} cmp $u{$b};
    } else {
      # we reach 0.27 secs here with mergesort, 0.28 secs after we
      # switched to quicksort.
      $u{$a} cmp $u{$b};
    }
  } keys %u;
  warn sprintf "TIME: sort on users: %7.4f", Time::HiRes::time()-$start;
  if (@tlcmark) {
    warn "COMPARISONS: $#tlcmark";
    my($Ltlcmark) = $tlcmark[0] =~ /:\s([\d\.]+)/;
    # warn "$Ltlcmark;$tlcmark[0]";
    my $Mdura = 0;
    for my $t (1..$#tlcmark) {
      my($tlcmark) = $tlcmark[$t] =~ /:\s([\d\.]+)/;
      my $dura = $tlcmark - $Ltlcmark;
      if ($dura > $Mdura) {
        my($lterm) = $tlcmark[$t-1] =~ /(.*):/;
        warn sprintf "%s: %9.7f\n", $lterm, $dura;
        $Mdura = $dura;
      }
      $Ltlcmark = $tlcmark;
    }
  }

  return (
          userid => {
                     type     => "scrolling_list",
                     args  => {
                               'values' => \@sorted,
                               size     => 10,
                               labels   => $sort_method eq "splitted" ? \%labels : \%u,
                              },
                    }
         );
}

1;

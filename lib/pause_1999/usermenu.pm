# -*- Mode: cperl; coding: utf-8 -*-
package pause_1999::usermenu;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use utf8;
our $VERSION = "854";

sub as_string {
  my $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my $user = $req->user;
  my $myurl = $mgr->myurl;
  my $server = $myurl->can("host") ? $myurl->host : $myurl->hostname;
  if (my $port = $myurl->port) {
      if ($port != 80) {
          warn "DEBUG: url[$myurl]port[$port]";
          $server .= ":$port";
      }
  }

  if (0) {
    $req->logger->({level => 'error', message => sprintf(
                          "Watch: server[%s]at[%s]line[%d]",
                          $server,
                          __FILE__,
                          __LINE__,
                         )});
  }
  my @m;
  push @m, qq{<table width="155" cellspacing="1" cellpadding="0">};
  my $activecolor = $mgr->{ActiveColor};
  unless ($user) {
    push @m, qq{<tr><td class="menuitem">};
    if ($mgr->{REQ}->port == 8000) {
      $server =~ s/:8000/:8443/ or $server .= ":8443";
    }
    my $schema = "https";
    if ($PAUSE::Config->{TESTHOST_SCHEMA} && $PAUSE::Config->{TESTHOST_SCHEMA}) {
        $schema = $PAUSE::Config->{TESTHOST_SCHEMA};
    }
    push @m, qq{<a class="menuitem" href="$schema://$server/pause/authenquery">Login</a>};
    push @m, qq{</td></tr>\n};

  }


  # warn "allowaction[@{$mgr->{AllowAction}||[]}]";
  my %grouplabel = (
		    public => "Public",
		    user => "User",
		    mlrepr => "Mailinglists",
                    modmaint => "ModListMaint",
		    admin => "Admin",
		   );
  my @offer_groups = "public";
  if ($mgr->{User}{userid}) {
    push @offer_groups, "user";
    for my $g (qw(mlrepr modmaint admin)) {
      if (exists $mgr->{UserGroups}{$g} || exists $mgr->{UserGroups}{"admin"}) {
        push @offer_groups, $g;
      }
    }
  }
  for my $priv (@offer_groups) {
    last if $priv eq "user" and ! $mgr->{User}{userid};
    last if $priv eq "admin" and ! exists $mgr->{UserGroups}{admin};
    push @m, qq{<tr><td class="menuheading" colspan="2"><b>$grouplabel{$priv} menu</b></td></tr>};
    my $Lscat = "";
    for my $action (
                    sort {
                      $mgr->{ActionTuning}{$a}{cat}
                          cmp
                              $mgr->{ActionTuning}{$b}{cat}
                    }
                    @{$mgr->{AllowAction}||[]}
                   ) {

      my $confpriv = $mgr->{ActionTuning}{$action}{priv};
      unless ($confpriv) {
        warn "action[$action] has no confpriv!";
        $confpriv = "admin";
      }
      next unless $confpriv eq $priv;

      my $verbose = $mgr->{ActionTuning}{$action}{verb}
	  if exists $mgr->{ActionTuning}{$action};
      $verbose ||= $action;
      my $class;
      warn "action undef" unless defined $action;
      warn "mgr->Action undef" unless defined $mgr->{Action};
      my $cat = $mgr->{ActionTuning}{$action}{cat};
      if (substr($cat,0,1) =~ tr/A-Z//) {
        my($scat) = $cat =~ m|.+?/\d\d(.+?)/|;
        if ($scat ne $Lscat) {
          push @m, qq{<tr><td class="menuheading">$scat</td></tr>\n};
          $Lscat = $scat;
        }
      }
      my $activemarkerleft = "";
      my $activemarkerright = "";
      my $activecol2 = "";
      if ($action eq $mgr->{Action}) {
	$class = "activemenu";
        # $activemarkerleft = "\x{21d2}&#160;"; # Pfeil

        $activemarkerleft = "&gt; "; # : "\x{25b6}&#160;"; # Dreieck

        #### IE6 alert. If I send this \x{25b6} with 5.6.1, then IE6
        #### cannot display a single page, as "Gregor Mosheh, B.S."
        #### <stigmata@blackangel.net> reported.

        # $activemarkerleft = "\x{266c}&#160;"; # 2 Sechzehntelnoten
        # $activemarkerleft = "\x{300b}&#160;"; # hohes Zeichen wie ">>"
        # $activemarkerright = "\x{21d0}";
        $activecol2 = ""; # "\x{25c0}";
      } else {
	$class = "menuitem";
      }
      push @m, qq{<tr><td class="$class">};
      push @m, sprintf(
                       qq{<a class="$class" href="%s?ACTION=%s">%s%s%s%s</a>},
                       $mgr->{QueryURL},
                       $action,
                       $activemarkerleft,
                       "", # $mgr->{ActionTuning}{$action}{cat},
                       $verbose,
                       $activemarkerright,
                      );
      push @m, qq{</td><td class="menupointer">$activecol2</td></tr>\n};
    }
  }
  push @m, qq{</table>\n};
  @m;
}

1;

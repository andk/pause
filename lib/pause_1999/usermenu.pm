# -*- Mode: cperl; coding: utf-8 -*-
package pause_1999::usermenu;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use utf8;

sub as_string {
  my pause_1999::usermenu $self = shift;
  my pause_1999::main $mgr = shift;
  my $r = $mgr->{R};
  my $user = $r->connection->user;
  my $server = $mgr->myurl->can("host") ? $mgr->myurl->host : $mgr->myurl->hostname;
  $r->log_error(sprintf "Watch: server[%s]at[%s]line[%d]", $server, __FILE__, __LINE__);
  my @m;
  push @m, qq{<table width="155" cellspacing="1" cellpadding="0">};
  my $activecolor = $mgr->{ActiveColor};
  if ($user) {
    my($encr,$class);
    if ($mgr->myurl->scheme eq "https") {
      $encr = 1;
      $class = "statusencr";
    } else {
      $encr = 0;
      $class = "statusunencr";
    }

    push @m, sprintf(
                     qq{<tr><td class="%s"><b>%s<br />%s session</b></td></tr>},
                     $class,
                     $user,
                     $encr ? "encrypted" : "unencrypted",
                     );

    unless ($encr) {
      my $loc = $mgr->myurl->path;
      push @m, qq{<tr><td class="menuitem">};
      push @m, qq{<a class="menuitem" href="https://$server$loc">Switch to SSL</a>};
      push @m, qq{</td></tr>};
    }

    push @m, qq{<tr><td class="menuitem">};
    push @m, qq{<a class="menuitem" href="authenquery?please_renegotiate_username">Login as sb. else</a>};
    push @m, qq{</td></tr>\n};

    push @m, qq{<tr><td class="menuitem">};
    push @m, qq{<a class="menuitem" href="query">Unauthenticate ("Logout")</a>};
    push @m, qq{</td></tr>\n};

  } else {

    push @m, qq{<tr><td class="menuitem">};
    if ($mgr->{R}->server->port == 8000) {
      $server =~ s/:8000/:8443/ or $server .= ":8443";
    }
    push @m, qq{<a class="menuitem" href="https://$server/pause/authenquery">Login</a>};
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
      my $activemarkerleft = "";
      my $activemarkerright = "";
      my $activecol2 = "";
      if ($action eq $mgr->{Action}) {
	$class = "activemenu";
        # $activemarkerleft = "\x{21d2}&nbsp;"; # Pfeil

        $activemarkerleft = "&gt; "; # : "\x{25b6}&nbsp;"; # Dreieck

        #### IE6 alert. If I send this \x{25b6} with 5.6.1, then IE6
        #### cannot display a single page, as "Gregor Mosheh, B.S."
        #### <stigmata@blackangel.net> reported.

        # $activemarkerleft = "\x{266c}&nbsp;"; # 2 Sechzehntelnoten
        # $activemarkerleft = "\x{300b}&nbsp;"; # hohes Zeichen wie ">>"
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
      push @m, qq{</td><td class="menupointer">$activecol2</td></tr
>};
    }
  }
  push @m, qq{</table
>};
  @m;
}

1;

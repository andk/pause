# -*- Mode: cperl; coding: utf-8 -*-
package pause_1999::userstatus;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use utf8;
our $VERSION = "946";

sub as_string {
  my $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my $user = $req->user;
  my $server = $mgr->myurl->can("host") ? $mgr->myurl->host : $mgr->myurl->hostname;
  # $req->logger->({level => 'error', message => sprintf "Watch: server[%s]at[%s]line[%d]", $server, __FILE__, __LINE__});
  my $activecolor = $mgr->{ActiveColor};
  return unless $user && $user ne "-";
  my @m;
  push @m, qq{<table  cellpadding="3" cellspacing="0">};
  my($encr,$class);
  if ($mgr->is_ssl) {
    $encr = 1;
    $class = "statusencr";
  } else {
    $encr = 0;
    $class = "statusunencr";
  }

  my $hu = "";
  if ($mgr->{HiddenUser}{userid}
      &&
      $mgr->{HiddenUser}{userid} ne $mgr->{User}{userid}
     ) {
    $hu = sprintf qq{acting as %s &lt;%s&gt;<br />},
        $mgr->{HiddenUser}{userid},
            $mgr->escapeHTML(
                             $mgr->{HiddenUser}{secretemail}
                             ||
                             $mgr->{HiddenUser}{email}
                             ||
                             "No email???"
                            );
  }
  push @m, sprintf(
                   qq{<tr><td class="%s" nowrap="nowrap">%s &lt;%s&gt;<br />%s%s</td></tr>},
                   $class,
                   $user,
                   $mgr->escapeHTML(
                                    $mgr->{User}{secretemail}
                                    ||
                                    $mgr->{User}{email}
                                    ||
                                    "No email???"
                                   ),
                   $hu,
                   $encr ? "encrypted session" : "<b>unencrypted session</b>",
                  );

  push @m, qq{</table>\n};
  @m;
}

1;

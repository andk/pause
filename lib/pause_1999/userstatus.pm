# -*- Mode: cperl; coding: utf-8 -*-
package pause_1999::userstatus;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use utf8;
our $VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

sub as_string {
  my pause_1999::userstatus $self = shift;
  my pause_1999::main $mgr = shift;
  my $r = $mgr->{R};
  my $user = $r->connection->user;
  my $server = $mgr->myurl->can("host") ? $mgr->myurl->host : $mgr->myurl->hostname;
  $r->log_error(sprintf "Watch: server[%s]at[%s]line[%d]", $server, __FILE__, __LINE__);
  my @m;
  push @m, qq{<table  cellpadding="3" cellspacing="0">};
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
                     qq{<tr><td class="%s" nowrap="nowrap">%s &lt;%s&gt;<br />%s</td></tr>},
                     $class,
                     $user,
                     $mgr->escapeHTML($mgr->{User}{secretemail}),
                     $encr ? "encrypted session" : "<b>unencrypted session</b>",
                     );

  }
  push @m, qq{</table>\n};
  @m;
}

1;

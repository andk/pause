# -*- Mode: cperl; coding: utf-8 -*-
package pause_1999::message;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use utf8;
our $VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

sub as_string {
  my pause_1999::message $self = shift;
  my pause_1999::main $mgr = shift;
  my $r = $mgr->{R};
  my $user = $mgr->{HiddenUser}{userid} || $mgr->{User}{userid} or return;
  my @m;
  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare("select * from messages where mto=? AND mstatus='active'");
  $sth->execute($user);
  if ($sth->rows > 0) {
    push @m, qq{<div class="messages">};
    push @m, qq{<p><b>Message board</b> for user <b>$user</b>:</p>};
    push @m, qq{<dl>};
    while (my $rec = $sth->fetchrow_hashref) {
      push @m, qq{<dt><b>$rec->{created}</b> from $rec->{mfrom}\@cpan.org</dt>};
      push @m, qq{<dd>};
      push @m, $mgr->escapeHTML($rec->{message});
      push @m, qq{</dd>};
    }
    push @m, qq{</dl>};

    push @m, qq{<p><b>Note:</b> Only the poster of a message can
        delete it. Please contact them.</p>};

    push @m, qq{</div>\n};
  }
  @m;
}

1;

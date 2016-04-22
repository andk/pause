# -*- Mode: cperl; coding: utf-8 -*-
package pause_1999::message;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use utf8;
our $VERSION = "946";

sub as_string {
  my $self = shift;
  my $mgr = shift;
  my $user = $mgr->{HiddenUser}{userid} || $mgr->{User}{userid} or return;
  my @m;
  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare("select * from messages where mto=? AND mstatus='active'");
  $sth->execute($user);
  if ($sth->rows > 0) {
    push @m, qq{<div class="messages">};

    push @m, qq{<p>This is the <b>Message Board</b> for user
        <b>$user</b>. On the message board you see messages posted by
        an admin to a user in case that email doesn't work:</p>};

    push @m, qq{<dl>};
    while (my $rec = $sth->fetchrow_hashref) {
      push @m, qq{<dt><b>$rec->{created}</b> from $rec->{mfrom}\@cpan.org</dt>};
      push @m, qq{<dd>};
      push @m, $mgr->escapeHTML($rec->{message});
      push @m, qq{</dd>};
    }
    push @m, qq{</dl>};

    push @m, qq{<p><b>Note:</b> Only the poster of a message can
        delete it from the message board. Please contact them, so that
        they clear the board for you.</p>};

    push @m, qq{</div>\n};
  }
  @m;
}

1;

#!/usr/bin/perl -- -*- Mode: cperl; coding: unicode-utf8; VAR: VALUE; ... -*-
package pause_1999::pausegif;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use vars qw( $Exeplan );
our $VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

sub as_string {
  my pause_1999::pausegif $self = shift;
  my pause_1999::main $mgr = shift;
  my $gif = $mgr->can_png ? "png" : "jpg";
  qq{<a href="authenquery"><img src="/pause/pause2.$gif"
 border="0" alt="PAUSE Logo"
 width="177" height="43" align="left" /></a>};
}

1;

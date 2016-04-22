#!/usr/bin/perl -- -*- Mode: cperl; coding: utf-8 -*-



=pod

From 1997 or 1998 till 2002-12-31, Speed-Link was our sponsor, hence
the filename.

From 2003-01-01, Loomes is taking over.

From 2003-11-27, Fiz-Chemie is the Sponsor.

=cut

package pause_1999::speedlinkgif;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use vars qw( $Exeplan );
our $VERSION = "1069";

sub as_string {
  my $self = shift;
  my $mgr = shift;
  my $pngjpg = $mgr->can_png ? "png" : "jpg";
  my $pnggif = $mgr->can_png ? "png" : "gif";
  my $validator_href = "http://validator.w3.org/check/referer";
  my $validator_comment = "";
  if ($mgr->{REQ}->path =~ /authen/ or $mgr->myurl->scheme eq "https") {
    $validator_href = "http://validator.w3.org/file-upload.html";
    $validator_comment = q{<div class="xexplain" align="right">To validate, download page first.</div><br />};
  }
  my $version = $mgr->version;
  qq{<table width="100%">
      <tr>
       <td>&#160;</td>
       <td width="100%" valign="top" align="center"><div class="xexplain">Rev: $version</div></td>
       <td valign="top">$validator_comment</td>
      </tr>
      <tr>
       <td width="100%"></td>
       <td>
        <a href="http://jigsaw.w3.org/css-validator/"><img
           src="/pause/vcss.$pnggif"
           alt="Valid CSS!" height="31" width="88" /></a>
       </td>
       <td>
        <a href="$validator_href">
         <img src="/pause/valid-xhtml10.$pnggif"
           alt="Valid XHTML 1.0!" height="31" width="88" />
        </a>
       </td>
      </tr>
     </table>
};
}

1;

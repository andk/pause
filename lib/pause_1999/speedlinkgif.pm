#!/usr/bin/perl -- -*- Mode: cperl; coding: unicode-utf8; VAR: VALUE; ... -*-
package pause_1999::speedlinkgif;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use vars qw( $Exeplan );

sub as_string {
  my pause_1999::speedlinkgif $self = shift;
  my pause_1999::main $mgr = shift;
  my $pngjpg = $mgr->can_png ? "png" : "jpg";
  my $pnggif = $mgr->can_png ? "png" : "gif";
  my $validator_href = "http://validator.w3.org/check/referer";
  my $validator_comment = "";
  if ($mgr->{R}->uri =~ /authen/ or $mgr->myurl->scheme eq "https") {
    $validator_href = "http://validator.w3.org/file-upload.html";
    $validator_comment = q{<div class="xexplain" align="right">To validate, download page first.</div><br />};
  }
  qq{<table width="100%">
      <tr>
       <td rowspan="2">
        <div class="xexplain">The PAUSE is sponsored by</div><br />
        <a href="http://www.speed-link.de">
         <img src="/pause/logo9a-sm.$pngjpg" border="0" alt="SPEEDLINK Logo"
              width="121" height="47" align="left" />
        </a>
       </td>
       <td width="100%"></td>
       <td colspan="2">$validator_comment
       </td>
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

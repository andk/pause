#!/usr/bin/perl -- -*- Mode: cperl; coding: utf-8; -*-
package pause_1999::layout;
use base 'Class::Singleton';
use Apache::HeavyCGI::Layout;
use pause_1999::main;
use strict;
our $VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

sub layout {
  my($self) = shift;
  my pause_1999::main $mgr = shift;

  # on a high-end application we would cache aggressively the three or
  # twelve layouts that might be generated. On the PAUSE we don't mind
  # to generate them again and again, speed is not an issue and layout
  # is primitive

  my @l;
  # http://validator.w3.org/check had (2000-10-17) the User-Agent
  # "W3C_Validator/1.67 libwww-perl/5.48"
  if (1 || $mgr->uagent =~ m|W3C_Validator/\d+\.\d+\s+libwww-perl/\d+\.\d+|) {
    # When we had still doubt, we did only send the doctype to the
    # validator.
    if ($mgr->can_utf8) {
      push @l, qq{<?xml version="1.0" encoding="UTF-8"?>};
    } else {
      push @l, qq{<?xml version="1.0" encoding="ISO-8859-1"?>};
    }
    push @l, qq{<!DOCTYPE html
                 PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
                 "DTD/xhtml1-transitional.dtd">};
  }
  push @l, qq{<html><head><title>};
  push @l, $PAUSE::Config->{TESTHOST} ? qq{pause\@home: } : qq{PAUSE: };
  push @l, $mgr->{Action} || "The CPAN back stage entrance";
  my $hspecial = $PAUSE::Config->{TESTHOST} ? "h2,h4,b { color: #f0f; }" : "";


=pod

Netscape 479 liest kommentare?

// body { font-family: Helvetica, Arial, sans-serif; }
// h2,h3,h4 { margin: 1% 8% 5% 3%; padding-left: 3em; background-color: silver; border: black; border-style: solid dotted none; }
// h1,h2,h3,h4 { margin: 0 0 5%; }

=cut

  push @l, qq{</title>
<link rel="shortcut icon" href="/pause/pause_favicon.jpg" type="image/jpeg" />
<style type="text/css">
.activemenu { background: #bfb; font-size: small; line-height: 1.5; }
.alternate1 {
  background: #f8f8f8;
  padding-bottom: 12px;
  }
.alternate2 {
  background: #ddd;
  padding-bottom: 12px;
  }
.explain { font-size: small; }
.firstheader { margin: 0 0 5%; }
.menuheading { background: white;
               font-size: small; }
.menuitem { background: #ddf; font-size: small; line-height: 1.5; }
.menupointer { color: green; }
.messages { text-align: left; border: 2px dashed red; padding: 2ex; }
.statusencr { background: #bfb;
              text-align: center;
                  border: green solid 2px;
               font-size: small; }
.statusunencr { background: #fbb;
                text-align: center;
                    border: red solid 2px;
                 font-size: small; }
.xexplain { font-size: x-small; }
a.activemenu { text-decoration: none; }
a.activemenu:hover { text-decoration: underline; }
a.menuitem { text-decoration: none; }
a.menuitem:hover { text-decoration: underline; }
h4.altering { margin: 0 0 12px; }
p.motd { margin: 12px 1in; padding: 6px; color: black; background: yellow; font-size: small; }
td.activemenu { border: green solid 1px; }
$hspecial
</style>
</head><body bgcolor="white" link="#0000CC" vlink="#0000BB"
 alink="#FF0000" text="#000000"><table width="100%" border="0"
 cellpadding="0" cellspacing="0"><tr><td valign="middle">}; #};
  push @l, $mgr->instance_of("pause_1999::pausegif");
  push @l, qq{</td><td nowrap="nowrap"><h4
  style="margin: 0 0 0 0; padding: 0 1em;">The Perl Authors Upload
  Server</h4></td><td align="right" style="width: 100%;">};
  push @l, $mgr->instance_of("pause_1999::userstatus");
  push @l, qq{</td></tr></table><br />};

  #
  # MOTD
  #

  if (time < 1058515976) {
    push @l, qq{<div align="center">};

    push @l, qq{<p class="motd"><b>Certificate News</b><br/>PAUSE's old SSL certificate was about
    to expire on 2003-05-20, so I had to issue a new one. This is why
    your browser was asking you to confirm the new certificate. The
    fingerprint of this certificate is <code>MD5 Fingerprint=83:E9:A6:4C:EC:CC:60:A8:A1:6C:5F:30:11:53:41:06</code>
    and it expires on 2009-01-07.</p>};

    push @l, qq{</div>};

  }

  my $downtime = 1057651200;
  if (time < $downtime) {
    push @l, qq{<div align="center">};
    use Time::Duration;
    my $delta = $downtime - time;
    my $expr = Time::Duration::duration($delta);

    push @l, qq{<p class="motd"><b>Scheduled downtime</b><br />On
2003-07-08 at 8 GMT (that is in $expr) we'll have to close PAUSE for
maintainance work (again). The estimated downtime is 2 hours. Thank
you for your patience and sorry for the inconvenience.</p>};

    push @l, qq{</div>};

  }

    push @l, $mgr->instance_of("pause_1999::message");
  if ($mgr->{ERROR} && @{$mgr->{ERROR}}) {
    push @l, qq{<h1>Error</h1><p>\n}, @{$mgr->{ERROR}},
	qq{</p><p>Please try again, probably by using the Back button of
 your browser and repeating the last action you took.</p>};
  } else {
    push @l, $mgr->instance_of("pause_1999::startform");
    push @l, qq{<table border="0" cellpadding="1"><tr><td valign="top">}; #};

    #
    # MENU on the LEFT
    #
    push @l, $mgr->instance_of("pause_1999::usermenu");

    push @l, qq{</td><td valign="top" bgcolor="red"\n>};
    push @l, qq{&nbsp;};
    push @l, qq{</td><td valign="top">};
    push @l, $mgr->instance_of("pause_1999::edit");
    push @l, qq{</td></tr></table>\n};
    push @l, qq{</form>};
  }
  push @l, qq{<hr noshade="noshade" />};
  push @l, $mgr->instance_of("pause_1999::speedlinkgif");
  push @l, qq{</body></html>\n};
  Apache::HeavyCGI::Layout->new(@l);
}

1;

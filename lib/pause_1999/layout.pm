#!/usr/bin/perl -- -*- Mode: cperl; coding: utf-8; ... -*-
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
.menuheading { background: white;
               font-size: small; }
.menuitem { background: #ddf; font-size: small; line-height: 1.5; }
.activemenu { background: #bfb; font-size: small; line-height: 1.5; }
.menupointer { color: green; }
td.activemenu { border: green solid 1px; }
.statusencr { background: #bfb;
              text-align: center;
                  border: green solid 2px;
               font-size: small; }
.statusunencr { background: #fbb;
                text-align: center;
                    border: red solid 2px;
                 font-size: small; }
a.menuitem { text-decoration: none; }
a.activemenu { text-decoration: none; }
a.menuitem:hover { text-decoration: underline; }
a.activemenu:hover { text-decoration: underline; }
.alternate1 { background: #f8f8f8; }
.alternate2 { background: #ddd; }
.explain { font-size: small; }
.xexplain { font-size: x-small; }
.firstheader { margin: 0 0 5%; }
p.motd { margin: 12px 1in; padding: 6px; color: black; background: yellow; font-size: small; }
.messages { text-align: left; border: 2px dashed red; padding: 2ex; }
$hspecial
</style>
</head><body bgcolor="white" link="#0000CC" vlink="#0000BB"
 alink="#FF0000" text="#000000"><table width="100%" border="0"
 cellpadding="0" cellspacing="0"
><tr><td valign="middle">}; #};
  push @l, $mgr->instance_of("pause_1999::pausegif");
  push @l, qq{</td><td nowrap="nowrap"><h4
  style="margin: 0 0 0 0; padding: 0 1em;">The Perl Authors Upload
  Server</h4></td><td align="right" style="width: 100%;">};
  push @l, $mgr->instance_of("pause_1999::userstatus");
  push @l, qq{</td></tr></table><br />};

  #
  # MOTD
  #

  if (0) {
    push @l, qq{<div align="center">};

    push @l, qq{<p class="motd">FUNET, the CPAN master site is <a
    href="http://use.perl.org/articles/03/02/16/1416231.shtml?tid=32">currently
    broken</a>. This means that your upload will not be propagated to
    the CPAN until this problem is fixed. Sorry <code>:-(</code> </p>};

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
    push @l, qq{</td><td valign="top"
>};
    push @l, $mgr->instance_of("pause_1999::edit");
    push @l, qq{</td></tr></table>};
    push @l, qq{</form>};
  }
  push @l, qq{<hr noshade="noshade" />};
  push @l, $mgr->instance_of("pause_1999::speedlinkgif");
  push @l, qq{</body></html>\n};
  Apache::HeavyCGI::Layout->new(@l);
}

1;

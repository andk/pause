#!/usr/bin/perl -- -*- Mode: cperl; coding: utf-8; -*-
package pause_1999::layout;
use base 'Class::Singleton';
use PAUSE::HeavyCGI::Layout;
use pause_1999::main;
use strict;
our $VERSION = "994";

sub layout {
  my($self) = shift;
  my $mgr = shift;

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
                 "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">};
  }
  push @l, qq{<html xmlns="http://www.w3.org/1999/xhtml"><head><title>};
  push @l, $PAUSE::Config->{TESTHOST} ? qq{pause\@home: } : qq{PAUSE: };
  push @l, $mgr->{Action} || "The CPAN back stage entrance";
  my $hspecial = $PAUSE::Config->{TESTHOST} ? "h2,h4,b,th,td { color: #486f8d; }" : "";


=pod

Netscape 479 was reading comments

// body { font-family: Helvetica, Arial, sans-serif; }
// h2,h3,h4 { margin: 1% 8% 5% 3%; padding-left: 3em; background-color: silver; border: black; border-style: solid dotted none; }
// h1,h2,h3,h4 { margin: 0 0 5%; }

=cut

  push @l, qq{</title>
<link rel="shortcut icon" href="/pause/pause_favicon.jpg" type="image/jpeg" />
<link rel="stylesheet" type="text/css" href="/pause/pause.css" title="pause"/>
}; #};
  push @l, qq{<style type="text/css">
$hspecial
</style>
} if $hspecial;
  push @l, qq{</head><body bgcolor="white" link="#0000CC" vlink="#0000BB"
 alink="#FF0000" text="#000000"><table width="100%" border="0"
 cellpadding="0" cellspacing="0"><tr><td valign="middle">}; #};
  push @l, $mgr->instance_of("pause_1999::pausegif");
  push @l, qq{</td><td nowrap="nowrap"><h4
  style="margin: 0 0 0 0; padding: 0 1em;">The [Perl programming] Authors Upload
  Server</h4></td><td align="right" style="width: 100%;">};
  push @l, $mgr->instance_of("pause_1999::userstatus");
  push @l, qq{</td></tr></table><br />};

  #
  # MOTD
  #

  my $downtime = $mgr->{DownTime}||0;
  my $willlast = $mgr->{WillLast}||0;
  my $deploy_two_apaches = 0;
  if ($deploy_two_apaches && $] > 5.009005) {
    require Config;
    my($bin) = $Config::Config{bin} =~ m|^.*?/perl-(.+?)/|;
    push @l, sprintf(qq{<p class="versionspecial">This is perl %s;},
                     $bin,
                    );
    push @l, sprintf(qq{ cf_time %s; },
                     $Config::Config{cf_time},
                    );

    push @l, qq{when you run into problems try <a
    class="versionspecial"
    href="https://pause.perl.org:8443/pause/authenquery">Port&#160;8443&#160;(https)</a>,
    where perl 5.8.7 should be running (or <a class="versionspecial"
    href="http://pause.perl.org:8000/pause/query">Port&#160;8000</a>
    if you need http).</p>};

  }

  if (time < $downtime) {
    push @l, qq{<div align="center">};
    use HTTP::Date;
    my $httptime = HTTP::Date::time2str($downtime);
    use Time::Duration;
    my $delta = $downtime - time;
    my $expr = Time::Duration::duration($delta);
    my $willlast_dur = Time::Duration::duration($willlast);

    push @l, qq{<p class="motd"><b>Scheduled downtime</b><br />On
$httptime (that is in $expr) PAUSE will be closed for maintainance
work. The estimated downtime is $willlast_dur.</p>}; #};

    push @l, qq{</div>};

  } elsif (time < $downtime+$willlast) {
    my $user = $mgr->{User}{userid};  # if closed and somebody comes
                                      # here, it currently is always
                                      # ANDK

    my $closed_text = $mgr->{REQ}->env->{'psgix.notes'}{CLOSED};

    push @l, qq{<div align="center"> <p class="motd">Hi $user, you
see the site now <b>but it is closed for maintainance</b>.
Please be careful not to disturb the database operation. Expect
failures everywhere. Do not edit anything, it may get lost. Other
users get the following text:</p> $closed_text </div>};

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
    push @l, qq{&#160;};
    push @l, qq{</td><td valign="top">};
    push @l, $mgr->instance_of("pause_1999::edit");
    push @l, qq{</td></tr></table>\n};
    push @l, qq{</form>};
  }
  push @l, qq{<hr noshade="noshade" />};
  push @l, $mgr->instance_of("pause_1999::speedlinkgif");
  push @l, qq{</body></html>\n};
  PAUSE::HeavyCGI::Layout->new(@l);
}

1;

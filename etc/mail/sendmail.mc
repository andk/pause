divert(-1)dnl
#-----------------------------------------------------------------------------
# $Sendmail: debproto.mc,v 8.13.4 2006-03-22 22:41:17 cowboy Exp $
#
# Copyright (c) 1998-2005 Richard Nelson.  All Rights Reserved.
#
# cf/debian/sendmail.mc.  Generated from sendmail.mc.in by configure.
#
# sendmail.mc prototype config file for building Sendmail 8.13.4
#
# Note: the .in file supports 8.7.6 - 9.0.0, but the generated
#	file is customized to the version noted above.
#
# This file is used to configure Sendmail for use with Debian systems.
#
# If you modify this file, you will have to regenerate /etc/mail/sendmail.cf
# by running this file through the m4 preprocessor via one of the following:
#	* `sendmailconfig` 
#	* `make`
#	* `m4 /etc/mail/sendmail.mc > /etc/mail/sendmail.cf`
# The first two options are preferred as they will also update other files
# that depend upon the contents of this file.
#
# The best documentation for this .mc file is:
# /usr/share/doc/sendmail-doc/cf.README.gz
#
#-----------------------------------------------------------------------------
divert(0)dnl
#
#   Copyright (c) 1998-2005 Richard Nelson.  All Rights Reserved.
#
#  This file is used to configure Sendmail for use with Debian systems.
#
define(`_USE_ETC_MAIL_')dnl
include(`/usr/share/sendmail/cf/m4/cf.m4')dnl
VERSIONID(`$Id: sendmail.mc, v 8.13.4-3sarge1 2006-03-22 22:41:17 cowboy Exp $')
OSTYPE(`debian')dnl
DOMAIN(`debian-mta')dnl
dnl # Items controlled by /etc/mail/sendmail.conf - DO NOT TOUCH HERE
undefine(`confHOST_STATUS_DIRECTORY')dnl        #DAEMON_HOSTSTATS=
dnl # Items controlled by /etc/mail/sendmail.conf - DO NOT TOUCH HERE
dnl #
dnl # General defines
dnl #
dnl # SAFE_FILE_ENV: [undefined] If set, sendmail will do a chroot()
dnl #	into this directory before writing files.
dnl #	If *all* your user accounts are under /home then use that
dnl #	instead - it will prevent any writes outside of /home !
dnl #   define(`confSAFE_FILE_ENV',             `')dnl
LOCAL_CONFIG
FEATURE(`masquerade_envelope')dnl
FEATURE(`always_add_domain')dnl
LOCAL_CONFIG
Cwpause.perl.org
FEATURE(`use_cw_file')dnl
FEATURE(`use_ct_file')dnl
FEATURE(`smrsh')dnl
define(`confME_TOO', True)dnl
dnl #
dnl # Daemon options - restrict to servicing LOCALHOST ONLY !!!
dnl # Remove `, Addr=' clauses to receive from any interface
dnl # If you want to support IPv6, switch the commented/uncommentd lines
FEATURE(`no_default_msa')dnl
dnl DAEMON_OPTIONS(`Family=inet6, Name=MTA-v6, Port=smtp, Addr=::1')dnl
DAEMON_OPTIONS(`Family=inet,  Name=MTA-v4, Port=smtp')dnl
dnl DAEMON_OPTIONS(`Family=inet6, Name=MSP-v6, Port=submission, Addr=::1')dnl
DAEMON_OPTIONS(`Family=inet,  Name=MSP-v4, Port=submission')dnl
dnl #
dnl # Be somewhat anal in what we allow
define(`confPRIVACY_FLAGS',dnl
`needmailhelo,needexpnhelo,needvrfyhelo,restrictqrun,restrictexpand,nobodyreturn,authwarnings')dnl
dnl #
dnl # Define connection throttling and window length
define(`confCONNECTION_RATE_THROTTLE', `15')dnl
define(`confCONNECTION_RATE_WINDOW_SIZE',`10m')dnl
dnl #
dnl # Features
dnl #
dnl # The access db is the basis for most of sendmail's checking
FEATURE(`access_db', , `skip')dnl
dnl #
dnl # The greet_pause feature stops some automail bots - but check the
dnl # provided access db for details on excluding localhosts...
FEATURE(`greet_pause', `1000')dnl 1 seconds
dnl #
dnl # Delay_checks allows sender<->recipient checking
FEATURE(`delay_checks', `friend', `n')dnl
dnl #
dnl # If we get too many bad recipients, slow things down...
define(`confBAD_RCPT_THROTTLE',`3')dnl
dnl #
dnl # Stop connections that overflow our concurrent and time connection rates
FEATURE(`conncontrol', `nodelay', `terminate')dnl
FEATURE(`ratecontrol', `nodelay', `terminate')dnl
dnl #
dnl # If you're on a dialup link, you should enable this - so sendmail
dnl # will not bring up the link (it will queue mail for later)
dnl define(`confCON_EXPENSIVE',`True')dnl
dnl #

dnl # Masquerading options
FEATURE(`always_add_domain')dnl
MASQUERADE_AS(`pause.perl.org')dnl
FEATURE(`allmasquerade')dnl
FEATURE(`masquerade_envelope')dnl

define(`confHOST_STATUS_DIRECTORY',`host_status')dnl
define(`confSINGLE_THREAD_DELIVERY', True)dnl
define(`SMTP_MAILER_MAXMSGS', 1)dnl
define(`RELAY_MAILER_MAXMSGS', 1)dnl

dnl # Default Mailer setup
MAILER_DEFINITIONS
MAILER(`local')dnl
MAILER(`smtp')dnl

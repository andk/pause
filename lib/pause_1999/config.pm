#!/usr/bin/perl -- -*- Mode: cperl;  -*-
package pause_1999::config;
use pause_1999::main;
use PAUSE::HeavyCGI::ExePlan;
use strict;
use PAUSE ();
use HTTP::Status qw(:constants);
use vars qw( $Exeplan );
use vars qw($VERSION);
$VERSION = "949";

# Tell the system which packages want to see the headers or the
# parameters.
$Exeplan = PAUSE::HeavyCGI::ExePlan->new(
					  CLASSES => [qw(
pause_1999::authen_user
pause_1999::edit
pause_1999::usermenu
)]);

our $DEFAULT_USER_ACTIONS =
{
    # PUBLIC
    request_id => {
        verb => "Request PAUSE account",
        priv => "public",
        cat  => "00reg/01",
        desc => "Apply for a PAUSE account.",
    },

    mailpw => {
        verb => "Forgot Password?",
        priv => "public",
        cat  => "00urg/01",
        desc => <<'DESC',
A passwordmailer that sends you a password that enables you to set a new password.
DESC
    },

    pause_04about => {
        verb => "About PAUSE",
        priv => "public",
        cat  => "01self/04a",
        desc => "Same as modules/04pause.html on any CPAN server",
    },

    pause_04imprint => {
        verb => "Imprint/Impressum",
        priv => "public",
        cat  => "01self/06b",
    },

    pause_05news => {
        verb => "PAUSE News",
        priv => "public",
        cat  => "01self/05",
        desc => "What's going on on PAUSE",
    },

    pause_06history => {
        verb => "PAUSE History",
        priv => "public",
        cat  => "01self/06",
        desc => "Old News",
    },

    pause_namingmodules => {
        verb => "On The Naming of Modules",
        priv => "public",
        cat  => "01self/04b",
        desc => "A couple of suggestions that hopefully get you on track",
    },

    who_pumpkin => {
        verb => "List of pumpkins",
        priv => "public",
        cat  => "02serv/05",
        desc => "A list, also available as YAML",
    },

    who_admin => {
        verb => "List of admins",
        priv => "public",
        cat  => "02serv/06",
        desc => "A list, also available as YAML",
    },

    # USER

    # USER/FILES

    add_uri => {
        verb => "Upload a file to CPAN",
        priv => "user",
        cat  => "User/01Files/01up",
        desc => <<'DESC',
This is the heart of the <b>Upload Server</b>, the page most heavily used on
PAUSE.
DESC
    },

    show_files => {
        verb => "Show my files",
        priv => "user",
        cat  => "User/01Files/02show",
        desc => "find . -ls resemblance",
    },

    edit_uris => {
        verb => "Repair a Pending Upload",
        priv => "user",
        cat  => "User/01Files/03rep",
        desc => <<'DESC',
When an upload you requested hangs for some reason, you can go here and edit the
file to be uploaded.
DESC
    },

    delete_files => {
        verb => "Delete Files",
        priv => "user",
        cat  => "User/01Files/04del",
        desc => <<'DESC',
Schedule files for deletion. There is a delay until the deletion really happens.
Until then you can also undelete files here.
DESC
    },

    # User/Permissions

    peek_perms => {
        verb => "View Permissions",
        priv => "user",
        cat  => "User/04Permissions/01",
        desc => "Whose uploads of what are being indexed on PAUSE",
    },

    share_perms => {
        verb => "Change Permissions",
        priv => "user",
        cat  => "User/04Permissions/02",
        desc => <<'DESC',
Enable other users to upload a module for any of your namespaces, manage your
own permissions.
DESC
    },

    # User/Util

    tail_logfile => {
        verb => "Tail Daemon Logfile",
        priv => "user",
        cat  => "User/05Utils/06",
    },

    reindex => {
        verb => "Force Reindexing",
        priv => "user",
        cat  => "User/05Utils/02",
        desc => <<'DESC',
Tell the indexer to index a file again (e.g. after a change in the perms table)
DESC
    },

    reset_version => {
        verb => "Reset Version",
        priv => "user",
        cat  => "User/05Utils/02",
        desc => <<'DESC',
Overrule the record of the current version number of a module that the indexer
uses and set it to 'undef'
DESC
    },

    # User/Account

    change_passwd => {
        verb => "Change Password",
        priv => "user",
        cat  => "User/06Account/02",
        desc => "Change your password any time you want.",
    },

    edit_cred => {
        verb => "Edit Account Info",
        priv => "user",
        cat  => "User/06Account/01",
        desc => <<'DESC',
Edit your user name, your email addresses (both public and secret one),
change the URL of your homepage.",
DESC
    },

    pause_logout => {
        verb => "About Logging Out",
        priv => "user",
        cat  => "User/06Account/04",
    },

    # ADMIN+mlrep+modlistmaint

    add_user => {
        verb => "Add a User or Mailinglist",
        priv => "admin",
        cat  => "01usr/01add",
        desc => "Admins can add users or mailinglists.",

    },

    manage_id_requests => {
        verb => "Manage a registration request (alpha)",
        priv => "admin",
        cat  => "01usr/01rej",
        desc => "show/reject open registration requests",
    },

    edit_ml => {
        verb => "Edit a Mailinglist",
        priv => "admin",
        cat  => "01usr/02",
        desc => <<'DESC',
Admins and mailing list representatives can change the name, address and
description of a mailing list.
DESC
    },

    email_for_admin => {
        verb => "Look up the forward email address",
        priv => "admin",
        cat  => "01usr/01look",
        desc => "Admins can look where email should go",
    },

    select_user => {
        verb => "Select User/Action",
        priv => "admin",
        cat  => "01usr/03",
        desc => <<'DESC',
Admins can access PAUSE as-if they were somebody else. Here they select a
user/action pair.
DESC
    },

    post_message => {
        verb => "Post a message",
        priv => "admin",
        cat  => "01usr/04",
        desc => "Post a message to a specific user.",
    },

    dele_message => {
        verb => "Show/Delete Msgs",
        priv => "admin",
        cat  => "01usr/05",
        desc => "Delete your messages from the message board.",
    },

    show_ml_repr => {
        verb => "Show Mailinglist Reps",
        priv => "mlrepr",
        cat  => "09root/04",
        desc => <<'DESC',
Admins and the representatives themselves can lookup who is elected to be
representative of a mailing list.
DESC
    },

    index_users => {
        verb => "Index users with digrams (BROKEN)",
        priv => "admin",
        desc => "Batch-index all users.",
        cat  => "09root/05",
    },

    select_ml_action => {

        verb => "Select Mailinglist/Action",
        priv => "mlrepr",
        cat  => "09root/02",
        desc => <<'DESC',
Representatives of mailing lists have their special menu here.
DESC
    },

    "check_xhtml" => {
        verb => "Show bad xhtml output",
        priv => "admin",
        cat  => "09root/06",
        desc => "Monitor bad xhtml output stored from previous sessions",
    },

    "coredump" => {
        priv => "admin",
        cat  => "09root/07",
        }

};

sub handler {
  my($req) = shift;
  my $dti = PAUSE::downtimeinfo();
  my $downtime = $dti->{downtime};
  my $willlast = $dti->{willlast};
  my $user = $req->user;
  if (time >= $downtime && time < $downtime + $willlast) {
    use Time::Duration;
    my $delta = $downtime + $willlast - time;
    my $expr = Time::Duration::duration($delta);
    my $willlast_dur = Time::Duration::duration($willlast);

    my $closed_text = qq{<p class="motd">PAUSE is closed for
maintainance for about $willlast_dur. Estimated time of opening is in
$expr.</p><p class="motd">Sorry for the inconvenience and Thanks for
your patience.</p>};

    if ($user && $user eq "ANDK") { # would prefer a check of the admin role here
      $req->env->{'psgix.notes'}{CLOSED} = $closed_text;
    } else {
      my $res = $req->new_response(HTTP_OK);
      $res->content_type("text/html");

      $res->body(qq{<html> <head><title>PAUSE
CLOSED</title></head><body> <h1>Closed for Maintainance</h1>
$closed_text <p>Andreas Koenig</p></body> </html>});

      return $res;
    }
  }
  my $self = pause_1999::main->
      new(

          DownTime => $downtime,
          WillLast => $willlast,
          ActionTuning => $DEFAULT_USER_ACTIONS,
          ActiveColor        => "#bbffbb",
          AllowAdminTakeover => [qw(
 add_uri
 change_passwd
 delete_files
 edit_cred
 edit_ml
 edit_uris
 reindex
 reset_version
 share_perms
 dele_message
 )],
          AllowMlreprTakeover => [qw(
edit_ml
reset_version
share_perms
)],
	    AuthenDsn       => $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
	    AuthenDsnPasswd => $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
	    AuthenDsnUser   => $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
	    CHARSET         => $pause_1999::main::DO_UTF8 ? "utf-8" : "iso-8859-1",
	    EXECUTION_PLAN => $Exeplan,
	    MailMailerConstructorArgs => $PAUSE::Config->{MAIL_MAILER},
	    MailtoAdmins => join(",",@{$PAUSE::Config->{ADMINS}}),
	    ModDsn       => $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
	    ModDsnPasswd => $PAUSE::Config->{MOD_DATA_SOURCE_PW},
	    ModDsnUser   => $PAUSE::Config->{MOD_DATA_SOURCE_USER},
	    REQ       => $req,
	    RES       => $req->new_response(HTTP_OK),
	    RootURL => "/pause",
            SessionDataDir => "$PAUSE::Config->{RUNDATA}/session/sdata",
            SessionCounterDir => "$PAUSE::Config->{RUNDATA}/session/cnt",
	    # add more instance variables here. Make sure, they are
	    # declared in main.pm

	   );

  if ($req->user) {
    $self->{QueryURL} = "authenquery";

    ############# Main Switch for experimental CGI Patch #############
    # patched CGI stands for overloaded values in multipart/formdata

    if (0) { # I do not intend to think further about the patchedCGI
             # approach. I believe these headers are not really needed
      $self->{UseModuleSet} = $self->{QueryURL} eq "authenquery" ?
          "patchedCGI" : "ApReq";
    } else {
      $self->{UseModuleSet} = "ApReq";
    }

    # Increase the risk but improve the debugging
    $self->need_multipart(1) if $self->{UseModuleSet} eq "patchedCGI";

  } else {

    $self->{QueryURL} = "query";
    $self->{UseModuleSet} = "ApReq";

  }

  $self->{OurEmailFrom} = "\"Perl Authors Upload Server\" <$PAUSE::Config->{UPLOAD}>";
  # warn "Debug: OurEmailFrom=UPLOAD[$self->{OurEmailFrom}]";
  my(@time) = gmtime; # sec,min,hour,day,month,year
  my $quartal = int($time[4]/3) + 1; # 1..4
  $self->{SessionCounterFile} = "$self->{SessionCounterDir}/Q$quartal";

  $self->{WaitDir} = "$PAUSE::Config->{RUNDATA}/wait";
  $self->{WaitUserDb} = "users";

  $self->dispatch;
}


######## The following patch allows us to track down what the
######## multipart header said about each variable

package CGI::MultipartVariables;
use overload "\"\"", "as_string", fallback => 1;

sub new { bless {}, shift; }
sub set_value { my($self,$val) = @_; $self->{VALUE} = $val; }
sub set_header { my($self,$val) = @_; $self->{HEADER} = $val; }
sub as_string { shift->{VALUE}; }
# sub as_number { shift->{"VALUE"}+0; }
sub multipart_header { shift->{HEADER}; }


package CGI;

#####
# subroutine: read_multipart
#
# Read multipart data and store it into our parameters.
# An interesting feature is that if any of the parts is a file, we
# create a temporary file and open up a filehandle on it so that the
# caller can read from it if necessary.
#####
sub CGI::read_multipart {
    my($self,$boundary,$length,$filehandle) = @_;
    my($buffer) = $self->new_MultipartBuffer($boundary,$length,$filehandle);
    return unless $buffer;
    my $filenumber = 0;
    while (!$buffer->eof) {
        my %header = $buffer->readHeader;

	unless (%header) {
	    $self->cgi_error("400 Bad request (malformed multipart POST)");
	    return;
	}

	my($param)= $header{'Content-Disposition'}=~/ name="?([^\";]*)"?/;

	# Bug:  Netscape doesn't escape quotation marks in file names!!!
	my($filename) = $header{'Content-Disposition'}=~/ filename="?([^\";]*)"?/;

	# add this parameter to our list
	$self->add_parameter($param);

	# If no filename specified, then just read the data and assign it
	# to our parameter list.
	unless ($filename) {
	    my($value) = $buffer->readBody;
	    my $var = CGI::MultipartVariables->new;
	    $var->set_value($value);
	    $var->set_header(\%header);
	    push(@{$self->{$param}},$var);
	    next;
	}

	my ($tmpfile,$tmp,$filehandle);
      UPLOADS: {
	  # If we get here, then we are dealing with a potentially large
	  # uploaded form.  Save the data to a temporary file, then open
	  # the file for reading.

	  # skip the file if uploads disabled
	  if ($CGI::DISABLE_UPLOADS) {
	      my $data;
	      while (defined($data = $buffer->read)) { }
	      last UPLOADS;
	  }

	  # choose a relatively unpredictable tmpfile sequence number
          my $seqno = unpack("%16C*",join('',localtime,values %ENV));
          for (my $cnt=10;$cnt>0;$cnt--) {
	    next unless $tmpfile = new TempFile($seqno);
	    $tmp = $tmpfile->as_string;
	    last if $filehandle = Fh->new($filename,$tmp,$CGI::PRIVATE_TEMPFILES);
            $seqno += int rand(100);
          }
          die "CGI open of tmpfile: $!\n" unless $filehandle;
	  $CGI::DefaultClass->binmode($filehandle) if $CGI::needs_binmode;

	  my ($data);
	  local($\) = '';
	  while (defined($data = $buffer->read)) {
	      print $filehandle $data;
	  }

	  # back up to beginning of file
	  seek($filehandle,0,0);
	  $CGI::DefaultClass->binmode($filehandle) if $CGI::needs_binmode;

	  # Save some information about the uploaded file where we can get
	  # at it later.
	  $self->{'.tmpfiles'}->{$filename}= {
	      name => $tmpfile,
	      info => {%header},
	  };
	  push(@{$self->{$param}},$filehandle);
      }
    }
    warn "leaving CGI::read_multipart";
}

1;

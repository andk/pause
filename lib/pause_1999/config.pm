#!/usr/bin/perl -- -*- Mode: cperl;  -*-
package pause_1999::config;
use pause_1999::main;
use Apache::HeavyCGI::ExePlan;
use Apache::Request;
use strict;
use PAUSE ();
use vars qw( $Exeplan );
use vars qw($VERSION);
$VERSION = sprintf "%d", q$Rev$ =~ /(\d+)/;

# Tell the system which packages want to see the headers or the
# parameters.
$Exeplan = Apache::HeavyCGI::ExePlan->new(
					  CLASSES => [qw(
pause_1999::authen_user
pause_1999::edit
pause_1999::usermenu
)]);

# edit must be before usermenu because it determines the AllowAction attribute

# http://hohenstaufen.in-berlin.de:81/pause/mimequery
# König

sub handler {
  my($r) = shift;
  my pause_1999::main $self = pause_1999::main->
      new(

          ActionTuning =>
          {

           # PUBLIC

           request_id => {
                      verb => "Request PAUSE account",
                      priv => "public",
                      cat => "00reg/01",

                      desc => "Apply for a PAUSE account.",

                     },

           mailpw => {
                      verb => "Forgot Password?",
                      priv => "public",
                      cat => "00urg/01",

                      desc => "A passwordmailer that sends you a
			password that enables you to set a new
			password.",

                     },
           pause_04about => {
                             verb => "About PAUSE",
                             priv => "public",
                             desc => "Same as modules/04pause.html on any CPAN server",
                             cat => "01self/04a",
                            },
           pause_04imprint => {
                               verb => "Imprint/Impressum",
                               priv => "public",
                               cat => "01self/04b",
                            },

           pause_05news => {
                            verb => "PAUSE News",
                            priv => "public",
                            desc => "What's going on on PAUSE",
                            cat => "01self/05",
                           },
           pause_06history => {
                               verb => "PAUSE History",
                               priv => "public",
                               desc => "Old News",
                               cat => "01self/06",
                              },
           who_is => {
                      verb => "Who is Who (long)",
                      priv => "public",
                      cat => "02serv/02",

                      desc => "A database query. Output is very
			similar to CPAN/authors/00whois.html",

                     },

           # USER

           add_uri => {
                       verb => "Upload a file to CPAN",
                       priv => "user",
                       cat => "01fil/01up",

                       desc => "This is the heart of the <b>Upload
			 Server</b>, the page most heavily used on
			 PAUSE.",

                      },
           apply_mod => {
                         verb => "Register Namespace",
                         priv => "user",
                         cat => "02mod/01reg",

                         desc => "Submit a namespace proposal for a
                            module to the modules\@perl.org people.",

                        },
           change_passwd => {
                             verb => "Change Password",
                             priv => "user",
                             cat => "06usr/02",

                             desc => "Change your password any time
				you want.",

                            },
           delete_files => {
                            verb => "Delete Files",
                            priv => "user",
                            cat => "01fil/03del",

                            desc => "Schedule files for deletion.
				There is a delay until the deletion
				really happens. Until then you can
				also undelete files here.",

                           },
	     edit_cred => {
			   verb => "Edit Account Info",
			   priv => "user",
                              cat => "06usr/01",

			   desc => "Edit your user name, your email
				   addresses (both public and secret
				   one), change the URL of your
				   homepage.",

			  },
	     edit_mod => {
			  verb => "Edit Module Metadata",
			  priv => "user",
                              cat => "02mod/02",

			  desc => "When your module is in the module
				  list, you can edit the description
				  and the DSLI status that are stored
				  about it in the database.",

			 },
	     edit_uris => {
			   verb => "Repair a Pending Upload",
			   priv => "user",
                              cat => "01fil/02rep",

			   desc => "When an upload you requested hangs
				   for some reason, you can go here
				   and edit the file to be uploaded.",

			  },
	     peek_perms => {
                            verb => "View Permissions",
                            priv => "user",
                            desc => "Whose uploads of what are being indexed on PAUSE",
                            cat => "04perm/01",
		       },
             reindex => {
                         verb => "Force Reindexing",
                         priv => "user",
                         cat => "05inx/02",

                         desc => "Tell the indexer to index a file
                                  again (e.g. after a change in the
                                  perms table)",

                        },
           share_perms => {
                           verb => "Change Permissions",
                           priv => "user",
                           cat => "04perm/02",

                           desc => "Enable other users to upload a
                                    module for any of your namespaces,
                                    manage your own permissions.",

                          },

           # ADMIN+mlrep+modlistmaint


           add_user => {
			  verb => "Add a User or Mailinglist",
			  priv => "admin",
                          cat => "01usr/01add",

			  desc => "Admins can add users or
				  mailinglists.",

			 },
	     edit_ml => {
			 verb => "Edit a Mailinglist",
			 priv => "admin",
                              cat => "01usr/02",

			 desc => "Admins and mailing list
				 representatives can change the name,
				 address and description of a mailing
				 list.",

			},
	     show_ml_repr => {
			      verb => "Show Mailinglist Reps",
			      priv => "admin",
                              cat => "09root/04",

			      desc => "Admins can lookup who is
				      elected to be representative of
				      a mailing list.",

			     },
             index_users => {
                             verb => "Index users with digrams (BROKEN)",
                             priv => "admin",
                             desc => "Batch-index all users.",
                              cat => "09root/05",
                            },
	     select_user => {
			     verb => "Select User/Action",
			     priv => "admin",
                              cat => "01usr/03",

			     desc => "Admins can access PAUSE as-if
				     they were somebody else. Here
				     they select a user/action pair.",

			    },
	     select_ml_action => {

				  verb => "Select Mailinglist/Action",
				  priv => "mlrepr",
                              cat => "09root/02",

				  desc => "Representatives of mailing
					  lists have their special
					  menu here.",

				 },

           add_mod =>          {

                                verb => "Register a Module",
                                priv => "modmaint",
                                cat => "02mods/02",

                                desc => "Register a new module in the
                                 database to be added to the module
                                 list. In development.",

                               },

           "check_xhtml" =>    {
                                verb => "Show bad xhtml output",
                                priv => "admin",
                                cat => "09root/06",
                                desc => "Monitor bad xhtml output stored from previous sessions",
                               },
           "coredump" => {
                          priv => "admin",
                          cat => "09root/07",
                         }
          },
          ActiveColor        => "#bbffbb",
          AllowAdminTakeover => [qw(
 add_uri
 apply_mod
 change_passwd
 delete_files
 edit_cred
 edit_ml
 edit_mod
 edit_uris
 reindex
 share_perms
 )],

	    AuthenDsn       => $PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME},
	    AuthenDsnPasswd => $PAUSE::Config->{AUTHEN_DATA_SOURCE_PW},
	    AuthenDsnUser   => $PAUSE::Config->{AUTHEN_DATA_SOURCE_USER},
	    CHARSET         => $pause_1999::main::DO_UTF8 ? "utf-8" : "iso-8859-1",
	    EXECUTION_PLAN => $Exeplan,
	    MailMailerConstructorArgs => ["sendmail"],
	    MailtoAdmins => join(",",@{$PAUSE::Config->{ADMINS}}),
	    ModDsn       => $PAUSE::Config->{MOD_DATA_SOURCE_NAME},
	    ModDsnPasswd => $PAUSE::Config->{MOD_DATA_SOURCE_PW},
	    ModDsnUser   => $PAUSE::Config->{MOD_DATA_SOURCE_USER},
	    R       => $r,
	    RootURL => "/pause",
            SessionDataDir => "/usr/local/apache/rundata/pause_1999/session/sdata",
            SessionCounterDir => "/usr/local/apache/rundata/pause_1999/session/cnt",
	    # add more instance variables here. Make sure, they are
	    # declared in main.pm

	   );

  if ($r->connection->user) {
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

  if ($self->{UseModuleSet} eq "patchedCGI") {
    warn "patchedCGI not supported anymore";
    require CGI;
    $self->{CGI} = CGI->new;
  } elsif ($self->{UseModuleSet} eq "ApReq") {
    my $req = Apache::Request->new($r);
    my $rc = $req->parse;
    # warn "rc[$rc]";
    $self->{CGI} = $req;
  } else {
    die "Illegal value for UseModuleSet: $self->{UseModuleSet}";
  }
  $self->{OurEmailFrom} = "\"Perl Authors Upload Server\" <$PAUSE::Config->{UPLOAD}>";
  # warn "Debug: OurEmailFrom=UPLOAD[$self->{OurEmailFrom}]";
  my(@time) = gmtime; # sec,min,hour,day,month,year
  my $quartal = int($time[4]/3) + 1; # 1..4
  $self->{SessionCounterFile} = "$self->{SessionCounterDir}/Q$quartal";

  $self->{WaitDir} = "/usr/local/apache/rundata/pause_1999/wait";
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

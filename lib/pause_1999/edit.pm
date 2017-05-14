#!/usr/bin/perl -- -*- Mode: cperl; -*-

package pause_1999::edit;
use base 'Class::Singleton';
use pause_1999::main;
use strict;
use Encode ();
use Fcntl qw(O_RDWR O_RDONLY);
use File::Find qw(find);
use PAUSE::Crypt;
use POSIX ();
use URI::Escape;
use Text::Format;
use HTTP::Status qw(:constants);
eval {require Time::Duration};
our $HAVE_TIME_DURATION = !$@;

our $Valid_Userid = qr/^[A-Z]{3,9}$/;
our $Yours = "Thanks,\n-- \nThe PAUSE\n";

use utf8; # must be after the qr// for perl-5.6.1

our $VERSION = "1071.02";

our $strict_chapterid = 1;

sub parameter {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my($param,@allow_submit,%allow_action);

  # What is allowed here is allowed to anybody
  @allow_action{
    (
     "pause_04about",
     "pause_04imprint",
     "pause_05news",
     "pause_06history",
     "pause_namingmodules",
     "request_id",
     "who_pumpkin",
     "who_admin",
    )} = ();

  @allow_submit = (
                   "request_id",
                  );

  if ($mgr->{User} && $mgr->{User}{userid} && $mgr->{User}{userid} ne "-") {

    # warn "userid[$mgr->{User}{userid}]";

    # All authenticated Users
    for my $command (
		     "add_uri",
		     "change_passwd",
		     "delete_files",
		     "edit_cred",
		     # "edit_mod",
		     "edit_uris",
		     # "apply_mod",
                     "pause_logout",
                     "peek_perms",
                     "reindex",
                     "reset_version",
                     "share_perms",
                     "show_files",
                     "tail_logfile",
		    ) {
      $allow_action{$command} = undef;
      push @allow_submit, $command;
    }

    # Only Mailinglist Representatives
    if (exists $mgr->{UserGroups}{mlrepr}) {
      for my $command (
		       "select_ml_action",
		       "edit_ml",
		       # "edit_mod",
                       "reset_version",
                       "show_ml_repr",
		      ) {
	$allow_action{$command} = undef;
	push @allow_submit, $command;
      }
    }

    # Only Modulelist Maintainers
    if (0 && exists $mgr->{UserGroups}{modmaint}) {
      for my $command (
		       "add_mod",
                       "apply_mod",
		      ) {
	$allow_action{$command} = undef;
	push @allow_submit, $command;
      }
    }

    # Postmaster or admin
    if (
        exists $mgr->{UserGroups}{admin}
        or
        exists $mgr->{UserGroups}{postmaster}
       ) {
      for my $command (
                       "email_for_admin",
		      ) {
	$allow_action{$command} = undef;
	push @allow_submit, $command;
      }
    }

    # Only Admins
    if (exists $mgr->{UserGroups}{admin}) {
      # warn "We have an admin here";
      for my $command (
		       "add_user",
		       "edit_ml",
		       "select_user",
		       "show_ml_repr",
                       # "add_mod", # all admins may maintain the module list for now
                       # "apply_mod",
                       "check_xhtml",
                       "coredump",
                       "dele_message",
                       "index_users",
                       "post_message",
                       "manage_id_requests",
                       # "test_session",
		      ) {
	$allow_action{$command} = undef;
	push @allow_submit, $command;
      }
    }

  } elsif ($param = $req->param("ABRA")) {

    # TUT: if they sent ABRA, the only thing we let them do is change
    # their password. The parameter consists of username-dot-token.
    my($user, $passwd) = $param =~ m|(.*?)\.(.*)|; #

    # We allow changing of the password with this password. We leave
    # everything else untouched

    my $dbh;
    $dbh = $mgr->authen_connect;
    my $sql = sprintf qq{DELETE FROM abrakadabra
                         WHERE NOW() > expires };
    $dbh->do($sql);
    $sql = qq{SELECT *
              FROM abrakadabra
              WHERE user=? AND chpasswd=?};
    my $sth = $dbh->prepare($sql);
    if ( $sth->execute($user,$passwd) and $sth->rows ) {
      # TUT: in the keys of %allow_action we store the methods that are
      # allowed in this request. @allow_submit does something similar.
      $allow_action{"change_passwd"} = undef;
      push @allow_submit, "change_passwd";

      # TUT: by setting $mgr->{User}{userid}, we can let change_passwd
      # know who we are dealing with
      $mgr->{User}{userid} = $user;

      # TUT: Let's pretend they requested change_passwd. I guess, if we
      # would drop that line, it would still work, but I like redundant
      # coding in such cases
      $param = $req->parameters->set("ACTION","change_passwd"); # override

    } else {
      die  PAUSE::HeavyCGI::Exception->new(ERROR => "You tried to authenticate the
parameter ABRA=$param, but the database doesn't know about this token.");
    }
    $allow_action{"mailpw"} = undef;
    push @allow_submit, "mailpw";

  } else {

    # warn "unauthorized access (but OK)";
    $allow_action{"mailpw"} = undef;
    push @allow_submit, "mailpw";

  }
  $mgr->{AllowAction} = [ sort { $a cmp $b } keys %allow_action ];
  # warn "allowaction[@{$mgr->{AllowAction}}]";
  # warn "allowsubmit[@allow_submit]";

  $param = $req->param("ACTION");
  # warn "ACTION-param[$param]req[$req]";
  if ($param && exists $allow_action{$param}) {
    $mgr->{Action} = $param;
  } else {
    # ...they might ask for it in a submit button
  ACTION: for my $action (@allow_submit) {

      # warn "DEBUG: action[$action]";

      # we inherited from a different project: One submitbutton on a page
      if (
	  $param = $req->param("pause99_$action\_sub")
	 ) {
	# warn "action[$action]";
	$mgr->{Action} = $action;
	last ACTION;
      }

      # Also inherited: One submitbutton but also only one textfield,
      # so that RETURN on the textfield submits the form
      if (
	  $param = $req->param("pause99_$action\_1")
	 ) {
	$req->parameters->set("pause99_$action\_sub", $param); # why?
	$mgr->{Action} = $action;
	last ACTION;
      }

      # I had intended that parameters matching /_sub.*/ are only used
      # in cases where RETURN might be used instead of SUBMIT. Then I
      # erroneously used "pause99_add_uri_subdirtext"

      my(@partial) = grep /^pause99_\Q$action\E_/, $req->param;
    PART: for my $partial (@partial) {
	$req->parameters->set("pause99_$action\_sub", $partial); # why not $mgr->{ActionComment}?
	$mgr->{Action} = $action;
	last PART;
      }
    }
  }
  my $action = $mgr->{Action};
  if (!$action || $req->param('lsw')) { # let submit win

    # the let submit win parameter was introduced when I realized that
    # submit should always win but was afraid that it might break
    # something when we suddenly let submit win in all cases. So new
    # forms should always specify lsw=1 so we can migrate to making it
    # the default some day.

    # New and more generic than the inherited ones above: several submit buttons
    my @params = grep s/^(weak)?SUBMIT_pause99_//i, $req->param;
    for my $p (@params) {
      # warn "p[$p]";
      for my $a (@allow_submit) {
	if ( substr($p,0,length($a)) eq $a ) {
	  $mgr->{Action} = $a;
	  last;
	}
      }
      last if $mgr->{Action};
    }
  }
  $action = $mgr->{Action};
  # warn "action[$action]";
  # warn sprintf "param[%s]", join ":", $mgr->{REQ}->param;
  if ($action) { # delegate to a subroutine
    die PAUSE::HeavyCGI::Exception->new(ERROR => "Unanticipated Error on Server.
Please report to the administrator what you were trying to do")
	unless $self->can($action);
    my @action_result = $self->$action($mgr);
    # sanity check:
    for (0..$#action_result) {
      next if defined $action_result[$_];
      warn "undefined element in \@action_result: _[$_]#[$#action_result]action[$action]";
    }
    $mgr->{EditOutput} = join "", @action_result;
  } else {
    $mgr->{Action} = "menu"; # no undefined warnings please
  }
}

sub menu {
  return;
}

sub manage_id_requests { # was reject_id_request
  # intimate knowledge of session handling required
  my $self = shift;
  my $mgr = shift;
  return unless exists $mgr->{UserGroups}{admin};
  my $req = $mgr->{REQ};
  my @m;
  my %ALL;
  my $delete;
  if ($req->param("subaction") && $req->param("subaction") eq "delete") {
    $delete = $req->param("USERID");
  }
  my $dbh = $mgr->connect;
  my $sthu = $dbh->prepare("SELECT userid from users where userid=?");
  my $sthm = $dbh->prepare("SELECT modid from mods where modid=?");
  find
      (
       {wanted => sub {
          my $path = $_;
          my @stat = stat $path or die "Could not stat '$path': $!";
          return unless -f _;
          my $mtime = $stat[9];
          open my $fh, $path or die "Couldn't open '$path': $!";
          local $/;
          my $content = <$fh>;
          my $session = Storable::thaw $content;
          # warn "DEBUG: mtime[$mtime]stat[@stat]session[$session]";
          my $userid = $session->{APPLY}{userid} or return;
          if ($delete && $session->{_session_id} eq $delete) {
            unlink $path or die "Could not unlink '$path': $!";
            return;
          }
          my $type;
          if (exists $session->{APPLY}{fullname}) {
            $sthu->execute($userid);
            return if $sthu->rows > 0;
            $type = "user";
          } elsif (exists $session->{APPLY}{modid}) {
            $sthm->execute($session->{APPLY}{modid});
            return if $sthm->rows > 0;
            $type = "mod";
          }
          if ($session->{APPLY}{rationale} =~ /\b(?:BLONDE\s+NAKED|NAKED\s+SEXY|FREE\s+CUMSHOT|CUMSHOT\s+VIDEOS|FREE\s+SEX|FREE\s+TUBE|GROUP\s+SEX|FREE\s+PORN|SEX\s+VIDEO|SEX\s+MOVIES?|SEX\s+TUBE|SEX\s+MATURE|STREET\s+BLOWJOBS|SEX\s+PUBLIC|TUBE\s+PORN|PORN\s+TUBE|TUBE\s+VIDEOS|VIDEO\s+TUBE|XNXX\s+VIDEOS|XXX\s+FREE|ANIMAL\s+SEX|GIRLS\s+SEX|PORN\s+VIDEOS?|PORN\s+MOVIES|TITS\s+PORN|RAW\s+SEX|DEEPTHROAT\s+TUBE|celeb\s+porn|PREGNANT\s+TUBE|picture\s+sex|NAKED\s+WOMEN|WOMEN\s+MOVIES|MATURE\s+NAKED|SEX\s+ANIME|hot\s+nude|nude\s+celebs|ANIME\s+TUBES|SEX\s+DOG|MATURE\s+SEX|MATURE\s+PUSSY|Rape\s+Porn|brutal\s+fuck|rape\s+video|ANIMAL\s+TUBE|SHEMALE\s+CUMSHOT|ANIMAL\s+PORN|ANIMAP\s+CLIP|CLIP\s+SEX|PUBLIC\s+BLOWJOB|free\s+lesbian|lesbian\s+sex|SEX\s+ZOO|tv-adult|numismata.org|www.soulcommune.com|www.petsusa.org|www.csucssa.org|www.thisis50.com|www.comunidad-latina.net|www.singlefathernetwork.com|www.freetoadvertise.biz|gayforum.dk|www.purevolume.com|playgroup.themouthpiece.com|www.bananacorp.cl|party.thebamboozle.com|blog.tellurideskiresort.com|www.pethealthforums.com|www.burropride.com|lpokemon.19.forumer.com|Zootube365|Eskimotube|xtube-1|phentermine without a prescription)\b/i) {
            unlink $path or die "Could not unlink '$path': $!";
            return;
          }
          $ALL{$path} = {
                         session => $session,
                         mtime   => $mtime,
                         type    => $type,
                        };
        },
        no_chdir => 1,
       },
       $mgr->{SessionDataDir}, # a bit under $PAUSE::Config->{RUNDATA}
      );
push @m, qq{<p>View all pending applications for new user IDs and for modules registrations</p>
<p><table class="administration">
<tr><th>Type</th><th>Userid/Time</th><th>Raw Session</th></tr>
};
  require YAML::Syck;
  require JSON::XS;
  my $jx = JSON::XS->new->indent->canonical;
  for my $k (sort { $ALL{$b}{type} cmp $ALL{$a}{type} || $ALL{$b}{mtime} <=> $ALL{$a}{mtime} } keys %ALL) {
    my $esc = $mgr->escapeHTML($jx->encode($ALL{$k}{session}));
    $esc =~ s/ /&#160;/g;
    $esc =~ s/\n/<br\/>/g;
    $esc =~ s/\\n/<br\/>/g;
    push @m, sprintf
        (
         '<tr><td class="administration" valign="top">
%s
</td>
<td valign="top">
%s
<br/>
%s
<br/>
<br/>
<a href="authenquery?ACTION=%s;USERID=%s;SUBMIT_pause99_%s=1">Go To Registration</a>
<br/>
<a href="authenquery?ACTION=manage_id_requests;subaction=delete;USERID=%s">Delete Registration</a>
</td><td valign="top">%s</td>
<td valign="top"><div id="contentBox"><pre style="overflow: auto; position: relative; height: auto; vertical-align: top">%s</pre></div></td></tr>
',
         $ALL{$k}{type},
         $ALL{$k}{session}{APPLY}{userid},
         POSIX::strftime("%FT%TZ", gmtime $ALL{$k}{mtime}),
         exists $ALL{$k}{session}{APPLY}{fullname} ? "add_user" : "add_mod",
         $ALL{$k}{session}{_session_id},
         exists $ALL{$k}{session}{APPLY}{fullname} ? "add_user_sub" : "add_mod_preview",
         $ALL{$k}{session}{_session_id},
         $esc,
        );
  }
  push @m, "</table></p>";
  join "", @m;
}

sub as_string {
  my $self = shift;
  my $mgr = shift;
  my @m;
  warn "mgr->Action undef" unless defined $mgr->{Action};
  my $action;
  $action = $mgr->{ActionTuning}{$mgr->{Action}}{verb}
      if exists $mgr->{ActionTuning}{$mgr->{Action}};
  # $action ||= $mgr->{Action};
  push @m, sprintf qq{\n<h2 class="firstheader">%s</h2>\n}, $action if $action;
  my $sentit;
  my @err = @{$mgr->{ERROR}||[]};
  push @m, @err and $sentit++ if @err;
  # warn "sentit[$sentit]";
  push @m, $mgr->{EditOutput} and $sentit++ if !$sentit && $mgr->{EditOutput};
  # warn "sentit[$sentit]";
  unless ($sentit) {
    push @m, sprintf(
                     qq{\n<h2 class="firstheader">%slease choose an action from the menu.</h2>\n},
                     $mgr->{User}{fullname} ?
                     sprintf("Hi %s,<br />p",$mgr->escapeHTML($mgr->{User}{fullname})) :
                     "P"
                    );

    # warn sprintf "DEBUG: host believes he is[%s]", $mgr->myurl->host;

    push @m, qq{<p>The usermenu to the left shows all menus available to
    you, the table below shows descriptions for all menues available
    to anybody on PAUSE.</p>\n};

    my $alter = 0;
    my $bgcolor = $alter ? "alternate1" : "alternate2";
    push @m, qq{<table
 border="0"
 bgcolor="black"
 cellspacing="0" cellpadding="0"><tr><td><table
 bgcolor="white"
 border="0" cellspacing="1" cellpadding="2"><tr
 class="$bgcolor"><th>Action</th><th>Group</th><th>Description</th></tr>\n}; #};
    for my $p (qw(public user mlrepr modmaint admin)) {
      for my $act (sort {
        $mgr->{ActionTuning}{$a}{cat} cmp $mgr->{ActionTuning}{$b}{cat}
      }
		 grep { $mgr->{ActionTuning}{$_}{priv} eq $p }
		 keys %{$mgr->{ActionTuning}}) {
        $alter ^= 1;
        $bgcolor = $alter ? "alternate1" : "alternate2";
        $mgr->{ActionTuning}{$act}{verb} ||= $act;
	push @m, qq{<tr class="$bgcolor">
<td><b>$mgr->{ActionTuning}{$act}{verb}</b><!-- ($act) --></td>};
	for my $k (qw(priv desc)) {
	  my $v = $mgr->{ActionTuning}{$act}{$k} || "N/A";
	  push @m, qq{<td>$v</td>}
	}
	push @m, qq{</tr>\n};
      }
    }
    push @m, qq{</table>\n</td></tr></table>\n};
  }
  @m;
}

=head2 active_user_record

Admin users can act on behalf of users. They do this by supplying
HIDDENNAME parameter which is checked here. Representatives of
mailinglists also have the ability to use HIDDENNAME to act on behalf
of a mailing list.

=cut

sub active_user_record {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $hidden_user = shift;
  my $opt = shift || {}; # hashref, e.g. checkonly => 1

  my $hidden_user_ok = $opt->{hidden_user_ok}; # caller is absolutely
                                               # sure that hidden_user
                                               # is authenticated or
                                               # harmless (mailpw)

  my $req = $mgr->{REQ};
  if ($hidden_user) {
    require Carp;
    Carp::cluck("hidden_user[$hidden_user] passed in as argument with hidden_user_ok[$hidden_user_ok]");
  } else {
    my $hiddenname_para = $req->param('HIDDENNAME') || "";
    $hidden_user ||= $hiddenname_para;
    warn "DEBUG: hidden_user[$hidden_user] after hiddenname parameter[$hiddenname_para]";
  }
  {
    my $uc_hidden_user = uc $hidden_user;
    unless ($uc_hidden_user eq $hidden_user) {
      $req->logger->({level => 'error', message => "Warning: Had to uc the hidden_user $hidden_user" });
      $hidden_user = $uc_hidden_user;
    }
  }
  my $u = {};
  $req->logger->({level => 'error', message => sprintf("Watch: mgr/User/userid[%s]hidden_user[%s]mgr/UserGroups[%s]caller[%s]where[%s]",
                        $mgr->{User}{userid},
                        $hidden_user,
                        join(":", keys %{$mgr->{UserGroups}}),
                        join(":", caller),
                        __FILE__.":".__LINE__,
                       )
               });
  if (
      $hidden_user
      &&
      $hidden_user ne $mgr->{User}{userid}
     ){

    # Imagine, MSERGEANT wants to pass Win32::ASP to WNODOM

    my $dbh1 = $mgr->connect;
    my $sth1 = $dbh1->prepare("SELECT * FROM users WHERE userid=?");
    $sth1->execute($hidden_user);
    unless ($sth1->rows){
      require Carp;
      Carp::cluck(
                  sprintf(
                          "ALERT: hidden_user[%s] rows_as_s[%s] rows_as_d[%d]",
                          $hidden_user,
                          $sth1->rows,
                          $sth1->rows,
                         ));
      die PAUSE::HeavyCGI::Exception
          ->new(ERROR =>
                "Unidentified error happened, please write to the PAUSE admin
 at $PAUSE::Config->{ADMIN} and help him identifying what's going on. Thanks!");
    }
    my $hiddenuser_h1 = $mgr->fetchrow($sth1, "fetchrow_hashref");
    require YAML::Syck; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . YAML::Syck::Dump({hiddenuser_h1 => $hiddenuser_h1}); # XXX

    $sth1->finish;

    # $hiddenuser_h1 should now be WNODOM's record

    if ($opt->{checkonly}) {
      # since we have checkonly this is the MSERGEANT case
      return $hiddenuser_h1;
    } elsif (
	$hiddenuser_h1->{isa_list}
       ) {

      # This is NOT the MSERGEANT case

      if (
	  exists $mgr->{IsMailinglistRepresentative}{$hiddenuser_h1->{userid}}
	  ||
	  (
	   $mgr->{UserGroups}
	   &&
	   exists $mgr->{UserGroups}{admin}
	  )
	 ){
	# OK, we believe you come with good intentions, but we check
	# if this action makes sense because we fear for the integrity
	# of the database, no matter if you are user or admin.
	if (
	    grep { $_ eq $mgr->{Action} } @{$mgr->{AllowMlreprTakeover}}
	   ) {
          warn "Watch: privilege escalation";
	  $u = $hiddenuser_h1; # no secrets for a mailinglist
	} else {
	  die PAUSE::HeavyCGI::Exception
	      ->new(ERROR =>
		    sprintf(
			    qq[Action '%s' seems not to be supported
			    for a mailing list],
			    $mgr->{Action},
			   )
		   );
	}
      }
    } elsif (
             $hidden_user_ok
             ||
	$mgr->{UserGroups}
	&&
	exists $mgr->{UserGroups}{admin}
       ) {

      # This isn't the MSERGEANT case either, must be admin
      # The case of hidden_user_ok is when they forgot password

      my $dbh2 = $mgr->authen_connect;
      my $sth2 = $dbh2->prepare("SELECT secretemail, lastvisit
                                 FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                                 WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
      $sth2->execute($hidden_user);
      my $hiddenuser_h2 = $mgr->fetchrow($sth2, "fetchrow_hashref");
      $sth2->finish;
      for my $h ($hiddenuser_h1, $hiddenuser_h2) {
	for my $k (keys %$h) {
	  $u->{$k} = $h->{$k};
	}
      }
    } elsif (0) {
      return $u;
    } else {
      # So here is the MSERGEANT case, most probably
      # But the ordinary record must do. No secret email stuff here, no passwords
      # 2009-06-15 akoenig : adamk reports a massive security hole
      require YAML::Syck;
      require Carp;
      Carp::confess
              (
               YAML::Syck::Dump({ hiddenuser => $hiddenuser_h1,
                                  error => "looks like unwanted privilege escalation",
                                  u => $u,
                                }));
      # maybe we should just return the current user here? or we
      # should check the action? Don't think so, filling HiddenUser
      # member might be OK but returning the other user? Unlikely.
    }
  } else {
    unless ($mgr->{User}{fullname}) {
      # this guy most probably came via ABRA and we should fill some slots


      my $dbh1 = $mgr->connect;
      my $sth1 = $dbh1->prepare("SELECT * FROM users WHERE userid=?");
      $sth1->execute($mgr->{User}{userid});
      die PAUSE::HeavyCGI::Exception
          ->new(ERROR =>
                "Unidentified error happened, please write to the PAUSE admin
 at $PAUSE::Config->{ADMIN} and help them identify what's going on. Thanks!")
              unless $sth1->rows;

      $mgr->{User} = $mgr->fetchrow($sth1, "fetchrow_hashref");
      $sth1->finish;

    }
    %$u = (%{$mgr->{User}||{}}, %{$mgr->{UserSecrets}||{}});
  }
  $mgr->{HiddenUser} = $u;
  $u;
}

sub edit_cred {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my($u,$nu); # user, newuser
  my @m = "\n";
  $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  push @m, qq{<h3>Editing $u->{userid}};
  if (exists $mgr->{UserGroups}{admin}) {
    push @m, sprintf " (lastvisit %s)", $u->{lastvisit}||"before 2005-12-02";
  }
  push @m, qq{</h3>};

  # @allmeta *must* be the union of meta and secmeta
  my @meta = qw( fullname asciiname email homepage cpan_mail_alias ustatus);
  my @secmeta = qw(secretemail);
  my @allmeta = qw( fullname asciiname email secretemail homepage cpan_mail_alias ustatus);

  my $cpan_alias = lc($u->{userid}) . '@cpan.org';
  my $fullnamecomment = "PAUSE supports names containing UTF-8 characters. ";
  if ($mgr->can_utf8) {

    $fullnamecomment .= "As your browser seems to support UTF-8 too,
    feel free to enter your name as it is written natively. ";

  } else {

    $fullnamecomment .= "As your browser <b>does not seem to support
    UTF-8</b>, you can only use characters encoded in ISO-8859-1. ";

  }

  $fullnamecomment .= "See also the field <i>ASCII transliteration</i>
  below.";

  my %meta = (
              ustatus => {
                          type => "checkbox",
                          args => {
                                   name => "pause99_edit_cred_ustatus",
                                   value => "delete",
                                   label => "Account can be removed",
                                  },
                          short => "Remove account?",

                          long => "You have not yet uploaded any files
                            to the CPAN, so your account can still be
                            cancelled. If you want to retire your
                            account, please click here. If you do
                            this, your account will not be removed
                            immediately but instead be removed
                            manually by the database maintainer at a
                            later date.",

                         },
	      email => {
			type => "textfield",
			args => {
				 name => "pause99_edit_cred_email",
				 size => 50,
				 maxlength => 255,
				},
			short => "Publicly visible email address
			(published in many listings)",
		       },
	      secretemail => {
			      type => "textfield",
			      args => {
				       name => "pause99_edit_cred_secretemail",
				       size => 50,
				       maxlength => 255,
				      },

			      short => "Secret email address only used
                              by the PAUSE, never published.",

                              long => "If you leave this field empty,
                              PAUSE will use the public email address
                              for communicating with you.",

		       },
	      homepage => {
			   type => "textfield",
			   args => {
				    name => "pause99_edit_cred_homepage",
				    size => 50,
				    maxlength => 255,
				   },
			   short => "Homepage or any contact URL except mailto:",
			  },
	      fullname => {
			   type => "textfield",
			   args => {
				    name => "pause99_edit_cred_fullname",
				    size => 50,
				    maxlength => 127, # caution!
				   },
			   short => "Full Name",
                           long => $fullnamecomment,
			  },
	      asciiname => {
			   type => "textfield",
			   args => {
				    name => "pause99_edit_cred_asciiname",
				    size => 50,
				    maxlength => 255,
				   },
			   short => "ASCII transliteration of Full Name",

                           long => "If your Full Name contains
                           characters above 0x7f, please supply an
                           ASCII transliteration that can be used in
                           mail written in ASCII. Leave empty if you
                           trust the Text::Unidecode module.",

			  },
	      cpan_mail_alias=>{
                                type=>"radio_group",
                                args=>{
                                       name=> "pause99_edit_cred_cpan_mail_alias",
                                       values=> [qw(publ secr none)],
                                       labels=>{
                                                none => "neither nor",
                                                publ => "my public email address",
                                                secr => "my secret email address",
                                               },
                                       default => "none",
                                      },
                                short=>"The email address
 <i>$cpan_alias</i> should be configured to forward mail to ...",

                                long=>"<b>cpan.org</b> has a mail
 address for you and it's your choice if you want it to point to your
 public email address or to your secret one. Please allow a few hours
 for any change you make to this setting for propagation. BTW, let us
 reassure you that cpan.org gets the data through a secure
 channel.<br/><br/><b>Note:</b> you can disable redirect by clicking
 <i>neither nor</i> or by using an invalid email address in the
 according field above, but this will prevent you from recieving
 emails from services like rt.cpan.org."

				 },
	     );
  my $consistentsubmit = 0;
  if ($req->param("pause99_edit_cred_sub")) {
    my $wantemail = $req->param("pause99_edit_cred_email");
    my $wantsecretemail = $req->param("pause99_edit_cred_secretemail");
    my $wantalias = $req->param("pause99_edit_cred_cpan_mail_alias");
    use Email::Address;
    my $addr_spec = $Email::Address::addr_spec;
    if ($wantemail=~/^\s*$/ && $wantsecretemail=~/^\s*$/) {
      push @m, qq{<b>ERROR</b>: Both of your email fields are left blank, this is not the way it is intended on PAUSE, PAUSE must be able to contact you. Please fill out at least one of the two email fields.<hr />};
    } elsif ($wantalias eq "publ" && $wantemail=~/^\s*$/) {
      push @m, qq{<b>ERROR</b>: You chose your email alias on CPAN to point to your public email address but your public email address is left blank. Please either pick a different choice for the alias or fill in a public email address.<hr />};
    } elsif ($wantalias eq "publ" && $wantemail=~/\Q$cpan_alias\E/i) {
      push @m, qq{<b>ERROR</b>: You chose your email alias on CPAN to point to your public email address but your public email address field contains $cpan_alias. This looks like a circular reference. Please either pick a different choice for the alias or fill in a more reasonable public email address.<hr />};
    } elsif ($wantalias eq "secr" && $wantsecretemail=~/^\s*$/) {
      push @m, qq{<b>ERROR</b>: You chose your email alias on CPAN to point to your secret email address but your secret email address is left blank. Please either pick a different choice for the alias or fill in a secret email address.<hr />};
    } elsif ($wantalias eq "secr" && $wantsecretemail=~/\Q$cpan_alias\E/i) {
      push @m, qq{<b>ERROR</b>: You chose your email alias on CPAN to point to your secret email address but your secret email address field contains $cpan_alias. This looks like a circular reference. Please either pick a different choice for the alias or fill in a more reasonable secret email address.<hr />};
    } elsif ($wantsecretemail!~/^\s*$/ && $wantsecretemail!~/^\s*$addr_spec\s*$/) {
      push @m, qq{<b>ERROR</b>: Your secret email address doesn't look like valid email address.<hr />};
    } elsif ($wantemail!~/^\s*$/ && $wantemail!~/^\s*$addr_spec\s*$/) {
      push @m, qq{<b>ERROR</b>: Your public email address doesn't look like valid email address.<hr />};
    } else {
      $consistentsubmit = 1;
    }
    if ($consistentsubmit) {
      # more testing: make sure that we have in asciiname only ascii
      if (my $wantasciiname = $req->param("pause99_edit_cred_asciiname")) {
        if ($wantasciiname =~ /[^\040-\177]/) {
          push @m, qq{<b>ERROR</b>: Your asciiname seems to contain non-ascii characters.};
          $consistentsubmit = 0;
        } else {
          # set asciiname to empty if it equals fullname
          my $wantfullname = $req->param("pause99_edit_cred_fullname");
          if ($wantfullname eq $wantasciiname) {
            $req->parameters->set("pause99_edit_cred_asciiname", "");
          }
        }
      } else {
        # set asciiname on our own if they don't supply it
        my $wantfullname = $req->param("pause99_edit_cred_fullname");
        if ($wantfullname =~ /[^\040-\177]/) {
          require Text::Unidecode;
          $wantfullname = $mgr->any2utf8($wantfullname);
          $wantasciiname = Text::Unidecode::unidecode($wantfullname);
          $req->parameters->set("pause99_edit_cred_asciiname", $wantasciiname);
        }
      }
    }

  }
  if ($consistentsubmit) {
    my($mailsprintf1,$mailsprintf2,$saw_a_change);
    $mailsprintf1 = "%11s: [%s]%s";
    $mailsprintf2 = " was [%s]\n";
    my $now = time;
    my $myurl = $mgr->myurl;
    my $myurlstr = $myurl->can("unparse") ? $myurl->unparse : $myurl->as_string;
    $myurlstr =~ s/[?;].*//;

    # We once duplicated nearly exactly the same code of 100 lines.
    # Once for secretemail, once for the other attributes. Lines
    # marked with four hashmarks are the ones that differ. Why not
    # make it a function? Well, that function would have to take at
    # least 5 arguments and we want some variables in the lexical
    # scope. So I made it a loop for two complicated arrays.
    for my $quid (
		  [
		   "connect",
		   \@meta,
		   "users",
		   "userid",
		   1
		  ],
		  ["authen_connect",
		   \@secmeta,
		   $PAUSE::Config->{AUTHEN_USER_TABLE},
		   $PAUSE::Config->{AUTHEN_USER_FLD},
		   0
		  ]
		 ) {
      my($connect,$atmeta,$table,$column,$mailto_admins) = @$quid;
      my(@set,@mailblurb);
      my $dbh = $mgr->$connect(); #### the () for older perls
      for my $field (@$atmeta) { ####
	# warn "field[$field]";
	# Ignore fields we do not intend to change
	unless ($meta{$field}){
	  warn "Someone tried strange field[$field], ignored";
	  next;
	}
	# find out the form field name
	my $form_field = "pause99_edit_cred_$field";
        if ( $field eq "ustatus" ) {
          if ( $u->{"ustatus"} eq "active" ) {
            next;
          } elsif (!$req->param($form_field)) {
            $req->parameters->set($form_field,"unused");
          }
        }
	# $s is the value they entered
        my $s_raw = $req->param($form_field) || "";
        # we're in edit_cred
        my $s;
        $s = $mgr->any2utf8($s_raw);
        $s =~ s/^\s+//;
        $s =~ s/\s+\z//;
        if ($s ne $s_raw) {
          $req->parameters->set($form_field,$s);
        }
	$nu->{$field} = $s;
        $u->{$field} = "" unless defined $u->{$field};
        my $mb; # mailblurb
	if ($u->{$field} ne $s) {
	  $saw_a_change = 1;

	  # No UTF8 running before we have the system walking
	  #	my $utf = $mgr->formfield_as_utf8($s);
	  #	unless ( $s eq $utf ) {
	  #	  $req->parameters->set($form_field, $utf);
	  #	  $s = $utf;
	  #	}
	  #	next if $mgr->{User}{$field} eq $s;

	  # not ?-ising this as rely on quote() method
	  push @set, "$field = " . $dbh->quote($s);
	  $mb = sprintf($mailsprintf1,
                        $field,
                        $s,
                        sprintf($mailsprintf2,$u->{$field})
                       );
          if ($field eq "ustatus") {
            push @set, "ustatus_ch = NOW()";
          }
	} else {
	  $mb = sprintf(
                        $mailsprintf1,
                        $field,
                        $s,
                        "\n"
                       );
	}
        if ($field eq "email") {
          $mb = sprintf $mailsprintf1, $field, "CENSORED", "\n";
        }
        push @mailblurb, $mb;
      }
      if (@set) {

	my @query_params = ($now, $mgr->{User}{userid}, $u->{userid});
	my $sql = "UPDATE $table SET " . ####
	    join(", ", @set, "changed = ?, changedby=?") .
		" WHERE $column = ?"; ####
	my $mailblurb = qq{Record update in the PAUSE users database:

};
	$mailblurb .= sprintf($mailsprintf1, "userid", $u->{userid}, "\n");
	$mailblurb .= join "", @mailblurb;
	$mailblurb .= qq{

Data were entered by $mgr->{User}{userid} ($mgr->{User}{fullname}).
Please check if they are correct.

Thanks,
The Pause
};
	# warn "sql[$sql]mailblurb[$mailblurb]";
	# die;
	if ($dbh->do($sql, undef, @query_params)) {
	  push @m, qq{The new data are registered in table $table.<hr />};
	  $nu = $self->active_user_record($mgr,$u->{userid});
	  if ($nu->{userid} && $nu->{userid} eq $mgr->{User}{userid}) {
	    $mgr->{User} = $nu;
	  }
	  # Send separate emails to user and public places because
	  # CC leaks secretemail to others
	  my @to;
	  my %umailset;
	  for my $lu ($u, $nu) {
	    for my $att (qw(secretemail email)) {
	      if ($lu->{$att}){
		$umailset{qq{<$lu->{$att}>}} = 1;
		last;
	      }
	    }
	  }
	  push @to, join ", ", keys %umailset;
	  push @to, $mgr->{MailtoAdmins} if $mailto_admins; ####
          my $header = {Subject => "User update for $u->{userid}"};
          $mgr->send_mail_multi(\@to,$header, $mailblurb);
	} else {
	  push @{$mgr->{ERROR}}, sprintf(qq{Could not enter the data
        into the database: <i>%s</i>.},$dbh->errstr);
	}
      }
    } # end of quid loop
    if ($saw_a_change) {
      # expire temporary token to free mailpw for immediate use
      my $sql = sprintf qq{DELETE FROM abrakadabra
              WHERE user = ?};
      my $dbh = $mgr->authen_connect();
      $dbh->do($sql,undef,$u->{userid});
    } else {
      push @m, qq{No change seen, nothing done.<hr />};
    }
  }
  push @m, qq{<br /><table cellspacing="2" cellpadding="8">};
  my $alter = 1;
  for my $field (@allmeta) {
    unless ($meta{$field}){
      warn "Someone tried strange field[$field], ignored";
      next;
    }
    if ( $field eq "ustatus" ) {
      if ( $u->{"ustatus"} eq "active" ) {
        next;
      }
    }
    $alter ^= 1;
    my $alterclass = $alter ? "alternate1" : "alternate2";
    push @m, qq{<tr><td class="$alterclass"><h4 class="altering">$meta{$field}{short}</h4>};
    push @m, qq{
<p class="explain">$meta{$field}{long}</p>
} if $meta{$field}{long};
    my %args = %{$meta{$field}{args}};
    my $type = $meta{$field}{type};
    my $form = $mgr->$type(%args, default=>$u->{$field});
    # warn "field[$field]u->field[$u->{$field}]";
    # warn "form[$form]";
    push @m, qq{$form</td></tr>};
  }
  push @m, qq{</table>\n};
  push @m, qq{<input type="submit" name="pause99_edit_cred_sub" value="Submit" />};
  @m;
}

sub select_user {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $mgr->prefer_post(0);
  my $req = $mgr->{REQ};
  if (my $action = $req->param("ACTIONREQ")) {
    if (
	$self->can($action)
       ) {
      $req->parameters->set("ACTION",$action);
      $mgr->{Action} = $action;
      return $self->$action($mgr);
    } else {
      die "cannot action[$action]";
    }
  }
  my @m;
  my %user_meta = $self->user_meta($mgr);
  push @m, $mgr->scrolling_list(
				'name'     =>'HIDDENNAME',
				default  => [$mgr->{User}{userid}],
                                %{$user_meta{userid}{args}},
			       );
  push @m, qq{\n<br />\n};
  my $action_map = $self->_action_map_to_verb($mgr,$mgr->{AllowAdminTakeover});
  push @m, $mgr->scrolling_list(
				'name' => 'ACTIONREQ',
				values => $mgr->{AllowAdminTakeover},
                                labels => $action_map,
				default => ['edit_cred'],
				size => 13,
			       );
  push @m, qq{\n<br />\n};
  push @m, qq{<input type="submit" name="pause99_select_user_sub" value="Submit" />};
  @m;
}

sub _action_map_to_verb {
  my($self,$mgr,$actions) = @_;
  my %action_map = map { $_, $_ } @$actions;
  while (my($k,$v) = each %{$mgr->{ActionTuning}}) {
    next unless exists $action_map{$k};
    for ($mgr->{ActionTuning}{$k}{verb}) {
      $action_map{$k} = $_ if $_;
    }
  }
  \%action_map;
}

=head2 select_ml_action

Like select_user, very much like select_user, more copy and paste than
should be.

=cut

sub select_ml_action {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my $dbh = $mgr->connect;
  if (my $action = $req->param("ACTIONREQ")) {
    if (
	$self->can($action)
	&&
        grep { $_ eq $action } @{$mgr->{AllowMlreprTakeover}}
       ) {
      $req->parameters->set("ACTION",$action);
      $mgr->{Action} = $action;
      return $self->$action($mgr);
    } else {
      die "cannot or want not action[$action]";
    }
  }
  my @m;

  push @m, qq{<p>Mailinglist support is intended to be available on a
      delegates/representatives basis, that means, one or more users
      are "elected" (no formal election though) to be allowed to act
      on behalf of a mailing list. There is no password for a mailing
      list, there are no user credentials for a mailing list. There
      are no uploads for mailing lists, thus no deletes or repairs of
      uploads.</p> <p>There are only the infos about the mailing list
      editable via the method <i>edit_ml</i> and ther are a number of
      modules associated with a mailing list and these are accessible
      in the <i>edit_mod</i> method.</p> <p>The menu item <i>Select
      Mailinglist/Action</i> lets you access the available methods and
      the mailing lists you are associated with. Only people elected
      as a representative of a mailing list should be able to ever see
      the menu entry.</p> <p>This feature is available since Oct 25th,
      1999 and hardly tested, so please take care and let us know how
      it goes.</p>

      <h3>Choose your mailing list and the action and click the submit
      button.</h3>};

  my $sql = qq{SELECT users.userid
               FROM users, list2user
               WHERE isa_list > ''
                 AND users.userid = list2user.maillistid
                 AND list2user.userid = ?
               ORDER BY users.userid
};

  my $sth = $dbh->prepare($sql);
  $sth->execute($mgr->{User}{userid});
  my %u;
  while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
    $u{$row[0]} = $row[0];
  }
  my $size1 = $sth->rows > 8 ? 5 : $sth->rows;
  my $size2 = scalar @{$mgr->{AllowMlreprTakeover}} > 8 ? 5 : scalar @{$mgr->{AllowMlreprTakeover}};
  my($action_map) = $self->_action_map_to_verb($mgr,$mgr->{AllowMlreprTakeover});
  push @m, $mgr->scrolling_list(
				'name'     =>'HIDDENNAME',
				'values' => [sort {lc($u{$a}) cmp lc($u{$b})} keys %u],
				default  => [$mgr->{User}{userid}],
				size     => $size1,
				labels   => \%u,
			       );
  push @m, $mgr->scrolling_list(
				'name' => 'ACTIONREQ',
				values => $mgr->{AllowMlreprTakeover},
                                labels => $action_map,
				default => ['edit_ml'],
				size => $size2,
			       );
  push @m, qq{<input type="submit"
 name="pause99_select_ml_action_sub" value="Submit" />};
  @m;
}

sub pause_04about {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $self->show_document($mgr,"04pause.html",1);
}

sub pause_logout {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $x = $self->show_document($mgr,"logout.html");
  my $rand = rand 1;
  # the redirect solutions fail miserably the second time when tried
  # with the exact same querystring again.
  $x =~ s/__RANDOMSTRING__/$rand/g;
  $x;
}

sub pause_04imprint {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $self->show_document($mgr,"imprint.html");
}

sub pause_05news {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $self->show_document($mgr,"index.html");
}

sub pause_06history {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $self->show_document($mgr,"history.html");
}

sub pause_namingmodules {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $self->show_document($mgr,"namingmodules.html");
}

sub show_document {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $doc = shift || "04pause.html";
  my $rewrite = shift || 0;
  my $dir = $FindBin::Bin;
  my @m;
  # push @m, sprintf "DEBUG: %s %s<br />", $dir, -e $dir ? "exists" : "doesn't exist. ";
  for my $subdir ("htdocs", "pause", "pause/../htdocs", "pause/..", "") {
    my $file = "$dir/$subdir/$doc";
    next unless -f $file;
    push @m, qq{<hr noshade="noshade" />};
    open my $fh, $file or die;
    if ($] > 5.007) {
      binmode $fh, ":utf8";
    }
    local $/;
    my $html_in = <$fh>;
    close $fh;

    if ($rewrite) {
      use XML::SAX::ParserFactory;
      use XML::SAX::Writer;
      use pause_1999::saxfilter01;
      use XML::LibXML::SAX;
      $XML::SAX::ParserPackage = "XML::LibXML::SAX";

      my @html_out;
      my $w = XML::SAX::Writer->new(Output => \@html_out);
      my $f = pause_1999::saxfilter01->new(Handler => $w);
      my $p = XML::SAX::ParserFactory->parser(Handler => $f);
      $p->parse_string($html_in);
      while ($html_out[0] =~ /^<[\?\!]/){ # remove XML Declaration, DOCTYPE
        shift @html_out;
      }
      push @m, join "", @html_out;
    } else {
      my $html = $html_in;
      $html =~ s/^.*?<body[^>]*>//si;
      $html =~ s|</body>.*$||si;
      push @m, $html;
    }

    last;
  }
  unless (@m) {
    push @m, "document '$doc' not found on the server";
  }
  join "", @m;
}

sub tail_logfile {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my $tail = $req->param("pause99_tail_logfile_1") || 5000;
  my($file) = $PAUSE::Config->{PAUSE_LOG};
  if ($PAUSE::Config->{TESTHOST}) {
    $file = "/usr/local/apache/logs/error_log"; # for testing
  }
  open my $fh, $file or die "Could not open $file: $!";
  seek $fh, -$tail, 2;
  local($/);
  $/ = "\n";
  <$fh>;
  $/ = undef;
  my @m;
  push @m, $mgr->scrolling_list(
				name => "pause99_tail_logfile_1",
				size => 1,
				values => [qw( 2000 5000 10000 20000 40000) ],
			       );
  push @m, qq{<input type="submit"
               name="pause99_tail_logfile_sub" value="Tail characters" />};
  push @m, "<pre>", $mgr->escapeHTML(<$fh>), "</pre>";
  join "", @m;
}

sub change_passwd {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $mgr->prefer_post(1);
  my $req = $mgr->{REQ};
  my @m;
  my $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  push @m, qq{<h3>Changing Password of $u->{userid}</h3>}; # };
  if (my $param = $req->param("ABRA")) {
    push @m, qq{<input type="hidden" name="ABRA" value="$param" />};
  }

  if ($req->param("pause99_change_passwd_sub")) {
    if (my $pw1 = $req->param("pause99_change_passwd_pw1")) {
      if (my $pw2 = $req->param("pause99_change_passwd_pw2")) {
	if ($pw1 eq $pw2) {
	  # create a new crypted password, store it, report
	  my $pwenc = PAUSE::Crypt::hash_password($pw1);
	  my $dbh = $mgr->authen_connect;
	  my $sql = qq{UPDATE $PAUSE::Config->{AUTHEN_USER_TABLE}
                       SET $PAUSE::Config->{AUTHEN_PASSWORD_FLD} = ?,
                           forcechange = ?,
                           changed = ?,
                           changedby = ?
                       WHERE $PAUSE::Config->{AUTHEN_USER_FLD} = ?};
	  # warn "sql[$sql]";
	  my $rc = $dbh->do($sql,undef,
			    $pwenc,0,time,$mgr->{User}{userid},$u->{userid});
	  warn "rc[$rc]";
	  die PAUSE::HeavyCGI::Exception
	      ->new(ERROR =>
		    sprintf qq[Could not set password: '%s'], $dbh->errstr
		   ) unless $rc;
	  if ($rc == 0) {
	    $sql = qq{INSERT INTO $PAUSE::Config->{AUTHEN_USER_TABLE}
                       ($PAUSE::Config->{AUTHEN_USER_FLD},
                           $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
                               forcechange,
                                   changed,
                                       changedby ) VALUES
                       (?, ?,  ?,  ?,  ?)
}; # };
	    $rc = $dbh->do($sql,undef,
			   $u->{userid},
			   $pwenc,
			   0,
			   time,
			   $mgr->{User}{userid},
			   $u->{userid}
			  );
	    die PAUSE::HeavyCGI::Exception
		->new(ERROR =>
		      sprintf qq[Could not insert user record: '%s'], $dbh->errstr
		     ) unless $rc;
	  }
          for my $anon ($mgr->{User}, $u) {
            die PAUSE::HeavyCGI::Exception
                ->new(ERROR => "Panic: unknown user") unless $anon->{userid};
            next if $anon->{fullname};
            $req->logger({level => 'error', message => "Unknown fullname for $anon->{userid}!" });
          }

	  push @m, "New password stored and enabled. Be prepared that
 you will be asked for a new authentication on the next request. If
 this doesn't work out, it may be that you have to restart the
 browser.";

	  my $mailblurb = sprintf(
                                  qq{Password update on PAUSE:

%s (%s) visited the
password changer on PAUSE at %s UTC
and changed the password for %s (%s).

No action is required, but it would be a good idea if somebody
would check the correctness of the new password.

Thanks,
The Pause
},
                                  $mgr->{User}->{userid},
                                  $mgr->{User}{fullname}||"fullname N/A",
                                  scalar gmtime,
                                  $u->{userid},
                                  $u->{fullname}||"fullname N/A");
	  my %umailset;
          my $name = $u->{asciiname} || $u->{fullname} || "";
          my $Uname = $mgr->{User}{asciiname} || $mgr->{User}{fullname} || "";
	  if ($u->{secretemail}) {
	    $umailset{qq{"$name" <$u->{secretemail}>}} = 1;
	  } elsif ($u->{email}) {
	    $umailset{qq{"$name" <$u->{email}>}} = 1;
	  }
          if ($u->{userid} ne $mgr->{User}{userid}) {
            if ($mgr->{User}{secretemail}) {
              $umailset{qq{"$Uname" <$mgr->{User}{secretemail}>}} = 1;
            }elsif ($mgr->{User}{email}) {
              $umailset{qq{"$Uname" <$mgr->{User}{email}>}} = 1;
            }
          }
          my @to = keys %umailset;
          my $header = {Subject => "Password Update"};
          $mgr->send_mail_multi(\@to, $header, $mailblurb);
	} else {
	  die PAUSE::HeavyCGI::Exception
              ->new(ERROR => "The two passwords didn't match.");
	}
      } else {
	die PAUSE::HeavyCGI::Exception
            ->new(ERROR => "You need to fill in the same password in both fields.");
      }
    } else {
      die PAUSE::HeavyCGI::Exception
          ->new(ERROR => "Please fill in the form with passwords.");
    }
  } else {
    if ( $mgr->{UserSecrets}{forcechange} ) {
      push @m, qq{<p>Your password in the database is tainted which
 means you have to renew it. If you believe this is wrong, please
 complain, it's always possible that you are seeing a bug.</p>};
    }

    push @m, qq{<p>Please fill in your new password in both textboxes.
 Only if both fields contain the same password, we will be able to
 proceed.</p>};

    push @m, $mgr->password_field(name=>"pause99_change_passwd_pw1",
				  maxlength=>72,
				  size=>16);
    push @m, qq{\n};
    push @m, $mgr->password_field(name=>"pause99_change_passwd_pw2",
				  maxlength=>72,
				  size=>16);
    push @m, qq{\n};
    push @m, qq{<input type="submit" name="pause99_change_passwd_sub"
    value="Submit" />};
  }
  @m;
}

sub add_uri {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my $debug_table = $req->parameters; # XXX: $r->parms
  warn sprintf "DEBUG: req[%s]", join(":",%$debug_table);
  $PAUSE::Config->{INCOMING_LOC} =~ s|/$||;
  my @m;
  my $u = $self->active_user_record($mgr);
  die PAUSE::HeavyCGI::Exception
      ->new(ERROR =>
            "Unidentified error happened, please write to the PAUSE admins
 at $PAUSE::Config->{ADMIN} and help them identifying what's going on. Thanks!")
          unless $u->{userid};
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  my $can_multipart = $mgr->can_multipart;
  push @m, qq{<input type="hidden" name="CAN_MULTIPART" value="$can_multipart" />};
  push @m, qq{<h3>Add a file for $u->{userid}</h3>};
  my($tryupload) = $mgr->can_multipart;
  my($uri);
  my $userhome = PAUSE::user2dir($u->{userid});

  if ($req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD")
      || $req->param("SUBMIT_pause99_add_uri_httpupload")) {
    my $upl = $req->upload('pause99_add_uri_httpupload');
    unless ($upl->size) {
      warn "Warning: maybe they hit RETURN, no upload size, not doing HTTPUPLOAD";
      $req->parameters->set("SUBMIT_pause99_add_uri_HTTPUPLOAD","");
      $req->parameters->set("SUBMIT_pause99_add_uri_httpupload","");
    }
  }
  if (!   $req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD")
      &&! $req->param("SUBMIT_pause99_add_uri_httpupload")
      &&! $req->param("SUBMIT_pause99_add_uri_uri")
      &&! $req->param("SUBMIT_pause99_add_uri_upload")
     ) {
    # no submit button
    if ($req->param("pause99_add_uri_uri")) {
      $req->parameters->set("SUBMIT_pause99_add_uri_uri", "2ndguess");
    } elsif ($req->param("pause99_add_uri_upload")) {
      $req->parameters->set("SUBMIT_pause99_add_uri_upload", "2ndguess");
    }
  }

  my $didit = 0;
  my $mailblurb = "";
  my $success = "";
  my $now = time;
  if (
      $req->param("SUBMIT_pause99_add_uri_httpupload") || # from 990806
      $req->param("SUBMIT_pause99_add_uri_HTTPUPLOAD")
     ) {
    if ($mgr->{UseModuleSet} eq "ApReq") {
      my $upl;
      if (
	  $upl = $req->upload("pause99_add_uri_httpupload") or # from 990806
	  $upl = $req->upload("HTTPUPLOAD")
	 ) {
	if ($upl->size) {
	  my $filename = $upl->filename;
	  $filename =~ s(.*/)()gs;      # no slash
	  $filename =~ s(.*\\)()gs;     # no backslash
	  $filename =~ s(.*:)()gs;      # no colon
	  $filename =~ s/[^A-Za-z0-9_\-\.\@\+]//g; # only ASCII-\w and - . @ + allowed
	  my $to = "$PAUSE::Config->{INCOMING_LOC}/$filename";
	  # my $fhi = $upl->fh;
	  require File::Copy;
	  if (-f $to && -s _ == 0) { # zero sized files are a common problem
	    unlink $to;
	  }
	  if (File::Copy::copy($upl->path, $to)){
	    $uri = $filename;
	    # Got an empty $to in the HTML page, so for debugging..
	    my $h1 = qq{<h3>File successfully copied to '$to'</h3>};
	    warn "h1[$h1]filename[$filename]";
	    push @m, $h1;
	  } else {
	    die PAUSE::HeavyCGI::Exception
		->new(ERROR =>
		      "Couldn't copy file '$filename' to '$to': $!");
	  }
          unless ($upl->filename eq $filename) {

            require Dumpvalue;
            my $dv = Dumpvalue->new;
            push @m, sprintf(q(

<p> Your filename has been altered as it contained characters besides
the class [A-Za-z0-9_\\-\\.\\@\\+]. DEBUG: your filename[%s] corrected
filename[%s]. </p>

),
                             $dv->stringify($upl->filename),
                             $dv->stringify($filename)
                            );
            $req->parameters->set("pause99_add_uri_httpupload",$filename);
          }
	} else {
	  die PAUSE::HeavyCGI::Exception
	      ->new(ERROR =>
		    "uploaded file was zero sized");
	}
      } else {
	die PAUSE::HeavyCGI::Exception
	    ->new(ERROR =>
		  "Could not create an upload object. DEBUG: upl[$upl]");
      }
    } elsif ($mgr->{UseModuleSet} eq "patchedCGI") {
      warn "patchedCGI not supported anymore";

      my $handle;
      if (
	  $handle = $req->param('pause99_add_uri_httpupload') or
	  $handle = $req->param('HTTPUPLOAD')
	 ) {
	no strict;
	use File::Copy;
	$filename = "$handle";
	$filename =~ s(.*/)()s;      # no slash
	$filename =~ s(.*\\)()s;     # no backslash
	$filename =~ s(.*:)()s;      # no colon
	$filename =~ s/[^A-Za-z0-9_\-\.\@\+]//g; # only ASCII-\w and - . @ + allowed
	my $to = "$PAUSE::Config->{INCOMING_LOC}/$filename";
	if (File::Copy::copy(\*$handle, $to)){
	  $uri = $filename;
	  push @m, qq{<h3>File successfully copied to '$to'</h3>};
	} else {
	  die PAUSE::HeavyCGI::Exception
	      ->new(ERROR =>
		    "Couldn't copy file '$filename' to '$to': $!");
	}
      }
    } else {
      die "Illegal UseModuleSet: $mgr->{UseModuleSet}";
    }
  } elsif ( $req->param("SUBMIT_pause99_add_uri_uri") ) {
    $uri = $req->param("pause99_add_uri_uri");
    $req->parameters->set("pause99_add_uri_httpupload",""); # I saw spurious
                                                  # nonsense in the
                                                  # field that broke
                                                  # XHTML
  } elsif ( $req->param("SUBMIT_pause99_add_uri_upload") ) {
    $uri = $req->param("pause99_add_uri_upload");
    $req->parameters->set("pause99_add_uri_httpupload",""); # I saw spurious
                                                  # nonsense in the
                                                  # field that broke
                                                  # XHTML
  }
  # my $myurl = $mgr->myurl;
  my $server = $PAUSE::Config->{SERVER_NAME}; # XXX: $r->server->server_hostname
  my $dbh = $mgr->connect;



  if (! $uri ) {
    push @m, "\n\n<div class='noactionnoresponse'></div>\n\n";
  } else {
    push @m, $self->add_uri_continue_with_uri($mgr,$uri,\$success,\$didit);
  }

  push @m, qq{\n<!-- Preamble: By uploading material to the
      PAUSE, you cause an eminent wide distribution mechanism, the
      CPAN, to bring your material to hundreds of mirroring ftp
      servers and other distribution channels. Thus it may not be easy
      or even possible to withdraw the material again. Please think,
      before you type, if this is what you want and agree upon. -->

      <p>This form enables you to enter one file at a time
      into CPAN in one of these ways:</p><table>};

  if ($tryupload) {

    push @m, qq{\n<tr><td bgcolor="#e0ffff"><b>HTTP Upload:</b> As an
        HTTP upload: enter the filename in the lower text field.
        <b>Hint:</b> If you encounter problems processing this form,
        it may be due to the fact that your browser can\'t handle
        <code>multipart/form-data</code> forms that support file
        upload. In such a case, please retry to access this <a
        href="authenquery?ACTION=add_uri;CAN_MULTIPART=0">file-upload-disabled
        form</a>.</td></tr>\n};

  } else {

    push @m, qq{\n<tr><td bgcolor="#e0ffff"><b>HTTP Upload:</b> <i>As
	    you do not seem to want HTTP upload enabled, we do
	    <b>not</b> offer it. If this is not what you want, try to
	    <a
	    href="authenquery?ACTION=add_uri;CAN_MULTIPART=1">explicitly
	    enable HTTP upload</a>.</i></td></tr>\n};

  }

  push @m, qq{<tr><td bgcolor="#ffe0ff"><b>GET URL:</b> PAUSE fetches
      any http or ftp URL that can be handled by LWP: use the text
      field (please specify the <i>complete URL</i>). How to use this
      for direct publishing from your github repository has been
      described by Mike Schilli <a
      href="http://blog.usarundbrief.com/?p=36">in his
      blog</a></td></tr>\n};

  push @m, qq{</table>\n <blockquote><b>Please,</b> make sure your filename
      contains a version number. For security reasons you will never
      be able to upload a file with the same name again (not even
      after deleting it). <b>Thank you.</b></blockquote>

      <p>There is no need to upload README files separately. The
      upload server will unwrap your files (.tar.gz or .zip files
      only) within a few hours after uploading and will put the
      topmost README file as, say, Foo-Bar-3.14.readme into your
      directory. <b>Hint:</b> if you're looking for an even more
      convenient way to upload files than this form, you can try the
      <a href="http://search.cpan.org/dist/cpan-upload-http/">cpan-upload-http</a> script.
      </p>

}; #};



  # SUBDIR

  # if ($mgr->{User}{userid} eq "ANDK") {
  if (1) {

    push @m, qq{<h3>Target Directory</h3><p> If you want to load the
                file into a directory below your CPAN directory,
                please specify the directory name here. Any number of
                subdirectory levels is allowed, they all will be
                created on the fly if they don't exist yet. Only sane
                directory names are allowed and the number of
                characters for the whole path is limited.</p><p>
                <b>NOTE</b>:  To upload a Perl6 distribution a target
                directory whose top level subdirectory is "Perl6" must
                be specified.  In addition, a Perl6 distribution must
                contain a META6.json.  Pause will only consider it a
                Perl6 dist if these two conditions are satisfied.
                </p>};


    push @m, qq{<div align="center">};
    push @m, $self->scroll_subdirs($mgr,$u);
    push @m, $mgr->textfield(
                             name => "pause99_add_uri_subdirtext",
                             size => 32,
                             maxlength => 128
                            );
    push @m, qq{</div>};

  }


  # HTTP UPLOAD

  push @m, "<h3>Upload Material</h3><table>";

  if ($tryupload) {
    $mgr->need_multipart(1);
    $mgr->{RES}->header("Accept","*");

    push @m, qq{<tr><td bgcolor="#e0ffff">If <b>your browser can handle
        file upload</b>, enter the filename here and I'll transfer it
        to your homedirectory:<br />};

    push @m, $mgr->file_field(name => 'pause99_add_uri_httpupload',
			      size => 50);
    push @m, "\n<br />";
    push @m, qq{<input type="submit" name="SUBMIT_pause99_add_uri_httpupload"
 value=' Upload this file from my disk ' /></td></tr>\n};
  }

  # via FTP GET

  warn "DEBUG: UPLOAD[$PAUSE::Config->{UPLOAD}]";
  push @m, qq{<tr><td bgcolor="#ffe0ff">If you want me <b>to fetch a
      file</b> from an URL, enter the full URL here.<br />};

  push @m, $mgr->textfield(
			   name => "pause99_add_uri_uri",
			   size => 64,
			   maxlength => 128
			  );
  push @m, "\n<br />";
  push @m, qq{<input type="submit" name="SUBMIT_pause99_add_uri_uri"
 value=' Upload this URL ' /></td></tr>\n};

  # END OF UPLOAD OPTIONS

  push @m, "\n</table>\n";

  my $want_to_send_email_on_upload_submission = 0;
  if ($want_to_send_email_on_upload_submission && $didit) {
    my $her = $mgr->{User}{userid} eq $u->{userid} ? "his/her" :
	"$u->{userid}'s";

    my $mailblurb = $self->wrap(qq{$mgr->{User}{userid}
($mgr->{User}{fullname}) visited the PAUSE and requested an upload
into $her directory. The request used the following parameters:});
    $mailblurb .= "\n";

    my @mb;
    my $longest = 0;
    for my $param ($req->param) {
      next if $param eq "HIDDENNAME";
      next if $param eq "CAN_MULTIPART";
      next if $param eq "pause99_add_uri_sub"; # we're not interested
      my $v = $req->param($param);
      next unless defined $v;
      next unless length $v;
      $longest = length($param) if length($param) > $longest;
      push @mb, [$param,$v];
    }
    for my $mb (@mb) {
      my($param, $v) = @$mb;
      $mailblurb .= sprintf qq{ %-*s [%s]\n}, $longest, $param, $v;
    }
    $mailblurb .= "\n";
    $mailblurb .= $self->wrappar($success);
    $mailblurb .= "\n\nThanks for your contribution,\n-- \nThe PAUSE\n";
#    my $header = {
#		  To => qq{$PAUSE::Config->{ADMIN}, $u->{email}, $mgr->{User}{email}},
#		  Subject => qq{Notification from PAUSE},
#		 };
    my %umailset;
    my $name = $u->{asciiname} || $u->{fullname} || "";
    if ($u->{secretemail}) {
      $umailset{qq{"$name" <$u->{secretemail}>}} = 1;
    } elsif ($u->{email}) {
      $umailset{qq{"$name" <$u->{email}>}} = 1;
    }
    if ($u->{userid} ne $mgr->{User}{userid}) {
      my $Uname = $mgr->{User}{asciiname} || $mgr->{User}{fullname} || "";
      if ($mgr->{User}{secretemail}) {
	$umailset{qq{"$Uname" <$mgr->{User}{secretemail}>}} = 1;
      }elsif ($mgr->{User}{email}) {
	$umailset{qq{"$Uname" <$mgr->{User}{email}>}} = 1;
      }
    }
    $umailset{$PAUSE::Config->{ADMIN}} = 1;
    my @to = keys %umailset;
    my $header = {
                  Subject => "Notification from PAUSE",
                 };
    $mgr->send_mail_multi(\@to, $header, $mailblurb);
  }

  @m;
}

sub add_uri_continue_with_uri {
  my($self,$mgr,$uri,$success,$didit) = @_;
  my $req = $mgr->{REQ};
  my $u = $self->active_user_record($mgr);
  my $userhome = PAUSE::user2dir($u->{userid});
  my $dbh = $mgr->connect;
  my $now = time;
  my $server = $PAUSE::Config->{SERVER_NAME}; # XXX: $r->server->server_hostname
  my @m;
    push @m, "\n\n<blockquote class='actionresponse'>\n",
     "<!-- start of response to user's action -->\n\n",
    ;

    require URI::URL;
    eval { URI::URL->new("$uri", $PAUSE::Config->{INCOMING}); };


    if ($@) {
      die PAUSE::HeavyCGI::Exception
	  ->new(ERROR => [qq{
Sorry, <b>$uri</b> could not be recognized as an uri (},
			  $@,
			 qq{\)<p>Please
try again or report errors to <a
href="mailto:},
			  $PAUSE::Config->{ADMIN},
			  qq{">the administrator</a></p>}]);
    } else {
      my $filename;
      ($filename = $uri) =~ s,.*/,, ;
      $filename =~ s/[^A-Za-z0-9_\-\.\@\+]//g; # only ASCII-\w and - . @ + allowed

      if ($filename eq "CHECKSUMS") {
        # userid DERHAAG demonstrated that it could be uploaded on 2002-04-26
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR => "Files with the name CHECKSUMS cannot be
                            uploaded to CPAN, they are reserved for
                            CPAN's internals.");

      }

      my $subdir = "";
      if ( $req->param("pause99_add_uri_subdirtext") ) {
        $subdir = $req->param("pause99_add_uri_subdirtext");
      } elsif ( $req->param("pause99_add_uri_subdirscrl") ) {
        $subdir = $req->param("pause99_add_uri_subdirscrl");
      }

      my $uriid = "$userhome/$filename";

      if (defined $subdir && length $subdir) {
        # disallowing . to make /./ and /../ handling easier
        $subdir =~ s|[^A-Za-z0-9_\-\@\+/]||g; # as above minus "." plus "/"
        $subdir =~ s|^/+||;
        $subdir =~ s|/$||;
        $subdir =~ s|/+|/|g;
      }
      my $is_perl6 = 0;
      if (defined $subdir && length $subdir) {
        $is_perl6 = 1 if $subdir =~ /^Perl6\b/;
        $uriid = "$userhome/$subdir/$filename";
      }

      if ( length $uriid > 255 ) {
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR => "Path name too long: $uriid is longer than
                255 characters.");
      }

    ALLOW_OVERWRITE: if (
	  $filename =~ /(readme|\.html|\.txt|\.[xy]ml|\.json|\.[pr]df|\.pod)(\.gz|\.bz2)?$/i
          ||
          $uriid =~ m!^C/CN/CNANDOR/(?:mp_(?:app|debug|doc|lib|source|tool)|VISEICat(?:\.idx)?|VISEData)!
	 ) {
	# Overwriting allowed
	$dbh->do("DELETE FROM uris WHERE uriid = ?", undef, $uriid);
      }
      my $query = q{INSERT INTO uris
                            (uriid,     userid,
                             basename,
                             uri,
		             changedby, changed, is_perl6)
                     VALUES (?, ?, ?, ?, ?, ?, ?)};
      my @query_params = (
	$uriid, $u->{userid}, $filename, $uri, $mgr->{User}{userid}, $now,
    $is_perl6
      );
      #display query
      my $cp = $mgr->escapeHTML("$query/(@query_params)");
      push @m, qq{<h3>Submitting query</h3>};
      if ($mgr->{UseModuleSet} eq "patchedCGI") {
        warn "patchedCGI not supported anymore";
	my @debug = "DEBUGGING patched CGI:\n";
	push @debug, scalar localtime;
	my %headers = %{ $req->headers }; # XXX: or maybe use header_field_names
	for my $h (keys %headers) {
          next if $h =~ /Authorization/; # security!
	  push @debug, sprintf " %s: %s\n", $h, $headers{$h};
	}
	for ($req->param) {
	  push @debug, " $_: ";
	  my($val) = $req->param($_);
	  push @debug, $val;
	  push @debug, "<br />\n";
	  if (ref $val) {
	    push @debug, " <blockquote>";
	    my $valh;
	    if ($val->can("multipart_header")) {
	      $valh = $val->multipart_header;
	    } else {
	      push(
                   @debug,
                   "      CAN'T multipart_header, val[$val]<br /></ul><br />\n");
	      next;
	    }
	    push @debug, "      valh[$valh]";
	    for my $h (keys %$valh) {
	      push @debug, "      $h: $valh->{$h}<br />\n";
	    }
	    push @debug, " </blockquote><br />\n";
	  }
	}
	warn join "", @debug;
	push @m, "Resulting SQL: ", $cp;
      }
      local($dbh->{RaiseError}) = 0;
      if ($dbh->do($query, undef, @query_params)) {
	$$success .= qq{

The request is now entered into the database where the PAUSE daemon
will pick it up as soon as possible (usually 1-2 minutes).

};
	$$didit = 1;
	push @m, (qq{

<p>Query succeeded. <b>Thank you for your contribution</b></p>

<p>As it is done by a separate process, it may take a few minutes to
complete the upload. The processing of your file is going on while you
read this. There\'s no need for you to retry. The form below is only
here in case you want to upload further files.</p>

<p><b>Please tidy up your homedir:</b> CPAN is getting larger every day which
is nice but usually there is no need to keep old an outdated version
of a module on several hundred mirrors. Please consider <a
href="authenquery?ACTION=delete_files">removing</a> old versions of
your module from PAUSE and CPAN. If you are worried that someone might
need an old version, it can always be found on the <a
href="http://backpan.cpan.org/authors/id/$userhome/">backpan</a>
</p>

});

	my $usrdir = "https://$server/pub/PAUSE/authors/id/$userhome";
	my $tailurl = "https://$server/pause/authenquery?ACTION=tail_logfile" .
            "&pause99_tail_logfile_1=5000";
	my $etailurl = $mgr->escapeHTML($tailurl);
	push @m, (qq{

<p><b>Debugging:</b> your submission should show up soon at <a
href="$usrdir">$usrdir</a>. If something's wrong, please
check the logfile of the daemon: see the tail of it with <a
href="$etailurl">$etailurl</a>. If you already know what's going wrong, you
may wish to visit the <a href="authenquery?ACTION=edit_uris">repair
tool</a> for pending uploads.</p>

}
		 );

	$$success .= qq{

During upload you can watch the logfile in $tailurl.

You'll be notified as soon as the upload has succeeded, and if the
uploaded package contains modules, you'll get another notification
from the indexer a little later (usually within 1 hour).

};

      } else {
	my $errmsg = $dbh->errstr;
        $mgr->{RES}->status(406);
	push @m, (qq{

<p><b>Could not enter the URL into the database.
Reason:</b></p><p>$errmsg</p>

});
	if ($errmsg =~ /non\s+unique\s+key|Duplicate/i) {
          $mgr->{RES}->status(409);
          my $sth = $dbh->prepare("SELECT * FROM uris WHERE uriid=?");
          $sth->execute($uriid);
          my $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
          for my $k (qw(changed dgot dverified)) {
            if ($rec->{$k}) {
              $rec->{$k} .= sprintf " [%s UTC]", scalar gmtime $rec->{$k};
            }
          }
          my $as_table = $self->hash_as_table($rec);
	  push @m, qq{

<p>This indicates that you probably tried to upload a file that is
already in the database. You will most probably have to rename your
file and try again, because <b>PAUSE doesn\'t let you upload a file
twice</b>.</p>

<p>This seems to be the record causing the conflict:<br/>$as_table</p>

};
	}
      }
    }
    
    push @m, "\n<!-- end of the response to the user's action -->\n</blockquote>\n";
    
    push @m, (qq{<hr noshade="noshade" />\n});
  return @m;
}

sub manifind {
  my($self) = @_;
  my $cwd = Cwd::cwd();
  warn "cwd[$cwd]";
  my %files = %{ExtUtils::Manifest::manifind()};
  if (keys %files == 1 && exists $files{""} && $files{""} eq "") {
    warn "ALERT: BUG in MANIFIND, falling back to zsh !!!";

    # This bug was caused by libc upgrade: perl and apache were
    # compiled with 2.1.3; upgrading to 2.2.5 and/or later
    # recompilation of apache has caused readdir() to return a list of
    # empty strings.

    open my $ls, "zsh -c 'ls **/*(.)' |" or die;
    %files = map { chomp; $_ => "" } <$ls>;
    close $ls;
  }

  %files;
}

sub scroll_subdirs {
  my $self = shift;
  my $mgr = shift;
  my $u = shift;
  my $userhome = PAUSE::user2dir($u->{userid});
  require ExtUtils::Manifest;
  if (chdir "$PAUSE::Config->{MLROOT}/$userhome"){
    warn "DEBUG: MLROOT[$PAUSE::Config->{MLROOT}] userhome[$userhome] E:M:V[$ExtUtils::Manifest::VERSION]";
  } else {
    return "";
  }
  my %files = $self->manifind;
  my %seen;
  my @dirs = sort grep !$seen{$_}++, grep s|(.+)/[^/]+|$1|, keys %files;
  return "" unless @dirs;
  unshift @dirs, ".";
  my $size = @dirs > 8 ? 5 : scalar(@dirs);
  my @m;
  push @m, $mgr->scrolling_list(
                                'name' => "pause99_add_uri_subdirscrl",
                                'values' => \@dirs,
                                'size' => $size,
                               );
  push @m, qq{<br />};
  @m;
}

sub wrap {
  my $self = shift;
  my $p = shift;
  my($wrapped);
  $wrapped = Text::Format->new("firstIndent"=>0)->format($p);
  $wrapped;
}

sub wrappar {
  my $self = shift;
  my @p = split /\n\n/, shift;
  my($wrapped);
  $wrapped = Text::Format->new("firstIndent"=>0)->paragraphs(@p);
  $wrapped;
}

sub delete_files {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my @m;
  my $u = $self->active_user_record($mgr);
  $mgr->prefer_post(1);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  require ExtUtils::Manifest;
  require HTTP::Date;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my $userhome = PAUSE::user2dir($u->{userid});
  push @m, qq{<h3>Files in directory authors/id/$userhome</h3>}; #};
  require Cwd;
  my $cwd = Cwd::cwd();

  if (chdir "$PAUSE::Config->{MLROOT}/$userhome"){
    warn "DEBUG: MLROOT[$PAUSE::Config->{MLROOT}] userhome[$userhome] ExtUtils:Manifest:VERSION[$ExtUtils::Manifest::VERSION]";
  } else {
    # QUICK DEPARTURE
    push @m, qq{No files found in authors/id/$userhome};
    return @m;
  }

  # NONO, this is nothing we should die from:
  #      die PAUSE::HeavyCGI::Exception
  #	  ->new(ERROR => [qq{No files found in authors/id/$userhome}]);


  my $time = time;
  my $blurb = "";
  # my $myurl = $mgr->myurl;
  my $server = $PAUSE::Config->{SERVER_NAME}; # XXX: $r->server->server_hostname
  if ($req->param('SUBMIT_pause99_delete_files_delete')) {

    foreach my $f ($req->param('pause99_delete_files_FILE')) {
      if ($f =~ m,^/, || $f =~ m,/\.\./,) {
	$blurb .= "WARNING: illegal filename: $userhome/$f\n";
	next;
      }
      unless (-f $f){
	$blurb .= "WARNING: file not found: $userhome/$f\n";
	next;
      }
      if ($f =~ m{ (^|/) CHECKSUMS }x) {
	$blurb .= "WARNING: CHECKSUMS not erasable: $userhome/$f\n";
	next;
      }
      $dbh->do(
	"INSERT INTO deletes VALUES (?, ?, ?)", undef,
	"$userhome/$f", $time, "$mgr->{User}{userid}"
      ) or next;

      $blurb .= "\$CPAN/authors/id/$userhome/$f\n";

      # README
      next if $f =~ /\.readme$/;
      my $readme = $f;
      $readme =~ s/(\.tar.gz|\.zip)$/.readme/;
      if ($readme ne $f && -f $readme) {
	$dbh->do(
	  q{INSERT INTO deletes VALUES (?,?,?)}, undef,
	  "$userhome/$readme", $time, $mgr->{User}{userid},
	) or next;
	$blurb .= "\$CPAN/authors/id/$userhome/$readme\n";
      }
    }
  } elsif ($req->param('SUBMIT_pause99_delete_files_undelete')) {
    foreach my $f ($req->param('pause99_delete_files_FILE')) {
      my $sql = "DELETE FROM deletes WHERE deleteid = ?";
      $dbh->do(
	$sql, undef,
	"$userhome/$f"
      ) or warn sprintf "FAILED Query: %s/: %s", $sql, "$userhome/$f", $DBI::errstr;
    }
  }
  if ($blurb) {
    my $tf = Text::Format->new("firstIndent"=>0,);
    my @blurb = scalar $tf->format(sprintf(
                                    qq{According to a request entered by %s the
following files and the symlinks pointing to them have been scheduled
for deletion. They will expire after 72 hours and then be deleted by a
cronjob. Until then you can undelete them via
https://%s/pause/authenquery?ACTION=delete_files or
http://%s/pause/authenquery?ACTION=delete_files
},
                                    $mgr->{User}{fullname},
                                    $server,
                                    $server));
    push @blurb, $blurb;
    push @blurb, scalar $tf->format(qq{Note: to encourage deletions, all of past CPAN
glory is collected on http://history.perl.org/backpan/});
    push @blurb, qq{The Pause};
    # $blurb = Text::Format->new("firstIndent"=>0,)->paragraphs(@blurb);
    $blurb = join "\n", @blurb;

    my %umailset;
    my $name = $u->{asciiname} || $u->{fullname} || "";
    my $Uname = $mgr->{User}{asciiname} || $mgr->{User}{fullname} || "";
    if ($u->{secretemail}) {
      $umailset{qq{"$name" <$u->{secretemail}>}} = 1;
    } elsif ($u->{email}) {
      $umailset{qq{"$name" <$u->{email}>}} = 1;
    }
    if ($u->{userid} ne $mgr->{User}{userid}) {
      if ($mgr->{User}{secretemail}) {
        $umailset{qq{"$Uname" <$mgr->{User}{secretemail}>}} = 1;
      }elsif ($mgr->{User}{email}) {
        $umailset{qq{"$Uname" <$mgr->{User}{email}>}} = 1;
      }
    }
    $umailset{$PAUSE::Config->{ADMIN}} = 1;
    my @to = keys %umailset;
    my $header = {
                  Subject => "Files of $u->{userid} scheduled for deletion"
                 };
    $mgr->send_mail_multi(\@to,$header,$blurb);
  }

  my $submit_butts = qq{<input type="submit"
 name="SUBMIT_pause99_delete_files_delete" value="Delete" /><input type="submit"
 name="SUBMIT_pause99_delete_files_undelete" value="Undelete" />};
  push @m, $submit_butts;
  push @m, "<pre>";

  my %files = $self->manifind;
  my(%deletes,%whendele,$sth);
  if (
      $sth = $dbh->prepare(qq{SELECT deleteid, changed
                              FROM deletes
                              WHERE deleteid
                              LIKE ?})           #}
      and
      $sth->execute("$userhome/%")
      and
      $sth->rows
     ) {
    my $dhash;
    while ($dhash = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $dhash->{deleteid} =~ s/\Q$userhome\E\///;
      $deletes{$dhash->{deleteid}}++;
      $whendele{$dhash->{deleteid}} = $dhash->{changed};
    }
  }
  $sth->finish if ref $sth;

  require HTTP::Date;
  foreach my $f (keys %files) {
    unless (stat $f) {
      warn "ALERT: Could not stat f[$f]: $!";
      next;
    }
    my $blurb = $deletes{$f} ?
	$self->scheduled($whendele{$f}) :
	    HTTP::Date::time2str((stat _)[9]);
    $files{$f} = sprintf " %-50s %7d  %s", $f, -s _, $blurb;
  }

  chdir $cwd or die;

  my $field = $mgr->checkbox_group(
				    name      => 'pause99_delete_files_FILE',
				    'values'  => [sort keys %files],
				    linebreak => 'true',
				    labels    => \%files
				   );
  $field =~ s!<br />\s*!\n!gs;

  push @m, $field;
  push @m, "</pre>";
  push @m, $submit_butts;

  @m;
}

sub show_files {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my @m;
  my $u = $self->active_user_record($mgr);
  $mgr->prefer_post(1);
  require ExtUtils::Manifest;
  require HTTP::Date;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my $userhome = PAUSE::user2dir($u->{userid});
  push @m, qq{<h3>Files in directory authors/id/$userhome</h3>};
  require Cwd;
  my $cwd = Cwd::cwd();

  if (chdir "$PAUSE::Config->{MLROOT}/$userhome"){
    warn "DEBUG: MLROOT[$PAUSE::Config->{MLROOT}] userhome[$userhome] E:M:V[$ExtUtils::Manifest::VERSION]";
  } else {
    # QUICK DEPARTURE
    push @m, qq{No files found in authors/id/$userhome};
    return @m;
  }

  my $time = time;

  push @m, "<pre>";

  my %files = $self->manifind;

  my(%deletes,%whendele,$sth);
  if (
      $sth = $dbh->prepare(qq{SELECT deleteid, changed
                              FROM deletes
                              WHERE deleteid
                              LIKE ?})
      and
      $sth->execute("$userhome/%")
      and
      $sth->rows
     ) {
    my $dhash;
    while ($dhash = $mgr->fetchrow($sth, "fetchrow_hashref")) {
      $dhash->{deleteid} =~ s/\Q$userhome\E\///;
      $deletes{$dhash->{deleteid}}++;
      $whendele{$dhash->{deleteid}} = $dhash->{changed};
    }
  }
  $sth->finish if ref $sth;

  require HTTP::Date;
  foreach my $f (sort keys %files) {
    unless (stat $f) {
      warn "ALERT: Could not stat f[$f]: $!";
      next;
    }
    my $blurb = $deletes{$f} ?
	$self->scheduled($whendele{$f}) :
	    HTTP::Date::time2str((stat _)[9]);
    push @m, sprintf " %-50s %7d  %s<br/>", $f, -s _, $blurb;
  }

  chdir $cwd or die;

  push @m, "</pre>";

  @m;
}

sub scheduled {
  my $self = shift;
  my($when) = shift;
  my $time = time;
  my $expires = $when + ($PAUSE::Config->{DELETES_EXPIRE}
			 || 60*60*24*2);
  my $return = "Scheduled for deletion \(";
  $return .= $time < $expires ? "due at " : "already expired at ";
  $return .= HTTP::Date::time2str($expires);
  $return .= "\)";
  $return;
}

sub add_user_doit {
  my($self,$mgr,$userid,$fullname,$dont_clear) = @_;
  my $req = $mgr->{REQ};
  my $T = time;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my @m;
  my($query,$sth,@qbind);
  my($email) = $req->param('pause99_add_user_email');
  my($homepage) = $req->param('pause99_add_user_homepage');
  if ( $req->param('pause99_add_user_subscribe') gt '' ) {
    $query = qq{INSERT INTO users (
                      userid,          isa_list,             introduced,
                      changed,         changedby)
                    VALUES (
                      ?,               ?,                    ?,
                      ?,               ?)};
    @qbind = ($userid,1,$T,$T,$mgr->{User}{userid});
  } else {
    $query = qq{INSERT INTO users (
               	     userid,     email,    homepage,  fullname,
                     isa_list, introduced, changed,  changedby)
                    VALUES (
                     ?,          ?,        ?,         ?,
                     ?,        ?,          ?,        ?)};
    @qbind = ($userid,"CENSORED",$homepage,$fullname,"",$T,$T,$mgr->{User}{userid});
  }

  # We have a query for INSERT INTO users

  push @m, qq{<h3>Submitting query</h3>};
  if ($dbh->do($query,undef,@qbind)) {
    push @m, sprintf(qq{<p>Query succeeded.</p><p>Do you want to }.
                     qq{<a href="/pause/authenquery?pause99_add_m}.
                     qq{od_userid=%s;SUBMIT_pause99_add_mod_previ}.
                     qq{ew=preview">register a module for %s?</a></p>},
                     $userid,
                     $userid,
                    );
    my(@blurb);
    my($subject);
    my $need_onetime = 0;
    if ( $req->param('pause99_add_user_subscribe') gt '' ) {

      # Add a mailinglist: INSERT INTO maillists

      $need_onetime = 0;
      $subject = "Mailing list added to PAUSE database";
      my($maillistid) = $userid;
      my($maillistname) = $fullname;
      my($subscribe) = $req->param('pause99_add_user_subscribe');
      my($changed) = $T;
      push @blurb, qq{
Mailing list entered by };
      push @blurb, $mgr->{User}{fullname};
      push @blurb, qq{:

Userid:      $userid
Name:        $maillistname
Description: };
      push @blurb, $self->wrap($subscribe);
      $query = qq{INSERT INTO maillists (
                        maillistid, maillistname,
                        subscribe,  changed,  changedby,            address)
                      VALUES (
                        ?,          ?,
                        ?,          ?,        ?,                    ?)};
      my @qbind2 = ($maillistid,    $maillistname,
                    $subscribe,     $changed, $mgr->{User}{userid}, $email);
      unless ($dbh->do($query,undef,@qbind2)) {
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR => [qq{<p><b>Query[$query]with qbind2[@qbind2] failed.
 Reason:</b></p><p>$DBI::errstr</p>}]);
      }

    } else {

      # Not a mailinglist: Compose Welcome

      $subject = qq{Welcome new user $userid};
      $need_onetime = 1;
      # not for mailing lists
      if ($need_onetime) {

        my $onetime = sprintf "%08x", rand(0xffffffff);

        my $sql = qq{INSERT INTO $PAUSE::Config->{AUTHEN_USER_TABLE} (
                       $PAUSE::Config->{AUTHEN_USER_FLD},
                        $PAUSE::Config->{AUTHEN_PASSWORD_FLD},
                         secretemail,
                          forcechange,
                           changed,
                            changedby
                       ) VALUES (
                       ?,?,?,?,?,?
                       )};
        my $pwenc = PAUSE::Crypt::hash_password($onetime);
        my $dbh = $mgr->authen_connect;
        local($dbh->{RaiseError}) = 0;
        my $rc = $dbh->do($sql,undef,$userid,$pwenc,$email,1,time,$mgr->{User}{userid});
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR =>
                  [qq{<p><b>Query [$sql] failed. Reason:</b></p><p>$DBI::errstr</p>}.
                   qq{<p>This is very unfortunate as we have no option to rollback.}.
                   qq{The user is now registered in mod.users and could not be regi}.
                   qq{stered in authen_pause.$PAUSE::Config->{AUTHEN_USER_TABLE}</p>}]
                 ) unless $rc;
        $dbh->disconnect;
        my $otpwblurb = qq{

(This mail has been generated automatically by the Perl Authors Upload
Server on behalf of the admin $PAUSE::Config->{ADMIN})

As already described in a separate message, you\'re a registered Perl
Author with the userid $userid. For the sake of approval I have
assigned to you a change-password-only-password that enables
you to pick your own password. This password is \"$onetime\"
(without the enclosing quotes). Please visit

  https://pause.perl.org/pause/authenquery?ACTION=change_passwd

and use this password to initialize your account in the authentication
database. Once you have entered your password there, your one-time
password is expired automatically. If you cannot connect to the above
URL, you can replace 'https' with 'http', but then you are not using
SSL encryption. Be careful to always use an SSL connection if
possible, otherwise your password can be intercepted by third parties.

Thanks & Regards,
--
$PAUSE::Config->{ADMIN}
};

        my $header = {
                      Subject => $subject,
                     };
        warn "header[$header]otpwblurb[$otpwblurb]";
        $mgr->send_mail_multi([$email,$PAUSE::Config->{ADMIN}],
                              $header,
                              $otpwblurb);

      }

      @blurb = qq{
Welcome $fullname,

PAUSE, the Perl Authors Upload Server, has a userid for you:

    $userid

Once you\'ve gone through the procedure of password approval (see the
separate mail you should receive about right now), this userid will be
the one that you can use to upload your work or edit your credentials
in the PAUSE database.

This is what we have stored in the database now:

  Name:      $fullname
  email:     CENSORED
  homepage:  $homepage
  enteredby: $mgr->{User}{fullname}

Please note that your email address is exposed in various listings and
database dumps. You can register with both a public and a secret email
if you want to protect yourself from SPAM. If you want to do this,
please visit
  https://pause.perl.org/pause/authenquery?ACTION=edit_cred
or
  http://pause.perl.org/pause/authenquery?ACTION=edit_cred

If you need any further information, please visit
  \$CPAN/modules/04pause.html.
If this doesn't answer your questions, contact modules\@perl.org.

Before uploading your first module, we strongly encourage you to discuss
your module idea on PrePAN at http://prepan.org/ to get feedback from
experienced Perl developers.

Thank you for your prospective contributions,
The Pause Team
};

      my($memo) = $req->param('pause99_add_user_memo');
      push @blurb, "\nNote from $mgr->{User}{fullname}:\n$memo\n\n"
          if length $memo;
    }

    # both users and mailing lists run this code

    warn "DEBUG: UPLOAD[$PAUSE::Config->{UPLOAD}]";
    my(@to) = @{$PAUSE::Config->{ADMINS}};
    push @m, qq{ Sending separate mails to:
}, join(" AND ", @to, $email), qq{
<pre>
From: $PAUSE::Config->{UPLOAD}
Subject: $subject\n};

    my($blurb) = join "", @blurb;
    require HTML::Entities;
    my($blurbcopy) = HTML::Entities::encode($blurb,"<>");
    push @m, $blurbcopy, "</pre>\n";

    my $header = {
                  Subject => $subject
                 };
    $mgr->send_mail_multi(\@to,$header,$blurb);
    $blurb =~ s/\bCENSORED\b/$email/;
    $mgr->send_mail_multi([$email],$header,$blurb);

    unless ($dont_clear) {
      warn "Info: clearing all fields";
      for my $field (qw(userid fullname email homepage subscribe memo)) {
        my $param = "pause99_add_user_$field";
        $req->parameters->set($param,"");
      }
    }

  } else {
    push @m, sprintf(qq{<p><b>Query [$query] failed. Reason:</b></p><p>%s</p>\n},
                     $dbh->errstr);
  }
  push @m, "Content of user record in table <i>users</i>:<br />";
  my $usertable = $self->usertable($mgr,$userid);
  push @m, $usertable;
  @m;
}

sub get_secretemail {
  my($self, $mgr, $userid) = @_;
  my $dbh2 = $mgr->authen_connect;
  my $sth2 = $dbh2->prepare("SELECT secretemail
                             FROM $PAUSE::Config->{AUTHEN_USER_TABLE}
                             WHERE $PAUSE::Config->{AUTHEN_USER_FLD}=?");
  $sth2->execute($userid);
  my($h2) = $mgr->fetchrow($sth2, "fetchrow_array");
  $sth2->finish;
  $h2;
}

sub add_user {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my @m;

  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;

  if ($req->param("USERID")) {
    my $session = $mgr->session;
    my $s = $session->{APPLY};
    for my $a (keys %$s) {
      $req->parameters->set("pause99_add_user_$a" => $s->{$a});
      warn "retrieving from session a[$a]s(a)[$s->{$a}]";
    }
  }

  my $userid;
  if ( $userid = $req->param("pause99_add_user_userid") ) {

    $userid = uc($userid);
    $userid ||= "";
    my @error;
    if ( $userid !~ $Valid_Userid ) {
      my $euserid = $mgr->escapeHTML($userid);

      push @error, qq{<b>userid[$euserid]</b> does not match
          <b>$Valid_Userid</b>.};

    }

    $req->parameters->set("pause99_add_user_userid", $userid) if $userid;
    my $doit = 0;
    my $dont_clear;
    my $fullname_raw = $req->param('pause99_add_user_fullname');
    my($fullname);
    $fullname = $mgr->any2utf8($fullname_raw);
    warn "fullname[$fullname]fullname_raw[$fullname_raw]";
    if ($fullname ne $fullname_raw) {
      $req->parameters->set("pause99_add_user_fullname",$fullname);
      my $debug = $req->param("pause99_add_user_fullname");
      warn "debug[$debug]fullname[$fullname]";
    }
    unless ($fullname) {
      warn "no fullname";
      push @error, qq{No fullname, nothing done.};
    }
    unless (@error) {
      if ($req->param('SUBMIT_pause99_add_user_Definitely')) {
	$doit = 1;
      } elsif (
	       $req->param('SUBMIT_pause99_add_user_Soundex')
	       ||
	       $req->param('SUBMIT_pause99_add_user_Metaphone')
	      ) {

	# START OF SOUNDEX/METAPHONE check

	my ($surname);
	my($s_package) = $req->param('SUBMIT_pause99_add_user_Soundex') ?
	    'Text::Soundex' : 'Text::Metaphone';

	($surname = $fullname) =~ s/.*\s//;
	my $query = qq{SELECT userid, fullname, email, homepage,
			      introduced, changedby, changed
		       FROM   users
		       WHERE  isa_list=''
};
	my $sth = $dbh->prepare($query);
	$sth->execute;
	my $s_func;
	if ($s_package eq "Text::Soundex") {
	  require Text::Soundex;
	  $s_func = \&Text::Soundex::soundex;
	} elsif ($s_package eq "Text::Metaphone") {
	  require Text::Metaphone;
	  $s_func = \&Text::Metaphone::Metaphone;
	}
	my $s_code = $s_func->($surname);
	warn "s_code[$s_code]";
        my $requserid   = $req->param("pause99_add_user_userid")||"";
        my $reqfullname = $req->param("pause99_add_user_fullname")||"";
        my $reqemail    = $req->param("pause99_add_user_email")||"";
        my $reqhomepage = $req->param("pause99_add_user_homepage")||"";
	my($suserid,$sfullname, $spublic_email, $shomepage,
	   $sintroduced, $schangedby, $schanged);
        # if a user has a preference to display secret emails in a
        # certain color, they can enter it here:
        my %se_color_map = (
                            jv => "black",
                            andk => "#f33",
                           );
        my $se_color = $se_color_map{lc $mgr->{User}{userid}} || "red";
        my @urows;
	while (($suserid, $sfullname, $spublic_email, $shomepage,
		$sintroduced, $schangedby, $schanged) =
               $mgr->fetchrow($sth, "fetchrow_array")) {
	  (my $dbsurname = $sfullname) =~ s/.*\s//;
	  next unless $s_func->($dbsurname) eq $s_code;
          my @urow;
          my $score = 0;
          my $ssecretemail = $self->get_secretemail($mgr, $suserid);
	  push @urow, "<tr>";
          if (defined($suserid)&&length($suserid)) {
              my $duserid = $mgr->escapeHTML($suserid);
              if ($requserid eq $suserid) {
                  $duserid = "<b>$duserid</b>";
                  $score++;
              }
              push @urow, "<td>$duserid</td>";
          } else {
              push @urow, "<td>&#160;</td>";
          }
          {
              my($bold,$end_bold) = ("","");
              my $dfullname = $mgr->escapeHTML($sfullname);
              if ($sfullname eq $reqfullname) {
                  $dfullname = "<b>$dfullname</b>";
                  $score++;
              } elsif ($sfullname =~ /\Q$surname\E/) {
                  $dfullname =~ s|(\Q$surname\E)|<b>$1</b>|;
                  $score++;
              }
              if (defined($sfullname)&&length($sfullname)) {
                  push @urow, "<td>$bold$dfullname$end_bold</td>";
              } else {
                  push @urow, "<td>&#160;</td>";
              }
          }
          my $broken_spublic_email = $spublic_email;
          $broken_spublic_email =~ $mgr->escapeHTML($broken_spublic_email);
          $broken_spublic_email =~ s|@|<br/>@|;
          {
              my($bold,$end_bold) = ("","");
              if ($spublic_email eq $reqemail) {
                  ($bold,$end_bold) = ("<b>","</b>");
                  $score++;
              }
              push @urow, "<td>$bold$broken_spublic_email$end_bold</td>";
          }
          push @urow, "<td>";
          if ($ssecretemail) {
              my($bold,$end_bold) = ("","");
              if ($ssecretemail eq $reqemail) {
                  ($bold,$end_bold) = ("<b>","</b>");
                  $score++;
              }
              push @urow, "secret&#160;email:&#160;<span style='color: $se_color'>$bold$ssecretemail$end_bold</span><br/>";
          }
          if ($shomepage) {
              my($bold,$end_bold) = ("","");
              if ($shomepage eq $reqhomepage) {
                  ($bold,$end_bold) = ("<b>","</b>");
                  $score++;
              }
              push @urow, "homepage:&#160;$bold$shomepage$end_bold<br/>";
          }
          if ($sintroduced) {
            my $time = scalar(gmtime($sintroduced));
            $time =~ s/\s/\&#160;/g;
            push @urow, "introduced&#160;on:&#160;$time<br/>";
          }
          if ($schanged) {
            my $time = scalar(gmtime($schanged));
            $time =~ s/\s/\&#160;/g;
            push @urow, "changed&#160;on:&#160;$time&#160;by&#160;$schangedby<br/>";
          } else {
            push @urow, "changed&#160;by:&#160;$schangedby<br/>";
          }
          push @urow, "</tr>\n";
          my $line = join "", @urow;
          push @urows, { line => $line, score => $score };
	}
	if (@urows) {
          my @rows = map { $_->{line} } sort { $b->{score} <=> $a->{score} } @urows;
	  $doit = 0;
	  $dont_clear = 1;
	  unshift @rows, qq{
 <h3>Not submitting <i>$userid</i>, maybe we have a duplicate here</h3>
 <p>$s_package converted the fullname [<b>$fullname</b>] to [$s_code]</p>
 <table border="1">
 <tr><td>userid</td>
 <td>fullname</td>
 <td>(public) email</td>
 <td>other</td>
 </tr>
};
	  push @rows, qq{</table>\n};
	  push @m, @rows;
	} else {
	  $doit = 1;
	}

	# END OF SOUNDEX/METAPHONE check

      }
    }
    my $T = time;
    if ($doit) {
      push @m, $self->add_user_doit($mgr,$userid,$fullname,$dont_clear);
    } elsif (@error) {
      push @m, qq{<h3>Error processing form</h3>};
      for (@error) {
        push @m, "<ul>", "<li>$_</li>", "</ul>";
      }
      push @m, qq{<p>Please retry.</p>};
    } else {
      warn "T[$T]doit[$doit]userid[$userid]";
    }
  } else {
    warn "No userid, nothing done";
  }

  my $submit_butts = join("",
			  $mgr->submit(name=>"SUBMIT_pause99_add_user_Soundex",
				       value=>"  Insert with soundex care  "),
			  $mgr->submit(name=>"SUBMIT_pause99_add_user_Metaphone",
				       value=>"  Insert with metaphone care  "),
			  $mgr->submit(name=>"SUBMIT_pause99_add_user_Definitely",
				       value=>"  Insert most definitely  "));

  my $delete_link = sprintf(
      qq{<p>If this is a bad request: <a href="authenquery?ACTION=manage_id_requests;subaction=delete;USERID=%s">Delete the ID request</a></p>},
      $userid,
  );

  push(@m,
       qq{<h3>Add a user or mailinglist</h3>},
       $submit_butts,

       "<br />userid (entering lowercase is OK, but it will be
       uppercased by the server):<br />",

       $mgr->textfield(name=>"pause99_add_user_userid", size=>12, maxlength=>9),

       qq{<br />full name (mailinglist name):<br />},

       $mgr->textfield(name=>"pause99_add_user_fullname",
                       size=>50,
                       maxlength=>50),

       qq{<br />email address (for mailing lists this is the real
       address):<br />},

       $mgr->textfield(name=>"pause99_add_user_email",
                       size=>50,
                       maxlength=>50),

       qq{<br />homepage url (ignored for mailing lists):<br />},

       $mgr->textfield(name=>"pause99_add_user_homepage",
                       size=>50,
                       maxlength=>256),

       qq{<br />subscribe information if this user is a mailing list
       (leave blank for ordinary users):<br />},

       $mgr->textfield(name=>"pause99_add_user_subscribe",
                       size=>50,
                       maxlength=>256),
       qq{<br />},

       qq{<br />If you want to send a message to new author, please
       enter it here:<br />},

       $mgr->textarea(name=>"pause99_add_user_memo",
                      rows=>6,
                      cols=>60),
       qq{<br />},
       $submit_butts,
       qq{<br />},
       $delete_link,
      );

  @m;
}


sub usertable {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $userid = shift;
  my $req = $mgr->{REQ};
  my $dbh = $mgr->connect;
  my $sql = "SELECT * FROM users WHERE userid=?";
  my $sth = $dbh->prepare($sql);
  $sth->execute($userid);
  return unless $sth->rows == 1;
  my $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
  return $self->hash_as_table($rec);
}

sub hash_as_table {
  my($self,$rec) = @_;
  my @m;
  push @m, qq{<table border="1">};
  for my $k (sort keys %$rec) {
    push @m, sprintf(qq{<tr><td>%s</td><td>%s</td></tr>\n},
                     $k,
                     $rec->{$k} || "&#160;"
                    );
  }
  push @m, qq{</table>\n};
  join "", @m;
}

sub request_id {
  my pause_1999::edit $self = shift;
  my $mgr  = shift;

  my(@m);

  push @m, q{
    <p>A PAUSE account is only required to distribute and manage Perl module
    distributions on CPAN. You do not need a PAUSE account to submit
    bug reports to <a href="http://rt.cpan.org/">RT</a> or participate
    in many Perl community sites — please register a
    <a href="http://www.bitcard.org">Bitcard</a> account instead.</p>
  };

  my $req = $mgr->{REQ};
  $mgr->prefer_post(1);

  # first time: form
  # second time with error: error message + form
  # second time without error: OK message
  # bot debunked? => "Thank you!"

  my $showform = 0;
  my $regOK = 0;

  if ($req->param('url')) { # debunked
    return "Thank you!";
  }
  my $fullname  = $req->param( 'pause99_request_id_fullname') || "";
  my $ufullname = $mgr->any2utf8($fullname);
  if ($ufullname ne $fullname) {
    $req->parameters->set("pause99_request_id_fullname", $ufullname);
    $fullname = $ufullname;
  }
  my $email     = $req->param( 'pause99_request_id_email') || "";
  my $homepage  = $req->param( 'pause99_request_id_homepage') || "";
  my $userid    = $req->param( 'pause99_request_id_userid') || "";
  my $rationale = $req->param("pause99_request_id_rationale") || "";
  my $urat = $mgr->any2utf8($rationale);
  if ($urat ne $rationale) {
    $req->parameters->set("pause99_request_id_rationale", $urat);
    $rationale = $urat;
  }
  warn sprintf(
               "userid[%s]Valid_Userid[%s]args[%s]",
               $userid,
               $Valid_Userid,
               scalar($req->uri->query)||"",
              );

  if ( $req->param("SUBMIT_pause99_request_id_sub") ) {
    # check for errors

    my @errors = ();
    if ( $fullname ) {
      unless ($fullname =~ /[ ]/) {
        push @errors, "Name does not look like a full civil name. Please accept our apologies if you believe we're wrong. In this case please write to @{$PAUSE::Config->{ADMINS}}.";
      }
    } else {
      push @errors, "You must supply a name\n";
    }
    unless( $email ) {
      push @errors, "You must supply an email address\n";
    }
    if ( $rationale ) {

      $rationale =~ s/^\s+//;
      $rationale =~ s/\s+$//;
      $rationale =~ s/\s+/ /;
      push @errors, "Thank you for giving us a short description of
        what you're planning to contribute, but frankly, this looks a
        bit too short" if length($rationale)<10;
      push @errors, "Please do not use HTML links in your description of
        what you're planning to contribute" if $rationale =~ /<\s*a\s+href\s*=/ims;

      my $url_count =()= $rationale =~ m{https?://}gi;
      push @errors, "Please do not include more than one URL in your description of
        what you're planning to contribute" if $url_count > 1;

    } else {

      push @errors, "You must supply a short description of what
        you're planning to contribute\n";

    }
    if ( $userid ) {
      $userid = uc $userid;
      $req->parameters->set('pause99_request_id_userid', $userid);
      my $db = $mgr->connect;
      my $sth = $db->prepare("SELECT userid FROM users WHERE userid=?");
      $sth->execute($userid);
      warn sprintf("userid[%s]Valid_Userid[%s]matches[%s]",
                   $userid,
                   $Valid_Userid,
                   $userid =~ $Valid_Userid || "",
                  );
      if ($sth->rows > 0) {
        my $euserid = $mgr->escapeHTML($userid);
        push @errors, "The userid $euserid is already taken.";
      } elsif ($userid !~ $Valid_Userid) {
        my $euserid = $mgr->escapeHTML($userid);
        push @errors, "The userid $euserid does not match $Valid_Userid.";
      }
      $sth->finish;
    } else {
      push @errors, "You must supply a desired user-ID\n";
    }

    if( @errors ) {
      push @m, qq{<h3>Error processing form</h3>};
      for (@errors) {
        push @m, "<ul>", "<li>$_</li>", "</ul>";
      }
      push @m, qq{<p>Please retry.</p>};
      $showform = 1;
    } else {
      $regOK = 1;
    }
  } else {
    $showform = 1;
  }
  if ($showform) {
    my $alt = 0;
    # push @m, "<table>\n";
    foreach my $arr (
                     {
                      topic => 'Your full name (civil name)',
                      fname => 'pause99_request_id_fullname',

                      fcomment => "Unicode Characters OK.",
                      footnote => "Note: PAUSE has been developed in a
      time when it was more common than today that people have names
      consisting of at least a first name and a second name, like
      <i>Ben Cartwright</i> or <i>Tony Nelson</i>, you get the idea.
      This field is considered to be filled with both names, separated
      by a space. This trivial expectation was then coded into the
      server side sanity check of this form and it turned out to be a
      super efficient spam protection because bots often did not try
      to enter a space in the middle of the field. It was about the
      year 2003 when people started to complain that they had tried
      <i>Peter</i> and it did not work. Poor Peter, please remember
      you <b>do</b> have a second name.",

                     },
                     {
                      topic => 'Email',
                      fname => 'pause99_request_id_email',
                      fcomment => 'required, otherwise we cannot send you the password',
                     },
                     {
                      topic => 'Web site',
                      fname => 'pause99_request_id_homepage',
                      fcomment => 'optional'
                     },
                     {
                      topic => 'Desired ID',
                      fname => 'pause99_request_id_userid',
                      fcomment => "3-9 characters matching [A-Z], please",

                     },
                    ) {
      $alt ^= 1;
      my $altname = $alt ? "alternate1" : "alternate2";
      push @m, qq{<div class="$altname"><p><b>$arr->{topic}</b></p><p>};
      if (my $note = $arr->{fcomment}) {
        push @m, qq{<small>$note</small></p><p>};
      }
      push @m, $mgr->textfield( name => $arr->{fname}, size => 32 );
      if (my $note = $arr->{footnote}) {
        push @m, qq{</p><div style='font-size:0.75em'>$note</div><p>};
      }
      push @m, "</p></div>";
    }

    push @m, qq{<p><b>A short description of why you would like a
          PAUSE ID:</b></p><p><small>required; include what you are planning to contribute; do not use HTML</small></p><p>};

    push @m, $mgr->textarea(name=>"pause99_request_id_rationale",
                            rows=>8,
                            cols=>60);
    push @m, q{<!-- zdjela meda -->
  <div style="visibility:hidden;">If you're a bot, then type something in here: <input name="url" size="1"/></div>};
    push @m, qq{</p>};
    # push @m, "</table>\n";

    push @m, qq{<input type="submit" name="SUBMIT_pause99_request_id_sub"
  	  value="Request Account" />};

  }
  if ($regOK) {

    my @to = $mgr->{MailtoAdmins};
    push @to, $email;
    my $time = time;
    push @m, qq{ Sending mail to: @to};
    if ($rationale) {
      # wrap it
      $rationale =~ s/\r\n/\n/g;
      $rationale =~ s/\r/\n/g;
      my @rat = split /\n\n/, $rationale;
      my $tf = Text::Format->new( bodyIndent => 4, firstIndent => 5);
      $rationale = $tf->paragraphs(@rat);
      $rationale =~ s/^\s{5}/\n    /gm;
    }

    my $session = $mgr->session;
    $session->{APPLY} = {
                         fullname => $fullname,
                         email => $email,
                         homepage => $homepage,
                         userid => $userid,
                         rationale => $rationale,
                        };
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$session->{APPLY}],[qw(APPLY)])->Indent(1)->Useqq(1)->Dump; # XXX
    if (lc($fullname) eq lc($userid)) {
      die "fullname looks like spam";
    }
    if (my @x = $rationale =~ /(\.info)/g) {
      die "rationale looks like spam" if @x >= 5;
    }
    if (my @x = $rationale =~ m|(http://)|g) {
      die "rationale looks like spam" if @x >= 5;
    }
    if ($rationale =~ /interesting/i && $homepage =~ m|http://[^/]+\.cn/.+\.htm$|) {
      die "rationale looks like spam";
    }
    my $sessionID = $mgr->userid;
    my $host = "https://pause.perl.org";
    # $host = "http://k242.linux.bogus" if $PAUSE::Config->{TESTHOST};
    my $blurb = <<"MAIL";
Request to register new user

fullname: $fullname
  userid: $userid
    mail: CENSORED
homepage: $homepage
     why:
$rationale

The following links are only valid for PAUSE maintainers:

Registration form with editing capabilities:
  $host/pause/authenquery?ACTION=add_user&USERID=$sessionID&SUBMIT_pause99_add_user_sub=1
Immediate (one click) registration:
  $host/pause/authenquery?ACTION=add_user&USERID=$sessionID&SUBMIT_pause99_add_user_Definitely=1
MAIL
    my $subject = "PAUSE ID request ($userid; $fullname)";
    my $header = {
  	To      => $email,
  	Subject => $subject,
  	};

    require HTML::Entities;
    my($blurbcopy) = HTML::Entities::encode($blurb,qq{<>&"});
    $blurbcopy =~ s{(
                     https?://
                     [^"'<>\s]+     # arbitrary exclusions, we had \S there,
                                    # but it broke too often
                    )
                   }{<a href=\"$1\">$1</a>}xg;
    $blurbcopy =~ s|(>http.*?)U|$1\n    U|gs; # break the long URL
    push @m, qq{<pre>
From: $PAUSE::Config->{UPLOAD}
Subject: $subject

$blurbcopy
</pre>
<hr noshade="noshade" />
}; #};
    $header = {
               Subject => $subject
              };
    warn "To[@to]Subject[$header->{Subject}]";
    $mgr->send_mail_multi(\@to,$header,$blurb);
  }

  return @m;
}

sub mailpw {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m,$param,$email);
  my $req = $mgr->{REQ};

  # TUT: We reach this point in the code only if the Querystring
  # specified ACTION=mailpw or something equivalent. The parameter ABRA
  # is used to denote the token that we might have sent them.
  my $abra = $req->param("ABRA") || "";
  push @m, qq{<input type="hidden" name="ABRA" value="$abra" />};

  # TUT: The parameter pause99_mailpw_1 denotes the userid of the user
  # for whom a password change was requested. Note that anybody has
  # access to that parameter, we do not authentify its origin. Of
  # course not, because that guy says he has lost the password:-) If
  # this parameter is there, we are asked to send a token. Otherwise
  # they only want to see the password-requesting form.
  $param = $req->param("pause99_mailpw_1");
  if ( $param ) {
    $param = uc($param);
    unless ($param =~ /^[A-Z\-]+$/) {
      if ($param =~ /@/) {
        die PAUSE::HeavyCGI::Exception->new(ERROR =>
                                             qq{Please supply a userid, not an email address.});
      }
      die PAUSE::HeavyCGI::Exception->new(ERROR =>
                                           sprintf qq{A userid of <i>%s</i>
 is not allowed, please retry with a valid userid. Nothing done.}, $mgr->escapeHTML($param));
    }

    # TUT: The object $mgr is our knows/is/can-everything object. Here
    # it connects us to the authenticating database
    my $authen_dbh = $mgr->authen_connect;
    my $sql = qq{SELECT *
                 FROM usertable
                 WHERE user = ? };
    my $sth = $authen_dbh->prepare($sql);
    $sth->execute($param);
    my $rec = {};
    if ($sth->rows == 1) {
      $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
    } else {
      my $u;
      eval {
        $u = $self->active_user_record($mgr,$param);
      };
      if ($@) {
        die PAUSE::HeavyCGI::Exception->new(ERROR =>
                                             qq{Cannot find a userid
                                             of <i>$param</i>, please
                                             retry with a valid
                                             userid.});

      } elsif ($u->{userid} && $u->{email}) {
        # this is one of the 94 users (counted on 2005-01-05) that has
        # a users record but no usertable record
        $sql = qq{INSERT INTO usertable (user,secretemail,forcechange,changed)
                                 VALUES (?,   ?,          1,          ?)};

        $authen_dbh->do($sql,{},$u->{userid},$u->{email},time)
            or die PAUSE::HeavyCGI::Exception->new(ERROR =>
                                                    qq{The userid of <i>$param</i>
 is too old for this interface. Please get in touch with administration.});

        $rec->{secretemail} = $u->{email};
      } else {
        die PAUSE::HeavyCGI::Exception->new(ERROR =>
                                             qq{A userid of <i>$param</i>
 is not known, please retry with a valid userid.});
      }
    }

    # TUT: all users may have a secret and a public email. We pick what
    # we have.
    unless ($email = $rec->{secretemail}) {
      my $u = $self->active_user_record($mgr,$param,{hidden_user_ok => 1});
      require YAML::Syck; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . YAML::Syck::Dump({u=>$u}); # XXX

      $email = $u->{email};
    }
    if ($email) {

      # TUT: Before we insert a record from that table, we remove old
      # entries so the primary key of an old record doesn't block us now.
      $sql = sprintf qq{DELETE FROM abrakadabra
                        WHERE NOW() > expires};
      $authen_dbh->do($sql);

      my $passwd = sprintf "%08x" x 4, rand(0xffffffff), rand(0xffffffff),
	  rand(0xffffffff), rand(0xffffffff);
      # warn "pw[$passwd]";
      my $then = time + $PAUSE::Config->{ABRA_EXPIRATION};
      $sql = sprintf qq{INSERT INTO abrakadabra
                        ( user, chpasswd, expires )
                  VALUES
                        ( ?, ?, from_unixtime(?) ) };
      local($authen_dbh->{RaiseError}) = 0;
      if ( $authen_dbh->do($sql,undef,$param,$passwd,$then) ) {
      } elsif ($authen_dbh->errstr =~ /Duplicate entry/) {
        my $duration;
        if ($HAVE_TIME_DURATION) {
          $duration = Time::Duration::duration($PAUSE::Config->{ABRA_EXPIRATION});
        } else {
          $duration = sprintf "%d seconds", $PAUSE::Config->{ABRA_EXPIRATION};
        }
	die PAUSE::HeavyCGI::Exception->new
            (
             ERROR => sprintf(
                              qq{A token for <i>$param</i> that allows
                  changing of the password has been requested recently
                  (less than %s ago) and is still valid. Nothing
                  done.},
                              $duration,
                             ),
            );
      } else {
	die PAUSE::HeavyCGI::Exception->new(ERROR => $authen_dbh->errstr);
      }

      # TUT: a bit complicated only because we switched back and forth
      # between Apache::URI and URI::URL
      my $myurl = $mgr->myurl;
      my $me;
      if ($myurl->can("unparse")) {
        $me = $myurl->unparse;
        $me =~ s/\?.*//;
      } else {
        $me = $myurl->as_string;
      }
      $me =~ s/^http:/https:/; # do not blindly inherit the schema
      my $mailblurb = qq{

(this an automatic mail sent by a program because somebody asked for
it. If you did not intend to get it, please let us know and we will
take more precautions to prevent abuse.)

Somebody, probably you, has visited the URL

    $me?ACTION=mailpw

and asked that you, "$param", should get a token that enables the
setting of a new password. Here it is (please watch out for line
wrapping errors of your mail reader and other cut and paste errors,
this URL must not contain any spaces):

    $me?ACTION=change_passwd;ABRA=$param.$passwd

Please visit this URL, it should open you the door to a password
changer that lets you set a new password for yourself. This token
will expire within a few hours. If you don't need it, do nothing. By
the way, your old password is still valid.

$Yours};
      my $header = { Subject => "Your visit at $me" };
      warn "mailto[$email]mailblurb[$mailblurb]";
      $mgr->send_mail_multi([$email], $header, $mailblurb);

      push @m, qq{

 <p>A token to change the password for <i>$param</i> is on its way to its
 owner. Should the mail not arrive, please tell us.</p>

};
      return @m; # no need to repeat form

    } else {
      push @m, sprintf qq{

 <p>We have not found the email of <i>$param</i>. Please try with a different
 name or mail to the administrator directly.</p>

};

    }
    return @m;
  }

  # TUT: First time here, send them the password requesting form
  push @m, qq{

<p>This form lets you request a token that enables you to set a new
password. It only operates correctly if the database knows you and
your email adress. Please fill in your userid on the CPAN. The token
will be mailed to that userid.</p>

};
  push @m, $mgr->textfield(name => "pause99_mailpw_1",
			   size => 32);
  push @m, qq{
<input type="submit" name="pause99_mailpw_sub" value="OK" />
};
  @m;
}

sub edit_ml {
  my pause_1999::edit $self = shift;

  my $mgr = shift;
  my(@m);
  push @m, q{
Excerpt from a mail:<pre>

   From: andreas.koenig@anima.de (Andreas J. Koenig)
   To: kstar@chapin.edu
   Subject: Re: [elagache@ipn.caida.org: No email found for CAIDA? (Re: Missing CAIDA password?)]
   Date: 02 Nov 2000 17:59:28 +0100

   A mailing list occupies the same namespace as users because we do
   not want that users and mailing lists get confused. But a mailing
   list does not have a password and does not have a directory of its
   own. Only people can upload and occupy a directory and have a
   password. (It's clear that the user namespace is not related to the
   modules namespace, right?)

   The Module List may list a mailinglist as "the contact", so the
   field userid in the table mods identifies either a mailing list or
   a user. This has been useful in the past when several clueful
   people represent several related modules and use a common mailing
   list as the contact.

   The table list2user maps mailing lists to their owners so that the
   owners can edit the data associated with the mailing list like
   address and comment. The table list2user does not have a web
   interface because we are not really established as the primary
   source for mailing list information and so it has not been used
   much. But I'm open to offer one if you believe it's useful.
   [...]
</pre>
};

  my $req = $mgr->{REQ};
  my $selectedid = "";
  my $selectedrec = {};
  my $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  my $param;
  if ($param = $req->param("pause99_edit_ml_3")) {  # upper selectbox
    $selectedid = $param;
  } elsif ($param = $req->param("HIDDENNAME")) {
    $selectedid = $param;
    $req->parameters->set("pause99_edit_ml_3",$param);
  }
  warn sprintf(
	       "selectedid[%s]IsMR[%s]",
	       $selectedid,
	       join(":",
		    keys(%{$mgr->{IsMailinglistRepresentative}})
		   )
	      );
  my($sql,@bind);
  if (exists $mgr->{IsMailinglistRepresentative}{$selectedid}) {
    $sql = qq{SELECT users.userid
              FROM   users JOIN list2user
                           ON   users.userid = list2user.maillistid
              WHERE  users.isa_list > ''
                 AND list2user.userid = ?
              ORDER BY users.userid
};
    @bind = $mgr->{User}{userid};
  } else {
    $sql = qq{SELECT userid FROM users WHERE isa_list > '' ORDER BY userid};
    @bind = ();
  }
  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);
  my @all_mls;
  my %mls_lab;
  if ($sth->rows) {
    my $sth2 = $dbh->prepare(qq{SELECT * FROM maillists WHERE maillistid=?});
    while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
      # register this mailinglist for the selectbox
      push @all_mls, $id;
      # query for more info about it
      $sth2->execute($id);
      my($rec) = $mgr->fetchrow($sth2, "fetchrow_hashref");
      # we will display the name along the ID
      $mls_lab{$id} = "$id ($rec->{maillistname})";
      if ($id eq $selectedid) {
	# if this is the selected one, we just store it immediately
	$selectedrec = $rec;
      }
    }
  }
  my $size = @all_mls > 8 ? 5 : scalar(@all_mls);
  push @m, $mgr->scrolling_list(
				'name' => "pause99_edit_ml_3",
				'values' => \@all_mls,
				'labels' => \%mls_lab,
				'size' => $size,
				);
  push @m, qq{<br /><input type="submit"
 name="pause99_edit_ml_2" value="Select" /><br />};
  if ($selectedid) {
    push @m, qq{<h3>Record for $selectedrec->{maillistid}</h3>\n};
    my @m_mlrec;
    my $force_sel = $req->param('pause99_edit_ml_2');
    my $update_sel = $req->param('pause99_edit_ml_4');
    my %meta = (
		maillistname => {

                                 headline => "The name of the mailing list",

                                 note => "The name appears in the CPAN
                                     authors list, so it is good if
                                     the name contains the term
                                     <i>mailing list</i> or something
                                     equivalent",

				 type => "textfield",
				 args => {
					  size => 50,
                                          maxsize => 64,
					 }
				},
		address      => {

                                 headline => "The address of the
                                     mailing list",

                                 note => "This is the address where
                                     people post to (where all members
                                     of the group can be contacted)",

				 type => "textfield",
				 args => {
					  size => 50,
					 }
				},
		subscribe    => {
                                 headline => "How to subscribe",

                                 note => "This is a text that
                                     describes how to join the mailing
                                     list. E.g. the mailing list
                                     subscribe address or a URL with
                                     more details.",

				 type => "textarea",
				 args => {
					  rows => 5,
					  cols => 60,
					 }
				},
	       );
    my $mailblurb = qq{Record update in the PAUSE mailinglists database:

};
    my($mailsprintf1,$mailsprintf2,$saw_a_change);
    $mailsprintf1 = "%12s: [%s]%s";
    $mailsprintf2 = " was [%s]\n";
    my $now = time;

    $mailblurb .= sprintf($mailsprintf1, "userid", $selectedrec->{maillistid}, "\n");

    for my $field (qw(maillistname address subscribe)) {
      my $headline = $meta{$field}{headline} || $field;
      my $note     = $meta{$field}{note};
      push @m_mlrec, sprintf qq{<p><b>%s</b></p>}, $headline;
      push @m_mlrec, sprintf qq{<p><small>%s</small></p>}, $note if $note;
      my $fieldtype = $meta{$field}{type};
      my $fieldname = "pause99_edit_ml_$field";
      if ($force_sel){
	$req->parameters->set($fieldname, $selectedrec->{$field}||"");
      } elsif ($update_sel) {
	my $param = $req->param($fieldname);
	if ($param ne $selectedrec->{$field}) {
	  $mailblurb .= sprintf($mailsprintf1,
				$field,
				$param,
			        sprintf($mailsprintf2,$selectedrec->{$field})
			       );
	  my $sql = qq{UPDATE maillists
                       SET $field=?,
                           changed=?,
                           changedby=?
                       WHERE maillistid=?};
	  my $usth = $dbh->prepare($sql);
	  my $ret = $usth->execute($param, $now, $u->{userid}, $selectedrec->{maillistid});
	  $saw_a_change = 1 if $ret > 0;
	  $usth->finish;
	} else {
	  $mailblurb .= sprintf($mailsprintf1, $field, $selectedrec->{$field}, "\n");
	}
      }
      push @m_mlrec, $mgr->$fieldtype(
				'name' => $fieldname,
				'value' => $selectedrec->{$field},
				%{$meta{$field}{args} || {}}
			       );
      push @m_mlrec, qq{<br />\n};
    }
    push @m_mlrec, qq{<input type="submit"
 name="pause99_edit_ml_4" value="Update" /><br />};

    if ($saw_a_change) {
      push @m, "<p>The record has been updated in the database</p>";
      $mailblurb .= qq{
Data entered by $mgr->{User}{fullname}.
Please check if they are correct.

$Yours};
      my @to = ($u->{secretemail}||$u->{email}, $mgr->{MailtoAdmins});
      warn "sending to[@to]";
      warn "mailblurb[$mailblurb]";
      my $header = {
                    Subject => "Mailinglist update for $selectedrec->{maillistid}"
                   };
      $mgr->send_mail_multi(\@to, $header, $mailblurb);
    } elsif ($update_sel) { # it should have been updated but wasn't?

      push @m, "<p>It seems to me the record was NOT updated. Maybe
nothing changed? Please take a closer look and inform an admin if
things didn't proceed as expected.</p>";

    }
    push @m, @m_mlrec;
  }
  @m;
}

sub edit_mod {
  my $self = shift;
  my $mgr = shift;
  $mgr->prefer_post(0);
  my(@m);
  my $req = $mgr->{REQ};
  my $selectedid = "";
  my $selectedrec = {};
  my $u = $self->active_user_record($mgr);
  my @to = $mgr->{MailtoAdmins};
  if ($u->{cpan_mail_alias} =~ /^(publ|secr)$/
      &&
      time - ($u->{introduced}||0) > 86400
     ) {
    $to[0] .= sprintf ",%s\@cpan.org", lc $u->{userid};
    # warn qq{Prepared to send mail to: @to};
  } else {
    # we have nothing else, so we must send separate mail
    my $user_email = $u->{secretemail};
    $user_email ||= $u->{email};
    push @to, $user_email if $user_email;
    warn qq{Prepared to send separate mails to: }, join(" AND ",
                                                    map { "[$_]" } @to);
  }

  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  if (my $param = $req->param("pause99_edit_mod_3")) { # upper selectbox
    $selectedid = $param;
  }

  push @m, qq{

            <p>The select box shows all the modules that have been
            registered for user <b>$u->{userid}</b> officially via
            modules\@perl.org, i.e. that are included (or about to be
            included) in the module list.</p><p>If you are missing a
            module of yours, maybe you have never registered it?
            Consider registering and visit the <a
            href="?ACTION=apply_mod">Register Namespace page</a>. If
            you are missing certain other pieces, please let
            modules\@perl.org know, see <a href=
            "http://www.cpan.org/modules/04pause.html">modules/04pause.html
            on CPAN</a> for details.</p><p>You can edit the infos
            stored in the database on this page. The changes you make
            will take effect when the next module list will be
            released. Thank you for your help!</p>

};

  my $dbh = $mgr->connect;
  if (0) {
    warn sprintf(
                 "selectedid[%s]IsMailinglistRepr[%s]",
                 $selectedid,
                 join(":",
                      keys(%{$mgr->{IsMailinglistRepresentative}})
                     )
                );
  }
  my($sth);
  if ($selectedid and exists $mgr->{IsMailinglistRepresentative}{$selectedid}) {
    my $sql = qq{SELECT modid
              FROM mods, list2user
                ON mods.userid = list2user.maillistid
              WHERE mods.userid=?
                AND list2user.userid = ?
              ORDER BY modid};
    my @bind = ($selectedid, $mgr->{User}{userid});
    $sth = $dbh->prepare($sql);
    my $ret = $sth->execute(@bind);
  } else {
    my $sql = qq{SELECT modid
              FROM mods
              WHERE userid=?
              ORDER BY modid};
    my @bind = $u->{userid};
    $sth = $dbh->prepare($sql);
    my $ret = $sth->execute(@bind);
  }
  my @all_mods;
  my $is_only_one;
  if (my $rows = $sth->rows) {
    while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
      # register this mailinglist for the selectbox
      push @all_mods, $id;
      if ($rows == 1) {
	# if this is the selected one, we just store it immediately
	$selectedid = $id;
        $is_only_one++;
      }
      if ($id eq $selectedid) {
        my $sth2 = $dbh->prepare(qq{SELECT *
                                FROM mods
                                WHERE modid=?
                                  AND userid=?});
        $sth2->execute($id,$u->{userid});
        my($rec) = $mgr->fetchrow($sth2, "fetchrow_hashref");
	$selectedrec = $rec;
      }
    }
  }
  my $all_mods = scalar @all_mods;
  my $size = $all_mods > 8 ? 5 : $all_mods;
  unless ($size) {

    push @m, qq{<p>Sorry, there are no modules registered belonging to
                $u->{userid}. Please note, only modules that are
                already registered in the module list can be edited
                here. If you believe, this is a bug, please contact
                @{$PAUSE::Config->{ADMINS}}.</p> };

    return @m;
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_edit_mod_3",
				'values' => \@all_mods,
				'size' => $size,
			       );

  push @m, qq{<input type="submit" name="pause99_edit_mod_2" value="Select" /><br />};
  if ($selectedid) {
    push @m, $self->_edit_mod_selected($mgr,\@to,$selectedrec,$u,$is_only_one);
  }

  @m;
}

sub _edit_mod_selected {
  my($self,$mgr,$to,$selectedrec,$u,$is_only_one) = @_;
  my @m;
  my $req = $mgr->{REQ};
  my @to = @$to;
  my $dbh = $mgr->connect;
  push @m, qq{<h3>Record for $selectedrec->{modid}</h3><p>More
        about the meaning of the DSLIP status in the <a href=
        "http://www.cpan.org/modules/00modlist.long.html#1)ModuleListing">module
        list</a>. To delete, add or rename an entry, mail to
        modules\@perl.org.</p>};

  my @m_modrec;
  my $force_sel = $req->param('pause99_edit_mod_2');
    # || $is_only_one;
    my $update_sel = $req->param('pause99_edit_mod_4');

    my(@stat_meta) = $self->stat_meta;
    my(@chap_meta) = $self->chap_meta($mgr);
    my(@desc_meta) = $self->desc_meta;

    my %meta = (
                @stat_meta,
                @desc_meta,
		userid => {
		           type => "textfield",
			   headline => "CPAN User-ID",

			   note => "If you change the userid, you will
        			   lose control over the module and
        			   the other userid will become the
        			   owner. That's a one way move, take
        			   care!",

			   args => {
				    size => 12,
				    maxlength => 9,
				   },
			  },
                mlstatus => {
                             type => "scrolling_list",
                             headline => "Lifecycle",

                             note => "Select one of <i>list</i>,
                                     <i>hide</i>, or <i>delete</i>,
                                     normal case is of course
                                     <i>list</i>. Select <i>delete</i>
                                     only if the module definitely has
                                     gone for some time. If the module
                                     has no public relevance and is
                                     not needed in the module list or
                                     if it is abandoned but might have
                                     a revival some day, maybe by
                                     being claimed by another author,
                                     please keep it for a while as
                                     <i>hide</i>.",

                             args => {
                                      size => 1,
                                      values => [qw(list hide delete)],
                                      labels =>
                                      {
                                       list  => "List in Module List",
                                       hide  => "Hide from modulelist, but keep in database",
                                       delete=> "Can be deleted from database",
                                      },
                                     }
                            },
                @chap_meta,
	       );
    my $mailblurb = qq{Record update in the PAUSE modules database:

};
    my($mailsprintf1,$mailsprintf2,$saw_a_change);
    $mailsprintf1 = "%12s: [%s]%s";
    $mailsprintf2 = " was [%s]\n";
    my $now = time;
    $mailblurb .= sprintf($mailsprintf1, "modid", $selectedrec->{modid}, "\n");

    my $alter = 0;
    for my $field (qw(
statd
stats
statl
stati
statp
description
userid
chapterid
mlstatus
)) {
      my $headline = $meta{$field}{headline} || $field;
      my $note = $meta{$field}{note} || "";
      $alter ^= 1;
      my $alterclass = $alter ? "alternate1" : "alternate2";
      push @m_modrec, qq{\n<div class="$alterclass"><h4>$headline</h4>};
      push @m_modrec, qq{<small>$note</small><br />} if $note;
      my $fieldtype = $meta{$field}{type};
      my $fieldname = "pause99_edit_mod_$field";
      if ($field =~ /^stat/) { # there are many blanks instead of
                               # question marks, I believe
        if (0) {
          warn sprintf(
                       "field[%s]value[%s]mfals[%s]",
                       $field,
                       $selectedrec->{$field},
                       $meta{$field}{args}{labels}{$selectedrec->{$field}},
                      );
        }
        $selectedrec->{$field} = "?" unless exists
            $meta{$field}{args}{labels}{$selectedrec->{$field}};
      } elsif ($field eq "chapterid") {
        die "chapterid not integer" if $strict_chapterid &&
            $selectedrec->{$field} !~ /^\d*$/;
      }
      if ($force_sel) {
	$req->parameters->set($fieldname, $selectedrec->{$field}||"");
      } elsif ($update_sel) {
	my $param = $req->param($fieldname);
        my $uparam = $mgr->any2utf8($param);
        if ($uparam ne $param) {
          $req->parameters->set($fieldname,$uparam);
          $param = $uparam;
        }
	if ($param ne $selectedrec->{$field}) {
          if ($field eq "userid") {
            # die if the user doesn't exist
            my $ucparam = uc $param;
            unless ($ucparam eq $param) {
              $param = $ucparam;
              $req->parameters->set($fieldname, $param);
            }
            my $nu = $self->active_user_record($mgr, $param, {checkonly => 1});

            die PAUSE::HeavyCGI::Exception
                ->new(ERROR => sprintf("Unknown user[%s]",
                                       $param,
                                      )) unless
                      $nu->{userid} eq $param;

            # add the new user to @to
            if ($nu->{cpan_mail_alias} =~ /^(publ|secr)$/
                &&
                time - ($nu->{introduced}||0) > 86400
               ) {
              $to[0] .= sprintf ",%s\@cpan.org", lc $nu->{userid};
              push @m, qq{ Sending mail to: @to};
            } else {
              # we have nothing else, so we must send separate mail
              my $nuser_email = $nu->{secretemail};
              $nuser_email ||= $nu->{email};
              push @to, $nuser_email if $nuser_email;
              push @m, qq{ Sending separate mails to: }, join(" AND ",
                                                              map { "[$_]" } @to);
            }
            # Now also update primeur table. We can do that with an
            # update. If the record does not exist, we don't need it
            # updated anyway
            my $query = "UPDATE primeur SET userid=? WHERE package=? AND userid=?";
            my $ret = $dbh->do($query,{},$nu->{userid},$selectedrec->{modid},$u->{userid});
            $ret ||= 0;
            warn "INFO: Updated primeur with $nu->{userid},$selectedrec->{modid},$u->{userid} and ret[$ret]";
          } elsif ($field eq "description") {
            # Truncate if necessary, the database won't do it anymore
            substr($param,44) = "" if length($param)>44;
          } elsif ($field eq "chapterid") {
            die "param not integer" if $strict_chapterid &&
                ($selectedrec->{$field} !~ /^\d*$/ || $param !~ /^\d*$/);
          }
	  $mailblurb .= sprintf($mailsprintf1,
				$field,
				$param,
				sprintf($mailsprintf2,$selectedrec->{$field})
			       );

	  my $sql = qq{UPDATE mods
                       SET $field=?,
                           changed=?,
                           changedby=?
                       WHERE modid=?};

	  my $usth = $dbh->prepare($sql);
	  my $ret = $usth->execute($param,
				   $now,
				   $mgr->{User}{userid},
				   $selectedrec->{modid});

	  $saw_a_change = 1 if $ret > 0;
	  $usth->finish;

	} else {

          if ($field eq "chapterid") {
            die "illegal chapterid. selectedrec/field[$selectedrec->{$field}]".
                "param[$param]"
                    if $strict_chapterid &&
                        ($selectedrec->{$field} !~ /^\d*$/ || $param !~ /^\d*$/);
          }
	  $mailblurb .= sprintf($mailsprintf1,
                                $field,
                                $selectedrec->{$field},
                                "\n"
                               );
	}
      } elsif ($is_only_one) {
        # as if they had selected it already
	$req->parameters->set($fieldname, $selectedrec->{$field}||"");
      }
      push @m_modrec, $mgr->$fieldtype(
				       'name' => $fieldname,
				       'value' => $selectedrec->{$field},
				       %{$meta{$field}{args} || {}}
				      );
      push @m_modrec, qq{</div>\n};
    }
    push @m_modrec, qq{<input type="submit" name="pause99_edit_mod_4"
 value="Update" /><br />};

    if ($saw_a_change) {
      push @m, "<h1>The record has been updated in the database</h1>";
      $mailblurb .= qq{
Data entered by $mgr->{User}{fullname} ($mgr->{User}{userid}).
Please check if they are correct.

$Yours};
      push @to, $mgr->{User}{secretemail}||$mgr->{User}{email}
	  unless $mgr->{User}{userid} eq $u->{userid};
      warn sprintf "sending to[%s]", join(" AND ",@to);
      warn "mailblurb[$mailblurb]";
      my $header = {
                    Subject => "Module update for $selectedrec->{modid}"
                   };
      $mgr->send_mail_multi(\@to, $header, $mailblurb);
    } elsif ($update_sel) {	# it should have been updated but wasn't?

      push @m, "It seems to me the record was NOT updated. Maybe
 nothing has changed? Please take a closer look and inform an admin if
 things didn't proceed as expected.<br />";

    }
    push @m, @m_modrec;
  return @m;
}
sub edit_uris {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};
  my $selectedid = "";
  my $selectedrec = {};
  if (my $param = $req->param("pause99_edit_uris_3")) { # upper selectbox
    $selectedid = $param;
  }
  my $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};

  push @m, qq{<h3>for user $u->{userid}</h3>};
  my $dbh = $mgr->connect;
  my $sql = qq{SELECT uriid
               FROM uris
               WHERE dgot=''
                 AND userid=?
               ORDER BY uriid};
  my $sth = $dbh->prepare($sql);
  $sth->execute($u->{userid});
  my @all_recs;
  my %labels;
  if (my $rows = $sth->rows) {
    my $sth2 = $dbh->prepare(qq{SELECT *
                                FROM uris
                                WHERE dgot=''
                                  AND dverified=''
                                  AND uriid=?
                                  AND userid=?});
    while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
      # register this mailinglist for the selectbox
      push @all_recs, $id;
      # query for more info about it
      $sth2->execute($id,$u->{userid}); # really needed only for the
                                        # record we want to edit, but
                                        # maybe also needed for a
                                        # label in the selectbox
      my($rec) = $mgr->fetchrow($sth2, "fetchrow_hashref");
      # we will display the name along the ID
      # $labels{$id} = "$id ($rec->{userid})";
      $labels{$id} = $id; # redundant, but flexible
      if ($rows == 1 || $id eq $selectedid) {
	# if this is the selected one, we just store it immediately
	$selectedid = $id;
	$selectedrec = $rec;
      }
    }
  } else {
    return "<p>No pending uploads for $u->{userid} found</p>";
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_edit_uris_3",
				'values' => \@all_recs,
				'labels' => \%labels,
				'size' => 1,
			       );
  push @m, qq{<input type="submit" name="pause99_edit_uris_2" value="Select" /><br />};
  if ($selectedid) {
    push @m, qq{<h3>Record for $selectedrec->{uriid}</h3>
};
    my @m_rec;
    my $force_sel = $req->param('pause99_edit_uris_2');
    my $update_sel = $req->param('pause99_edit_uris_4');

    my %meta =
	(
	 uri =>
	 {
	  type => "textfield",
	  headline => "URI to download",
	  args => {
		   size => 60,
		   maxlength => 255,
		  },

	  note => qq{If you change this field to a different URI,
	PAUSE will try to fetch this URI instead. Note that the
	filename on PAUSE will remain unaltered. So you can fix a
	typo, but you cannot alter the name of the uploaded file, it
	will be the original filename. So this is only an opportunity
	to fix <i>broken</i> uploads that cannot be completed, not an
	opportunity to turn the time back.

        <p> To re-iterate: If you change the content of this field to
	<b>http://www.slashdot.org/</b>, PAUSE will fetch the current
	Slashdot page and will put it into
	<b>$selectedrec->{uriid}</b>. If you change it to
	<b>FooBar-3.14.tar.gz</b>, PAUSE will try to get
	<b>$PAUSE::Config->{INCOMING}/FooBar-3.14.tar.gz</b> and if it
	finds it, it puts it into <b>$selectedrec->{uriid}</b>.</p>

        <p>An example: if you made a typo and requested to upload
	<b>http://badsite.org/foo</b> instead of
	<b>http://goodsite.org/foo</b>, just correct the thing in the
	textfield below.</p>

        <p>Another example: If your upload was unsuccessful and you now have
	a bad file in the incoming directory, then you have the
	problem that PAUSE tries to fetch your file (say <b>foo</b>)
	but doesn't succeed and then it retries and retries. Your
	solution: transfer the file into the incoming directory with
	<b>a different name</b> (say <b>bar</b>) using ftp. Fill in
	the different name below. PAUSE will fetch <b>bar</b> and
	upload it as <b>foo</b>. So you're done.</p>}

		       },
		nosuccesstime => {

				  headline => "UNIX time of last
				  unsuccessful attempt to retrieve
				  this item",

				 },
		nosuccesscount => {

				   headline=>"Number of unsuccessful
				   attempts so far",

				  },
		changed => {
			    headline => "Record was last changed on",
			   },
		changedby => {
			      headline => "Record was last changed by",
			     },
	       );
    my $mailblurb = qq{Record update in the PAUSE uploads database:

};
    my($mailsprintf1,$mailsprintf2,$saw_a_change);
    $mailsprintf1 = "%12s: [%s]%s";
    $mailsprintf2 = " was [%s]\n";
    my $now = time;
    $mailblurb .= sprintf($mailsprintf1, "uriid", $selectedrec->{uriid}, "\n");

    for my $field (qw(
uri
nosuccesstime
nosuccesscount
changed
changedby
)) {
      my $headline = $meta{$field}{headline} || $field;
      my $note = $meta{$field}{note} || "";
      push @m_rec, qq{<p><b>$headline</b></p>};
      push @m_rec, qq{<small>$note</small><br />} if $note;
      my $fieldtype = $meta{$field}{type};
      my $fieldname = "pause99_edit_uris_$field";
      if ($force_sel) {
	$req->parameters->set($fieldname, $selectedrec->{$field}||"");
      } elsif ($update_sel && $fieldtype) {
	my $param = $req->param($fieldname);
	if ($param ne $selectedrec->{$field}) {
	  $mailblurb .= sprintf($mailsprintf1,
				$field,
				$param,
				sprintf($mailsprintf2,$selectedrec->{$field})
			       );

	  # no, we do not double check for user here. What if they
	  # change the owner? And we do not prepare outside the loop
	  # because the is a $fields in there
	  my $sql = qq{UPDATE uris
                       SET $field=?,
                           changed=?,
                           changedby=?
                       WHERE uriid=?};

	  my $usth = $dbh->prepare($sql);
	  my $ret = $usth->execute($param,
				   $now,
				   $u->{userid},
				   $selectedrec->{uriid});

	  $saw_a_change = 1 if $ret > 0;
	  $usth->finish;

	} else {
	  $mailblurb .= sprintf($mailsprintf1, $field, $selectedrec->{$field}, "\n");
	}
      }
      if ($fieldtype) {
	warn "fieldtype[$fieldtype]fieldname[$fieldname]field[$field]rec->{field}[$selectedrec->{$field}]";
	push @m_rec, $mgr->$fieldtype(
				      'name' => $fieldname,
				      'value' => $selectedrec->{$field},
				      %{$meta{$field}{args} || {}}
				     );
      } else {
	# not editable fields
	push @m_rec, sprintf "%s<br />\n", $selectedrec->{$field}||0;
      }
      push @m_rec, qq{<br />\n};
    }
    push @m_rec, qq{<input type="submit" name="pause99_edit_uris_4"
 value="Update" /><br />};

    if ($saw_a_change) {
      push @m, "<p>The record has been updated in the database</p>";
      $mailblurb .= qq{
Data entered by $mgr->{User}{fullname} ($mgr->{User}{userid}).
Please check if they are correct.

$Yours};
      my @to = ($u->{secretemail}||$u->{email}, $mgr->{MailtoAdmins});
      push @to, $mgr->{User}{secretemail}||$mgr->{User}{email};
      warn "sending to[@to]";
      warn "mailblurb[$mailblurb]";
      my $header = {
                    Subject => "Uri update for $selectedrec->{uriid}"
                   };
      $mgr->send_mail_multi(\@to,$header,$mailblurb);
    } elsif ($update_sel) {	# it should have been updated but wasn't?
      push @m, "It seems to me the record was NOT updated. Maybe nothing has changed?
 Please take a closer look and
 inform an admin if things didn't proceed as expected.<br />";
    }
    push @m, @m_rec;
  }
  @m;
}

sub show_ml_repr {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare("SELECT maillistid, userid
 FROM list2user
 ORDER BY maillistid, userid");
  $sth->execute;

  push @m, qq{<p>These are the contents of the table <b>list2user</b>.
              There\'s currently no way to edit the table except
              direct SQL. The table says who is representative of a
              mailing list.</p>};

  push @m, qq{<table border="1"><tr><th>Mailing list</th>
<th>User-ID</th>
</tr>\n};
  while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
    push @m, sprintf(
                     qq{<tr><td>%s</td><td>%s</td></tr>\n},
                     $rec->{maillistid},
                     $rec->{userid},
                    );
  }
  $sth->finish;
  push @m, qq{</table>\n};
  @m;
}



sub add_mod {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;

  my %meta = ($self->modid_meta,
              $self->chap_meta($mgr),
              $self->stat_meta,
              $self->desc_meta,
              $self->user_meta($mgr));

  $meta{modid}{note} = qq{Modulename or a complete line in module list
                       format. The latter is only valid for the
                       <i>guess</i> button.};

  $meta{comment} = {
                    type => "textarea",
                    note => "only for the mail, not for the database",
                    args => {
                             rows => 5,
                             cols => 60,
                            }
                   };

  if ($req->param("USERID")) {
    my $session = $mgr->session;
    my $s = $session->{APPLY};
    for my $a (keys %$s) {
      $req->parameters->set("pause99_add_mod_$a", $s->{$a});
      warn "retrieving from session a[$a]s(a)[$s->{$a}]";
    }
  }

  my @errors = ();
  my @hints = ();
  my($guessing,$modid);
  if ( $req->param("SUBMIT_pause99_add_mod_hint") ) {
    $guessing++;
    my $wanted = {};
    $self->_add_mod_hint($mgr, $wanted, $dbh, \@hints);
    $modid = $wanted->{modid};
  } elsif ( $req->param("SUBMIT_pause99_add_mod_insertit") ) {

    $modid = $req->param('pause99_add_mod_modid')||"";
    if ($modid =~ /([^A-Za-z0-9_\:])/) {
      my $illegal = ord($1);
      push @errors, sprintf(qq{The module name contains the illegal character 0x%x.
 Please correct and retry.}, #},
                            $illegal); #
    }
    unless (length($modid)) {
      push @errors, qq{The module name is missing.};
    }
    # $req->parameters->set("pause99_add_mod_modid", $modid) if $modid;

    my($chapterid) = $req->param('pause99_add_mod_chapterid');
    warn "chapterid[$chapterid]";
    die "chapterid not integer" if $strict_chapterid && $chapterid !~ /^\d*$/;
    warn "chapterid[$chapterid]";
    unless ($meta{chapterid}{args}{labels}{$chapterid}) {
      push @errors, qq{The chapterid [$chapterid] is not known.};
    }
    die "chapterid not integer" if $strict_chapterid && $chapterid !~ /^\d*$/;
    warn "chapterid[$chapterid]";

    my($statd) = $req->param('pause99_add_mod_statd');
    $req->parameters->set('pause99_add_mod_statd',$statd='?') unless $statd;
    unless ($meta{statd}{args}{labels}{$statd}) {
      push @errors, qq{The D status of the DSLIP [$statd] is not known.};
    }

    my($stats) = $req->param('pause99_add_mod_stats');
    $req->parameters->set('pause99_add_mod_stats',$stats='?') unless $stats;
    unless ($meta{stats}{args}{labels}{$stats}) {
      push @errors, qq{The S status of the DSLIP [$stats] is not known.};
    }

    my($statl) = $req->param('pause99_add_mod_statl');
    $req->parameters->set('pause99_add_mod_statl',$statl='?') unless $statl;
    unless ($meta{statl}{args}{labels}{$statl}) {
      push @errors, qq{The L status of the DSLIP [$statl] is not known.};
    }

    my($stati) = $req->param('pause99_add_mod_stati');
    $req->parameters->set('pause99_add_mod_stati',$stati='?') unless $stati;
    unless ($meta{stati}{args}{labels}{$stati}) {
      push @errors, qq{The I status of the DSLIP [$stati] is not known.};
    }

    my($statp) = $req->param('pause99_add_mod_statp');
    $req->parameters->set('pause99_add_mod_statp',$statp='?') unless $statp;
    unless ($meta{statp}{args}{labels}{$statp}) {
      # XXX for the first few weeks we allow statp to be empty
      # push @errors, qq{The P status of the DSLIP [$statp] is not known.};
    }

    # must be treated as utf8
    my($description) = $req->param('pause99_add_mod_description')||"";
    my $ud = $mgr->any2utf8($description);
    if ($ud ne $description) {
      $req->parameters->set('pause99_add_mod_description',$ud);
      $description = $ud;
    }
    $description =~ s/^\s+//;
    $description =~ s/\s+\z//;
    if (length($description)>44) {
      substr($description,44) = '';
      push @errors, qq{The description was too long and had to be truncated.};
    } elsif (not length($description)) {
      push @errors, qq{The description is missing.};
    }
    $req->parameters->set("pause99_add_mod_description", $description) if $description;

    my($userid) = $req->param('pause99_add_mod_userid');
    unless ($meta{userid}{args}{labels}{$userid}) {
      push @errors, qq{The userid [$userid] is not known.};
    }

    goto FORMULAR if @errors;

    my(@to,$subject,@blurb,$query,$sth,@qvars,@qbind);
    my $time = time;

    @qvars = qw( modid statd stats statl stati statp
                 description userid
                 chapterid introduced changed changedby );

    @qbind = ( $modid, $statd, $stats, $statl, $stati, $statp,
               $description, $userid,
               $chapterid, $time, $time, $mgr->{User}{userid} );

    $query = qq{INSERT INTO mods \(} .
        join(", ", @qvars) .
            qq{\) VALUES \(} . join(",",map {qq{?}} @qbind) . qq{)};

    push @m, qq{<b>Submitting query:</b> };
    if (0) { # too noisy for my taste
      push @m, qq{<i>$query</i><br />
 <table border="1" cellpadding="2" cellspacing="2">
 <tr><th>param</th><th>bindvalue</th></tr>
};
      for my $i (0..$#qvars) {
        push @m, qq{<tr><td>}, $mgr->escapeHTML($qvars[$i]),
            qq{</td><td>}, $mgr->escapeHTML($qbind[$i]), qq{</td></tr>\n};
      }
      push @m, qq{</table>\n};
    }

    unless ($dbh->do($query,undef,@qbind)) {
      my $err = $dbh->errstr;
      if ($err =~ /duplicate/i) {
        $sth = $dbh->prepare("SELECT userid
                              FROM   mods
                              WHERE  modid=?");
        $sth->execute($modid);
        my $otheruser = $mgr->fetchrow($sth, "fetchrow_array");
        my $url = "authenquery?ACTION=edit_mod;pause99_edit_mod_modid=$modid;HIDDENNAME=$otheruser";
        push @errors, qq{$err --
 Do you want to <a href="$url">edit $modid</a> instead?};
      } else {
        push @errors, $err;
      }
      goto FORMULAR;
    }
    push @m, qq{Query succeeded.};

    @to = $mgr->{MailtoAdmins};
    my $userobj = $self->active_user_record($mgr,$userid);
    # The logic for sending mail up to version 1.144 made
    # replying difficult. That's why we change that after 1.144

    # New logic: public address might be fake. We send to secret or
    # public email separately if we need to, otherwise we send to
    # userid@cpan.org. But there is a time gap between this database
    # and cpan.org's database.
    if ($userobj->{cpan_mail_alias} =~ /^(publ|secr)$/
        &&
        time - ($userobj->{introduced}||0) > 86400
       ) {
      $to[0] .= sprintf ",%s\@cpan.org", lc $userid;
      push @m, qq{ Sending mail to: @to};
    } else {
      # we have nothing else, so we must send separate mail
      my $user_email = $userobj->{secretemail};
      $user_email ||= $userobj->{email};
      push @to, $user_email if $user_email;
      push @m, qq{ Sending separate mails to: }, join(" AND ",
                                                      map { "[$_]" } @to);
    }

    my $user_fullname = $userobj->{fullname};

    my $chap_shorttitle = "???";
    $sth = $dbh->prepare("SELECT shorttitle
                          FROM chapters
                          WHERE chapterid=?");
    warn "chapterid[$chapterid]";
    $sth->execute($chapterid);
    warn "chapterid[$chapterid]";
    if ($sth->rows == 1) {
      $chap_shorttitle = $mgr->fetchrow($sth, "fetchrow_array");
      $chap_shorttitle = substr($chap_shorttitle,3) if $chap_shorttitle =~ /^\d/;
    } else {
      warn "ALERT: could not find chaptertitle";
    }

    my $gmtime = gmtime($time) . " UTC";

    # as string
    # 	sprintf "%-$Modlist::GLOBAL->{WIDTH_COL1WRITE}s%s%s%s%s %-45s%-${filler}s %s", @{$self}[2..9]; # 15/16
    # as HTML
    # 	sprintf "%-$Modlist::GLOBAL->{WIDTH_COL1WRITE}s%s%s%s%s %-45s", @{$self}[2..7];

    my($mdirname,$mbasename) = $modid =~ /^(.+::)([^:]+)$/;
    $mdirname ||= "";
    $mbasename ||= $modid;
    my $modwidth = $mdirname ? 15 : 17; # for the two colons
    $mdirname .= "\n::" if $mdirname;
    my $ml_entry = sprintf(("%s%-".$modwidth."s %s%s%s%s%s %-44s %s\n"),
        $mdirname, $mbasename, $statd, $stats, $statl, $stati, $statp,
            $description, $userid);
    my $server = $PAUSE::Config->{SERVER_NAME}; # XXX: $r->server->server_hostname

    my $comment = $req->param("pause99_add_mod_comment") || "";
    if ($comment) {
      # Don't wrap it, this is written by us.
      # Don't escape it, it's for mail
      $comment = sprintf "\n%s comments:\n%s\n--\n",
          $mgr->{User}{userid}, $comment;
    }

    $subject = qq{New module $modid};
    @blurb = qq{
The next version of the Module List will list the following module:

  modid:       $modid
  DSLIP:       $statd$stats$statl$stati$statp
  description: $description
  userid:      $userid ($user_fullname)
  chapterid:   $chapterid ($chap_shorttitle)
  enteredby:   $mgr->{User}{userid} ($mgr->{User}{fullname})
  enteredon:   $gmtime

The resulting entry will be:

$ml_entry$comment
Please allow a few days until the entry will appear in the published
module list.

Parts of the data listed above can be edited interactively on the
PAUSE. See https://$server/pause/authenquery?ACTION=edit_mod

Thanks for registering,
-- 
The PAUSE
};

    my($blurb) = join "", @blurb;
    require HTML::Entities;
    my($blurbcopy) = HTML::Entities::encode($blurb,"<>&");
    warn "DEBUG: UPLOAD[$PAUSE::Config->{UPLOAD}]";
    push @m, qq{<pre>
From: $PAUSE::Config->{UPLOAD}
Subject: $subject

$blurbcopy
</pre>
};
    warn "blurb[$blurb]";

    my $header = {
                  Subject => $subject
                 };
    warn "To[@to]Subject[$header->{Subject}]";
    $mgr->send_mail_multi(\@to, $header, $blurb);
  } else {
    $modid = $req->param('pause99_add_mod_modid')||"";
  }
  if ($modid) {

    # http://www.xray.mpe.mpg.de/cgi-bin/w3glimpse/modules?query=LibWeb%3A%3ACore&errors=0&case=on&maxfiles=100&maxlines=30
    # xray does not allow semicolons instead of ampersands, so we have
    # to do some extra escaping
    my $emodid = URI::Escape::uri_escape($modid,'\W');
    my $query = join(
                     "&amp;",
                     "query=$emodid",
                     "error=0",
                     "case=on",
                     "maxfiles=100",
                     "maxlines=30"
                    );
    my $uri = "http://www.xray.mpe.mpg.de/cgi-bin/w3glimpse/modules?" . $query;
    push @m, sprintf qq{<a href="%s">Search for %s at xray</a><br />}, $uri, $modid;
    warn "uri[$uri]modid[$modid]";
  } else {
    warn "DEBUG: No modid";
  }

 FORMULAR:
  my @formfields = qw( modid chapterid statd stats statl stati statp
                       description userid comment );
  if (@errors) {
    push @m, qq{<p><b>ERROR:</b>
 The submission was rejected due to the following:</p>};
    push @m, join("\n", map { "<p>$_</p>" } @errors);

    push @m, qq{<p><b>Nothing done.</b> Please correct the form below
    and retry.</p><hr noshade="noshade" />};

  } elsif ($guessing) {
    # Nothing to do here, I suppose
  } elsif ($req->param("SUBMIT_pause99_add_mod_preview")) {
    # Currently it is always  eq "preview", but we do not check that.
    # Nothing to do here, they said so. Used in CPAN::Admin. Undocumented!
  } else {
    # As we have had so much success, there is no point in leaving the
    # form filled
    # warn "clearing all fields";
    for my $field (@formfields) {
      my $param = "pause99_add_mod_$field";
      # there must be a more elegant way to specify empty list for
      # chapterid. If I knew, which, the setting of 99 would be
      # triggered later on. I would believe.
      if ($req->param($param)){
        if ($param =~ /_chapterid$/) {
          $req->parameters->set($param,"");
        } elsif ($param =~ /_stat.$/) {
          $req->parameters->set($param,"?");
        } else {
          $req->parameters->set($param,"");
        }
      }
    }
  }

  my $submit_butts = $mgr->submit(
                                  name=>"SUBMIT_pause99_add_mod_insertit",
                                  value=>" Submit to database ",
                                 );
  my $hint_butt = $mgr->submit(
                               name=>"SUBMIT_pause99_add_mod_hint",
                               value=>" Guess the rest without submitting ",
                              );
  if ($req->param("pause99_add_mod_userid")) {
    # Easier to spot, harder to browse on Netscape
    # $meta{userid}{args}{size} = 1;

    # Yet better, much less bandwidth:
    $meta{userid}{type} = "textfield";
    $meta{userid}{headline} = "userid";
    $meta{userid}{args}{size} = 12;
    $meta{userid}{args}{maxlength} = 9;
  }
  push @m, qq{<br />};
  push @m, $submit_butts;
  push @m, qq{<br />};
  for my $field (@formfields){
    my $headline = $meta{$field}{headline} || $field;
    my $note = $meta{$field}{note} || "";
    push @m, qq{<p><b>$headline</b></p>};
    push @m, qq{<p><small>$note</small></p>} if $note;
    my $fieldtype = $meta{$field}{type} or die "empty fieldtype";
    my $fieldname = "pause99_add_mod_$field";
    # warn sprintf "field[%s]value[%s]", $field, $req->param($fieldname);
    if ($field eq "chapterid") {
      my $val = $req->param($fieldname);
      die "chapterid not integer" if $strict_chapterid && $val !~ /^\d*$/;
    }
    push @m, $mgr->$fieldtype(
                              'name' => $fieldname,
                              %{$meta{$field}{args} || {}}
                             );
    if ($field eq "modid") {
      push @m, qq{<table border="1"><tr><td bgcolor="#faba99">};
      if (@hints) {
        push @m, qq{<table>};
        for (@hints) {
          push @m, qq{<tr><td>$_</td></tr>\n};
        }
        push @m, qq{</table>\n</td><td bgcolor="#faba99">};
      }
      push @m, $hint_butt;
      push @m, qq{</td></tr></table>\n};
    }
  }
  push @m, qq{<br />};
  push @m, $submit_butts;
  return @m;
}

sub _add_mod_hint {
    my($self, $mgr, $wanted, $dbh, $hints) = @_;
    my($dsli,@desc);
    my $req = $mgr->{REQ};
    ($wanted->{modid},$dsli,@desc) = split /\s+/, $req->param("pause99_add_mod_modid");

    my $userid = pop @desc;
    my $sth_mods = $dbh->prepare(qq{SELECT * FROM mods WHERE modid=?});
    $sth_mods->execute($wanted->{modid});

    if ($sth_mods->rows > 0) {
      my $rec = $mgr->fetchrow($sth_mods, "fetchrow_hashref");
      my $userid = $rec->{userid};
      push @$hints, "$wanted->{modid} is registered in the module list by $userid. ";
    } else {
      push @$hints, "$wanted->{modid} is not registered in the module list. ";
    }

    my $sth = $dbh->prepare(qq{SELECT * FROM packages
                            WHERE package=?});
    $sth->execute($wanted->{modid});

    if ($userid) {
      warn "userid[$userid]";
      # XXX check if user exists, and if not, suggest alternatives
    } else {
      # XXX check if somebody has already uploaded the module and if
      # so, tell the user. Link to readme.
      my $rows = $sth->rows;
      warn "rows[$rows]";
      if ($rows > 0) {
        my $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
        my $dist = $rec->{dist};
        my $readme = $dist;
        $readme =~ s/(\.tar[._-]gz|\.tar.Z|\.tgz|\.zip)$/.readme/;
        $userid = $mgr->file_to_user($dist);

        push @$hints, qq{Dist <i>$dist</i>, current version
        <i>$rec->{version}</i> has been uploaded by <i>$userid</i>.
        Try the <a href="/pub/PAUSE/authors/id/$readme">readme</a>.}

      }
    }
    $sth->finish;

    # guess the chapter, code also found in mldistwatch
    my($root) = $wanted->{modid} =~ /^([^:]+)/;

    $sth = $dbh->prepare("SELECT chapterid
                          FROM   mods
                          WHERE  modid = ?");
    $sth->execute($root);
    my $chapterid;
    if ($sth->rows == 1) {
      $chapterid = $mgr->fetchrow($sth, "fetchrow_array");
    } else {
      $sth = $dbh->prepare(qq{SELECT chapterid
                              FROM   mods
                              WHERE  modid LIKE ?});

      $sth->execute("$root\::%");
      $chapterid = $mgr->fetchrow($sth, "fetchrow_array");
    }

    warn "chapterid[$chapterid]";
    $req->parameters->set("pause99_add_mod_modid",$wanted->{modid});
    my(@dsli) = $dsli =~ /(.?)(.?)(.?)(.?)(.?)/;
    $req->parameters->set("pause99_add_mod_statd",$dsli[0]||"?");
    $req->parameters->set("pause99_add_mod_stats",$dsli[1]||"?");
    $req->parameters->set("pause99_add_mod_statl",$dsli[2]||"?");
    $req->parameters->set("pause99_add_mod_stati",$dsli[3]||"?");
    $req->parameters->set("pause99_add_mod_statp",$dsli[4]||"?");
    my $description = join " ", @desc;
    $description ||= "";
    $req->parameters->set("pause99_add_mod_description",$description);
    $chapterid ||= "";
    warn "chapterid[$chapterid]";
    $req->parameters->set("pause99_add_mod_chapterid",$chapterid);
    $req->parameters->set("pause99_add_mod_userid",$userid);
}

sub apply_mod {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  $mgr->prefer_post(1);
  my(@m);
  my $req = $mgr->{REQ};
  $mgr->{CAN_GZIP} = 0; # for debugging
  my $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  if ($mgr->{User}{userid} ne $u->{userid}) {
    push @m, qq{<h3>Applying in the name of $u->{userid}</h3>\n};
  }

  my $dbh = $mgr->connect;
  my $sth;
  local($dbh->{RaiseError}) = 0;

  my %meta = ($self->modid_meta,
              $self->chap_meta($mgr),
              $self->stat_meta,
              $self->desc_meta);

  $meta{modid}{note} = "Please try to suggest a nested namespace that
                        is based on an existing root namespace. New
                        entries to the root namespace are less likely
                        to be approved.";

  $meta{chapfirm}  = {
                      headline => "Do you really want this chapterid?",
                      type     => "checkbox",
                     };
  $meta{similar}   = {

                      headline => "Modules with similar functionality",
                      type     => "textfield",

                      note => "If any related modules already exist on
                              CPAN, please let us know and discuss the
                              relation between your module and these
                              already existing modules below. Enter
                              just the module names, separated by
                              whitespace.",

                      args => {
                               size => 60,
                              }

                     };
  $meta{communities} = {
                        headline => "Places where this module has been or will be discussed publicly",
                        note     => "Mailinglists, newsgroups, chatrooms, CVS repository, etc.",
                        type     => "textfield",
                        args => {
                                 size => 60,
                                }

                       };
  $meta{rationale} = {
                      headline => "Rationale",
                      type => "textarea",

                      note => "Please discuss your reasoning about the
                        namespace choice, the uniqueness of your
                        approach and why you believe this module
                        should be listed in the module list.
                        Especially if you suggest a new rootlevel
                        namespace you are required to argue why this
                        new namespace is necessary.",

                      args => {
                               rows => 15,
                               cols => 60,
                              }
                   };

  my @errors = ();
  my @hints = ();
  my $applying_userid = $u->{userid};
  my($chap_confirm,$modid);
  if ( $req->param("SUBMIT_pause99_apply_mod_send") ) {
    my($modid,$root,@appropriate_chapterid);
    if (length($modid = $req->param("pause99_apply_mod_modid"))) {
      if ($modid =~ /([^A-Za-z0-9_\:])/) {
        my $illegal = ord($1);
        push @errors, sprintf(qq{The module name contains the illegal character 0x%x.
 Please correct and retry.}, #},
                              $illegal);
      } elsif ($modid !~ /^[A-Za-z]/) {
        push @errors, qq{The module name doesn't start with a letter.
 Please correct and retry.};
      } elsif ($modid !~ /[A-Za-z0-9]\z/) {
        push @errors, qq{The module name doesn't end with a letter or digit.
 Please correct and retry.};
      }

      $sth = $dbh->prepare(qq{SELECT * FROM mods
                            WHERE modid=?});
      $sth->execute($modid);
      if ($sth->rows) {
        my $modrec = $mgr->fetchrow($sth, "fetchrow_hashref");
        push @errors, qq{Module $modid has already been registered by <i>$modrec->{userid}</i>.};
# with the modulelist line<br />
# <pre>$mlline</pre>};
      }

      $sth = $dbh->prepare(qq{SELECT * FROM packages
                            WHERE package=?});
      $sth->execute($modid);

      # XXX check if somebody has already uploaded the module and if
      # so, tell the user. Link to readme.

      # XXX nonono, we should rather check the perms, not the uploads.
      # If somebody else has first come rights we must reject
      # everything now. If this user has first come rights we can
      # auto-register immediately (unless other errors occur, maybe
      # even a root namespace should be rejected). Only if nobody has
      # first come rights we shall proceed with the application.
      my $rows = $sth->rows;
      if ($rows > 0) {
        my $rec = $mgr->fetchrow($sth, "fetchrow_hashref");
        my $dist = $rec->{dist};
        my $registered_userid = $mgr->file_to_user($dist);

        if ($applying_userid eq $registered_userid) {
          if ($PAUSE::Config->{AUTO_REGISTER_FOR_FIRST_COME}) {
            # examine the perms of this user now if he is first-come,
            # set something so that we do not even send a mail and
            # promote/upgrade him to state "module list" right away.
          }
        } else {
          push @errors, qq{Dist <i>$dist</i>, current version
        <i>$rec->{version}</i> has been uploaded by <i>$registered_userid</i>.
        Please contact <i>$registered_userid</i> or choose a different namespace.};
        }
      }
      $sth->finish;

      # guess the chapter, code also found in mldistwatch
      ($root) = $modid =~ /^([^:]+)/;
      warn "root[$root]";
      $sth = $dbh->prepare("SELECT chapterid
                            FROM   mods
                            WHERE  modid = ? OR modid LIKE ?");
      $sth->execute($root, "$root\::%");
      my(%appr);
      if ($sth->rows) {
        while (my $chid = $mgr->fetchrow($sth, "fetchrow_array")) {
          $appr{$chid} = undef;
        }
        @appropriate_chapterid = keys %appr;
      }


    } else {
      push @errors, qq{No module name chosen. You need to supply a module name.};
    }

    my($chapterid) = $req->param('pause99_apply_mod_chapterid');
    die "chapterid not numeric" if $strict_chapterid && $chapterid !~ /^\d*$/;
    warn "appropriate_chapterid[@appropriate_chapterid]";
    my($chap_confirmed) = $req->param('pause99_apply_mod_chapfirm');
    if (!$chapterid) {
      push @errors, qq{No chapter given.};
    } elsif ( ! @appropriate_chapterid) {
      # That's OK, a new rootnamespace
    } elsif (! $self->is_subset($chapterid,\@appropriate_chapterid)){
      $chap_confirm++;
      unless ( $chap_confirmed ) {
        my $plural = @appropriate_chapterid>1 ? "s" : "";
        my $chlist = @appropriate_chapterid>1 ?
            $self->verbose_list(@appropriate_chapterid) : $appropriate_chapterid[0];

        push @errors, sprintf(qq{Module rootnamespace <i>%s</i> doesn\'t
                       match chapter. <i>%s</i> is already registered
                       in the chapter%s %s. If you really believe that
                       it belongs to chapter %s too, please turn on the
                       small checkbox next to the chapterselection.},

                              $root,
                              $root,
                              $plural,
                              $chlist,
                              $chapterid
                             );
      }
    }

    my($statd) = $req->param('pause99_apply_mod_statd');
    $req->parameters->set('pause99_apply_mod_statd',$statd='?') unless $statd;
    if ($statd eq '?') {
      push @errors, qq{The D status of the DSLIP [$statd] is not known.};
    }

    my($stats) = $req->param('pause99_apply_mod_stats');
    $req->parameters->set('pause99_apply_mod_stats',$stats='?') unless $stats;
    if ($stats eq '?') {
      push @errors, qq{The S status of the DSLIP [$stats] is not known.};
    }

    my($statl) = $req->param('pause99_apply_mod_statl');
    $req->parameters->set('pause99_apply_mod_statl',$statl='?') unless $statl;
    if ($statl eq "?") {
      push @errors, qq{The L status of the DSLIP [$statl] is not known.};
    }

    my($stati) = $req->param('pause99_apply_mod_stati');
    $req->parameters->set('pause99_apply_mod_stati',$stati='?') unless $stati;
    if ($stati eq "?") {
      push @errors, qq{The I status of the DSLIP [$stati] is not known.};
    }

    my($statp) = $req->param('pause99_apply_mod_statp');
    $req->parameters->set('pause99_apply_mod_statp',$statp='?') unless $statp;
    if ($statp eq "?") {
      push @errors, qq{The P status of the DSLIP [$statp] is not known.};
    }

    # must be treated as utf8
    my($description) = $req->param('pause99_apply_mod_description')||"";
    my $ud = $mgr->any2utf8($description);
    if ($ud ne $description) {
      $req->parameters->set('pause99_apply_mod_description',$ud);
      $description = $ud;
    }
    $description =~ s/^\s+//;
    $description =~ s/\s+\z//;
    if (length($description)>44) {
      substr($description,44) = '';
      push @errors, qq{The description was too long and had to be truncated.};
    } elsif (not length($description)) {
      push @errors, qq{The description is missing.};
    }
    $req->parameters->set("pause99_apply_mod_description", $description) if $description;

    goto FORMULAR2 if @errors;

    my(@to,$subject,@blurb,$query,$sth,@qvars,@qbind);
    my $time = time;

    @to = $mgr->{MailtoAdmins};
    my $userobj = $self->active_user_record($mgr,$applying_userid);

    if ($userobj->{cpan_mail_alias} =~ /^(publ|secr)$/
        &&
        time - ($userobj->{introduced}||0) > 86400
       ) {
      $to[0] .= sprintf ",%s\@cpan.org", lc $applying_userid;
      push @m, qq{ Sending mail to: @to};
    } else {
      my $user_email = $userobj->{secretemail};
      $user_email ||= $userobj->{email};
      push @to, $user_email if $user_email;
      push @m, qq{ Sending separate mails to: }, join(" AND ",
                                                      map { "[$_]" } @to);
    }

    my $user_fullname = $userobj->{fullname};

    my $chap_shorttitle = "???";
    $sth = $dbh->prepare("SELECT shorttitle
                          FROM chapters
                          WHERE chapterid=?");
    $sth->execute($chapterid);
    if ($sth->rows == 1) {
      $chap_shorttitle = $mgr->fetchrow($sth, "fetchrow_array");
      $chap_shorttitle = substr($chap_shorttitle,3) if $chap_shorttitle =~ /^\d/;
    } else {
      warn "ALERT: could not find chaptertitle";
    }

    my $gmtime = gmtime($time) . " UTC";

    my($mdirname,$mbasename) = $modid =~ /^(.+::)([^:]+)$/;
    $mdirname ||= "";
    $mbasename ||= $modid;
    my $modwidth = $mdirname ? 15 : 17; # for the two colons
    $mdirname .= "\n::" if $mdirname;
    my $ml_entry = sprintf(("%s%-".$modwidth."s %s%s%s%s%s %-44s %s\n"),
        $mdirname, $mbasename, $statd, $stats, $statl, $stati, $statp,
            $description, $applying_userid);
    my $server = $PAUSE::Config->{SERVER_NAME}; # XXX: $r->server->server_hostname

    my $rationale = $req->param("pause99_apply_mod_rationale") || "";
    if ($rationale) {
      # wrap it
      $rationale =~ s/\r\n/\n/g;
      $rationale =~ s/\r/\n/g;
      my @rat = split /\n\n/, $rationale;
      my $tf = Text::Format->new( bodyIndent => 4, firstIndent => 5);
      $rationale = $tf->paragraphs(@rat);
      $rationale =~ s/^\s{5}/\n    /gm;
    }
    my $similar = $req->param("pause99_apply_mod_similar") || "";
    if ($similar) {
      # wrap it
      my $tf = Text::Format->new( bodyIndent => 4, firstIndent => 4);
      $similar = $tf->format($similar);
    }
    my $communities = $req->param("pause99_apply_mod_communities") || "";
    if ($communities) {
      # wrap it
      my $tf = Text::Format->new( bodyIndent => 4, firstIndent => 4);
      $communities = $tf->format($communities);
    }

    my $session = $mgr->session;
    $session->{APPLY} = {
                         modid => $modid,
                         statd => $statd,
                         stats => $stats,
                         statl => $statl,
                         stati => $stati,
                         statp => $statp,
                         description => $description,
                         userid => $applying_userid,
                         chapterid => $chapterid,
                        };
    my $sessionID = $mgr->userid;
    $subject = qq{Module submission $modid};
    my $urlenc_module = URI::Escape::uri_escape($modid,'\W');
    @blurb = qq{
The following module was proposed for inclusion in the Module List:

  modid:       $modid
  DSLIP:       $statd$stats$statl$stati$statp
  description: $description
  userid:      $applying_userid ($user_fullname)
  chapterid:   $chapterid ($chap_shorttitle)
  communities:
$communities
  similar:
$similar
  rationale:
$rationale
  enteredby:   $mgr->{User}{userid} ($mgr->{User}{fullname})
  enteredon:   $gmtime

The resulting entry would be:

$ml_entry

Thanks for registering,
-- 
The PAUSE

PS: The following links are only valid for module list maintainers:

Registration form with editing capabilities:
  https://pause.perl.org/pause/authenquery?ACTION=add_mod&USERID=$sessionID&SUBMIT_pause99_add_mod_preview=1
Immediate (one click) registration:
  https://pause.perl.org/pause/authenquery?ACTION=add_mod&USERID=$sessionID&SUBMIT_pause99_add_mod_insertit=1
Peek at the current permissions:
  https://pause.perl.org/pause/authenquery?pause99_peek_perms_by=me&pause99_peek_perms_query=$urlenc_module
};

    my($blurb) = join "", @blurb;
    require HTML::Entities;
    my($blurbcopy) = HTML::Entities::encode($blurb,"<>&");
    $blurbcopy =~ s|(https?://[^\s\"]+)|<a href="$1">$1</a>|g;
    $blurbcopy =~ s|(>http.*?)U|$1\n    U|gs; # break the long URL
    # warn "DEBUG: UPLOAD[$PAUSE::Config->{UPLOAD}]";
    push @m, qq{<pre>
From: $PAUSE::Config->{UPLOAD}
Subject: $subject

$blurbcopy
</pre>
<hr noshade="noshade" />
};
    warn "blurb[$blurb]";

    my $header = {
                  Subject => $subject
                 };
    warn "To[@to]Subject[$header->{Subject}]";
    $mgr->send_mail_multi(\@to, $header, $blurb);
  } else {
    $modid = $req->param('pause99_apply_mod_modid')||"";
  }

  push @m, qq{<p>Please use this form to apply for the registration of
              a namespace for a module you have written or are going
              to write. The request will be sent off to the
              modules\@perl.org people who are maintaining the <a
              href="http://www.perl.org/CPAN/modules/00modlist.long.html">Modules
              List</a>. A registration is not a prerequisite for
              uploading. It is just recommended for better
              searchability of the CPAN and to avoid namespace
              clashes. You will be notified when the registration is
              approved but you can upload immediately, there's no need
              to wait for an approval. <b>On the contrary, you are
              encouraged to upload immediately.</b></p><p>If you are
              facing any problems with this form, please report to
              modules\@perl.org.<br />Thank you for
              registering.</p><hr noshade="noshade" />};


 FORMULAR2:
  my @formfields = qw( modid chapterid chapfirm statd stats statl stati statp
                       description communities similar rationale );
  if (@errors) {
    my $plural = @errors > 1 ? "s" : "";
    push @m, qq{<p><b>ERROR:</b>
 The submission didn't succeed due to the following reason$plural:</p>};
    push @m, join("\n", map { "<p>$_</p>" } @errors);

    push @m, qq{<p><b>Nothing done.</b> Please correct the form below
    and retry.</p><hr noshade="noshade" />};

  } elsif ($req->param("SUBMIT_pause99_apply_mod_preview")) {
    # Currently it is always  eq "preview", but we do not check that.
    # Nothing to do here, they said so. Used in CPAN::Admin. Undocumented!
  } else {
    # As we have had so much success, there is no point in leaving the
    # form filled
    # warn "clearing all fields";
    for my $field (@formfields) {
      my $param = "pause99_apply_mod_$field";
      # there must be a more elegant way to specify empty list for
      # chapterid. If I knew, which, the setting of 99 would be
      # triggered later on. I would believe.
      if ($req->param($param)){
        if ($param =~ /chapterid/) {
          $req->parameters->set($param,"");
        } else {
          $req->parameters->set($param,"");
        }
      }
    }
  }

  my $submit_butts = $mgr->submit(
                                  name=>"SUBMIT_pause99_apply_mod_send",
                                  value=>" Submit to modules\@perl.org ",
                                 );
  push @m, qq{<br />};
  for my $field (@formfields){
    next if $field eq "chapfirm" && ! $chap_confirm;
    my $headline = $meta{$field}{headline} || $field;
    my $note = $meta{$field}{note} || "";
    push @m, qq{<p><b>$headline</b></p>};
    push @m, qq{<p><small>$note</small></p>} if $note;
    push @m, qq{<p>};
    my $fieldtype = $meta{$field}{type} or die "empty fieldtype";
    my $fieldname = "pause99_apply_mod_$field";
    push @m, $mgr->$fieldtype(
                              'name' => $fieldname,
                              %{$meta{$field}{args} || {}}
                             );
    push @m, qq{</p>\n};
  }
  push @m, qq{<br />};
  push @m, $submit_butts;
  return @m;
}

sub is_subset {
  my($self, $item, $arr) = @_;
  for my $i (@$arr) {
    return 1 if $i eq $item;
  }
  return;
}

sub verbose_list {
  my($self,@arr) = @_;
  my $result;
  return unless @arr;
  if (@arr > 2) {
    $result = join ", ", @arr[0..$#arr-1];
    $result .= ", and $arr[-1]";
  } elsif (@arr > 1) {
    $result = "$arr[0] and $arr[1]";
  } else {
    $result = $arr[0];
  }
  $result;
}

sub stat_meta {
  my($deftype) = "scrolling_list"; # or "radio_group";
  my(%statd,%stats,%statl,%stati,%statp,@statd,@stats,@statl,@stati,@statp);
  @statd{@statd = qw(i c a b R M S ?)} = qw( idea pre-alpha
        alpha beta released mature standard unknown);
  @stats{@stats = qw(d m u n a ?)}       = qw(
	developer mailing-list comp.lang.perl.* none abandoned unknown);
  @statl{@statl = qw(p c + o h ?)}       = qw( perl C C++ other hybrid unknown);
  @stati{@stati = qw(f r O p h n ?)}         = qw( functions
	references+ties object-oriented pragma hybrid none unknown );
  @statp{@statp = qw(p g l b a 2 o d r n ?)}         = qw( Standard-Perl
	GPL LGPL BSD Artistic Artistic_2 open-source distribution_allowed
        restricted_distribution no_licence unknown );

  for my $hash (\%statd,\%stats,\%statl,\%stati,\%statp) {
    for my $k (keys %$hash) {
      $hash->{$k} = $deftype =~ /radio/ ?
          qq{<font color="green"><b>$k</b></font>&#160;($hash->{$k}) } :
              qq{$k -- $hash->{$k}};
    }
  }

  return (
          statd => {
                    type => $deftype,
                    headline => "Development Stage (Note: No implied timescales)",
                    args => {
                             values => \@statd,
                             labels => \%statd,
                             default => '?',
                            }
                   },
          stats => {
                    type => $deftype,
                    headline => "Support Level",

                    note => qq{The module list says about the flags
                      <i>n</i> and <i>a</i>:<br/>
<br/>
n  - None known, try comp.lang.perl.modules<br/>
a  - abandoned; volunteers welcome to take over maintainance<br/>
},

                    args => {
                             values => \@stats,
                             labels => \%stats,
                             default => '?',
                            }
                   },
          statl => {
                    type => $deftype,
                    headline => "Language Used",
                    args => {
                             values => \@statl,
                             labels => \%statl,
                             default => '?',
                            }
                   },
          stati => {
                    type => $deftype,
                    headline => "Interface Style",
                    args => {
                             values => \@stati,
                             labels => \%stati,
                             default => '?',
                            }
                   },
          statp => {
                    type => $deftype,
                    headline => "Public license",

                    note => qq{This field is here to help acquiring
    solid data about which licences the CPAN modules are subject to.
    Filling in this form field is <i>not a substitute</i> for a proper
    license statement in the actual package you are uploading. So
    please verify that all your uploaded files contain a proper
    license. This field will be used to help certifying the legal
    status of your package.<br /> <b>Standard-Perl</b> denotes that
    the user may choose between GPL and Artistic,<br /><b>GPL</b>
    stands for GNU General Public License, <br /> <b> LGPL</b> for GNU
    Lesser General Public License (previously known as "GNU Library
    General Public License"),<br /> <b>BSD</b> for the BSD License,
    <br /> <b>Artistic</b> for the Artistic license alone,<br />
    <b>Artistic_2</b> for the artistic license 2.0 or later<br />
    <b>open-source</b> for any other Open Source license listed at <a
    href="http://www.opensource.org/licenses/">http://www.opensource.org/licenses/</a>,
    <br /><b>distribution_allowed</b> is for any license that is not
    approved by www.opensource.org but that allows distribution
    without restrictions, <br /><b>restricted_distribution</b> is for
    code that limits distribution somehow, and <br /><b>no_licence</b>
    is for code that bears no licence at all.<br />The last two items
    on the list might become a problem for CPAN in the future, so
    please try to clear things up to avoid them.--Thanks!

},

                    args => {
                             values => \@statp,
                             labels => \%statp,
                             default => '?',
                            }
                   },
         );
}

sub chap_meta {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $dbh = $mgr->connect;
  my $sth3  = $dbh->prepare("SELECT chapterid, shorttitle
                             FROM   chapters");
  my(%chap);
  $sth3->execute;
  while (my($chapterid, $shorttitle) = $mgr->fetchrow($sth3, "fetchrow_array")) {
    $chap{$chapterid} = sprintf "%03d %s", $chapterid, $shorttitle;
  }
  my @sorted = sort { $a <=> $b } keys %chap;
  unshift @sorted, "";
  $chap{""} = "Please select chapter";
  $sth3->finish;
  return (
          chapterid => {
                        type => "scrolling_list",
                        headline => "Module List Chapter",

                        note => "The module list has all modules
		      categorized in chapters. Please pick the one
		      you would prefer to have your module listed
		      in.",

                        args => {
                                 size => 1,
                                 default => "",
                                 values => \@sorted,
                                 labels => \%chap,
                                },
                       }
         );
}

sub desc_meta {
    return (
            description => {
                            type => "textfield",
                            headline => "Description in Module List (44 chars limit)",
                            args => {
                                     size => 44,
                                     maxlength => 44,
                                    }
                           },
           );
}

sub modid_meta {
    return (
            modid => {
                      type => "textfield",
                      headline => "Name of the module",
                      args => {
                               size => 44,
                               maxlength => 112,
                              }
                     },
           );
}

=pod

In user_meta liegt noch der ganze Scheiss herum, mit dem ich die
unglaubliche Langsamkeit analysiert habe, die eintrat, als ich den
alten Algorithmus durch 5.8 habe durchlaufen lassen.

Am Schluss (mit $sort_method="splitted") war 5.8 etwa gleich schnell
wie 5.6, aber die Trickserei ist etwas zu aufwendig fuer meinen
Geschmack.

Also, der Fehler war, dass ich zuerst einen String zusammengebaut
habe, der UTF-8 enthalten konnte und uebermaessig lang war und dann
darueber im Sort-Algorithmus lc laufen liess. Jedes einzelne lc hat
etwas Zeit gekostet, da es im Sort-Algorithmus war, musste es 40000
mal statt 2000 mal laufen. Soweit, so klar auf einen Blick: richtige
Loesung ist es, den String mit Hilfe des "translit" Feldes zo kurz zu
lassen, dass nur ASCII verbleibt, dann ein downgrade, dann lc, und
dann erst Sortieren. In einem zweiten Hash traegt man den
Display-String herum.

Was bis heute ein Mysterium ist, ist die Frage, wieso das Einschalten
der Statistik, also ein hoher *zusaetzlicher* Aufwand, die Zeit auf
ein Sechstel biz Zehntel *gedrueckt* hat. Da muss etwas Schlimmes mit
$a und $b passieren.

=cut

sub user_meta {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $dbh = $mgr->connect;
  my $sql = qq{SELECT userid, fullname, isa_list, asciiname
               FROM users};
  my $sth = $dbh->prepare($sql);
  $sth->execute;
  my(%u,%labels);
  # my $sort_method = "gogo";
  my $sort_method = "splitted";
  if (0) { # worked mechanically correct but slow with 5.7.3@16103.
           # The slowness is not in the fetchrow but in the sort with
           # lc below. At the time of the test $mgr->fetchrow turned
           # on UTF-8 flag on everything, including pure ASCII.

    while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
      $u{$row[0]} = $row[2] ? "mailinglist $row[0]" : "$row[1] ($row[0])";
    }

  } elsif (0) {

    # here we are measuring where the time is spent and tuning up and
    # down and experiencing strange effects.

    my $start = Time::HiRes::time();
    my %tlc;
    while (my @row = $sth->fetchrow_array) {
      if ($] > 5.007) {
        # apparently it pays to only turn on UTF-8 flag if necessary
        defined && /[^\000-\177]/ && Encode::_utf8_on($_) for @row;
      }
      $u{$row[0]} = $row[2] ? "mailinglist $row[0]" :
          $row[3] ? "$row[3]=$row[1] ($row[0])" : "$row[1] ($row[0])";

      if (0) {
        # measuring lc() alone does not explain the slow sort. We see
        # about 0.4 secs for lc() on all names when they all have the
        # UTF-8 flag on, about 0.07 secs when only selected ones have
        # the flag on.
        next unless $row[1];
        my $tlcstart = Time::HiRes::time();
        $tlc{$row[1]} = lc $row[1];
        $tlc{$row[1]} = Time::HiRes::time() - $tlcstart;
      }
    }
    # warn sprintf "TIME: fetchrow and lc on users: %7.4f", Time::HiRes::time()-$start;
    my $top = 10;
    for my $t (sort { $tlc{$b} <=> $tlc{$a} } keys %tlc) {
      warn sprintf "%-43s: %9.7f\n", $t, $tlc{$t};
      last unless --$top;
    }
  } else { # splitted!
    my $start = Time::HiRes::time();
    while (my @row = $sth->fetchrow_array) {
      if ($] > 5.007) {
        # apparently it pays to only turn on UTF-8 flag if necessary
        defined && /[^\000-\177]/ && Encode::_utf8_on($_) for @row;
      }
      my $disp = $row[2] ?
          "$row[0] (mailinglist)" :
              $row[3] ?
                  "$row[0]:$row[3]=$row[1]" :
                      "$row[0]:$row[1]";
      substr($disp, 52) = "..." if length($disp) > 55;
      my($sort) = $disp =~ /^([\000-\177]+)/;
      utf8::downgrade($sort) if $] > 5.007;
      $u{$row[0]} = lc $sort;
      $labels{$row[0]} = $disp;
    }
    warn sprintf "TIME: fetchrow and split on users: %7.4f", Time::HiRes::time()-$start;
  }
  my $start = Time::HiRes::time();
  our @tlcmark = ();
  our $Collator;
  if ($sort_method eq "U:C") {
    require Unicode::Collate;
    $Collator = Unicode::Collate->new();
  }
  # use sort qw(_mergesort);
  # use sort qw(_quicksort);
  my @sorted = sort {
    if (0) {
      # Mysterium: the worst case was to have all names with UTF-8
      # flag, Sort_method="lc" and running no statistics. Turning on
      # the statistics here reduced runtime from 77-133 to 12 secs.
      # With only selected names having UTF-8 flag on we reach 10 secs
      # without the statistics and 12 with it. BTW, mergesort counts
      # 20885 comparisons, quicksort counts 23201.
      push(
           @tlcmark,
           sprintf("%s -- %s: %9.7f",
                   $u{$a},
                   $u{$b},
                   Time::HiRes::time())
          );
    }
    if (0) {
    } elsif ($sort_method eq "lc") {
      # we reach minimum of 10 secs here, better than 77-133 but still
      # unacceptable. We seem to have to fight against two bugs: slow
      # lc() always is one bug, extremely slow lc() when combined with
      # sort is the other one. We must solve it as we did in metalist:
      # maintain a sortdummy in the database and let the database sort
      # on ascii.
      lc($u{$a}) cmp lc($u{$b});
    } elsif ($sort_method eq "U:C") {
      $Collator->cmp($a,$b);
      # v0.10 completely bogus and 67 secs
    } elsif ($sort_method eq "splitted") {
      $u{$a} cmp $u{$b};
    } else {
      # we reach 0.27 secs here with mergesort, 0.28 secs after we
      # switched to quicksort.
      $u{$a} cmp $u{$b};
    }
  } keys %u;
  warn sprintf "TIME: sort on users: %7.4f", Time::HiRes::time()-$start;
  if (@tlcmark) {
    warn "COMPARISONS: $#tlcmark";
    my($Ltlcmark) = $tlcmark[0] =~ /:\s([\d\.]+)/;
    # warn "$Ltlcmark;$tlcmark[0]";
    my $Mdura = 0;
    for my $t (1..$#tlcmark) {
      my($tlcmark) = $tlcmark[$t] =~ /:\s([\d\.]+)/;
      my $dura = $tlcmark - $Ltlcmark;
      if ($dura > $Mdura) {
        my($lterm) = $tlcmark[$t-1] =~ /(.*):/;
        warn sprintf "%s: %9.7f\n", $lterm, $dura;
        $Mdura = $dura;
      }
      $Ltlcmark = $tlcmark;
    }
  }

  return (
          userid => {
                     type     => "scrolling_list",
                     args  => {
                               'values' => \@sorted,
                               size     => 10,
                               labels   => $sort_method eq "splitted" ? \%labels : \%u,
                              },
                    }
         );
}

sub check_xhtml {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my @m;
  my $dir = "/var/run/httpd/deadmeat";
  if (my $file = $req->param("pause99_check_xhtml_look")) {
    open my $fh, "$dir/$file" or die "Couldn't open $file: $!";
    if ($] > 5.007) {
      binmode $fh, ":utf8";
    }
    local $/;
    my $html = <$fh>;
    push @m, $mgr->escapehtml($html);
  } else {
    require DirHandle;
    my $dh = DirHandle->new($dir) or die "Couldn't open dir[$dir]: $!";
    if (my @dirent = grep /\.xhtml$/, $dh->read()) {
      my %label;
      my %mtime;
      for my $de (@dirent) {
        my @stat = stat "$dir/$de";
        $label{$de} = sprintf " %s %d %s\n", $de, $stat[7], scalar gmtime($stat[9]);
        $mtime{$de} = $stat[9];
      }
      @dirent = sort { $mtime{$b} <=> $mtime{$a}} @dirent;
      push @m, $mgr->radio_group("name" => "pause99_check_xhtml_look",
                                 "values" => \@dirent,
                                 "labels" => \%label,
                                 "linebreak" => 1,
                                );
      push @m, $mgr->submit(name => "SUBMIT_pause99_check_xhtml_sub",
                            value => "Look");
    } else {
      push @m, qq{No bad xhtml output detected.};
    }
  }
  @m;
}

sub index_users {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  push @m, "NOT YET";
  my $db = $mgr->connect;
  my $id_sql = qq{SELECT userid, fullname
                  FROM users};
  my $id_sth = $db->prepare($id_sql);

  require WAIT;
  require WAIT::Database;

  my @localtime = localtime;
  $localtime[5] += 1900;
  $localtime[4]++;
  my $jobid = sprintf "%04s-%02s-%02s_%02s:%02s_%d", @localtime[5,4,3,2,1], $$;
  my $name = "$mgr->{WaitUserDb}-$jobid";
  my $directory = $mgr->{WaitDir};
  warn "name[$name] directory[$directory]";
  my $wdb = WAIT::Database->create(name      => $name,
                                  directory => $directory,
                                 )
      or die "Could not create database $mgr->{WaitUserDb}: $@\n";


  my $filter = [
                "pause99_edit_users_utflc_20010505",
                "pause99_edit_users_digrams_20010505",
               ];

  # create-table statement
  my $table = $wdb->create_table(
                                name => "uidx",
                                attr => [
                                         'docid',
                                         'userid',         # key
                                        ],
                                keyset => [['docid']],
                                ## layout => $layout,
                                invindex => [
                                             userid_and_fullname => $filter,
                                            ]
                               );

  # XXX

  $table->close;
  $wdb->close;

  @m;
}

sub WAIT::Filter::pause99_edit_users_digrams_20010505 {
  # must be written with "shift" and not with = @_. WAIT seems to need
  # that.
  my $string = shift;
  my @result;
  my $start;
#  use utf8;
  my $end = length($string) - 2;
  for ($start=0; $start<$end; $start++) {
    my $s =  substr $string, $start, 3;
    push @result, $s;
  }
  @result;
}

sub WAIT::Filter::pause99_edit_users_utflc_20010505 {
#  use utf8;
  my $s = shift;
  my $lc = lc $s;
  $lc;
}

sub who_pumpkin {
  my $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};

  my @m;

  push @m, qq{<p>Query the <code>grouptable</code> table for who is a
          pumpkin bit holder</p>

          <p>Registered pumpkins:
};

  my @hres;
  {
    my $db = $mgr->authen_connect;
    my $sth = $db->prepare("SELECT user FROM grouptable WHERE ugroup='pumpking' order by user");
    $sth->execute;
    while (my @row = $sth->fetchrow_array) {
      push @hres, $row[0];
    }
    $sth->finish;
  };
  my $output_format = $req->param("OF");
  if ($output_format){
    if ($output_format eq "YAML") {
      require YAML::Syck;
      local $YAML::Syck::ImplicitUnicode = 1;
      my $dump = YAML::Syck::Dump(\@hres);
      my $edump = Encode::encode_utf8($dump);
      my $res = $mgr->{RES};
      $res->content_type("text/plain; charset=utf8");
      $res->body($edump);
      return $mgr->{DONE} = HTTP_OK;
    } else {
      die "not supported OF=$output_format"
    }
  } else {
    push @m, join ", ", @hres;
    push @m, "</p>";
    my $href = sprintf("query?ACTION=who_pumpkin;OF=YAML");
    push @m, qq{<p><a href="$href" style="text-decoration: none;">
<span class="orange_button">YAML</span>
</a></p>};
    return join "", @m;
  }
}

sub who_admin {
  my $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};

  my @m;

  push @m, qq{<p>Query the <code>grouptable</code> table for who is an
          admin bit holder</p>

          <p>Registered admins:
};

  my @hres;
  {
    my $db = $mgr->authen_connect;
    my $sth = $db->prepare("SELECT user FROM grouptable WHERE ugroup='admin' order by user");
    $sth->execute;
    while (my @row = $sth->fetchrow_array) {
      push @hres, $row[0];
    }
    $sth->finish;
  };
  my $output_format = $req->param("OF");
  if ($output_format){
    if ($output_format eq "YAML") {
      require YAML::Syck;
      local $YAML::Syck::ImplicitUnicode = 1;
      my $dump = YAML::Syck::Dump(\@hres);
      my $edump = Encode::encode_utf8($dump);
      my $res = $mgr->{RES};
      $res->content_type("text/plain; charset=utf8");
      $res->body($edump);
      return $mgr->{DONE} = HTTP_OK;
    } else {
      die "not supported OF=$output_format"
    }
  } else {
    push @m, join ", ", @hres;
    push @m, "</p>";
    my $href = sprintf("query?ACTION=who_admin;OF=YAML");
    push @m, qq{<p><a href="$href" style="text-decoration: none;">
<span class="orange_button">YAML</span>
</a></p>};
    return join "", @m;
  }
}

sub email_for_admin {
  my $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};

  my @m;
  my %ALL;

  push @m, qq{<p>Query a combination of <code>usertable</code> table and user for public or private emails according to the preferences</p>

          <table><tr><th>id</th><th><i>id</i>\@cpan.org gets forwarded to</th></tr>
};

  {
    my $dba = $mgr->authen_connect;
    my $dbm = $mgr->connect;
    my $sth1 = $dbm->prepare(qq{SELECT userid, email
                                FROM   users
                                WHERE  isa_list = ''
                                  AND  (
                                        cpan_mail_alias='publ'
                                        OR
                                        cpan_mail_alias='secr'
                                       )});
    $sth1->execute;
    while (my($id,$mail) = $sth1->fetchrow_array) {
      $ALL{$id} = $mail; # we store public email even for those who want
                         # secret, because we never know if we will find a
                         # secret one
    }
    $sth1->finish;
    my $sth2 = $dbm->prepare(qq{SELECT userid
                                FROM   users
                                WHERE  cpan_mail_alias='secr'
                                  AND  isa_list = ''});
    $sth2->execute;
    my $sth3 = $dba->prepare(qq{SELECT secretemail
                                FROM   usertable
                                WHERE  user=?});
    while (my($id) = $sth2->fetchrow_array) {
      $sth3->execute($id);
      next unless $sth3->rows;
      my($mail) = $sth3->fetchrow_array or next;
      $ALL{$id} = $mail;
    }
    $sth2->finish;
    $sth3->finish;
  };
  my $output_format = $req->param("OF");
  if ($output_format){
    if ($output_format eq "YAML") {
      require YAML::Syck;
      local $YAML::Syck::ImplicitUnicode = 1;
      my $dump = YAML::Syck::Dump(\%ALL);
      my $edump = Encode::encode_utf8($dump);
      my $res = $mgr->{RES};
      $res->content_type("text/plain; charset=utf8");
      $res->body($edump);
      return $mgr->{DONE} = HTTP_OK;
    } else {
      die "not supported OF=$output_format"
    }
  } else {
    for my $id (sort keys %ALL) {
      my($mail) = $ALL{$id};
      my $esc_mail = $mgr->escapeHTML($mail);
      push @m, "<tr><td>$id</td><td>$esc_mail</td></tr>\n";
    }
    push @m, "</table>";
    my $href = sprintf("authenquery?ACTION=email_for_admin;OF=YAML");
    push @m, qq{<p><a href="$href" style="text-decoration: none;">
<span class="orange_button">YAML</span>
</a></p>};
    return join "", @m;
  }
}

sub peek_perms {
  my $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};

  my @m;

  push @m, qq{<p>Query the <code>perms</code> table by author or by
            module. Select the option and fill in a module name or
            user ID as appropriate. The answer is all modules that an
            user ID is registered for or all user IDs registered for a
            module, as appropriate.</p>

            <p>Registration comes in one of three types: type
            <b>modulelist</b> is the registration in the old module
            list (like first-come with metadata). Type
            <b>first-come</b> is the automatic registration on a
            first-come-first-serve basis that happens on the initial
            upload. And type <b>co-maint</b> is the registration as
            co-maintainer which means that the primary maintainer of
            the namespace has granted permission to upload this module
            to other userid(s). Per namespace there can only be one
            primary maintainer (userid in the <b>modulelist</b> or the
            <b>first-come</b> category) and any number of userids in
            the <b>co-maint</b> category. Being registered in any of
            the categories means that a user is able not only to
            upload a module in that namespace but also be accepted by
            the indexer. In other words, the indexer will not ignore
            uploads for that namespace by that person.</p>

            <p>The
            contents of the tables presented on this page are mostly
            generated automatically, so please report any errors you
            observe to @{$PAUSE::Config->{ADMINS}} so that the tables
            can be corrected.--Thank you!</p><p>};


  unless ($req->param("pause99_peek_perms_query")) {
    $req->parameters->set("pause99_peek_perms_query", $mgr->{User}{userid});
  }
  unless ($req->param("pause99_peek_perms_by")) {
    $req->parameters->set("pause99_peek_perms_by","a");
  }

  push @m, $mgr->scrolling_list('name' => 'pause99_peek_perms_by',
                                size => 1,
                                values => [qw(me ml a)],
                                labels => {
                                           "me" => "for a module--exact match",
                                           "ml" => qq{for a module--SQL "LIKE" match},
                                           "a" => "of an author",
                                          }
                               );
  push @m, $mgr->textfield('name' => 'pause99_peek_perms_query',
                           size => 44,
                           maxlength => 112,
                          );
  push @m, qq{<input type="submit" name="pause99_peek_perms_sub" value="Submit" />
              </p>};

  if (my $qterm = $req->param("pause99_peek_perms_query")) {
    my $by = $req->param("pause99_peek_perms_by");
    my @query       = (
                qq{SELECT primeur.package,
                          primeur.userid,
                          "first-come",
                          primeur.userid
                   FROM primeur LEFT JOIN users ON primeur.userid=users.userid
},
                qq{SELECT perms.package,
                          perms.userid,
                          "co-maint",
                          primeur.userid
                   FROM perms LEFT JOIN users ON perms.userid=users.userid
                              LEFT JOIN primeur ON perms.package=primeur.package
},
               );

    my $db = $mgr->connect;
    my @res;
    my %seen;
    for my $query (@query) {
      my %fields = (
                    "first-come" => {
                                     package => "primeur.package",
                                     userid  => "primeur.userid",
                                    },
                    "co-maint" => {
                                   package => "perms.package",
                                   userid  => "perms.userid",
                                  }
                   );
      my($qtype) = $query =~ /\"(.+)\"/;
      my($fmap) = $fields{$qtype};
      my $where;
      if ($by =~ /^m/) {
        if ($by eq "me") {
          $where = qq{WHERE $fmap->{package}=?};
        } else {
          $where = qq{WHERE $fmap->{package} LIKE ? LIMIT 1000};
          # I saw 5.7.3 die with Out Of Memory on the query "%" when no
          # Limit was applied
        }
      } elsif ($by eq "a") {
        $where = qq{WHERE $fmap->{userid}=?};
      } else {
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR => "Illegal parameter for pause99_peek_perms_by");
      }
      $query .= $where;
      my $sth = $db->prepare($query);
      $sth->execute($qterm);
      if ($sth->rows > 0) {
        # warn sprintf "query[%s]qterm[%s]rows[%d]", $query, $qterm, $sth->rows;
        while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
          if ($seen{join "|", @row[0,1]}++){
            # warn "Ignoring row[$row[0]][$row[1]]";
            next;
          }
          push @res, \@row;
        }
      }
      $sth->finish;
    }
    if (@res) {
      for my $row (@res) {
        # add the owner on column 3
        # will already be set except for co-maint modules where the
        # owner is in the modlist but not first-come
        $row->[3] ||= $self->owner_of_module($mgr,$row->[0]);
      }
      my @column_names = qw(module userid type owner);
      my $output_format = $req->param("OF");
      if ($output_format){
        my @hres;
        for my $row (@res) {
          push @hres, { map {$column_names[$_] => $row->[$_] } 0..$#$row };
        }
        if ($output_format eq "YAML") {
          require YAML::Syck;
          local $YAML::Syck::ImplicitUnicode = 1;
          my $dump = YAML::Syck::Dump(\@hres);
          my $edump = Encode::encode_utf8($dump);
          my $res = $mgr->{RES};
          $res->content_type("text/plain; charset=utf8");
          $res->body($edump);
          return $mgr->{DONE} = HTTP_OK;
        } else {
          die "not supported OF=$output_format"
        }
      }
      push @m, qq{<table border="1" cellspacing="1" cellpadding="4">}; #};
      push @m, qq{<tr>};
      push @m, map { "<td><b>" . $mgr->escapeHTML($_) . "</b></td>"} @column_names;
      push @m, qq{</tr>};
      for my $row (sort {
        $a->[0] cmp $b->[0]
            ||
        $a->[1] cmp $b->[1]
            ||
        $a->[2] cmp $b->[2]
            ||
        $a->[3] cmp $b->[3]
      } @res) {
          push @m, qq{<tr>};
          # pause99_peek_perms_by=m&pause99_peek_perms_query=PerlIO&pause99_peek_perms_sub=+Submit+

          push @m, sprintf(
                           qq{<td><a href="authenquery?pause99_peek_perms_by=me&amp;pause99_peek_perms_query=%s&amp;pause99_peek_perms_sub=1">%s</a></td>
                               <td><a href="authenquery?pause99_peek_perms_by=a&amp;pause99_peek_perms_query=%s&amp;pause99_peek_perms_sub=1">%s</a></td>
                               <td>%s</td>
                               <td>%s</td>
},
                           $mgr->escapeHTML($row->[0]),
                           $mgr->escapeHTML($row->[0]),
                           $mgr->escapeHTML($row->[1]),
                           $mgr->escapeHTML($row->[1]),
                           $mgr->escapeHTML($row->[2]),
                           $mgr->escapeHTML($row->[3]),
                           );
          push @m, qq{</tr>};
      }
      my $href = sprintf("authenquery?pause99_peek_perms_by=%s;".
                         "pause99_peek_perms_query=%s;pause99_peek_perms_sub=1;".
                         "OF=YAML",
                         $req->param("pause99_peek_perms_by"),
                         URI::Escape::uri_escape($req->param("pause99_peek_perms_query"),'\W'),
                        );
      push @m, qq{</table><a href="$href" style="text-decoration: none;">
<span class="orange_button">YAML</span>
</a>};
    } else {
      push @m, qq{No records found.};
    }

  }

  @m;
}

sub owner_of_module {
  my($self,$mgr,$m) = @_;
  my $dbh = $mgr->connect;
  return PAUSE::owner_of_module($m, $dbh);
}

sub reindex {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my @m;
  my $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  require ExtUtils::Manifest;
  require HTTP::Date;
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;
  my $userhome = PAUSE::user2dir($u->{userid});

  push @m, qq{Indexing normally happens only once, shortly after the
              upload takes place. Sometimes it is necessary to reindex
              a file. The reason is typically one of the
              following:<ul>

<li>A file that contained a current version of a module got deleted,
now an older file should be considered current.</li>

<li>The <code>perms</code> table got altered, now a file should be
visited again to overrule the previous indexing decision.</li>

<li>At the time of uploading PAUSE had a bug and made a wrong indexing
decision.</li>

</ul> With this form you can tell the indexer to index selected files
    again. As it is done by a cron job, it may take up to an hour
    until the indexer actually executes the command. If this doesn't
    repair the index, please <a
    href="mailto:$PAUSE::Config->{UPLOAD}">email me</a>. };

  require Cwd;
  my $cwd = Cwd::cwd();

  # QUICK DEPARTURE
  unless (chdir "$PAUSE::Config->{MLROOT}/$userhome"){
    push @m, qq{No files found in authors/id/$userhome};
    return @m;
  }

  my $blurb;
  my $server = $PAUSE::Config->{SERVER_NAME}; # XXX: $r->server->server_hostname
  if ($req->param('SUBMIT_pause99_reindex_delete')) {

    my $sql = "DELETE FROM distmtimes
               WHERE dist = ?";
    my $sth = $dbh->prepare($sql);
    foreach my $f ($req->param('pause99_reindex_FILE')) {
      if ($f =~ m,^/, || $f =~ m,/\.\./,) {
	$blurb .= "WARNING: illegal filename: $userhome/$f\n";
	next;
      }
      unless (-f $f){
	$blurb .= "WARNING: file not found: $userhome/$f\n";
	next;
      }
      if ($f =~ m{ (^|/) CHECKSUMS }x) {
	$blurb .= "WARNING: indexing CHECKSUMS considered unnecessary: $userhome/$f\n";
	next;
      }
      # delete from distmtimes where distmtimes.dist like '%SREZIC%Tk-DateE%';
      my $ret = $sth->execute("$userhome/$f");
      $blurb .= "\$CPAN/authors/id/$userhome/$f\n";

    }
  }
  if ($blurb) {
    my $eta;
    {
      my $ctf = "$PAUSE::Config->{CRONPATH}/CRONTAB.ROOT"; # crontabfile
      unless (-f $ctf) {
        $ctf = "/tmp/crontab.root";
      }
      if (-f $ctf) {
        open my $fh, $ctf or die "XXX";
        local $/ = "\n";
        my $minute;
        while (<$fh>) {
          s/\#.*//;
          next unless /mldistwatch/;
          ($minute) = split " ", $_, 2;
          last;
        }
        require Set::Crontab;
        my $sc;
        eval { $sc = Set::Crontab->new($minute,[0..59]); };
        if ($@) {
          warn "Could not create a Crontab object: $@ (minute[$minute])";
          $eta = "N/A";
        } else {
          my $now = time;
          $now -= $now%60;
          for (my $i = 1; $i<=60; $i++) {
            my $fut = $now + $i * 60;
            my $fum = int $fut % 3600 / 60;
            next unless $sc->contains($fum);
            $eta = gmtime( $fut + $PAUSE::Config->{RUNTIME_MLDISTWATCH} ) . " UTC";
            last;
          }
        }
      } else {
        warn "Not found: $ctf";
        $eta = "N/A";
      }
    }
    $blurb =  sprintf(qq{According to a request entered by %s the
following files have been scheduled for reindexing.

%s
Estimated time of job completion: %s

%s},
                      $mgr->{User}{fullname},
                      $blurb,
                      $eta,
                      $Yours,
                     );
    my %umailset;
    my $name = $u->{asciiname} || $u->{fullname} || "";
    my $Uname = $mgr->{User}{asciiname} || $mgr->{User}{fullname} || "";
    if (0) { # debugging
      require Data::Dumper;
      my $dd = Data::Dumper::Dumper({ u => $u, mgrUser => $mgr->{User} });
      warn "email debugging: dd[$dd]";

      # By debugging this, I found out, that $u always had a
      # secretemail but $mgr->{User} didn't (upto rev 230).

    }
    if ($u->{secretemail}) {
      $umailset{qq{"$name" <$u->{secretemail}>}} = 1;
    } elsif ($u->{email}) {
      $umailset{qq{"$name" <$u->{email}>}} = 1;
    }
    if ($mgr->{User}{userid} ne $u->{userid}) {
      if ($mgr->{User}{secretemail}) {
        $umailset{qq{"$Uname" <$mgr->{User}{secretemail}>}} = 1;
      }elsif ($mgr->{User}{email}) {
        $umailset{qq{"$Uname" <$mgr->{User}{email}>}} = 1;
      }
    }
    $umailset{$PAUSE::Config->{ADMIN}} = 1;
    my $header = {
                  Subject => "Scheduled for reindexing $u->{userid}"
                 };
    $mgr->send_mail_multi([keys %umailset], $header, $blurb);

    push @m, qq{<hr /><pre>$blurb</pre><hr />};

  }

  push @m, qq{<h3>Files in directory authors/id/$userhome</h3>};

  my $submitbutton = qq{<input type="submit"
 name="SUBMIT_pause99_reindex_delete" value="Reindex" />};
  push @m, $submitbutton;
  push @m, "<pre>";

  my %files = $self->manifind;

  foreach my $f (keys %files) {
    if (
        $f =~ /readme$/ ||
        $f eq "CHECKSUMS"
       ) {
      delete $files{$f};
      next;
    }
    $files{$f} = sprintf " %s", $f;
  }

  chdir $cwd or die;

  my $field = $mgr->checkbox_group(
				    name      => 'pause99_reindex_FILE',
				    'values'  => [sort keys %files],
				    linebreak => 'true',
				    labels    => \%files
				   );
  $field =~ s!<br />\s*!\n!gs;

  push @m, $field;
  push @m, "</pre>";
  push @m, $submitbutton;

  @m;
}

sub share_perms {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  $mgr->prefer_post(1); # because the querystring can get too long

  my $subaction = $req->param("SUBACTION");
  unless ($subaction) {
    ####################### 2.1    2.2    3.1    3.2     4.1
  SUBACTION: for my $sa (qw(movepr remopr makeco remocos remome)) {
      if ($req->param("pause99_share_perms_$sa")
          or
          $req->param("SUBMIT_pause99_share_perms_$sa")
          or
          $req->param("weaksubmit_pause99_share_perms_$sa")
         ) {
        $subaction = $sa;
        last SUBACTION;
      }
    }
  }
  my $u = $self->active_user_record($mgr);
  # warn sprintf "subaction[%s] u->userid[%s]", $subaction||"", $u->{userid}||"";
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  push @m, qq{<input type="hidden" name="lsw" value="1" />}; # let submit win

  my $scrolling_list_mod = $self->share_perms_scrl_mod($mgr,$u->{userid});
  my $scrolling_list_remove_primary = $self->share_perms_scrl_remove_primary($mgr,$u);
  my $scrolling_list_make_comaintainer = $self->share_perms_scrl_make_comaintainer($mgr,$u);
  my $scrolling_list_remove_maintainer = $self->share_perms_scrl_remove_maintainer($mgr,$u);

  unless ($subaction) {

    # NOTE: the 6 submit buttons below are "weak" submit buttons. I
    # want that people first reach the next page with more text and
    # more options.


    push @m, qq{<p>Permissions on PAUSE come in three flavors:</p>


  <ul>
    <li>
      only one user per module can be either
      <br/>
      <ul>
        <li>
          registered in <i>modulelist</i> or
        </li>
        <li>
          primary maintainer on a <i>first-come-first-serve</i>
          basis;
        </li>
      </ul>
    </li>
    <li>
      many users can get granted permissions as <i>co-maintainers</i>,
      which means their uploads for the given module are honoured by
      the indexer.
    </li>
  </ul>

  <p>You can <i>view</i> your current set of permissions on the <a
  href="authenquery?ACTION=peek_perms">View Permissions</a> page. To
  <i>change</i> permissions, select one of the following submit
  buttons, each of which leads you to a different page:</p>

  <table class="texttable" cellspacing="2" cellpadding="3">

    <tbody>

      <tr>
        <td colspan="3">
          1. You are registered in modulelist
        </td>
      </tr>

      <tr>
        <td valign="top">$scrolling_list_mod</td>
        <td align="right" valign="top">
        </td>
        <td valign="top">
          <i>Module Metadata</i> has been removed from PAUSE and
          is no longer editable.  Please contact a PAUSE administrator to
          choose a new owner.
        </td>
      </tr>

      <tr><td colspan="3">2. You are primary maintainer:</td></tr>

      <tr>
        <td rowspan="2">$scrolling_list_remove_primary</td>
        <td align="right" valign="top">
          <input type="submit"
                 name="weaksubmit_pause99_share_perms_movepr"
                 value="Select"
                 />
        </td>
        <td valign="top">
          2.1 Transfer primary maintainership status to somebody else
          (you become co-maintainer)
        </td>
      </tr>

      <tr>
        <td align="right" valign="top">
          <input type="submit"
                 name="weaksubmit_pause99_share_perms_remopr"
                 value="Select"
                 />
        </td>
        <td valign="top">
          2.2 Give up primary maintainership status (abandoning it without
          transfering it to someone else)
        </td>
      </tr>

      <tr>
        <td colspan="3">
          3. Making and unmaking co-maintainers (for both modulelist
          owners and primary maintainers):
        </td>
      </tr>

      <tr>
        <td rowspan="2">$scrolling_list_make_comaintainer</td>
        <td align="right"
            valign="top">
          <input type="submit"
                 name="weaksubmit_pause99_share_perms_makeco"
                 value="Select"
                 />
        </td>
        <td valign="top">
          3.1 Make somebody else co-maintainer
        </td>
      </tr>

      <tr>
        <td align="right" valign="top">
          <input type="submit"
                 name="weaksubmit_pause99_share_perms_remocos"
                 value="Select"
                 />
        </td>
        <td valign="top">3.2 Remove a co-maintainer</td>
      </tr>

      <tr> <td colspan="3">4. You are co-maintainer</td> </tr>

      <tr>
        <td valign="top">$scrolling_list_remove_maintainer</td>
        <td align="right"
            valign="top"><input type="submit"
            name="weaksubmit_pause99_share_perms_remome" value="Select"
            />
        </td>
        <td valign="top">
          4.1 Give up co-maintainership status
        </td>
      </tr>

    </tbody>
  </table>

};

    return @m;
  }

  my $method = "share_perms_$subaction";
  # warn "method[$method]";
  push @m, $self->$method($mgr);
  @m;
}

sub share_perms_scrl_mod {
  my($self,$mgr,$userid) = @_;
  my $dbh = $mgr->connect;
  my $sql = qq{SELECT modid
              FROM mods
              WHERE userid=?
              AND mlstatus='list'
              ORDER BY modid};
  my @bind = $userid;
  my $sth = $dbh->prepare($sql);
  my $ret = $sth->execute(@bind);
  my @all_mods;
  while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
    # register this mailinglist for the selectbox
    push @all_mods, $id;
  }
  return "--NONE--" unless @all_mods;
  my $all_mods = scalar @all_mods;
  my $size = $all_mods > 8 ? 5 : $all_mods;
  $mgr->scrolling_list(
                       'name' => "pause99_edit_mod_3",
                       'values' => \@all_mods,
                       'size' => $size,
                      );
}

sub share_perms_scrl_remove_primary {
  my($self,$mgr,$u) = @_;
  my $dbh = $mgr->connect;

  my $all_mods = $self->all_pmods_not_mmods($mgr,$u);
  my @all_mods = sort keys %$all_mods;
  my $n = scalar @all_mods;
  return "--NONE--" unless $n;
  my $size = $n > 8 ? 5 : $n;
  $mgr->scrolling_list(
                       'name' => "pause99_share_perms_pr_m",
                       'multiple' => 1,
                       'values' => \@all_mods,
                       'size' => $size,
                      );
}

sub share_perms_scrl_make_comaintainer {
  my($self,$mgr,$u) = @_;
  my $dbh = $mgr->connect;

  my $all_mods = $self->all_pmods($mgr,$u);
  my @all_mods = sort keys %$all_mods;
  my $n = scalar @all_mods;
  return "--NONE--" unless $n;
  my $size = $n > 8 ? 5 : $n;
  # it should be sufficiently helpful to prepare only makeco_m on
  # these two submit buttons. For 3.2 people may be a little confused
  # but it is so rarely needed that we do not worry.
  $mgr->scrolling_list(
                       'name' => "pause99_share_perms_makeco_m",
                       'multiple' => 1,
                       'values' => \@all_mods,
                       'size' => $size,
                      );
}

sub share_perms_scrl_remove_maintainer {
  my($self,$mgr,$u) = @_;
  my $dbh = $mgr->connect;

  my $all_mods = $self->all_only_cmods($mgr,$u);
  my @all_mods = sort keys %$all_mods;
  my %labels;
  for my $m (@all_mods) {
    # get the owner for modlist modules that don't have first-come
    my $owner = $all_mods->{$m} || $self->owner_of_module($mgr,$m) || '?';
    $labels{$m} = "$m => $owner";
  }
  my $n = scalar @all_mods;
  return "--NONE--" unless $n;
  my $size = $n > 8 ? 5 : $n;
  $mgr->scrolling_list(
                       name     => "pause99_share_perms_remome_m",
                       multiple => 1,
                       values   => \@all_mods,
                       labels   => \%labels,
                       size     => $size,
                      );
}

sub share_perms_remocos {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  my $u = $self->active_user_record($mgr);

  my $db = $mgr->connect;
  my $all_mmods = $self->all_mmods($mgr,$u);
  my $all_pmods = $self->all_pmods($mgr,$u);
  my $all_mods = { %$all_mmods, %$all_pmods, $u };
  my $all_comaints = $self->all_comaints($mgr,$all_mods,$u);
  if (
      $req->param("SUBMIT_pause99_share_perms_remocos")
     ) {
    eval {
      my @sel = $req->param("pause99_share_perms_remocos_tuples");
      my $sth1 = $db->prepare("DELETE FROM perms WHERE package=? AND userid=?");
      if (@sel) {
        for my $sel (@sel) {
          my($selmod,$otheruser) = $sel =~ /^(\S+)\s--\s(\S+)$/;
          die PAUSE::HeavyCGI::Exception
              ->new(ERROR => "You do not seem to be owner of $selmod")
                  unless exists $all_mods->{$selmod};
          unless (exists $all_comaints->{$sel}) {
            push @m, "<p>Cannot handle tuple <i>$sel</i>. If you
              believe, this is a bug, please complain.</p>";
            next;
          }
          my $ret = $sth1->execute($selmod,$otheruser);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]ret[$ret]err[$err]";
          if ($ret) {
            push @m, "<p>Removed $otheruser from co-maintainers of $selmod.</p>\n";
          } else {
            push @m, "<p>Error trying to remove $otheruser from co-maintainers of
                    $selmod: $err</p>\n";
          }
        }
      } else {
        push @m, qq{<p>You need to select one or more packages. Nothing done.</p>}
      }
    };
    if ($@) {
      push @m, "<p>", $@->{ERROR}, "</p>";
    }
    push @m, "<hr />\n";
  }
  $all_comaints = $self->all_comaints($mgr,$all_mods,$u);
  my @all = sort keys %$all_comaints;
  my $n = scalar @all;
  my $size = $n > 8 ? 5 : $n;
  unless ($size) {

    push @m, qq{<p>There are no co-maintainers registered to any of
                $u->{userid}'s modules.</p> };

    return @m;
  }

  push @m, qq{<h3>Remove co-maintainer status</h3><p>The scrolling
            list shows you, which packages are associated with other
            maintainers besides yourself. Every line denotes a tuple
            of a namespace and a userid. Select those that you want to
            remove and press <i>Remove</i></p><p>};
  if (@all == 1) {
    # selectboxes with only ine option to select look confusing and
    # better be preselected:
    $req->parameters->set("pause99_share_perms_remocos_tuples",$all[0]);
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_share_perms_remocos_tuples",
                                'multiple' => 1,
				'values' => \@all,
				'size' => $size,
			       );
  push @m, qq{</p>};
  push @m, qq{<p>};
  push @m, qq{<input type="submit" name="SUBMIT_pause99_share_perms_remocos"
 value="Remove" /></p>};
  @m;
}

sub all_comaints {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $all_mods = shift;
  my $u = shift;
  my $result = {};
  my $db = $mgr->connect;
  my $or = join " OR\n", map { "package='$_'" } keys %$all_mods;
  my $sth2 = $db->prepare(qq{SELECT package, userid
                             FROM perms
                             WHERE userid <> '$u->{userid}' AND ( $or )});
  $sth2->execute;
  while (my($p,$i) = $mgr->fetchrow($sth2,"fetchrow_array")) {
    $result->{"$p -- $i"} = undef;
    warn "p[$p]i[$i]";
  }
  return $result;
}

sub all_only_cmods {
  my($self,$mgr,$u) = @_;
  my $all_mmods = $self->all_mmods($mgr,$u);
  my $all_pmods = $self->all_pmods($mgr,$u);
  my $all_mods = $self->all_cmods($mgr,$u);

  for my $k (keys %$all_mmods) {
    delete $all_mods->{$k};
  }
  for my $k (keys %$all_pmods) {
    delete $all_mods->{$k};
  }
  $all_mods;
}

sub share_perms_remome {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  my $u = $self->active_user_record($mgr);
  my $db = $mgr->connect;

  my $all_mods = $self->all_only_cmods($mgr,$u);

  if (
      $req->param("SUBMIT_pause99_share_perms_remome")
     ) {
    eval {
      my(@selmods);
      if (@selmods = $req->param("pause99_share_perms_remome_m")
         ) {
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("DELETE FROM perms WHERE package=? AND userid=?");
        for my $selmod (@selmods) {
          die PAUSE::HeavyCGI::Exception
              ->new(ERROR => "You do not seem to be co-maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($selmod,$u->{userid});
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]ret[$ret]err[$err]";
          if ($ret) {
            push @m, "<p>Removed $u->{userid} from co-maintainers of $selmod.</p>\n";
            delete $all_mods->{$selmod};
          } else {
            push @m, "<p>Error trying to remove $u->{userid} from co-maintainers of
                    $selmod: $err</p>\n";
          }
        }
      } else {
        push @m, qq{<p>You need to select one or more packages. Nothing done.</p>};
      }
    };
    if ($@) {
      push @m, "<p>", $@->{ERROR}, "</p>";
    }
    push @m, "<hr />\n";
  }

  my @all_mods = sort keys %$all_mods;
  my $n = scalar @all_mods;
  my $size = $n > 8 ? 5 : $n;
  unless ($size) {

    push @m, qq{<p>Sorry, $u->{userid} does not seem to be co-maintainer of any module.</p> };

    return @m;
  }
  push @m, qq{<h3>Give up co-maintainer status</h3><p>Please select one or
           more namespaces for which you want to be removed from
           the co-maintainer table and press <i>Give Up</i></p>};

  push @m, qq{<p>Select one or more namespaces:</p><p>};
  if (@all_mods == 1) {
    $req->parameters->set("pause99_share_perms_remome_m",$all_mods[0]);
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_share_perms_remome_m",
                                'multiple' => 1,
				'values' => \@all_mods,
				'size' => $size,
			       );
  push @m, qq{</p>};
  push @m, qq{<p>};
  push @m, qq{<input type="submit" name="SUBMIT_pause99_share_perms_remome"
 value="Give Up" /></p>};

  @m;
}

sub share_perms_makeco {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  my $u = $self->active_user_record($mgr);
  # warn "u->userid[%s]", $u->{userid};

  my $db = $mgr->connect;

  my $all_mmods = $self->all_mmods($mgr,$u);
  # warn sprintf "all_mmods[%s]", join("|", keys %$all_mmods);
  my $all_pmods = $self->all_pmods($mgr,$u);
  # warn sprintf "all_pmods[%s]", join("|", keys %$all_pmods);
  my $all_mods = {%$all_mmods, %$all_pmods};

  if (
      $req->param("SUBMIT_pause99_share_perms_makeco")
     ) {
    eval {
      my(@selmods,$other_user);
      if (@selmods = $req->param("pause99_share_perms_makeco_m")
          and
          $other_user = $req->param("pause99_share_perms_makeco_a")
         ) {
        $other_user = uc $other_user;
        my $sth1 = $db->prepare("SELECT userid
                                 FROM users
                                 WHERE userid=?");
        $sth1->execute($other_user);
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR => sprintf(
                                   "%s is not a valid userid.",
                                   $mgr->escapeHTML($other_user),
                                  )
                 )
                unless $sth1->rows;
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("INSERT INTO perms (package,userid)
                            VALUES (?,?)");
        for my $selmod (@selmods) {
          die PAUSE::HeavyCGI::Exception
              ->new(ERROR => "You do not seem to be maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($selmod,$other_user);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]other_user[$other_user]ret[$ret]err[$err]";
          if ($ret) {
            push @m, "<p>Added $other_user to co-maintainers of $selmod.</p>\n";
          } elsif ($err =~ /Duplicate entry/) {
            push @m, "<p>$other_user was already a co-maintainer of $selmod: skipping</p>";
          } else {
            push @m, "<p>Error trying to add $other_user to co-maintainers of
                    $selmod: $err</p>\n";
          }
        }
      } else {
        push @m, qq{<p>You need to select one or more packages and enter a userid.
 Nothing done.</p>};
      }
    };
    if ($@) {
      push @m, "<p>", $@->{ERROR}, "</p>";
    }
    push @m, "<hr />\n";
  }

  my @all_mods = sort keys %$all_mods;
  my $n = scalar @all_mods;
  my $size = $n > 8 ? 5 : $n;
  unless ($size) {

    push @m, qq{<p>Sorry, there are no modules registered belonging to
                $u->{userid}.</p> };

    return @m;
  }
  push @m, qq{<h3>Select a co-maintainer</h3><p>Please select one or
           more namespaces for which you want to select a
           co-maintainer, enter the CPAN userid of the co-maintainer
           into the text field and press <i>Make Co-Maintainer</i></p>};

  push @m, qq{<p>Select one or more namespaces:</p><p>};
  if (@all_mods == 1) {
    $req->parameters->set("pause99_share_perms_makeco_m",$all_mods[0]);
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_share_perms_makeco_m",
                                'multiple' => 1,
				'values' => \@all_mods,
				'size' => $size,
			       );
  push @m, qq{</p>};
  push @m, qq{<p>Select a userid:<br />};
  push @m, $mgr->textfield(
                           'name' => "pause99_share_perms_makeco_a",
                           size => 15,
                           maxlength => 9,
                          );
  push @m, qq{</p><p>};
  push @m, qq{<input type="submit" name="SUBMIT_pause99_share_perms_makeco"
 value="Make Co-Maintainer" /></p>};

  @m;
}

sub share_perms_remopr {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  my $u = $self->active_user_record($mgr);

  my $db = $mgr->connect;

  my $all_mods = $self->all_pmods_not_mmods($mgr,$u);

  if (0) {
    # here I discovered that Apache::Request has case-insensitive keys
    my %p = map { $_, [ $req->param($_)] } $req->param;
    require Data::Dumper; print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([\%p],[qw()])->Indent(1)->Useqq(1)->Dump; # XXX

  }

  if (
      $req->param("SUBMIT_pause99_share_perms_remopr")
     ) {
    eval {
      my(@selmods);
      if (@selmods = $req->param("pause99_share_perms_pr_m")
         ) {
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("DELETE FROM primeur WHERE userid=? AND package=?");
        for my $selmod (@selmods) {
          die PAUSE::HeavyCGI::Exception
              ->new(ERROR => "You do not seem to be maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($u->{userid},$selmod);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]ret[$ret]err[$err]";
          if ($ret) {
            push @m, "<p>Removed primary maintainership of $u->{userid} from $selmod.</p>\n";
          } else {
            push @m, "<p>Error trying to remove primary maintainership of $u->{userid}
                    from $selmod: $err</p>\n";
          }
        }
      } else {
        push @m, qq{<p>You need to select one or more packages. Nothing done.</p>};
      }
    };
    if ($@) {
      push @m, "<p>", $@->{ERROR}, "</p>";
    }
    push @m, "<hr />\n";
  }

  $all_mods = $self->all_pmods_not_mmods($mgr,$u); # yes, again!
  my @all_mods = sort keys %$all_mods;
  my $n = scalar @all_mods;
  my $size = $n > 8 ? 5 : $n;
  unless ($size) {

    push @m, qq{<p>Sorry, there are no modules registered belonging to
                $u->{userid}.</p> };

    return @m; } push @m, qq{<h3>Give up maintainership
      status</h3><p>Please select one or more namespaces for which you
      want to give up primary maintainership status and press
      <i>Give Up Maintainership Status</i>. Note: you keep co-maintainer
      status after this move. If you want to get rid of that too,
      please visit <a
      href="authenquery?pause99_share_perms_remome=1">Give up
      co-maintainership status</a> next.</p>};

  push @m, qq{<p>Select one or more namespaces:</p><p>};
  if (@all_mods == 1) {
    $req->parameters->set("pause99_share_perms_pr_m",$all_mods[0]);
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_share_perms_pr_m",
                                'multiple' => 1,
				'values' => \@all_mods,
				'size' => $size,
			       );
  push @m, qq{</p><p>};
  push @m, qq{<input type="submit" name="SUBMIT_pause99_share_perms_remopr"
 value="Give Up Maintainership Status" /></p>};

  @m;
}

sub share_perms_movepr {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my(@m);
  my $req = $mgr->{REQ};

  my $u = $self->active_user_record($mgr);

  my $db = $mgr->connect;

  my $all_mods = $self->all_pmods_not_mmods($mgr,$u);

  if (
      $req->param("SUBMIT_pause99_share_perms_movepr")
     ) {
    eval {
      my(@selmods,$other_user);
      if (@selmods = $req->param("pause99_share_perms_pr_m")
          and
          $other_user = $req->param("pause99_share_perms_movepr_a")
         ) {
        $other_user = uc $other_user;
        my $sth1 = $db->prepare("SELECT userid
                                 FROM users
                                 WHERE userid=?");
        $sth1->execute($other_user);
        die PAUSE::HeavyCGI::Exception
            ->new(ERROR => sprintf(
                                   "%s is not a valid userid.",
                                   $mgr->escapeHTML($other_user),
                                  )
                 )
                unless $sth1->rows;
        local($db->{RaiseError}) = 0;
        my $sth = $db->prepare("UPDATE primeur SET userid=? WHERE package=?");
        for my $selmod (@selmods) {
          die PAUSE::HeavyCGI::Exception
              ->new(ERROR => "You do not seem to be maintainer of $selmod")
                  unless exists $all_mods->{$selmod};
          my $ret = $sth->execute($other_user,$selmod);
          my $err = "";
          $err = $db->errstr unless defined $ret;
          $ret ||= "";
          warn "DEBUG: selmod[$selmod]other_user[$other_user]ret[$ret]err[$err]";
          if ($ret) {
            push @m, "<p>Made $other_user primary maintainer of $selmod.</p>\n";
          } else {
            push @m, "<p>Error trying to make $other_user primary maintainer of
                    $selmod: $err</p>\n";
          }
        }
      } else {
        push @m, qq{<p>You need to select one or more packages and enter a userid.
 Nothing done.</p>};
      }
    };
    if ($@) {
      push @m, "<p>", $@->{ERROR}, "</p>";
    }
    push @m, "<hr />\n";
  }

  $all_mods = $self->all_pmods_not_mmods($mgr,$u); # yes, again!
  my @all_mods = sort keys %$all_mods;
  my $n = scalar @all_mods;
  my $size = $n > 8 ? 5 : $n;
  unless ($size) {

    push @m, qq{<p>Sorry, there are no modules registered belonging to
                $u->{userid}.</p> };

    return @m;
  }

  push @m, qq{<h3>Pass maintainership status</h3><p>Please select one
      or more namespaces for which you want to pass primary
      maintainership status, enter the CPAN userid of the new
      maintainer into the text field and press <i>Pass Maintainership
      Status</i>. Note: you keep co-maintainer status after this move.
      If you want to get rid of that too, please visit <a
      href="authenquery?pause99_share_perms_remome=1">Give up
      co-maintainership status</a> next.</p>};

  push @m, qq{<p>Select one or more namespaces:</p><p>};
  if (@all_mods == 1) {
    $req->parameters->set("pause99_share_perms_pr_m",$all_mods[0]);
  }
  push @m, $mgr->scrolling_list(
				'name' => "pause99_share_perms_pr_m",
                                'multiple' => 1,
				'values' => \@all_mods,
				'size' => $size,
			       );
  push @m, qq{</p>};
  push @m, qq{<p>Select a userid:<br />};
  push @m, $mgr->textfield(
                           'name' => "pause99_share_perms_movepr_a",
                           size => 15,
                           maxlength => 9,
                          );
  push @m, qq{</p><p>};
  push @m, qq{<input type="submit" name="SUBMIT_pause99_share_perms_movepr"
 value="Pass Maintainership Status" /></p>};

  @m;
}

sub all_mmods {
  my $self = shift;
  my $mgr = shift;
  my $u = shift;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT modid
                             FROM mods
                             WHERE userid=?});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = undef;
  }
  $sth2->finish;
  \%all_mods;
}

sub all_pmods {
  my $self = shift;
  my $mgr = shift;
  my $u = shift;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT package
                             FROM primeur
                             WHERE userid=?});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = undef;
  }
  $sth2->finish;
  \%all_mods;
}

sub all_pmods_not_mmods {
  my $self = shift;
  my $mgr = shift;
  my $u = shift;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT package
                             FROM primeur
                             WHERE userid=?});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = undef;
  }
  $sth2->finish;
  $sth2 = $db->prepare(qq{SELECT modid
                             FROM mods
                             WHERE userid=?
                             AND mlstatus='list'
});
  $sth2->execute($u->{userid});
  while (my($id) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    delete $all_mods{$id};
  }
  $sth2->finish;
  \%all_mods;
}

sub all_cmods {
  my $self = shift;
  my $mgr = shift;
  my $u = shift;
  my $db = $mgr->connect;
  my(%all_mods);
  my $sth2 = $db->prepare(qq{SELECT perms.package, primeur.userid
                             FROM perms LEFT JOIN primeur
                               ON perms.package = primeur.package
                             WHERE perms.userid=?});
  $sth2->execute($u->{userid});
  while (my($id, $owner) = $mgr->fetchrow($sth2, "fetchrow_array")) {
    $all_mods{$id} = $owner;
  }
  $sth2->finish;
  \%all_mods;
}




=pod

Thanks to Slaven Rezic for his help in finding the solution how to
produce core dumps of apache under Linux. Here are the guts:

Running h2ph is required and beforehand it is recommended to test as
root something like this:

mkdir tmp
chown nobody tmp
cd tmp
limit coredumpsize 30m
perl -e '
    require "syscall.ph";
    require "linux/sys.ph";
    require "linux/prctl.ph";
    $user = shift or die;
    my $uid = (getpwnam($user))[2];
    $< = $> = $uid;
    print syscall(&SYS_prctl,&PR_SET_DUMPABLE,1);
    warn $<;
    dump;' nobody
ls -l core

If this shows a core file when run with the same perl as the
webserver, then it should succeed on the webserver too.

You will additionally have to set coredumpsize for nobody via
/etc/security/limits.conf and add CoreDumpDirectory
/directory/owned/by/nobody to the httpd.conf or do something
equivalent.

=cut


sub coredump {
  my $self = shift;
  my $mgr = shift;

  die "The coredump interface was just a testbed to find out how to
  enable coredumps on Linux. Now disabled.";

  require "syscall.ph";
  require "linux/sys.ph";
  require "linux/prctl.ph";
  warn syscall(&SYS_prctl,&PR_SET_DUMPABLE,1);
  chdir "/usr/local/apache/cores" or die "Couldn't chdir: $!";
  warn "**************>>>>>>>>>>     strace -p $$\n";
  sleep 10;
  require Cwd;
  my $cwd = Cwd::cwd();
  require BSD::Resource;
  my($nowsoft,$nowhard) = BSD::Resource::getrlimit(BSD::Resource::RLIMIT_CORE());
  $mgr->{REQ}->logger({level => 'error', message => "UID[$<]EUID[$>]cwd[$cwd]nowsoft[$nowsoft]nowhard[$nowhard]"});
  CORE::dump;
}

sub dele_message {
  my($self,$mgr) = @_;

  my @m = qq{<p>Admins can add and delete messages to a message board.
  When a user visits PAUSE they see the pending messages for them and
  are requested to answer to the admin who placed the message. Usage
  scenario: email bounces, google doesn't get us closer to the user,
  that kind of thing. When the cause is settled the admin should
  delete the message to not any longer annoy the user with it. The
  user cannot delete the message.</p>

  <p>To delete messages, click on the radio buttons and then press
  <i>Delete</i>.</p>};

  my $dbh = $mgr->connect;
  my $req = $mgr->{REQ};
  my $sth = $dbh->prepare("SELECT * FROM messages where mfrom=? AND mstatus='active'
 ORDER BY created desc");
  $sth->execute($mgr->{User}{userid});
  if ($sth->rows) {
    if ($req->param('SUBMIT_pause99_dele_message_sub')) {
      # get another handle
      my $sth2 = $dbh->prepare("UPDATE messages set mstatus='deleted'
 WHERE mfrom=? AND c=?");
      for my $m ($req->param('pause99_dele_message_m')) {
        $sth2->execute($mgr->{User}{userid}, $m);
      }
      $sth->execute($mgr->{User}{userid});
    }
  }
  if ($sth->rows) {
    push @m, qq{<input type="submit"
 name="SUBMIT_pause99_dele_message_sub" value="Delete" /><pre>};
    my(@v,%l);
    my $tf = Text::Format->new(firstIndent => 36, bodyIndent => 36, columns => 90);
    while (my $rec = $sth->fetchrow_hashref) {
      push @v, $rec->{c};
      my $fmessage = $tf->format($rec->{message});
      $fmessage =~ s/^\s+//;
      $l{$rec->{c}} = sprintf(qq{<a href="?ACTION=edit_cred&amp;HIDDENNAME=%s">%*s</a>%*s %s | %s},
                              $rec->{mto},
                              length($rec->{mto}),
                              $rec->{mto},
                              10-length($rec->{mto}),
                              "",
                              $rec->{created},
                              $mgr->escapeHTML($fmessage),
                             );
    }
    my $field = $mgr->checkbox_group(
                                      name      => 'pause99_dele_message_m',
                                      'values'  => \@v,
                                      linebreak => 'true',
                                      labels    => \%l
                                     );
    $field =~ s!<br />\s*!\n!gs;

    push @m, $field;
    push @m, qq{</pre>};
  } else {
    push @m, qq{<p>No messages found.</p>};
  }
  @m;
}

sub post_message {
  my($self,$mgr) = @_;

  my @m = qq{<p>Admins can add and delete messages to a message board.
  When a user visits PAUSE they see the pending messages for them and
  are requested to answer to the admin who placed the message. Usage
  scenario: email bounces, google doesn't get us closer to the user,
  that kind of thing. When the cause is settled the admin should
  delete the message to not any longer annoy the user with it. The
  user cannot delete the message.</p>

  <p>To post a message, fill in the form and press
  <i>Submit</i>.</p><hr />};

  my $dbh = $mgr->connect;
  my $req = $mgr->{REQ};

  my $mto = $req->param('pause99_post_message_mto');
  $mto = uc $mto;
  my $mess = $req->param('pause99_post_message_mess');
  warn "mto[$mto]mess[$mess]";

  my $showform = 0;
  my $regOK = 0;

  if ($req->param('SUBMIT_pause99_post_message_sub')) {
    my @errors = ();
    unless ($mto) {
      push @errors, "You must supply a message";
    }
    if ($mto) {
      my $sth = $dbh->prepare("SELECT userid FROM users where userid=?");
      $sth->execute($mto);
      unless ($sth->rows) {
        push @errors, sprintf "Userid %s is not known", $mgr->escapeHTML($mto);
      }
      $sth->finish;
    } else {
      push @errors, "You must supply a userid";
    }
    if( @errors ) {
      push @m, qq{<h3>Error processing form</h3>};
      for (@errors) {
        push @m, "<ul>", "<li>$_</li>", "</ul>";
      }
      push @m, qq{<p>Please retry.</p>};
    } else {
      # we don't sweat over the time zone, mysql does it in the zone
      # of the server and turning it into UTC seems not worth the
      # effort right now (2003-03-04)
      my $sth = $dbh->prepare("INSERT INTO messages
                                      (mfrom,mto,created,message)
                               VALUES (?    ,?  ,NOW()  ,?      )");
      $sth->execute($mgr->{User}{userid},$mto,$mess);
      push @m, sprintf qq{Message to
 <a href="?ACTION=edit_cred&amp;HIDDENNAME=%s">%s</a> posted.},
          ($mgr->escapeHTML($mto))x2;
      for my $f (qw(mto mess)) {
        $req->parameters->set("pause99_post_message_$f","");
      }
    }
  }
  for my $arr (
               ['Userid','mto',10,10],
               ['Message','mess',60,255],
              ) {
    push @m, qq{<p><b>$arr->[0]</b></p><p>};
    push @m, $mgr->textfield(
                             name => "pause99_post_message_$arr->[1]",
                             size => $arr->[2],
                             maxsize => $arr->[3]
                            );
    push @m, "</p>";
  }
  push @m, qq{<input type="submit" name="SUBMIT_pause99_post_message_sub"
  	  value="Submit" />};


  @m;
}

sub reset_version {
  my pause_1999::edit $self = shift;
  my $mgr = shift;
  my $req = $mgr->{REQ};
  my @m;
  my $u = $self->active_user_record($mgr);
  push @m, qq{<input type="hidden" name="HIDDENNAME" value="$u->{userid}" />};
  my $dbh = $mgr->connect;
  local($dbh->{RaiseError}) = 0;

  push @m, qq{<p>Note: resetting versions is a major inconvenience for
    module users. This page will probably be withdrawn from PAUSE if
    the perl community does not want to allow falling version numbers
    on the CPAN. For now: use with care. Thanks.</p>

    <p>Below you see the packages and version numbers that
    the indexer considers the current and highest version number that
    it has seen so far. By selecting an item in the list and clicking
    <i>Forget</i>, this value is set to <i>undef</i>. This opens the
    way for a <i>Force Reindexing</i> run in which the version of the
    package in the reindexed distribution can become the current.</p>

    <p>Did I say, this operation should not be done lightly? Because
    users of the module out there may still have that higher version
    installed and so will not notice the newer but lower-numbered
    release. Let me repeat: please make responsible use of this
    page.</p>

    <p>Q: So why is this page up at all?</p>

    <p>A: Combine a multi-module-distro with a small mistake in an
    older release or a bug in the PAUSE indexer. In such a case you
    will be happy to use this page and nobody else will ever notice
    there was a problem.</p>

};
  my $blurb = "";
  my($usersubstr) = sprintf("%s/%s/%s/",
                            substr($u->{userid},0,1),
                            substr($u->{userid},0,2),
                            $u->{userid},
                           );
  my($usersubstrlen) = length $usersubstr;
  my $sqls = "SELECT package, version, dist FROM packages
             WHERE substring(dist,1,$usersubstrlen) = ?";
  my $sths = $dbh->prepare($sqls);
  if ($req->param('SUBMIT_pause99_reset_version_forget')) {
    my $sqls2 = "SELECT version FROM packages
             WHERE package = ? AND substring(dist,1,$usersubstrlen) = ?";
    my $sths2 = $dbh->prepare($sqls2);
    my $sqlu = "UPDATE packages
               SET version='undef'
               WHERE package = ? AND substring(dist,1,$usersubstrlen) = ?";
    my $sthu = $dbh->prepare($sqlu);
  PKG: foreach my $f ($req->param('pause99_reset_version_PKG')) {
      $sths2->execute($f,$usersubstr);
      my($version) = $sths2->fetchrow_array;
      next PKG if $version eq 'undef';
      my $ret = $sthu->execute($f,$usersubstr);
      $blurb .= sprintf(
                        "%s: %s '%s' => 'undef'\n",
                        $ret==0 ? "Not reset" : "Reset",
                        $f,
                        $version,
                       );
    }
  }
  if ($blurb) {

    $blurb = sprintf(qq{According to a request by %s the following
packages have their recorded version set to 'undef'.

%s

%s},
                     $mgr->{User}{fullname},
                     $blurb,
                     $Yours,
                    );
    my %umailset;
    my $name = $u->{asciiname} || $u->{fullname} || "";
    my $Uname = $mgr->{User}{asciiname} || $mgr->{User}{fullname} || "";

    if ($u->{secretemail}) {
      $umailset{qq{"$name" <$u->{secretemail}>}} = 1;
    } elsif ($u->{email}) {
      $umailset{qq{"$name" <$u->{email}>}} = 1;
    }
    if ($mgr->{User}{userid} ne $u->{userid}) {
      if ($mgr->{User}{secretemail}) {
        $umailset{qq{"$Uname" <$mgr->{User}{secretemail}>}} = 1;
      }elsif ($mgr->{User}{email}) {
        $umailset{qq{"$Uname" <$mgr->{User}{email}>}} = 1;
      }
    }
    $umailset{$PAUSE::Config->{ADMIN}} = 1;
    my $header = {
                  Subject => "Version reset for $u->{userid}"
                 };
    $mgr->send_mail_multi([keys %umailset], $header, $blurb);

    push @m, qq{<hr /><pre>$blurb</pre><hr />};

  }
  $sths->execute($usersubstr);
  if ($sths->rows == 0) {
    push @m, qq{<h3>No packages associated with $u->{userid}</h3>};
    return @m;
  }

  push @m, sprintf(
                   qq{<h3>%d %s associated with %s</h3>},
                   $sths->rows,
                   $sths->rows == 1 ? "package" : "packages",
                   $u->{userid},
                  );
  my(@maxl,%p);
  while (my(@row) = $sths->fetchrow_array) {
    for my $i (0..$#row) {
      if (!$maxl[$i] or $maxl[$i]<length($row[$i])) {
        $maxl[$i] = length($row[$i]);
      }
    }
    $p{$row[0]} = \@row;
  }
  my $sprintf = join " | ", map { "%-$_"."s" } @maxl;
  while (my($k,$v) = each %p) {
    $p{$k} = sprintf $sprintf, @$v;
  }
  
  my $submitbutton = qq{<input type="submit"
 name="SUBMIT_pause99_reset_version_forget" value="Forget" />};
  push @m, $submitbutton;
  push @m, "<pre>";
  my $field = $mgr->checkbox_group(
                                   name      => 'pause99_reset_version_PKG',
                                   'values'  => [sort keys %p],
                                   linebreak => 'true',
                                   labels    => \%p
                                  );
  $field =~ s!<br />\s*!\n!gs;

  push @m, $field;
  push @m, "</pre>";
  push @m, $submitbutton;
  @m;
}

1;
#Local Variables:
#mode: cperl
#cperl-indent-level: 2
#End:

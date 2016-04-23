=head1 NAME

main -

=head1 SYNOPSIS



=head1 DESCRIPTION

=head2 About how to add an action item to the usermenu

Add a subroutine that implements it in edit.pm,

add a security policy for the item in edit::parameter method,

(optionally) add a verbose name to attribute ActionTuning in
config.pm,

decide if the action should be allowed to the admin with "HIDDENNAME"
and if so, add it to AllowAdminTakeover attribute.

if a mailing list is to be involved, decide if the action should be
allowed to the mailinglist-representative and if so, add it to
AllowMlreprTakeover

That is it.

In the menu, entries are being sorted by method name. If we have too
many menu entries, we need to think about grouping and different
sorting.

=head2 about testing the whole thing

query must offer "Forgot password", "About PAUSE", "PAUSE News",
"PAUSE History", and "Who is Who".

Who is Who must display a list of > 1400 users and Szabo Balazs must
have an accent on the o and the last a. At the end of the list we find
KUJUN and KENSHAN in Japanese letters. Currently we have lowercase
people after uppercase people, but this ought to change.

authenquery must display several menus. Edit account info should be
tested for Andreas Koenig with and without Umlaut. The mails that get
sent out should be reviewed if they have correct charset.

A new perl installation will not only have impact on the Web
application but also on the cronjobs and other scripts on PAUSE and
possibly in the modulelist/ directory. So we should not replace the
perl at the same time as the application. We should rather leave the
default perl be the old perl and port one script after the other to
the new perl.

=head2 Methods

=over

=cut



package pause_1999::main;
use PAUSE::HeavyCGI; # This is much better than only second line
                      # alone. If PAUSE::HeavyCGI is not available,
                      # the errormessage of the next line would be 'No
                      # such pseudo-hash field "R" in variable $self'
use base PAUSE::HeavyCGI;
use Sys::Hostname;
# # use Apache::URI ();

 # use encoding "utf-8";

 # apparently very buggy with 5.7.3@16103: test with select_user and
 # the warn statement within scrolling_list that matches /AND/.
 # Several nonsense things in the output. I do not want to dig into that.

 # Outcommenting of the use encoding statement is not enough: you must
 # restart the server to get rid of it. BTW, HTML::Parser was 3.26 but
 # with Unicode support off.

use strict;
use vars qw($VERSION %entity2char $DO_UTF8);
$VERSION = "854";

$DO_UTF8 = 1;
use HTTP::Status qw(:constants);
require Unicode::String;
use HTML::Entities;
use String::Random ();
use Fcntl qw(O_RDWR);
use Time::HiRes ();

{
  %entity2char = %HTML::Entities::entity2char;
  while (my($k,$v) = each %entity2char) {
    if ($v =~ /[^\000-\177]/) {
      $entity2char{$k} = Unicode::String::latin1($v)->utf8;
      # warn "CONV k[$k] v[$v]";
    } else {
      delete $entity2char{$k};
      # warn "DEL v[$v]";
    }
  }
}

use fields qw(

Action
ActionTuning
ActiveColor
AllowAction
AllowAdminTakeover
AllowMlreprTakeover
AuthenDsn
AuthenDsnPasswd
AuthenDsnUser
CanMultipart
DbHandle4Authen
DbHandle
DocumentRoot
DownTime
EditOutput
HiddenUser
IsMailinglistRepresentative
IsSSL
MailMailerConstructorArgs
MailtoAdmins
ModDsn
ModDsnPasswd
ModDsnUser
NeedMultipart
OurEmailFrom
PreferPost
QueryURL
RootURL
Session
SessionDataDir
SessionCounterDir
SessionCounterFile
UseModuleSet
User
UserAgent
UserGroups
UserId
UserSecrets
VERSION
WaitDir
WaitUserDb
WillLast

);

sub dispatch {
  my $self = shift;
  $self->init;
  my $req = $self->{REQ};
  warn sprintf "DEBUG: uri[%s]location[%s]", $req->path, ''; # $r->location;
  if ($req->path =~ m|^/pause/query/|) { # path info?
      warn "Warning: killing this request, it has a path_info, only bots have them";
      return HTTP_NOT_FOUND;
  }
  eval { $self->prepare; };
  if ($@) {
    if (UNIVERSAL::isa($@,"PAUSE::HeavyCGI::Exception")) {
      if ($@->{ERROR}) {
        require Carp;
	$@->{ERROR} = [ $@->{ERROR} ] unless ref $@->{ERROR};
	push @{$self->{ERROR}}, @{$@->{ERROR}};
        require Data::Dumper;
        print STDERR "Line " . __LINE__ . ", File: " . __FILE__ . "\n" . Data::Dumper->new([$self->{ERROR}],[qw(error)])->Indent(1)->Useqq(1)->Dump; # XXX
      } elsif ($@->{HTTP_STATUS}) {
	return $@->{HTTP_STATUS};
      }
    } else {
      # this is NOT a known error type, we need to handle it anon
      if ($self->{ERRORS_TO_BROWSER}) {
	push @{$self->{ERROR}}, " ", $@;
      } else {
	$req->logger->({level => 'error', message => $@ });
	return HTTP_INTERNAL_SERVER_ERROR;
      }
    }
  }
  return $self->{RES}->finalize if $self->{DONE}; # backwards comp now, will go away
  $self->{CONTENT} = $self->layout->as_string($self);
  $self->finish;
  $self->deliver;
}

sub layout {
  my $self = shift;
  $self->instance_of("pause_1999::layout")->layout($self);
}

sub can_gzip {
  my $self = shift;
  my $req = $self->{REQ};
  # my $remote = $r->get_remote_host; <-- is not used now
  # Just for debugging, because Netscape doesn't show source on gzipped pages
  # if ($remote =~ /^62\.104\.4/ and $r->server->server_hostname =~ /^ak-/) {
  #   return $self->{CAN_GZIP} = 0;
  # }
  $self->SUPER::can_gzip;
}

sub can_utf8 {
  my $self = shift;
  return $self->{CAN_UTF8} if defined $self->{CAN_UTF8};

  # From chapter 14.2. HTTP/1.1

  ##   If no Accept-Charset header is present, the default is that any
  ##   character set is acceptable. If an Accept-Charset header is present,
  ##   and if the server cannot send a response which is acceptable
  ##   according to the Accept-Charset header, then the server SHOULD send
  ##   an error response with the 406 (not acceptable) status code, though
  ##   the sending of an unacceptable response is also allowed.

  my $acce = $self->{REQ}->header("Accept-Charset");
  if (defined $acce){
    if ($acce =~ m|\butf-8\b|i){
      $self->{CAN_UTF8} = 1;
    } else {
      $self->{CAN_UTF8} = 0;
    }
    warn "CAN_UTF8[$self->{CAN_UTF8}]acce[$acce]";
    return $self->{CAN_UTF8};
  }
  # Mozilla/5.0 (X11; U; Linux 2.2.16-RAID i686; en-US; m18)
  my $uagent = $self->uagent;
  if ($uagent =~ /^Mozilla\/(\d+)\.\d+\s+\(X11;/
      &&
      $1 >= 5
     ) {
      $self->{CAN_UTF8} = "mozilla 5X";
      warn "CAN_UTF8[$self->{CAN_UTF8}]uagent[$uagent]";
      return $self->{CAN_UTF8};
  }
  if (0) {
      # since we have a perlbal this protocol check is turns UTF-8 off
      # more often than in previous times and reveals that our
      # solutions for non-utf-8 browsers do not work anymore.
      # Disabling completely for now. May need reconsidering, but
      # maybe UTF-8 works everywhere now...
      my $protocol = $self->{REQ}->protocol || "";
      my($major,$minor) = $protocol =~ m|HTTP/(\d+)\.(\d+)|;
      $self->{CAN_UTF8} = $major >= 1 && $minor >= 1;
      warn "CAN_UTF8[$self->{CAN_UTF8}]protocol[$protocol]uagent[$uagent]";
  }
  $self->{CAN_UTF8} = 1;
}

sub uagent {
  my $self = shift;
  return $self->{UserAgent} if defined $self->{UserAgent};
  $self->{UserAgent} = $self->{REQ}->header('User-Agent');
}

sub connect {
  my $self = shift;
  # local($SIG{PIPE}) = 'IGNORE';
  eval {$self->{DbHandle} ||= DBI->connect($self->{ModDsn},
				     $self->{ModDsnUser},
				     $self->{ModDsnPasswd},
				    { RaiseError => 1 })};
  return $self->{DbHandle} if $self->{DbHandle};
  $self->database_alert;
}

sub database_alert {
  my($self) = @_;
  require Carp;
  my $mess = Carp::longmess($@);
  my $tsf = "$PAUSE::Config->{RUNDATA}/alert.db.not.available.ts";
  if (! -f $tsf or (time - (stat _)[9]) > 6*60*60) {
    my $server = $self->myurl->can("host") ? $self->myurl->host : $self->myurl->hostname;
    my $header = {
                  From => "database_alert",
                  To => $PAUSE::Config->{ADMIN},
                  Subject => "PAUSE Database Alert $server",
                 };
    $self->send_mail($header,$mess);
    open my $fh, ">", $tsf or warn "Could not open $tsf: $!";
  }
  die PAUSE::HeavyCGI::Exception->new(ERROR => qq{
Sorry, the PAUSE Database currently seems unavailable.<br />
Administration has been notified.<br />
Please try again later.
});
}

sub authen_connect {
  my $self = shift;
  # local($SIG{PIPE}) = 'IGNORE';
  eval {$self->{DbHandle4Authen} ||= DBI->connect($self->{AuthenDsn},
				     $self->{AuthenDsnUser},
				     $self->{AuthenDsnPasswd},
				    { RaiseError => 1 })};
  return $self->{DbHandle4Authen} if $self->{DbHandle4Authen};
  $self->database_alert;
}

# 2000-04-02: Apache::URI does not satisfy me. It does not include
# scheme and server, but it does contain the whole querystring. I'll
# back out this myurl. The reason why I introduced it, was a problem
# on my machine at home, not on PAUSE, so there is hope that nothing
# breaks by setting it back to the previous state.

# # sub myurl {
# #   my PAUSE::HeavyCGI $self = shift;
# #   return $self->{MYURL} if defined $self->{MYURL};
# #   my $r = $self->{R};
# #   my $myurl = $r->parsed_uri;
# #   my $port = $r->server->port || 80;
# #   my $scheme = $port == 443 ? "https" : "http";
# #   $myurl->scheme($scheme); # Apache::URI doesn't know that without
# #                            # hint, at least not with v1.00. Not well
# #                            # tested
# #   $self->{MYURL} = $myurl;
# # }

# 2002-06-08: Discovering that HeavyCGI gets https wrong. Retrying to
# reanimate Apache::URI now.
sub myurl {
  my $self = shift;
  return $self->{MYURL} if defined $self->{MYURL};
  use URI::URL;
  my $req = $self->{REQ} or
      return URI::URL->new("http://localhost");
  my $uri = $req->uri;

  # use Data::Dumper;
  # warn "subprocess_env[".Data::Dumper::Dumper(scalar $r->subprocess_env)."]";
  # ONLY WORKS WITH PerlSetupEnv On:
  # my $envscheme = $r->subprocess_env('HTTPS') ? "https" : "http";
  # my $scheme = $uri->scheme;
  # warn "scheme[$scheme]envscheme[$envscheme]";
  # $uri->scheme($scheme);

  #### Summary scheme: don't use subprocess_env unless PerlSetupEnv is
  #### On. You don't need it anyway, because $uri->scheme seems to
  #### work OK.

  my $Hhostname = $req->header('Host');
  my $hostname = $uri->host();
  warn "hostname[$hostname]Hhostname[$Hhostname]";
  # $uri->hostname($Hhostname); # contains :8443!!!!!

  # my $rpath = $uri->rpath;
  # $uri->path($rpath);
  warn sprintf "DEBUG: uri[%s]location[%s]", $uri, ""; # $r->location;

  # XXX should have additional test if we are on pause
  if (( $uri->port == 81 || $uri->port == 12081 )
      and $PAUSE::Config->{HAVE_PERLBAL}
     ) {
      if ($self->is_ssl($uri)) {
          $uri->port(443);
          $uri->scheme("https");
      } else {
          $uri->port(80);
          $uri->scheme("http");
      }
      my($hh,$hport);
      if ($Hhostname =~ /([^:]+):(\d+)/) {
          ($hh,$hport) = ($1,$2);
          $uri->port($hport);
      } else {
          $hh = $Hhostname;
      }
      $uri->host($hh);
  }

  # my $port = $r->server->port || 80;
  # my $explicit_port = ($port == 80 || $port == 443) ? "" : ":$port";
  # $self->{MYURL} = URI::URL->new(
  #				 "$protocol://" .
  #				 $r->server->server_hostname .
  #				 $explicit_port .
  #				 $script_name);
  $uri->host($PAUSE::Config->{SERVER_NAME}) if $PAUSE::Config->{SERVER_NAME};
  $self->{MYURL} = $uri;
}

# the argument $uri is important to prevent recursion between myurl
# and is_ssl
sub is_ssl {
    my($self, $uri) = @_;
    return $self->{IsSSL} if defined $self->{IsSSL};
    my $is_ssl = 0;
    $uri ||= $self->myurl;
    if ($uri->scheme eq "https") {
        $is_ssl = 1;
    } elsif (Sys::Hostname::hostname() =~ /pause2/) {
        my $header = $self->{REQ}->header("X-pause-is-SSL") || 0;
        $is_ssl = !!$header;
    }
    return $self->{IsSSL} = $is_ssl;
}

sub file_to_user {
  my($self, $uriid) = @_;
  $uriid =~ s|^/?authors/id||;
  $uriid =~ s|^/||;
  my $ret;
  if ($uriid =~ m|^\w/| ) {
    ($ret) = $uriid =~ m|\w/\w\w/([^/]+)/|;
  } else {
    die "Error: invalid uriid[$uriid]";
  }
  $ret;
}

sub send_mail_multi {
  my($self,$to,$header,$blurb) = @_;
  for my $to2 (@$to) {
    $header->{To} = $to2;
    $self->send_mail($header,$blurb);
  }
}

sub send_mail {
  my($self, $header, $blurb) = @_;
  require Mail::Mailer;

  my @args = @{$self->{MailMailerConstructorArgs}};

  warn "constructing mailer with args[@args]";
  my $mailer = Mail::Mailer->new(@args);

  my @hdebug = %$header; $self->{REQ}->logger({level => 'error', message => sprintf("hdebug[%s]", join "|", @hdebug) });
  $header->{From}                        ||= $self->{OurEmailFrom};
  $header->{"Reply-To"}                  ||= join ", ", @{$PAUSE::Config->{ADMINS}};

  if ($] > 5.007) {
    require Encode;
    for my $k (keys %$header) {
      if ( grep { ord($_)>127 } $header->{$k} =~ /(.)/g ) {
        $header->{$k} = Encode::encode("MIME-Q",$header->{$k});
      }
    }
  }

  my $u = Unicode::String::utf8($blurb);
  my $binmode;
  if (grep { $_>255 } $u->unpack) {
    $header->{"MIME-Version"}              = "1.0";
    $header->{"Content-Type"}              = "Text/Plain; Charset=UTF-8";
    $header->{"Content-Transfer-Encoding"} = "8bit";
    $binmode = "utf8";
  } elsif (grep { $_>127 } $u->unpack) {
    $header->{"MIME-Version"}              = "1.0";
    $header->{"Content-Type"}              = "Text/Plain; Charset=ISO-8859-1";
    $header->{"Content-Transfer-Encoding"} = "8bit";
    $blurb = $u->latin1;
  }

  if ($PAUSE::Config->{TESTHOST}){
    warn "TESTHOST is NOT sending mail";
    require Data::Dumper;
    warn "Line " . __LINE__ . ", File: " . __FILE__ . "\n" .
        Data::Dumper->new([$header,$blurb],[qw(header blurb)])
              ->Indent(1)->Useqq(1)->Dump;
  } else {
    warn "opening mailer";
    $mailer->open($header);
    warn "opened mailer";
    if ($binmode && $] > 5.007) {
      my $ret = binmode $mailer, ":$binmode";
      warn "set binmode of mailer[$mailer] to :utf8? ret[$ret]";
    }
    $mailer->print($blurb);
    warn "printed blurb[$blurb]";
    $mailer->close;
    warn "closed mailer";
  }
  1;
}

sub finish {
  my $self = shift;

  if ($self->can_utf8) {
  } else {
    warn sprintf "DEBUG: using Unicode::String uri[%s]gmtime[%s]", $self->{REQ}->uri, scalar gmtime();
    my $ustr = Unicode::String::utf8($self->{CONTENT});
    $self->{CONTENT} = $ustr->latin1;
    $self->{CHARSET} = "ISO-8859-1";
  }

  use XML::Parser;
  my $p1 = XML::Parser->new;
  eval { $p1->parse($self->{CONTENT}); };
  if ($@) {
    my $rand = String::Random::random_string("cn");
    warn "XML::Parser error. rand[$rand]\$\@[$@]";
    my $deadmeat = "/var/run/httpd/deadmeat/$rand.xhtml";
    require IO::Handle;
    my $fh = IO::Handle->new;
    if (open $fh, ">$deadmeat") {
      if ($] > 5.007) {
        binmode $fh, ":utf8";
      }
      $fh->print($self->{CONTENT});
      $fh->close;
    } else {
      warn "Couldn't open >$deadmeat: $!";
    }
  }

  if ($] > 5.007) {
    require Encode;
    # utf8::upgrade($self->{CONTENT}); # make sure it is UTF-8 encoded
    $self->{CONTENT} = Encode::encode_utf8($self->{CONTENT});
  }
  # $self->cleanup; # close db handles if necessary
  $self->SUPER::finish;
}

sub text_pw_field {
  my($self, %arg) = @_;
  my $name = $arg{name} || "";
  my $fieldtype = $arg{FIELDTYPE};

  my $req = $self->{REQ};
  my $val;
  if ($fieldtype eq "FILE") {
    if ($req->can("upload")) {
      if ($req->upload($name)) {
	$val = $req->upload($name);
      } else {
	$val = $req->param($name);
        if ($] > 5.007) { require Encode; $val = Encode::decode_utf8($val); }
      }
    } else {
      $val = $req->param($name);
      if ($] > 5.007) { require Encode; $val = Encode::decode_utf8($val); }
    }
  } else {
    $val = $req->param($name);
    # warn sprintf "name[%s]val[%s]", $name, $val||"UNDEF";
    if ($] > 5.007) {
      require Encode;
      # Warning: adding second parameter changes behavior (eats characters or so?)
      $val = Encode::decode_utf8($val
                                 # , Encode::FB_WARN()
                                );
    }
    # warn sprintf "name[%s]val[%s]", $name, $val||"UNDEF";
  }
  defined $val or
      defined($val = $arg{value}) or
	  defined($val = $arg{default}) or
	      ($val = "");

  sprintf(qq{<input type="$fieldtype" name="%s" value="%s"%s%s />\n},
          $self->escapeHTML($name),
          $self->escapeHTML($val),
          exists $arg{size} ? " size=\"$arg{size}\"" : "",
          exists $arg{maxlength} ? " maxlength=\"$arg{maxlength}\"" : ""
         );
}

sub textfield {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"text", @_);
}

sub password_field {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"password", @_);
}

sub file_field {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"file", @_);
}

sub checkbox {
  my($self,%arg) = @_;

  my $name = $arg{name};
  my $value;
  defined($value = $arg{value}) or ($value = "on");
  my $checked;
  my @sel = $self->{REQ}->param($name);
  if (@sel) {
    for (@sel) {
      if ($_ eq $value) {
	$checked = 1;
	last;
      }
    }
  } else {
    $checked = $arg{checked};
  }
  $arg{label} = "" unless defined $arg{"label"};
  sprintf(qq{<input type="checkbox" name="%s" value="%s"%s />%s},
	  $self->escapeHTML($name),
	  $self->escapeHTML($value),
	  $checked ? qq{ checked="checked"} : "",
          $arg{label},
	 );
}

sub radio_group {
  my($self,%arg) = @_;
  my $name = $arg{name};
  my $value;
  my $checked;
  my $sel = $self->{REQ}->param($name);
  my $haslabels = exists $arg{labels};
  my $values = $arg{values} or Carp::croak "radio_group called without values";
  defined($checked = $arg{checked})
      or defined($checked = $sel)
	  or defined($checked = $arg{default})
	      or $checked = "";
  # warn "checked[$checked]";
#	  or ($checked = $values->[0]);
  my $escname=$self->escapeHTML($name);
  my $linebreak = $arg{linebreak} ? "<br />" : "";
  my @m;
  for my $v (@$values) {
    my $escv = $self->escapeHTML($v);
    warn "escname undef" unless defined $escname;
    warn "escv undef" unless defined $escv;
    warn "v undef" unless defined $v;
    warn "\$arg{labels}{\$v} undef" unless defined $arg{labels}{$v};
    warn "checked undef" unless defined $checked;
    warn "haslabels undef" unless defined $haslabels;
    warn "linebreak undef" unless defined $linebreak;
    push(@m,
	 sprintf(
		 qq{<input type="radio" name="%s" value="%s"%s />%s%s},
		 $escname,
		 $escv,
		 $v eq $checked ? qq{ checked="checked"} : "",
		 $haslabels ? $arg{labels}{$v} : $escv,
		 $linebreak,
		));
  }
  join "", @m;
}

sub checkbox_group {
  my($self,%arg) = @_;

  my $name = $arg{name};
  my @sel = $self->{REQ}->param($name);
  unless (@sel) {
    if (exists $arg{default}) {
      my $default = $arg{default};
      @sel = ref $default ? @$default : $default;
    }
  }

  my %sel;
  @sel{@sel} = ();
  my @m;

  $name = $self->escapeHTML($name);

  my $haslabels = exists $arg{labels};
  my $linebreak = $arg{linebreak} ? "<br />" : "";

  for my $v (@{$arg{values} || []}) {
    push(@m,
	 sprintf(
		 qq{<span class="%s"><input type="checkbox" name="%s" value="%s"%s />%s</span>%s},

		 "line" . (1 + (scalar(@m) % 3)),
		  # toggle through "line1", "line2", "line3",  "line1", ...

		 $name,
		 $self->escapeHTML($v),
		 exists $sel{$v} ? qq{ checked="checked"} : "",
		 $haslabels ? $arg{labels}{$v} : $self->escapeHTML($v),
		 $linebreak,
		)
	);
  }
  join "", @m;
}

# last edit 2000-03-30
sub scrolling_list {
  my($self, %arg) = @_;
  # name values size labels
  my $size = $arg{size} ? qq{ size="$arg{size}"} : "";
  my $multiple = $arg{multiple} ? qq{ multiple="multiple"} : "";
  my $haslabels = exists $arg{labels};
  my $name = $arg{name};
  # warn "name[$name]CGI[$self->{CGI}]";
  my @sel = $self->{REQ}->param($name);
  if (!@sel && exists $arg{default} && defined $arg{default}) {
    my $d = $arg{default};
    @sel = ref $d ? @$d : $d;
  } else {
    # require Data::Dumper;
    # my $sel = Data::Dumper::Dumper(\@sel);
    # warn "HERE2 sel[$sel]default[$arg{default}]";
  }
  my %sel;
  @sel{@sel} = ();
  my @m;
  push @m, sprintf qq{<select name="%s"%s%s>}, $name, $size, $multiple;
  $arg{values} = [$arg{value}] unless exists $arg{values};
  for my $v (@{$arg{values} || []}) {
    #### warn "v[$v]label[$arg{labels}{$v}]" if $v =~ /AND/;
    my $escv = $self->escapeHTML($v);
    push @m, sprintf qq{<option%s value="%s">%s</option>\n},
	exists $sel{$v} ? qq{ selected="selected"} : "",
	    $escv,
		$haslabels ? $self->escapeHTML($arg{labels}{$v}) : $escv;
  }
  push @m, "</select>";
  join "", @m;
}

# sub escapeHTML { # slow but doesn't lose the UTF8-Flag
sub escapeHTML {
  my($self, $what) = @_;
  return unless defined $what;
  # require Devel::Peek; Devel::Peek::Dump($what) if $what =~ /Andreas/;
  my %escapes = qw(& &amp; " &quot; > &gt; < &lt;);
  $what =~ s[ ([&"<>]) ][$escapes{$1}]xg; # ]] cperl-mode comment
  $what;
}

sub can_multipart {
  my $self = shift;
  return $self->{CanMultipart} if defined $self->{CanMultipart};
  my $req = $self->{REQ};
  my $can = $req->param('CAN_MULTIPART'); # no guessing, no special casing
  $can = 1 unless defined $can; # default
  $self->{CanMultipart} = $can;
}

sub need_multipart {
  my $self = shift;
  my $set = shift;
  $self->{NeedMultipart} = $set if defined $set;
  return $self->{NeedMultipart};
}

sub prefer_post {
  return 1; # Because we should always prefer post now

  my $self = shift;
  my $set = shift;
  $self->{PreferPost} = $set if defined $set;
  return $self->{PreferPost};
}

sub any2utf8 {
  my $self = shift;
  my $s = shift;

  if ($s =~ /[\200-\377]/) {
    # warn "s[$s]";
    my $warn;
    local $^W=1;
    local($SIG{__WARN__}) = sub { $warn = $_[0]; warn "warn[$warn]" };
    my($us) = Unicode::String::utf8($s);
    if ($warn and $warn =~ /utf8|can't/i) {
      warn "DEBUG: was not UTF8, we suppose latin1 (apologies to shift-jis et al): s[$s]";
      $s = Unicode::String::latin1($s)->utf8;
      warn "DEBUG: Now converted to: s[$s]";
    } else {
      warn "seemed to be utf-8";
    }
  }
  $s = $self->decode_highbit_entities($s); # modifies in-place
  if ($] > 5.007) {
    require Encode;
    Encode::_utf8_on($s);
  }
  $s;
}

sub decode_highbit_entities {
  my $self = shift;
  my $s = shift;
  # warn "s[$s]";
  my $c;
  use utf8;
  for ($s) {
    s{ ( & \# (\d+) ;? )
      }{ ($2 > 127) ? chr($2) : $1
      }xeg;

    s{ ( & \# [xX] ([0-9a-fA-F]+) ;? )
      }{$c = hex($2); $c > 127 ? chr($c) : $1
      }xeg;

    s{ ( & (\w+) ;? )
    }{my $r = $entity2char{$2} || $1; warn "r[$r]2[$2]"; $r;
    }xeg;

  }
  # warn "s[$s]";
  $s;
}

sub textarea {
  my($self,%arg) = @_;
  my $req = $self->{REQ};
  my $name = $arg{name} || "";
  my $val  = $req->param($name) || $arg{default} || $arg{value} || "";
  my($r)   = exists $arg{rows} ? qq{ rows="$arg{rows}"} : '';
  my($c)   = exists $arg{cols} ? qq{ cols="$arg{cols}"} : '';
  my($wrap)= exists $arg{wrap} ? qq{ wrap="$arg{wrap}"} : '';
  sprintf qq{<textarea name="%s"%s%s%s>%s</textarea>},
      $self->escapeHTML($name),
	  $r, $c, $wrap, $self->escapeHTML($val);
}

sub submit {
  my($self,%arg) = @_;
  my $name = $arg{name} || "";
  my $val  = $arg{value} || $name;
  sprintf qq{<input type="submit" name="%s" value="%s" />},
      $self->escapeHTML($name),
	  $self->escapeHTML($val);
}

sub DESTROY {
  my $self = shift;
  $self->{DbHandle4Authen}->disconnect if ref $self->{DbHandle4Authen};
  $self->{DbHandle}->disconnect if ref $self->{DbHandle};
}

sub session {
  my $self = shift;
  return $self->{Session} if defined $self->{Session};
  my $req = $self->{REQ};
  my $sid = $req->param('USERID'); # may fail
  my %session;
  require Apache::Session::Counted;
  # XXX date string into CounterFile!
  tie %session, 'Apache::Session::Counted',
      $sid, {
	     Directory => $self->{SessionDataDir},
	     DirLevels => 1,
	     CounterFile => $self->{SessionCounterFile},
	    };
  $self->{Session} = \%session;
}

sub userid {
  my $self = shift;
  # I'm working for the first time with Apache::Session::Counted
  # Things have changed a bit. Until today we had no userid until we
  # had dumped the current request. With Apache::Session we have a
  # userid from the moment we open a session. Under many circumstances
  # we do not need a session, so we do not need a userid. We typically
  # need a userid either to retrieve an old value or to store a new
  # value. We know that we have to retrieve an old value if there is a
  # USERID=xxx parameter on the request. We know that we want to store
  # something if we call ->userid.

  # Apache::Session will dump the current request even if we do not
  # need it. That's stupid. Cookie based session concepts are
  # careless. But let's delay this discussion and see if our code
  # works first.

  return $self->{UserId} if defined $self->{UserId};
  # we must find out if there is an old request that needs to be
  # restored because if there is, we must not create a new one.
  # Because if we create a new one, the restorer cannot restore it
  # without clobbering _session_id

  # Talking about session: lets delegate the problem to the session

  my $session = $self->session;
  $self->{UserId} = $session->{_session_id};
  $session->{_session_id} = $self->{UserId}; # funny, isn't it? We
                                             # trigger a STORE here
                                             # which triggers a
                                             # MODIFIED so that the
                                             # DESTROY will actually
                                             # save the hash
}

sub wait_user_record_hook {
  my $self = shift;

  my $method = shift;
  my $id = shift;

  warn "method[$method]id[$id]\$\$[$$]";

  require WAIT::Database;
  require WAIT::Query::Base;
  require WAIT::Query::Wais;
  my $wdb = WAIT::Database->open(name      => $self->{WaitUserDb},
                                 mode      => O_RDWR,
                                 directory => $self->{WaitDir});
  my $table = $wdb->table(name => "uidx");
  warn "HERE";
  my $sel_sth;
  my $sel_sql = qq{SELECT  userid, fullname
                   FROM    users
                   WHERE   userid=?};
  my $db = $self->connect;
  $sel_sth = $db->prepare($sel_sql);
  $sel_sth->execute($id);
  unless ($sel_sth->rows) {
    warn sprintf "WARNING: wait_hook called for method[%s] on id[%s] which
 isn't in database. Skipping.", #'
	$method, $id;
    $sel_sth->finish;
    $table->close;
    $wdb->close;
    return;
  }
  my $rec = $self->fetchrow($sel_sth, "fetchrow_hashref");
  my $uf = "$rec->{userid} $rec->{fullname}";
  warn "HERE";

  if ($method eq "delete" && !$table->have(docid => $id)) {
    warn "delete on not existing record id[$id], nothing done";
  } else {
    my $ret = $table->$method(
                              'docid' => $id,
                              userid_and_fullname => $uf,
                             );
    warn "HERE";
    # So it failed? Where's the error, what's the reason???'
    warn sprintf("WARNING: FAILED to run method[%s]on id[%s]record[%s]",#'
                 $method,
                 $id,
                 join(":",%$rec),
                ) unless $ret;
  }

  warn "HERE";
  $table->close;
  warn "HERE";
  $wdb->close;
  warn "HERE";
  $sel_sth->finish;
}

# A wrapper function for fetchrow_array and fetchrow_hashref
sub fetchrow {
  my($self,$sth,$what) = @_;
  if ($] < 5.007) {
    return $sth->$what;
  } else {
    require Encode;
    if (wantarray) {
      my @arr = $sth->$what;
      for (@arr) {
        defined && /[^\000-\177]/ && Encode::_utf8_on($_);
      }
      return @arr;
    } else {
      my $ret = $sth->$what;
      if (ref $ret) {
        for my $k (keys %$ret) {
          defined && /[^\000-\177]/ && Encode::_utf8_on($_) for $ret->{$k};
        }
        return $ret;
      } else {
        defined && /[^\000-\177]/ && Encode::_utf8_on($_) for $ret;
        return $ret;
      }
    }
  }
}

sub version {
  my($self) = @_;
  return $self->{VERSION} if defined $self->{VERSION};
  my $version = $VERSION;
  for my $m (grep {! m!/Test/!} grep /pause_1999/, keys %INC) {
    $m =~ s|/|::|g;
    $m =~ s|\.pm$||;
    my $v = $m->VERSION || 0;
    warn "Warning: Strange versioning style in m[$m]v[$v]" if $v < 10;
    $version = $v if $v > $version;
  }
  $version;
}

1;

=back

=cut

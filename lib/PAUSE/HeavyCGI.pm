package PAUSE::HeavyCGI;
use 5.005; # for fields support and package-named exceptions
use HTTP::Status qw(:constants);
use PAUSE::HeavyCGI::Date;
use PAUSE::HeavyCGI::Exception;
use strict;
use vars qw($VERSION $DEBUG);

$VERSION = "0.013302";

sub can_gzip {
  my PAUSE::HeavyCGI $self = shift;
  return $self->{CAN_GZIP} if defined $self->{CAN_GZIP};
  my $acce = $self->{REQ}->header('Accept-Encoding') || "";
  return $self->{CAN_GZIP} = 0 unless $acce;
  $self->{CAN_GZIP} = $acce =~ /\bgzip\b/;
}

sub can_png {
  my PAUSE::HeavyCGI $self = shift;
  return $self->{CAN_PNG} if defined $self->{CAN_PNG};
  my $acce = $self->{REQ}->header("Accept") || "";
  return $self->{CAN_PNG} = 0 unless $acce;
  $self->{CAN_PNG} = $acce =~ m|image/png|i;
}

sub can_utf8 {
  my PAUSE::HeavyCGI $self = shift;
  return $self->{CAN_UTF8} if defined $self->{CAN_UTF8};

  # From chapter 14.2. HTTP/1.1

  ##   If no Accept-Charset header is present, the default is that any
  ##   character set is acceptable. If an Accept-Charset header is present,
  ##   and if the server cannot send a response which is acceptable
  ##   according to the Accept-Charset header, then the server SHOULD send
  ##   an error response with the 406 (not acceptable) status code, though
  ##   the sending of an unacceptable response is also allowed.

  my $acce = $self->{REQ}->header("Accept-Charset") || "";
  if (defined $acce){
    if ($acce =~ m|\butf-8\b|i){
      $self->{CAN_UTF8} = 1;
    } else {
      $self->{CAN_UTF8} = 0;
    }
    return $self->{CAN_UTF8};
  }
  my $protocol = $self->{REQ}->protocol || "";
  my($major,$minor) = $protocol =~ m|HTTP/(\d+)\.(\d+)|;
  $self->{CAN_UTF8} = $major >= 1 && $minor >= 1;
}

sub deliver {
  my PAUSE::HeavyCGI $self = shift;
  my $req = $self->{REQ};
  my $res = $self->{RES};
  # warn "Going to send_http_header";
  return $res->finalize if $req->method eq "HEAD";
  # warn "Going to print content";
  $res->body($self->{CONTENT});
  $res->finalize; # we've sent the headers and the body, apache shouldn't talk
        # to the browser anymore
}

sub handler {
  warn "The handler of the request hasn't defined a handler subroutine.";
  __PACKAGE__->new( REQ => shift )->dispatch;
}

sub dispatch {
  my PAUSE::HeavyCGI $self = shift;
  $self->init;
  eval { $self->prepare; };
  if ($@) {
    if (UNIVERSAL::isa($@,"PAUSE::HeavyCGI::Exception")) {
      if ($@->{ERROR}) {
	warn "\$\@ ERROR[$@->{ERROR}]";
	$@->{ERROR} = [ $@->{ERROR} ] unless ref $@->{ERROR};
	warn "\$\@ ERROR[$@->{ERROR}]";
	push @{$self->{ERROR}}, @{$@->{ERROR}};
	warn "self ERROR[$self->{ERROR}]";
      } elsif ($@->{HTTP_STATUS}) {
	return $@->{HTTP_STATUS};
      }
    } else {
      # this is not a known error type, we need to handle it anon
      if ($self->{ERRORS_TO_BROWSER}) {
	push @{$self->{ERROR}}, " ", $@;
      } else {
	$self->{REQ}->logger->({level => 'error', message => $@});
	return HTTP_INTERNAL_SERVER_ERROR;
      }
    }
  }
  return $self->{DONE} if $self->{DONE}; # backwards comp now, will go away
  $self->{CONTENT} = $self->layout->as_string($self);
  $self->finish;
  $self->deliver;
}

sub expires {
  my PAUSE::HeavyCGI $self = shift;
  my($set) = @_;
  $set = PAUSE::HeavyCGI::Date->new(unix => $set)
      if defined($set) and not ref($set); # allow setting to a number
  $self->{EXPIRES} = $set if defined $set;
  return $self->{EXPIRES}; # even if not defined $self->{EXPIRES};
}

sub finish {
  my PAUSE::HeavyCGI $self = shift;

  my $res = $self->{RES};
  my $content_type = "text/html";
  $content_type .= "; charset=$self->{CHARSET}" if defined $self->{CHARSET};
  $res->content_type($content_type);

  eval { require Compress::Zlib; };
  $self->{CAN_GZIP} = 0 if $@; # we cannot compress anyway :-)

  if ($self->can_gzip) {
    $res->header('Content-Encoding', 'gzip');
    $self->{CONTENT} = Compress::Zlib::memGzip($self->{CONTENT});
  }

  $res->header('Vary', join ", ", 'accept-encoding');
  $res->header('Expires', $self->expires->http) if $self->expires;
  $res->header('Last-Modified',$self->last_modified->http);
  $res->header('Content-Length', length($self->{CONTENT}));
}

sub init {
  return;
}

sub instance_of {
  my($self,$class) = @_;
  return $class->instance if $class->can("instance");
  my $requirefile = $class;
  $requirefile =~ s/::/\//g;
  $requirefile .= ".pm";
  # warn "requiring[$requirefile]";
  require $requirefile;
  $class->instance;
}

sub layout {
  my PAUSE::HeavyCGI $self = shift;
  require PAUSE::HeavyCGI::Layout;
  my @l;
  push @l, qq{<html><head><title>PAUSE::HeavyCGI default page</title>
</head><body><pre>};
  push @l, $self->instance_of("PAUSE::HeavyCGI::Debug");
  push @l, qq{</pre></body></html>};
  PAUSE::HeavyCGI::Layout->new(@l);
}

sub last_modified {
  my PAUSE::HeavyCGI $self = shift;
  my($set) = @_;
  $set = PAUSE::HeavyCGI::Date->new(unix => $set)
      if defined($set) and not ref($set); # allow setting to a number
  $self->{LAST_MODIFIED} = $set if defined $set;
  return $self->{LAST_MODIFIED} if defined $self->{LAST_MODIFIED};
  $self->{LAST_MODIFIED} =
      PAUSE::HeavyCGI::Date->new(unix => $self->time);
}

sub myurl {
  my PAUSE::HeavyCGI $self = shift;
  return $self->{MYURL} if defined $self->{MYURL};
  require URI::URL;
  my $req = $self->{REQ} or
      return URI::URL->new("http://localhost");
  $self->{MYURL} = URI::URL->new($req->base);
}

sub new {
  my($class,%opt) = @_;
  no strict "refs";
  my $self = bless {}, $class;
  while (my($k,$v) = each %opt) {
    $self->{$k} = $v;
  }
  $self;
}

sub prepare {
  my PAUSE::HeavyCGI $self = shift;
  if (my $ep = $self->{EXECUTION_PLAN}) {
    $ep->walk($self);
  } else {
    die "No execution plan!";
  }
}

sub serverroot_url {
  my PAUSE::HeavyCGI $self = shift;
  return $self->{SERVERROOT_URL} if $self->{SERVERROOT_URL};
  require URI::URL;
  my $req = $self->{REQ} or
      return URI::URL->new("http://localhost");
  my $host   = $req->env->{SERVER_NAME}; # XXX: $r->server->server_hostname;
  my $port = $req->port || 80;
  my $protocol = $port == 443 ? "https" : "http";
  my $explicit_port = ($port == 80 || $port == 443) ? "" : ":$port";
  $self->{SERVERROOT_URL} = URI::URL->new(
				   "$protocol\://" .
				   $host .
				   $explicit_port .
				   "/"
				  );
}

sub time {
  my PAUSE::HeavyCGI $self = shift;
  $self->{TIME} ||= time;
}

sub today {
  my PAUSE::HeavyCGI $self = shift;
  return $self->{TODAY} if defined $self->{TODAY};
  my(@time) = localtime($self->time);
  $time[4]++;
  $time[5] += 1900;
  $self->{TODAY} = sprintf "%04d-%02d-%02d", @time[5,4,3];
}

# CGI form handling

sub checkbox {
  my($self,%arg) = @_;

  my $name = $arg{name};
  my $value;
  defined($value = $arg{value}) or ($value = "on");
  my $checked;
  my @sel = $self->{REQ}->param($name);
  if (@sel) {
    for my $s (@sel) {
      if ($s eq $value) {
	$checked = 1;
	last;
      }
    }
  } else {
    $checked = $arg{checked};
  }
  sprintf(qq{<input type="checkbox" name="%s" value="%s"%s />},
	  $self->escapeHTML($name),
	  $self->escapeHTML($value),
	  $checked ? qq{ checked="checked"} : ""
	 );
}

# pause_1999::main
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
		 qq{<input type="checkbox" name="%s" value="%s"%s />%s%s},
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

sub escapeHTML {
  my($self, $what) = @_;
  return unless defined $what;
  my %escapes = qw(& &amp; " &quot; > &gt; < &lt;);
  $what =~ s[ ([&"<>]) ][$escapes{$1}]xg; # ]] cperl-mode comment
  $what;
}

sub file_field {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"file", @_);
}

sub hidden_field {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"hidden", @_);
}

sub password_field {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"password", @_);
}

# pause_1999::main
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
  # some people like to check the first item anyway:
  #	  or ($checked = $values->[0]);
  my $escname=$self->escapeHTML($name);
  my $linebreak = $arg{linebreak} ? "<br />" : "";
  my @m;
  for my $v (@$values) {
    my $escv = $self->escapeHTML($v);
    if ($DEBUG) {
      warn "escname undef" unless defined $escname;
      warn "escv undef" unless defined $escv;
      warn "v undef" unless defined $v;
      warn "\$arg{labels}{\$v} undef" unless defined $arg{labels}{$v};
      warn "checked undef" unless defined $checked;
      warn "haslabels undef" unless defined $haslabels;
      warn "linebreak undef" unless defined $linebreak;
    }
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

# pause_1999::main
sub scrolling_list {
  my($self, %arg) = @_;
  # name values size labels
  my $size = $arg{size} ? qq{ size="$arg{size}"} : "";
  my $multiple = $arg{multiple} ? q{ multiple="multiple"} : "";
  my $haslabels = exists $arg{labels};
  my $name = $arg{name};
  my @sel = $self->{REQ}->param($name);
  if (!@sel && exists $arg{default} && defined $arg{default}) {
    my $d = $arg{default};
    @sel = ref $d ? @$d : $d;
  }
  my %sel;
  @sel{@sel} = ();
  my @m;
  push @m, sprintf qq{<select name="%s"%s%s>}, $name, $size, $multiple;
  $arg{values} = [$arg{value}] unless exists $arg{values};
  for my $v (@{$arg{values} || []}) {
    my $escv = $self->escapeHTML($v);
    push @m, sprintf qq{<option%s value="%s">%s</option>\n},
	exists $sel{$v} ? q{ selected="selected"} : "",
	    $escv,
		$haslabels ? $self->escapeHTML($arg{labels}{$v}) : $escv;
  }
  push @m, "</select>";
  join "", @m;
}

# pause_1999::main
sub submit {
  my($self,%arg) = @_;
  my $name = $arg{name} || "";
  my $val  = $arg{value} || $name;
  sprintf qq{<input type="submit" name="%s" value="%s" />},
      $self->escapeHTML($name),
	  $self->escapeHTML($val);
}

# pause_1999::main
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

# pause_1999::main
sub textfield {
  my($self) = shift;
  $self->text_pw_field(FIELDTYPE=>"text", @_);
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
      }
    } else {
      $val = $req->param($name);
    }
  } else {
    $val = $req->param($name);
  }
  defined $val or
      defined($val = $arg{value}) or
	  defined($val = $arg{default}) or
	      ($val = "");

  sprintf qq{<input type="$fieldtype"
 name="%s" value="%s"%s%s />},
      $self->escapeHTML($name),
	   $self->escapeHTML($val),
	       exists $arg{size} ? " size=\"$arg{size}\"" : "",
		   exists $arg{maxlength} ? " maxlength=\"$arg{maxlength}\"" : "";
}

sub uri_escape {
  my PAUSE::HeavyCGI $self = shift;
  my $string = shift;
  return "" unless defined $string;
  require URI::Escape;
  my $s = URI::Escape::uri_escape($string, '^\w ');
  $s =~ s/ /+/g;
  $s;
}

sub uri_escape_light {
  my PAUSE::HeavyCGI $self = shift;
  require URI::Escape;
  URI::Escape::uri_escape(shift,q{<>#%"; \/\?:&=+,\$}); #"
}

1;

=head1 NAME

PAUSE::HeavyCGI - Framework to run complex CGI tasks on an Apache server

=head1 SYNOPSIS

 use PAUSE::HeavyCGI;

=head1 WARNING UNSUPPORTED ALPHA CODE RELEASED FOR DEMO ONLY

The release of this software was only for evaluation purposes to
people who are actively writing code that deals with Web Application
Frameworks. This package is probably just another Web Application
Framework and may be worth using or may not be worth using. As of this
writing (July 1999) it is by no means clear if this software will be
developed further in the future. The author has written it over many
years and is deploying it in several places. B<Update 2006-02-03:
Development stalled since 2001 and now discontinued.>

There is no official support for this software. If you find it useful
or even if you find it useless, please mail the author directly.

But please make sure you remember: THE RELEASE IS FOR DEMONSTRATION
PURPOSES ONLY.

=head1 DESCRIPTION

The PAUSE::HeavyCGI framework is intended to provide a couple of
simple tricks that make it easier to write complex CGI solutions. It
has been developed on a site that runs all requests through a single
mod_perl handler that in turn uses CGI.pm or Apache::Request as the
query interface. So PAUSE::HeavyCGI is -- as the name implies -- not
merely for multi-page CGI scripts (for which there are other
solutions), but it is for the integration of many different pages into
a single solution. The many different pages can then conveniently
share common tasks.

The approach taken by PAUSE::HeavyCGI is a components-driven one with
all components being pure perl. So if you're not looking for yet
another embedded perl solution, and aren't intimidated by perl, please
read on.

=head2 Stacked handlers suck

If you have had a look at stacked handlers, you might have noticed
that the model for stacking handlers often is too primitive. The model
supposes that the final form of a document can be found by running
several passes over a single entity, each pass refining the entity,
manipulating some headers, maybe even passing some notes to the next
handler, and in the most advanced form passing pnotes between
handlers. A lot of Web pages may fit into that model, even complex
ones, but it doesn't scale well for pages that result out of a
structure that's more complicated than adjacent items. The more
complexity you add to a page, the more overhead is generated by the
model, because for every handler you push onto the stack, the whole
document has to be parsed and recomposed again and headers have to be
re-examined and possibly changed.

=head2 Why not subclass Apache

Inheritance provokes namespace conflicts. Besides this, I see little
reason why one should favor inheritance over a B<using> relationship.
The current implementation of PAUSE::HeavyCGI is very closely coupled
with the Apache class anyway, so we could do inheritance too. No big
deal I suppose. The downside of the current way of doing it is that we
have to write

    my $r = $obj->{R};

very often, but that's about it. The upside is, that we know which
manpage to read for the different methods provided by C<$obj->{R}>,
C<$obj->{CGI}>, and C<$obj> itself.

=head2 Composing applications

PAUSE::HeavyCGI takes an approach that is more ambitious for handling
complex tasks. The underlying model for the production of a document
is that of a puzzle. An HTML (or XML or SGML or whatever) page is
regarded as a sequence of static and dynamic parts, each of which has
some influence on the final output. Typically, in today's Webpages,
the dynamic parts are filled into table cells, i.e. contents between
some C<< <TD></TD> >> tokens. But this is not necessarily so. The
static parts in between typically are some HTML markup, but this also
isn't forced by the model. The model simply expects a sequence of
static and dynamic parts. Static and dynamic parts can appear in
random order. In the extreme case of a picture you would only have one
part, either static or dynamic. HeavyCGI could handle this, but I
don't see a particular advantage of HeavyCGI over a simple single
handler.

In addition to the task of generating the contents of the page, there
is the other task of producing correct headers. Header composition is
an often neglected task in the CGI world. Because pages are generated
dynamically, people believe that pages without a Last-Modified header
are fine, and that an If-Modified-Since header in the browser's
request can go by unnoticed. This laissez-faire principle gets in the
way when you try to establish a server that is entirely driven by
dynamic components and the number of hits is significant.

=head2 Header Composition, Parameter Processing, and Content Creation

The three big tasks a CGI script has to master are Headers, Parameters
and the Content. In general one can say, content creation SHOULD not
start before all parameters are processed. In complex scenarios you
MUST expect that the whole layout may depend on one parameter.
Additionally we can say that some header related data SHOULD be
processed very early because they might result in a shortcut that
saves us a lot of processing.

Consequently, PAUSE::HeavyCGI divides the tasks to be done for a
request into four phases and distributes the four phases among an
arbitrary number of modules. Which modules are participating in the
creation of a page is the design decision of the programmer.

The perl model that maps (at least IMHO) ideally to this task
description is an object oriented approach that identifies a couple of
phases by method names and a couple of components by class names. To
create an application with PAUSE::HeavyCGI, the programmer specifies
the names of all classes that are involved. All classes are singleton
classes, i.e. they have no identity of their own but can be used to do
something useful by working on an object that is passed to them.
Singletons have an @ISA relation to L<Class::Singleton> which can be
found on CPAN. As such, the classes can only have a single instance
which can be found by calling the C<< CLASS->instance >> method. We'll
call these objects after the mod_perl convention I<handlers>.

Every request maps to exactly one PAUSE::HeavyCGI object. The
programmer uses the methods of this object by subclassing. The
HeavyCGI constructor creates objects of the AVHV type (pseudo-hashes).

*** Note: after 0.0133 this was changed to an ordinary hash. ***

If the inheriting class needs its own constructor, this needs to be an
AVHV compatible constructor. A description of AVHV can be found in
L<fields>.

*** Note: after 0.0133 this was changed to be an ordinary hash. ***

An PAUSE::HeavyCGI object usually is constructed with the
C<new> method and after that the programmer calls the C<dispatch>
method on this object. HeavyCGI will then perform various
initializations and then ask all nominated handlers in turn to perform
the I<header> method and in a second round to perform the I<parameter>
method. In most cases it will be the case that the availability of a
method can be determined at compile time of the handler. If this is
true, it is possible to create an execution plan at compile time that
determines the sequence of calls such that no runtime is lost to check
method availability. Such an execution plan can be created with the
L<PAUSE::HeavyCGI::ExePlan> module. All of the called methods will
get the HeavyCGI request object passed as the second parameter.

There are no fixed rules as to what has to happen within the C<header>
and C<parameter> method. As a rule of thumb it is recommended to
determine and set the object attributes LAST_MODIFIED and EXPIRES (see
below) within the header() method. It is also recommended to inject
the L<PAUSE::HeavyCGI::IfModified> module as the last header handler,
so that the application can abort early with an Not Modified header. I
would recommend that in the header phase you do as little as possible
parameter processing except for those parameters that are related to
the last modification date of the generated page.

=head2 Terminating the handler calls or triggering errors.

Sometimes you want to stop calling the handlers, because you think
that processing the request is already done. In that case you can do a

 die PAUSE::HeavyCGI::Exception->new(HTTP_STATUS => status);

at any point within prepare() and the specified status will be
returned to the Apache handler. This is useful for example for the
PAUSE::HeavyCGI::IfModified module which sends the response headers
and then dies with HTTP_STATUS set to Apache::Constants::DONE.
Redirectors presumably would set up their headers and set it to
Apache::Constants::HTTP_MOVED_TEMPORARILY.

Another task for Perl exceptions are errors: In case of an error
within the prepare loop, all you need to do is

 die PAUSE::HeavyCGI::Exception->new(ERROR=>[array_of_error_messages]);

The error is caught at the end of the prepare loop and the anonymous
array that is being passed to $@ will then be appended to
C<@{$self-E<gt>{ERROR}}>. You should check for $self->{ERROR} within
your layout method to return an appropriate response to the client.

=head2 Layout and Text Composition

After the header and the parameter phase, the application should have
set up the object that is able to characterize the complete
application and its status. No changes to the object should happen
from now on.

In the next phase PAUSE::HeavyCGI will ask this object to perform the
C<layout> method that has the duty to generate an
PAUSE::HeavyCGI::Layout (or compatible) object. Please read more
about this object in L<PAUSE::HeavyCGI::Layout>. For our HeavyCGI
object it is only relevant that this Layout object can compose itself
as a string in the as_string() method. As a layout object can be
composed as an abstraction of a layout and independent of
request-specific contents, it is recommended to cache the most
important layouts. This is part of the reponsibility of the
programmer.

In the next step HeavyCGI stores a string representation of current
request by calling the as_string() method on the layout object and
passing itself to it as the first argument. By passing itself to the
Layout object all the request-specific data get married to the
layout-specific data and we reach the stage where stacked handlers
usually start, we get at a composed content that is ready for
shipping.

The last phase deals with setting up the yet unfinished headers,
eventually compressing, recoding and measuring the content, and
delivering the request to the browser. The two methods finish() and
deliver() are responsible for that phase. The default deliver() method
is pretty generic, it calls finish(), then sends the headers, and
sends the content only if the request method wasn't a HEAD. It then
returns Apache's constant DONE to the caller, so that Apache won't do
anything except logging on this request. The method finish is more apt
to being overridden. The default finish() method sets the content type
to text/html, compresses the content if the browser understands
compressed data and Compress::Zlib is available, it also sets the
headers Vary, Expires, Last-Modified, and Content-Length. You most
probably will want to override the finish method.

head2 Summing up
                                        +-------------------+
                                        | sub handler {...} |
 +--------------------+                 | (sub init {...})  |
 |Your::Class         |---defines------>|                   |
 |ISA PAUSE::HeavyCGI|                 | sub layout {...}  |
 +--------------------+                 | sub finish {...}  |
                                        +-------------------+

                                        +-------------------+
                                        | sub new {...}     |
 +--------------------+                 | sub dispatch {...}|
 |PAUSE::HeavyCGI    |---defines------>| sub prepare {...} |
 +--------------------+                 | sub deliver {...} |
                                        +-------------------+

 +----------------------+               +--------------------+
 |Handler_1 .. Handler_N|               | sub header {...}   |
 |ISA Class::Singleton  |---define----->| sub parameter {...}|
 +----------------------+               +--------------------+

                                                                       +----+
                                                                       |Your|
                                                                       |Duty|
 +----------------------------+----------------------------------------+----+
 |Apache                      | calls Your::Class::handler()           |    |
 +----------------------------+----------------------------------------+----+
 |                            | nominates the handlers,                |    |
 |Your::Class::handler()      | constructs $self,                      | ** |
 |                            | and calls $self->dispatch              |    |
 +----------------------------+----------------------------------------+----+
 |                            |        $self->init     (does nothing)  | ?? |
 |                            |        $self->prepare  (see below)     |    |
 |PAUSE::HeavyCGI::dispatch()| calls  $self->layout   (sets up layout)| ** |
 |                            |        $self->finish   (headers and    | ** |
 |                            |                         gross content) |    |
 |                            |        $self->deliver  (delivers)      | ?? |
 +----------------------------+----------------------------------------+----+
 |PAUSE::HeavyCGI::prepare() | calls HANDLER->instance->header($self) | ** |
 |                            | and HANDLER->instance->parameter($self)| ** |
 |                            | on all of your nominated handlers      |    |
 +----------------------------+----------------------------------------+----+


=head1 Object Attributes

As already mentioned, the HeavyCGI object is a pseudo-hash, i.e. can
be treated like a HASH, but all attributes that are being used must be
predeclared at compile time with a C<use fields> clause.

The convention regarding attributes is as simple as it can be:
uppercase attributes are reserved for the PAUSE::HeavyCGI class, all
other attribute names are at your disposition if you write a subclass.

The following attributes are currently defined. The module author's
production environment has a couple of attributes more that seem to
work well but most probably need more thought to be implemented in a
generic way.

=over

=item CAN_GZIP

Set by the can_gzip method. True if client is able to handle gzipped
data.

=item CAN_PNG

Set by the can_png method. True if client is able to handle PNG.

=item CAN_UTF8

Set by the can_utf8 method. True if client is able to handle UTF8
endoded data.

=item CGI

An object that handles GET and POST parameters and offers the method
param() and upload() in a manner compatible with Apache::Request.
Needs to be constructed and set by the user typically in the
contructor.

=item CHARSET

Optional attribute to denote the charset in which the outgoing data
are being encoded. Only used within the finish method. If it is set,
the finish() method will set the content type to text/html with this
charset.

=item CONTENT

Scalar that contains the content that should be sent to the user
uncompressed. During te finish() method the content may become
compressed.

=item DOCUMENT_ROOT

Unused.

=item ERROR

Anonymous array that accumulates error messages. HeavyCGI doesn't
handle the error though. It is left to the user to set up a proper
response to the user.

=item EXECUTION_PLAN

Object of type L<PAUSE::HeavyCGI::ExePlan>. It is recommended to
compute the object at startup time and always pass the same execution
plan into the constructor.

=item EXPIRES

Optional Attribute set by the expires() method. If set, HeavyCGI will
send an Expires header. The EXPIRES attribute needs to contain an
L<PAUSE::HeavyCGI::Date> object.

=item HANDLER

If there is an EXECUTION_PLAN, this attribute is ignored. Without an
EXECUTION_PLAN, it must be an array of package names. HeavyCGI treats
the packages as Class::Singleton classes. During the prepare() method
HeavyCGI calls HANDLER->instance->header($self) and
HANDLER->instance->parameter($self) on all of your nominated handlers.

=item LAST_MODIFIED

Optional Attribute set by the last_modified() method. If set, HeavyCGI
will send a Last-Modified header of the specified time, otherwise it
sends a Last-Modified header of the current time. The attribute needs
to contain an L<PAUSE::HeavyCGI::Date> object.

=item MYURL

The URL of the running request set by the myurl() method. Contains an
URI::URL object.

=item R

The Apache Request object for the running request. Needs to be set up
in the constructor by the user.

=item REFERER

Unused.

=item SERVERROOT_URL

The URL of the running request's server-root set by the
serverroot_url() method. Contains an URI::URL object.

=item SERVER_ADMIN

Unused.

=item TIME

The time when this request started set by the time() method. Please
note, that the time() system call is considerable faster than the
method call to PAUSE::HeavyCGI::time. The advantage of calling using
the TIME attribute is that it is self-consistent (remains the same
during a request).

=item TODAY

Today's date in the format 9999-99-99 set by the today() method, based
on the time() method.

=back



=head2 Performance

Don't expect PAUSE::HeavyCGI to serve 10 million page impressions a
day. The server I have developed it for is a double processor machine
with 233 MHz, and each request is handled by about 30 different
handlers: a few trigonometric, database, formatting, and recoding
routines. With this overhead each request takes about a tenth of a
second which in many environments will be regarded as slow. On the
other hand, the server is well respected for its excellent response
times. YMMV.

=head1 BUGS

The fields pragma doesn't mix very well with Apache::StatINC. When
working with HeavyCGI you have to restart your server quite often when
you change your main class. I believe, this could be fixed in
fields.pm, but I haven't tried. A workaround is to avoid changing the
main class, e.g. by delegating the layout() method to a different
class.

*** Note: this has no meaning anymore after 0.0133 ***

=head1 AUTHOR

Andreas Koenig <andreas.koenig@anima.de>. Thanks to Jochen Wiedmann
for heavy debates about the code and crucial performance enhancement
suggestions. The development of this code was sponsered by
www.speed-link.de.

=cut


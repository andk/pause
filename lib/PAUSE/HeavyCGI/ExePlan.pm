package PAUSE::HeavyCGI::ExePlan;
use PAUSE::HeavyCGI; # want only the instance_of method
use strict;
# use fields qw(PLAN DEBUG FUNCTIONAL WATCHVARIABLE);

use vars '$VERSION';
$VERSION = sprintf "%d.%03d", q$Revision: 1.10 $ =~ /(\d+)\.(\d+)/;

# no singleton, every Application can have its own execution plan even
# every object can have it's own, although, it probably doesn't pay

sub new {
  my($me,%arg) = @_;
  my $methods = $arg{METHODS} || [qw(header parameter)];
  my $classes = $arg{CLASSES} || [];
  my $functional = $arg{WALKTYPE} eq "f";
  my $watchvariable = $arg{WATCHVARIABLE};
  my $debug   = $arg{DEBUG} || 0; #### undocumented
  my @plan;
  for my $method (@$methods) {
    for my $class (@$classes) {
      my($obj,$subr);
      eval { $obj = $class->instance; };
      if ($@) {
	$obj = PAUSE::HeavyCGI->instance_of($class);
      }
      next unless $subr = $obj->can($method);
      if ($functional) {
	push @plan, $subr, $obj;
      } else {
	push @plan, $obj, $method;
      }
    }
  }
  no strict "refs";
  my $self = bless {}, $me;
  $self->{PLAN} = [ @plan ];
  $self->{DEBUG} = $debug;
  $self->{FUNCTIONAL} = $functional;
  $self->{WATCHVARIABLE} = $watchvariable;
  $self;
}

sub walk {
  my PAUSE::HeavyCGI::ExePlan $self = shift;
  my PAUSE::HeavyCGI $application = shift;
  if ($self->{WATCHVARIABLE}) {
    require Data::Dumper;
  }
  for (my $i=0;;$i+=2) {
    warn sprintf(
                 "entering method[%s] walktype[%s]",
                 $self->{PLAN}[$i]."::".$self->{PLAN}[$i+1],
                 $self->{FUNCTIONAL} ? "f" : "m",
                ) if $self->{DEBUG} && $self->{DEBUG} & 1;
    my $before = $self->{WATCHVARIABLE} ?
        Data::Dumper::Dumper($application->{$self->{WATCHVARIABLE}}) :
              "";
    if ($self->{FUNCTIONAL}) {
      my $subr = $self->{PLAN}[$i] or last;
      my $obj = $self->{PLAN}[$i+1];
      $subr->($obj,$application);
    } else {
      my $obj = $self->{PLAN}[$i] or last;
      my $method = $self->{PLAN}[$i+1];
      $obj->$method($application);
    }
    warn sprintf "exiting" if $self->{DEBUG} && $self->{DEBUG} & 2;
    my $after = $self->{WATCHVARIABLE} ?
        Data::Dumper::Dumper($application->{$self->{WATCHVARIABLE}}) : "";
    unless ($before eq $after) {
      warn sprintf(
                   "variable %s changed value from[%s]to[%s] in method[%s]",
                   $self->{WATCHVARIABLE},
                   $before,
                   $after,
                   $self->{PLAN}[$i]."::".$self->{PLAN}[$i+1],
                  );
    }
  }
}

1;

__END__


=head1 NAME

PAUSE::HeavyCGI::ExePlan - Creates an execution plan for PAUSE::HeavyCGI

=head1 SYNOPSIS

 use PAUSE::HeavyCGI::ExePlan;
 my $plan = PAUSE::HeavyCGI::ExePlan->new(
    METHODS => ["header", "parameter"],
    CLASSES => ["my_application::foo", "my_application::bar", ... ],
    DEBUG    => 1,
    WALKTYPE => "m",
    WATCHVARIABLE => "SOME VARIABLE",

 $plan->walk;

=head1 DESCRIPTION

When an execution plan object is instantiated, it immediately visits
all specified classes, collects the singleton objects for these
classes, and checks if the classes define the specified methods. It
creates an array of objects and methods or an array of code
references.

The walk method walks through the execution plan in the stored order
and sends each singleton object the appropriate method and passes the
application object as the first argument.

Normally, every application has its own execution plan. If the
execution plan is calculated at load time of the application class,
all objects of this class can share a common execution plan, thus
speeding up the requests. Consequently it is recommended to have an
initialization in all applications that instantiates an execution plan
and passes it to all application objects in the constructor.

=head1 ARGUMENTS TO THE CONSTRUCTOR

=over

=item METHODS

An anonymous array consisting of method names that shall be called
when walk() is called. Defaults to

    [qw(header parameter)]

=item CLASSES

An anonymous array of class names (a.k.a. widgets) that shall be
visited when walk() is called. Has no default.

=item DEBUG

Currently only 0 and 1, 2 or 3 are allowed. If 1, each class/method
pair triggers a warning on entering their execution. If 2, the warning
is triggered at exit of the subroutine. If 3, both entry and exit
trigger a warning.

=item WATCHVARIABLE

Name of a member variable. Defaults to C<undef>. By setting
WATCHVARIABLE you can watch a member variable of the PAUSE::HeavyCGI
object on entering/exiting each call to each class/method pair. Only
changes of the variable trigger a warning.

=item WALKTYPE

A single letter, either C<m> (default) or C<f>. If set to C<m>, all
method calls issued by the call to walk() are execute as method calls.
If set to C<f>, all method calls are replaced by their equivalent
subroutine calls, bypassing perl's method dispatch algorithm. The
latter is recommended on the production server, the former is
recommended in the development environment. C<m> allows you to use the
Apache::StatINC module with the effect it usually has. Using
Apache::StatINC with WALKTYPE=f has B<no effect>, as all subroutines
are preserved when Apache::StatINC reloads a file, so the execution
plan will not note the change.

=back

=cut


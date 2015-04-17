package PAUSE::HeavyCGI::Date;
use 5.005;
use strict;

use vars qw($VERSION);
$VERSION = sprintf "%d.%03d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/;

use HTTP::Date ();
use overload '""' => "http";

sub new {
  my($class,%arg) = @_;
  $arg{unix} = time unless %arg;
  my $self = bless {}, $class;
  while (my($k,$v) = each %arg) {
    $self->{$k} = $v;
  }
  $self;
}

sub unix {
  my $self = shift;
  my($set) = @_;
  if (defined $set) {
    $self->{unix} = $set;
    $self->{http} = undef;
  }
  return $self->{unix} if defined $self->{unix}; # can be 0
  $self->{unix} = HTTP::Date::str2time($self->{http});
}

sub http {
  my $self = shift;
  my($set) = @_;
  if (defined $set) {
    $self->{http} = $set;
    $self->{unix} = undef;
  }
  unless (defined $self->{unix}) {
    require Carp;
    Carp::confess("No time in my object");
  }
  $self->{http} ||= HTTP::Date::time2str($self->{unix}); # can't be 0 or ""
}

1;

=head1 NAME

PAUSE::HeavyCGI::Date - represent a date as both unix time and HTTP time

=head1 SYNOPSIS

 my $date = PAUSE::HeavyCGI::Date->new;

 $date->unix(time);   # set
 print $date->unix;   # get
 print $date->http;   # get as http
 print $date;         # same thing due to overloading

=head1 DESCRIPTION

This class implements a simple dual value date variable. There are
only two accessor methods that let you set and get dates. unix() sets
and gets the UNIX time, and http() gets and sets the HTTP time.
Whenever a time is set the other time gets undefined. Retrieving an
undefined time triggers a conversion from the other time. That way the
two times are always synced.

=head1 PREREQUISITES

The class uses HTTP::Date internally.

=head1 AUTHOR

andreas koenig <andreas.koenig@anima.de>

=cut


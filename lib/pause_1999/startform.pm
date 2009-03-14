package pause_1999::startform;
use base 'Class::Singleton';
use pause_1999::main;

use strict;
our $VERSION = "854";

sub as_string {
  my pause_1999::startform $self = shift;
  my pause_1999::main $mgr = shift;
  my @m;
  my $myurl = $mgr->myurl;
  my $me = $myurl->can("unparse") ? $myurl->unparse : $myurl->as_string;
  $me =~ s/\?.*//; # unparse keeps the querystring which breaks XHTML

  my $enctype;
  my $method;

  # 2005 I decided to prefer post *always*, but then for example links
  # to peek_perms stopped to work, so we should really decide
  # case-by-case if we want get or post
  if ($mgr->can_multipart && $mgr->need_multipart) {
    $enctype = "multipart/form-data";
    $method = "post";
  } elsif (defined $mgr->prefer_post and $mgr->prefer_post) {
    $enctype = "application/x-www-form-urlencoded";
    $method = "post";
  } else {
    $enctype = "application/x-www-form-urlencoded";
    $method = "get";
  }
  if ($PAUSE::Config->{TESTHOST}) {
    warn "DEBUG: me[$me]enctype[$enctype]method[$method]";
    push @m, qq{<h2>[ATTN: Form going to post to $me]</h2>};
  }
  push @m, qq{<form
 action="$me"
 enctype="$enctype"
 method="$method">};
  @m;
}

1;

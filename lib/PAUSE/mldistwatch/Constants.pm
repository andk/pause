use strict;
use warnings;
package PAUSE::mldistwatch::Constants;

# constants used for index_status:
use constant EDUALOLDER => 50; # pumpkings only
use constant EDUALYOUNGER => 30; # pumpkings only
use constant EOPENFILE => 21;
use constant EMISSPERM => 20;
use constant EPARSEVERSION => 10;
use constant EOLDRELEASE => 4;
use constant EMTIMEFALLING => 3; # deprecated after rev 478
use constant EVERFALLING => 2;
use constant OK => 1;

our $heading = {
  EMISSPERM() => "Permission missing",
  EDUALOLDER() => "An older dual-life module stays reference",
  EDUALYOUNGER() => "Dual-life module stays reference",
  EVERFALLING() => "Decreasing version number",
  EMTIMEFALLING() => "Decreasing mtime on a file (category to be deprecated)",
  EOLDRELEASE() => "Release seems outdated",
  EPARSEVERSION() => "Version parsing problem",
  EOPENFILE() => "Problem while reading the distribtion",
  OK() => "Successfully indexed",
};

sub heading ($) {
  my($status) = shift;
  # warn "status[$status]";
  $heading->{$status};
}

1;



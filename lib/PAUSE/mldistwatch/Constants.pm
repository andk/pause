use strict;
use warnings;
package PAUSE::mldistwatch::Constants;

# constants used for index_status:
use constant EDUALOLDER => 50; # pumpkings only
use constant EDUALYOUNGER => 30; # pumpkings only
use constant EDBERR => 25;
use constant EDBCONFLICT => 23;
use constant EOPENFILE => 21;
use constant EMISSPERM => 20;
use constant EBADVERSION => 12;
use constant EPARSEVERSION => 10;
use constant EMETAUNSTABLE => 6;
use constant EBAREPMFILE => 5;
use constant EOLDRELEASE => 4;
use constant EMTIMEFALLING => 3; # deprecated after rev 478
use constant EVERFALLING => 2;
use constant OK => 1;

our $heading = {
  EBADVERSION() => "Version string is not a valid 'lax version' string",
  EBAREPMFILE() => "Bare .pm files are not indexed",
  EDBCONFLICT() => "Conflicting record found in index",
  EDBERR() => "Database error",
  EDUALOLDER() => "An older dual-life module stays reference",
  EDUALYOUNGER() => "Dual-life module stays reference",
  EMISSPERM() => "Permission missing",
  EMTIMEFALLING() => "Decreasing mtime on a file (category to be deprecated)",
  EOLDRELEASE() => "Release seems outdated",
  EOPENFILE() => "Problem while reading the distribtion",
  EMETAUNSTABLE() => "META release_status is not stable, will not index",
  EPARSEVERSION() => "Version parsing problem",
  EVERFALLING() => "Decreasing version number",
  OK() => "Successfully indexed",
};

sub heading ($) {
  my($status) = shift;
  # warn "status[$status]";
  $heading->{$status};
}

1;



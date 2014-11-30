package TestSetup;

use File::Path;
use File::Spec;
my $path = File::Spec->catdir(qw(blib privatelib));
my $file = File::Spec->catfile($path, 'PrivatePAUSE.pm');
die "mkpath $path: $!" unless -d $path or mkpath $path;

unless (-e $file) {
  die "$file: $!" unless open my $fh, '>', $file;
  die "$file: $!" unless print $fh "package PrivatePAUSE;\n1;\n";
}

1;

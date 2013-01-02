#!/usr/local/bin/perl -w

=comment

The reason why this script exists is that the first Upload Server we
had, sent ls -lR in GMT when an ftp client asked. Later, when I wanted
to provide an ls-lR file for funet, I could not write the localtime
into it, because mirror would have fetched _all_ files again, because
they would seem to be newer. And that for the whole CPAN!

This script outputs something that looks like an ls -lR, but has
gmtime instead of localtime.

=cut

use FindBin;
use lib "$FindBin::Bin/../lib";
use PAUSE ();
use File::Compare qw(compare);
use strict;

chdir $PAUSE::Config->{FTPPUB} or die "Could not chdir to $PAUSE::Config->{FTPPUB}: $!";
mkdir "indexes", 0755 unless -d "indexes";

for my $dir (qw(authors modules)) {
    chdir $dir or die;

#    system qq(ls -lgR > ../indexes/.$dir.ls-lR);

    # find goes depth first algorithm, we need breadth first
    use File::Find;
    local *FH;
    open FH, ">../indexes/.$dir.ls-lR" or die;
    my %seen;
    find(sub {
	     return if $seen{$File::Find::dir}++;
	     my $ffdir = $File::Find::dir;
	     $ffdir =~ s|^./?||;
	     print FH "\n\n$ffdir\:\n" if $ffdir;
	     print FH "total 123456789\n";
	     local *DIR;
	     opendir DIR, "." or die "Couldn't open . [=$ffdir]: $!";
	     my @dir = sort readdir DIR;
	     closedir DIR;
	     for my $dirent (@dir) {
		 next if substr($dirent,0,1) eq ".";
		 print FH gmls($dirent);
	     }
	     print FH "\n\n";
	 }, "." );

    close FH;
    chdir "../indexes";
#    system(qq(gzip -c9 < .$dir.ls-lR > .$dir.ls-lR.gz))==0 or
# 	rename ".$dir.ls-lR.gz", ".$dir.ls-lR.gz.error";

    if (
	-f ".$dir.ls-lR"
	&&
	(
	 ! -f "$dir.ls-lR"
	 or
	 compare("$dir.ls-lR", ".$dir.ls-lR")
	)
	&&
	system(qq(gzip -c9 < .$dir.ls-lR > .$dir.ls-lR.gz))==0
       ) {
      rename ".$dir.ls-lR", "$dir.ls-lR";
      rename ".$dir.ls-lR.gz", "$dir.ls-lR.gz";
    }
    chdir "..";
}

sub gmls {
    my($name) = @_;
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$sizemm,
     $atime,$mtime,$ctime,$blksize,$blocks) = lstat($name);

    my($perms,%user);
    my $pname = $name;

    if ($blocks) {
	$blocks = int(($blocks + 1) / 2);
    } else {
	$blocks = int(($sizemm + 1023) / 1024);
    }

    if    (-f _) { $perms = '-'; }
    elsif (-d _) { $perms = 'd'; }
    elsif (-c _) { $perms = 'c'; $sizemm = &sizemm; }
    elsif (-b _) { $perms = 'b'; $sizemm = &sizemm; }
    elsif (-p _) { $perms = 'p'; }
    elsif (-S _) { $perms = 's'; }
    else         { $perms = 'l'; $pname .= ' -> ' . readlink($name); }

    my(@rwx) = ('---','--x','-w-','-wx','r--','r-x','rw-','rwx');
    my(@moname) = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my $tmpmode = $mode;
    my $tmp = $rwx[$tmpmode & 7];
    $tmpmode >>= 3;
    $tmp = $rwx[$tmpmode & 7] . $tmp;
    $tmpmode >>= 3;
    $tmp = $rwx[$tmpmode & 7] . $tmp;
    substr($tmp,2,1) =~ tr/-x/Ss/ if -u _;
    substr($tmp,5,1) =~ tr/-x/Ss/ if -g _;
    substr($tmp,8,1) =~ tr/-x/Tt/ if -k _;
    $perms .= $tmp;

    my $user = $uid;   # too lazy to implement lookup

    my($sec,$min,$hour,$mday,$mon,$year) = gmtime($mtime);
    my($timeyear);
    my($moname) = $moname[$mon];
    if (-M _ > 365.25 / 2) {
	$timeyear = $year + 1900;
    }
    else {
	$timeyear = sprintf("%02d:%02d", $hour, $min);
    }

    sprintf "%-10s %2d %-3s %8s %s %2d %5s %s\n",
	      $perms,
		    $nlink,
		       $user,
			    $sizemm,
			        $moname,
				    $mday,
				        $timeyear,
					    $pname;
}


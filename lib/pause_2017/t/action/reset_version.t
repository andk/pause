use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_reset_version_PKG => ["Foo"],
    SUBMIT_pause99_reset_version_forget => 1,
};

Test::PAUSE::Web->setup;

subtest 'basic' => sub {
    my $t = Test::PAUSE::Web->new;

    $t->mod_dbh->do("TRUNCATE packages");
    my $sth = $t->mod_dbh->prepare("INSERT INTO packages (
      package,
      version,
      dist,
      file,
      filemtime,
      pause_reg,
      comment,
      status
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $sth->execute("Foo", "0.01", "T/TE/TESTUSER/Foo-0.01.tar.gz", "Foo-0.01.tar.gz", 0, "TESTUSER", "", "index");
    $sth->execute("Bar", "0.02", "T/TE/TESTUSER/Bar-0.02.tar.gz", "Bar-0.02.tar.gz", 0, "TESTUSER", "", "index");



    my %form = %$default;
    $t->user_post_ok("/pause/authenquery?ACTION=reset_version", \%form);
    # note $t->content;
};

done_testing;

use v5.10;
use strict;
use warnings;
use DBI;
use Path::Tiny;
use PAUSE;
use PAUSE::Crypt;
use SQL::Maker;

my @users = qw(TESTUSER TESTADMIN TESTCNSRD);

my $maker = SQL::Maker->new(driver => 'mysql');
my $dbh = DBI->connect("dbi:mysql:pause;host=mysql", $ENV{PAUSE_DEV_DBUSER}, $ENV{PAUSE_DEV_DBPASS}, {
	AutoCommit => 1,
	PrintError => 0,
	RaiseError => 1,
	ShowErrorStatement => 1,
});
{
    $dbh->do('TRUNCATE pause.usertable');
    for my $user (@users) {
        my ($sql, @bind) = $maker->insert('pause.usertable', {
            user => $user,
            password => PAUSE::Crypt::hash_password('test'),
            secretemail => lc($user) . '@localhost',
		});
        $dbh->do($sql, undef, @bind);
	    my $user_dir = join "/", $PAUSE::Config->{MLROOT}, PAUSE::user2dir($user);
	    path($user_dir)->mkpath;
    }
    $dbh->do('TRUNCATE grouptable');
    my ($sql, @bind) = $maker->insert('pause.grouptable', {user => 'TESTADMIN', ugroup => 'admin'});
    $dbh->do($sql, undef, @bind);
}

{
    $dbh->do('TRUNCATE pause.users');
    for my $user (@users) {
        my ($sql, @bind) = $maker->insert('pause.users', {
            userid => $user,
            fullname => "$user Name",
            email => ($user eq "TESTCNSRD" ? "CENSORED" : (lc($user) . '@localhost')),
            cpan_mail_alias => 'secr',
            isa_list => '',
        });
        $dbh->do($sql, undef, @bind);
    }
}

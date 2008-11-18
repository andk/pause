
use LWP::UserAgent;
use Sys::Hostname qw(hostname);
use utf8;

{
    my $ua;
    sub _ua {
        return $ua if $ua;
        $ua = LWP::UserAgent->new
            (
             keep_alive => 1,
            );
        $ua->parse_head(0);
        $ua;
    }
}
my $root;
$|=1;
BEGIN {
    unshift @INC, './lib', './t';

    my $exit_message;
    if (hostname eq "k75") {
        $root = "http://andk:ddd\@k75:8406";
        my $resp = _ua->get("$root/pause/query");
        unless ($resp->is_success) {
            $exit_message = "local staging host not running, maybe try 'sudo /home/src/www/apache/apachebin/1.3.37/bin/httpd -f  `pwd`/apache-conf/httpd.conf.pause.atk75' (watch error log '...')";
        }
    } else {
        $exit_message = sprintf "unknown staging host[%s]", hostname;
    }
    if ($exit_message) {
        $|=1;
        print "1..0 # SKIP $exit_message\n";
        eval "require POSIX; 1" and POSIX::_exit(0);
    }
}
use Test::More tests => 2;

my $resp = _ua->get("$root/pause/authenquery");
ok $resp->is_success, "Got root[$root]";
like $resp->decoded_content, qr/Hi Andreas J. König,/, "Saw name of Andreas Koenig";

# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:

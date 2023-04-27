package PrivatePAUSE;
use File::Spec::Functions qw(catdir catfile);

my $Root  = $ENV{PAUSE_DEV_ROOT} // '/home/k/pause';
my $Email = $ENV{PAUSE_DEV_EMAIL} // 'pause@localhost.localdomain';

print STDERR "ENV: $_: $ENV{$_}\n" for sort keys %ENV;

print STDERR "Root: $Root\n";
print STDERR "Email: $Email\n";

$PAUSE::Config->{AUTHEN_DATA_SOURCE_NAME} = 'dbi:mysql:pause;host=mysql';
$PAUSE::Config->{AUTHEN_DATA_SOURCE_USER} = 'pause';
$PAUSE::Config->{AUTHEN_DATA_SOURCE_PW} = 'test';

$PAUSE::Config->{MOD_DATA_SOURCE_NAME} = 'dbi:mysql:pause;host=mysql';
$PAUSE::Config->{MOD_DATA_SOURCE_USER} = 'pause';
$PAUSE::Config->{MOD_DATA_SOURCE_PW} = 'test';

$PAUSE::Config->{DOCUMENT_ROOT} = catdir($Root, 'htdocs');
$PAUSE::Config->{ADMIN} = $Email;
$PAUSE::Config->{ADMINS} = [$Email];
$PAUSE::Config->{CPAN_TESTERS} = $Email;
$PAUSE::Config->{TO_CPAN_TESTERS} = $Email;
$PAUSE::Config->{REPLY_TO_CPAN_TESTERS} = $Email;
$PAUSE::Config->{GONERS_NOTIFY} = $Email;
$PAUSE::Config->{P5P} = $Email;
$PAUSE::Config->{ML_CHOWN_USER} = 'nobody';
$PAUSE::Config->{ML_CHOWN_GROUP} = 'nogroup';
$PAUSE::Config->{ML_MIN_INDEX_LINES} = 0;
$PAUSE::Config->{ML_MIN_FILES} = 0;
$PAUSE::Config->{RUNDATA} = '/usr/local/rundata';
$PAUSE::Config->{UPLOAD} = $Email;
$PAUSE::Config->{HAVE_PERLBAL} = 0;
$PAUSE::Config->{SLEEP} = 1;
$PAUSE::Config->{PAUSE_LOG} = '/var/log/paused.log';
$PAUSE::Config->{PAUSE_LOG_DIR} = '/var/log';
$PAUSE::Config->{INCOMING} = 'http://pause.localhost/incoming/';
$PAUSE::Config->{RECAPTCHA_ENABLED} = 1 unless $ENV{TEST_HARNESS};
$PAUSE::Config->{CHECKSUMS_SIGNING_ARGS} = '--homedir /root/.gnupg --clearsign --default-key';
$PAUSE::Config->{CHECKSUMS_SIGNING_KEY} = 'A34B1DABBB49489C';
$PAUSE::Config->{BATCH_SIG_HOME} = '/root/.gnupg';


1;

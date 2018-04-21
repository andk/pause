use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default = {
    pause99_request_id_fullname => 'full name',
    pause99_request_id_email => 'test@localhost.localdomain',
    pause99_request_id_homepage => 'none',
    pause99_request_id_userid => 'NEWUSER',
    pause99_request_id_rationale => 'Hello, my ratoinale is to test PAUSE',
    SUBMIT_pause99_request_id_sub => 1,
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for_get('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        $t->$method("$path?ACTION=request_id")
          ->text_is("h2.firstheader", "Request PAUSE account");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = %$default;
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_like("pre.email_sent", qr/Subject: PAUSE ID request \(NEWUSER/);
        is $t->deliveries => 2, "two deliveries (one for admin, one for requester)";
        # note $t->content;
    }
};

subtest 'post: thank you, bot' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            url => 'http://host/path',
        );
        $t->$method("$path?ACTION=request_id", \%form);
        is $t->content => "Thank you!";
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: no space in full name' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_fullname => 'FULLNAME',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/Name does not look like a full civil name/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: no full name' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_fullname => '',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/You must supply a name/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: no email' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_email => '',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/You must supply an email address/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: rational is too short' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_rationale => 'rationale',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/this looks a\s+bit too short/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

# XXX: might be better to ignore other attributes (or YAGNI)
subtest 'post: rational has html links' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_rationale => '<a href="link">',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/Please do not use HTML links/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: multiple links' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_rationale => <<'SPAM',
http://spam/path
http://spam/path
SPAM
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/Please do not include more than one URL/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: no rationale' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_rationale => '',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/You must supply a short description/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: userid is taken' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_userid => 'TESTUSER',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/The userid TESTUSER is already taken/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: invalid userid' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_userid => 'INV#LID',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/The userid INV#LID does not match/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: no userid' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_userid => '',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2.firstheader", "Request PAUSE account")
          ->text_is("h3", "Error processing form")
          ->text_like("ul.errors li", qr/You must supply a desired user-ID/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: lots of .info' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_rationale => <<'SPAM',
ttp://spam.info
ttp://spam.info
ttp://spam.info
ttp://spam.info
ttp://spam.info
SPAM
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/rationale looks like spam/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

subtest 'post: interesting .cn homepage' => sub {
    local $PAUSE::Config->{RECAPTCHA_ENABLED} = 0;
    for my $test (Test::PAUSE::Web->tests_for_post('public')) {
        my ($method, $path) = @$test;
        note "$method for $path";
        my $t = Test::PAUSE::Web->new;
        my %form = (
            %$default,
            pause99_request_id_homepage => 'http://some.cn/index.htm',
            pause99_request_id_rationale => 'interesting site',
        );
        $t->$method("$path?ACTION=request_id", \%form)
          ->text_is("h2", "Error")
          ->text_like("p.error_message", qr/rationale looks like spam/);
        ok !$t->deliveries, "no deliveries";
        # note $t->content;
    }
};

done_testing;

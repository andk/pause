use Mojo::Base -strict;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::PAUSE::Web;
use utf8;

my $default_for_add_uri = {
    pause99_add_uri_httpupload => [Test::PAUSE::Web->file_to_upload],
    SUBMIT_pause99_add_uri_httpupload => 1,
};

my $default = {
    pause99_delete_files_FILE => ["Hash-RenameKey-0.02.tar.gz"],
};

Test::PAUSE::Web->setup;

subtest 'get' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);
        $t->get_ok("/user/delete_files");
        # note $t->content;
    }
};

subtest 'post: basic' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");
        $t->mod_dbh->do("TRUNCATE deletes");
        $t->remove_authors_dir($user);

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);

        # delete
        my %form = %$default;
        $form{SUBMIT_pause99_delete_files_delete} = 1;
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        my @deliveries = $t->deliveries;
        is @deliveries => 2;
        my ($mail_body) = map {$_->body} @deliveries;
        like $mail_body => qr!/user/delete_files!;

        my $rows = $t->mod_db->select('deletes', ['*']);
        is @$rows => 1;
        like $rows->[0]{deleteid} => qr!/$form{pause99_delete_files_FILE}[0]$!;

        # undelete
        delete $form{SUBMIT_pause99_delete_files_delete};
        $form{SUBMIT_pause99_delete_files_undelete} = 1;
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        ok $rows = $t->mod_db->select('deletes', ['*']);
        ok !@$rows;
    }
};

subtest 'post: absolute path' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");
        $t->mod_dbh->do("TRUNCATE deletes");
        $t->remove_authors_dir($user);

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        my $copied = $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);
        ok(File::Spec->file_name_is_absolute($copied));

        # delete
        my %form = (
            pause99_delete_files_FILE => [$copied],
            SUBMIT_pause99_delete_files_delete => 1
        );
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        my @deliveries = $t->deliveries;
        is @deliveries => 2;
        my ($mail_body) = map {$_->body} @deliveries;
        like $mail_body => qr/WARNING: illegal filename/;

        my $rows = $t->mod_db->select('deletes', ['*']);
        ok !@$rows;
    }
};

subtest 'post: file not found' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");
        $t->mod_dbh->do("TRUNCATE deletes");
        $t->remove_authors_dir($user);

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        my $copied = $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);

        # delete
        my %form = (
            pause99_delete_files_FILE => ['Something-Else-0.02.tar.gz'],
            SUBMIT_pause99_delete_files_delete => 1
        );
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        my @deliveries = $t->deliveries;
        is @deliveries => 2;
        my ($mail_body) = map {$_->body} @deliveries;
        like $mail_body => qr/WARNING: file not found/;

        my $rows = $t->mod_db->select('deletes', ['*']);
        ok !@$rows;
    }
};

subtest 'post: CHECKSUMS' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");
        $t->mod_dbh->do("TRUNCATE deletes");
        $t->remove_authors_dir($user);

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        my $copied = $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);
        $t->save_to_authors_dir($user, "CHECKSUMS", "CHECKSUMS");

        # delete
        my %form = (
            pause99_delete_files_FILE => ['CHECKSUMS'],
            SUBMIT_pause99_delete_files_delete => 1
        );
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        my @deliveries = $t->deliveries;
        is @deliveries => 2;
        my ($mail_body) = map {$_->body} @deliveries;
        like $mail_body => qr/WARNING: CHECKSUMS not erasable/;

        my $rows = $t->mod_db->select('deletes', ['*']);
        ok !@$rows;
    }
};

subtest 'post: readme' => sub {
    for my $test (Test::PAUSE::Web->tests_for('user')) {
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");
        $t->mod_dbh->do("TRUNCATE deletes");
        $t->remove_authors_dir($user);

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        my $copied = $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);
        $t->save_to_authors_dir($user, "Hash-RenameKey-0.02.readme", "README");

        # delete
        my %form = %$default;
        $form{SUBMIT_pause99_delete_files_delete} = 1;
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        # .readme is deleted when a related tarball is removed
        my @deliveries = $t->deliveries;
        is @deliveries => 2;
        my ($mail_body) = map {$_->body} @deliveries;
        like $mail_body => qr/\.readme/;

        my $rows = $t->mod_db->select('deletes', ['*']);
        is @$rows => 2;
        ok grep {$_->{deleteid} =~ /\.readme$/} @$rows;
    }
};

subtest 'post: delete by admin using select_user' => sub {
    {
        my $test = Test::PAUSE::Web->tests_for('user');
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        $t->mod_dbh->do("TRUNCATE uris");
        $t->mod_dbh->do("TRUNCATE deletes");
        $t->remove_authors_dir($user);

        # prepare distribution
        $t->post_ok("/user/add_uri", $default_for_add_uri, "Content-Type" => "form-data");

        my $copied = $t->copy_to_authors_dir($user, scalar Test::PAUSE::Web->file_to_upload);
    }
    {
        my $test = Test::PAUSE::Web->tests_for('admin');
        my ($path, $user) = @$test;
        my $t = Test::PAUSE::Web->new;
        $t->login(user => $user);

        my %action_form = (
            HIDDENNAME => "TESTUSER",
            ACTIONREQ => "delete_files",
            pause99_select_user_sub => 1,
        );
        $t->post_ok("/admin/select_user", \%action_form);
        # note $t->content;

        # delete
        my %form = %$default;
        $form{SUBMIT_pause99_delete_files_delete} = 1;
        $form{HIDDENNAME} = "TESTUSER";
        $t->post_ok("/user/delete_files", \%form);
        # note $t->content;

        my @deliveries = $t->deliveries;
        is @deliveries => 3; # for TESTUSER, TESTADMIN, pause_admin
        my ($mail_body) = map {$_->body} @deliveries;
        like $mail_body => qr!/user/delete_files!;

        my $rows = $t->mod_db->select('deletes', ['*']);
        is @$rows => 1;
        like $rows->[0]{deleteid} => qr!/$form{pause99_delete_files_FILE}[0]$!;
    }
};

done_testing;

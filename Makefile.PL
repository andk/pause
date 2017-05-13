#!/usr/bin/perl

use strict;
use ExtUtils::MakeMaker;
WriteMakefile(
              NAME          => 'PAUSE',
              VERSION_FROM  => 'lib/PAUSE.pm',
              ABSTRACT_FROM => 'lib/PAUSE.pod',
              AUTHOR        => 'Andreas Koenig <andreas.koenig.7os6VVqR@franz.ak.mind.de>',
              LICENSE       => 'perl',
              PREREQ_PM     => { map +($_ => 0), qw(
    Apache::Session::Counted
    BSD::Resource
    Capture::Tiny
    CPAN::Checksums
    CPAN::DistnameInfo
    CPAN::Indexer::Mirror
    Class::MOP::Class
    Class::Singleton
    Compress::Zlib
    Crypt::Eksblowfish::Bcrypt
    Cwd
    DB_File
    DBD::mysql
    DBD::SQLite
    DBI
    DBIx::RunSQL
    Devel::Peek
    Dumpvalue
    Email::Address
    Email::MIME
    Email::Sender::Simple
    File::Copy::Recursive
    File::pushd
    File::Rsync::Mirror::Recentfile
    File::Temp
    File::Which
    Git::Wrapper
    HTML::Entities
    HTTP::Date
    HTTP::Request::Common
    IO::Socket::SSL
    IPC::Cmd
    IPC::Run3
    JSON::XS
    Log::Dispatch
    Log::Dispatch::Config
    LWP::UserAgent
    LWP::Protocol::https
    Digest::MD5
    Digest::SHA1
    Mail::Mailer
    Mail::Send
    Module::Faker::Dist
    Module::Signature
    MooseX::StrictConstructor
    Net::FTP
    Parse::CPAN::Packages
    Parse::CPAN::Perms
    Path::Class
    Path::Tiny
    Plack
    Plack::App::Directory::Apaxy
    Plack::Middleware::Auth::Basic
    Plack::Middleware::ReverseProxy
    Plack::Middleware::ServerStatus::Tiny
    Set::Crontab
    String::Random
    Test::Class
    Test::Deep
    Test::FITesque::Fixture
    Test::MockObject
    Test::mysqld
    Test::WWW::Mechanize::PSGI
    Text::Format
    Text::Metaphone
    Text::Soundex
    Text::Unidecode
    Time::Duration
    Time::HiRes
    URI::Escape
    URI::URL
    Unicode::Collate
    Unicode::String
    WWW::Mechanize::Boilerplate
    XML::LibXML
    XML::Parser
    XML::SAX::Base
    XML::SAX::Writer
    YAML::XS
)},
              SIGN => 1,
              ($ExtUtils::MakeMaker::VERSION >= 6.4502 ?
               (META_ADD => {
                             resources => {
                                 repository => "git://github.com/andk/pause.git",
                             },
                             keywords => ['CPAN','perl','perl authors upload server'],
                            }) : ()),
             );

sub MY::postamble {
  <<EOF;
cpanshell ::
\t\$(PERL) -MCPAN -e shell

rsynctest ::
\t\$(ECHO) USER=\$(USER) RSYNC_PASSWORD=\$(RSYNC_PASSWORD) ...
\tUSER=\$(USER) RSYNC_PASSWORD=\$(RSYNC_PASSWORD) rsync --port=8732 pause.perl.org::PAUSE/authors/02STAMP

getdump:
	rsync -P pause.perl.org::pausedata/moddump.current .
	\@echo You need to call next: make recorddump

recorddump: moddump.current
	mysql -u root -p mod < moddump.current

stopslave:
	mysql -u root -p -e 'stop slave'

startslave:
	mysql -u root -p -e 'start slave; show slave status\\G'

doc/mod.schema.txt:
	mysqldump -u root -p mod          --quote-names=false --no-data --skip-add-drop-table > \$\@

doc/authen_pause.schema.txt:
	mysqldump -u root -p authen_pause --quote-names=false --no-data --skip-add-drop-table > \$\@

htdocs/namingmodules.html: htdocs/namingmodules.pod
	-[ -r \$\@ ] && chmod +w \$\@
	-\$(PERL) -MPod::Xhtml -e 'Pod::Xhtml->new->parse_from_file(\*ARGV)' htdocs/namingmodules.pod > \$\@

EOF
}

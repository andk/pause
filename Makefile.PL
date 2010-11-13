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
    Apache::DB
    Apache::HeavyCGI
    Apache::Request
    Apache::Session::Counted
    BSD::Resource
    CPAN::Checksums
    CPAN::DistnameInfo
    CPAN::Indexer::Mirror
    Class::Singleton
    Compress::Zlib
    Cwd
    DBI
    Devel::Peek
    Dumpvalue
    Email::Address
    File::Rsync::Mirror::Recentfile
    HTML::Entities
    HTTP::Date
    IPC::Run3
    MD5
    Mail::Mailer
    Mail::Send
    Module::Faker::Dist
    Module::Signature
    Net::FTP
    Set::Crontab
    String::Random
    Test::FITesque::Fixture
    Text::Format
    Text::Metaphone
    Text::Unidecode
    Time::HiRes
    URI::Escape
    URI::URL
    Unicode::Collate
    Unicode::String
    XML::SAX::Base
    XML::SAX::Writer
    YAML::XS
)},
              SIGN => 1,
             );
open my $fh, ">>", "Makefile" or die;
print $fh <<EOF;
cpanshell ::
\t\$(PERL) -MCPAN -e shell

rsynctest ::
\t\$(ECHO) USER=\$(USER) RSYNC_PASSWORD=\$(RSYNC_PASSWORD) ...
\tUSER=\$(USER) RSYNC_PASSWORD=\$(RSYNC_PASSWORD) rsync --port=8732 pause.perl.org::PAUSE/authors/02STAMP

EOF

print $fh <<'EOF' or die;
htdocs/namingmodules.html: htdocs/namingmodules.pod
	-[ -r $@ ] && chmod +w $@
	-$(PERL) -MPod::Xhtml -e 'Pod::Xhtml->new->parse_from_file(\*ARGV)' htdocs/namingmodules.pod > $@

EOF

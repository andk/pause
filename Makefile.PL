#!/usr/bin/perl

use strict;
use inc::Module::Install;

name            ('PAUSE');
version_from    ('lib/PAUSE.pm');
abstract        ('Perl Authors Upload Server');
author          ('Andreas Koenig <andreas.koenig.7os6VVqR@franz.ak.mind.de>');
license         ('perl');
requires        (map +($_ => 0), qw(
    Apache::DB               Apache::HeavyCGI         Apache::Request
    Apache::Session::Counted BSD::Resource            CPAN::Checksums
    CPAN::Indexer::Mirror    Class::Singleton         Compress::Zlib
    Cwd                      DBI                      Devel::Peek
    Dumpvalue                HTML::Entities           HTTP::Date
    MD5                      Mail::Mailer             Mail::Send
    Module::Faker::Dist      Module::Signature        Net::FTP
    Set::Crontab             String::Random           Test::FITesque::Fixture
    Text::Format             Text::Metaphone          Text::Unidecode
    Time::HiRes              URI::Escape              URI::URL
    Unicode::Collate         Unicode::String          XML::SAX::Base
    XML::SAX::Writer         YAML::XS
    
));
WriteAll        ( sign => 1, check_nmake => 0 );
open my $fh, ">>", "Makefile" or die;
print $fh <<EOF;
cpanshell ::
\t\$(PERL) -MCPAN -e shell
EOF

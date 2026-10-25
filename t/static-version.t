use v5.36.0;

use lib 't/lib';
use lib 't/privatelib'; # Stub PrivatePAUSE

use File::Temp ();
use PAUSE;
use PAUSE::pmfile;
use Test::More;

# These tests check the version found in a file without running any of it.
# Where a line is accepted, the expected value is what PAUSE got back when it
# used to evaluate the line in a Safe compartment.

sub version_from ($source) {
  my $tmp = File::Temp->new;
  print {$tmp} $source;
  close $tmp;
  return PAUSE::pmfile::static_version_from_file($tmp->filename);
}

sub version_is ($line, $want, $desc = $line) {
  my $got = version_from("package Foo;\n$line\n1;\n");
  is_deeply($got, { version => $want }, "version: $desc")
    or diag explain $got;
}

sub version_refused ($line, $desc = $line) {
  my $got = version_from("package Foo;\n$line\n1;\n");
  is_deeply($got, { refused => $line }, "refused: $desc")
    or diag explain $got;
}

sub file_version_is ($source, $want, $desc) {
  my $got = version_from($source);
  is_deeply($got, { version => $want }, "file version: $desc")
    or diag explain $got;
}

subtest "literal strings" => sub {
  version_is(q{our $VERSION = '1.23';},             '1.23');
  version_is(q{$VERSION = "1.23";},                 '1.23');
  version_is(q{our $VERSION = '0.006'; # VERSION},  '0.006');
  version_is(q{our $VERSION = 'v1.2.3';},           'v1.2.3');
  version_is(q{our $VERSION = '1.0_01';},           '1.0_01');
  version_is(q{$VERSION = $VERSION = q{1.0};},      '1.0');
  version_is(q{$VERSION = qq(1.04);},               '1.04');
  version_is(q{$Foo::Bar::VERSION = '0.12';},       '0.12');
  version_is(qq{our \$VERSION = '1.0';\r},          '1.0', 'CRLF line ending');
};

subtest "literal numbers" => sub {
  version_is(q{our $VERSION = 1.10;},          1.1);
  version_is(q{our $VERSION = 1_002.003_004;}, 1002.003004);
  version_is(q{our $VERSION = .5;},            0.5);
  version_is(q{our $VERSION=(2.001);},         2.001);
};

subtest "surrounding syntax" => sub {
  version_is(q{our ($VERSION) = ('1.11');},                  '1.11');
  version_is(q{use vars qw($VERSION); $VERSION = '1.0';},    '1.0');
  version_is(q[{ our $VERSION = '1.0'; }],                   '1.0');
  version_is(q{package Foo; our $VERSION = '1.0';},          '1.0');
  version_is(
    q{use 5.006; use strict; use warnings; no warnings qw(void); use utf8; our $VERSION = '1.01';},
    '1.01',
  );
};

subtest "version objects" => sub {
  version_is(q{use version; our $VERSION = version->declare('v1.2.3');}, '1.002003');
  version_is(q{use version; our $VERSION = version->declare("1.2.3");},  '1.002003');
  version_is(q{use version; our $VERSION = qv('1.2.3');},                '1.002003');
  version_is(q{use version; our $VERSION = qv(1.2);},                    '1.002000');
  version_is(q{our $VERSION = version->new('1.10');},                    '1.100');
  version_is(q{our $VERSION = version->new(1.10);},                      '1.100');
  version_is(q{our $VERSION = version->parse('1.002003');},              '1.002003');
};

subtest "lexical or localized \$VERSION" => sub {
  version_refused(q{my $VERSION = '1.0';},     'lexical');
  version_refused(q{my ($VERSION) = '1.0';},   'lexical, list assignment');
  version_refused(q{local $VERSION = '1.0';},  'localized');
};

subtest "refused" => sub {
  version_refused(q{our $VERSION = v1.2.3;},  'bare v-string');
  version_refused(q{our $VERSION = 1.2.3;},   'bare dotted v-string');
  version_refused(q{our $VERSION = 012;},     'octal');
  version_refused(q{our $VERSION = 1e3;},     'exponent');
  version_refused(q{our $VERSION = "$x";},    'interpolation');
  version_refused(q{our $VERSION = 'it\'s';}, 'escaped apostrophe');
  version_refused(q{our $VERSION = '1\.0';},  'backslash in single quotes');
  version_refused(q{BEGIN { our $VERSION = '1.0' }});
  version_refused(q{*VERSION = \'1.0';});
  version_refused(q{our $VERSION = $Other::VERSION;});
  version_refused(q{our $VERSION = '1.0'; $VERSION = eval $VERSION;});
  version_refused(q{our $VERSION = version->declare('garbage');});
  version_refused(q{our $VERSION = version->declare('v1.2.3')->numify;});
  version_refused(q{$VERSION = sprintf "%d.%02d", q$Revision: 1.5 $ =~ /(\d+)\.(\d+)/;});
  version_refused(q{our $VERSION = do { system("id"); '1.0' };});
};

subtest "finding the line" => sub {
  file_version_is("package Foo 1.23;\n1;\n", '1.23', 'package NAME VERSION');

  file_version_is(
    "package Foo 1.23;\nour \$VERSION = do { die };\n",
    '1.23',
    'package NAME VERSION comes first',
  );

  file_version_is("package Foo;\nsub foo { 1 }\n1;\n", 'undef', 'no version');

  file_version_is(
    "package Foo;\n\n=head1 VERSION\n\nour \$VERSION = do { die };\n\n=cut\n\nour \$VERSION = '2.0';\n",
    '2.0',
    'assignments in pod are ignored',
  );

  file_version_is(
    "package Foo;\n# our \$VERSION = do { die };\nour \$VERSION = '2.0';\n",
    '2.0',
    'commented-out assignments are ignored',
  );

  file_version_is(
    "package Foo;\n1;\n__END__\nour \$VERSION = do { die };\n",
    'undef',
    'assignments after __END__ are ignored',
  );

  file_version_is(
    "package Foo;\nif (\$VERSION == 1) { }\nour \$VERSION = '2.0';\n",
    '2.0',
    'comparisons to $VERSION are not assignments',
  );
};

subtest "unreadable file" => sub {
  my $got = PAUSE::pmfile::static_version_from_file('/nonexistent/Foo.pm');
  ok(exists $got->{openerr}, "missing file gives openerr");
};

done_testing;

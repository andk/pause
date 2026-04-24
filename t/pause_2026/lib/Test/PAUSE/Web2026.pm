package Test::PAUSE::Web2026;

use strict;
use warnings;
use Test::PAUSE::Web;
use parent 'Test::PAUSE::Web';
use Exporter qw/import/;

our @EXPORT = @Test::PAUSE::Web::EXPORT;

unshift @INC, "$Test::PAUSE::Web::AppRoot/lib/pause_2026";

$ENV{TEST_PAUSE_WEB_PSGI} //= "app_2026.psgi";

1;


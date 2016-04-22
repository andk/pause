package pause_1999::Test::SiteModel::Parser;

use Moose::Role;
use HTML::TreeBuilder;
requires 'mech';

# See the SiteModel for the basic justification
#
# Extend the SiteModel to be able to ->parse() certain pages
#
# Add the URL fragment to %pages, with a list of parsers to be used to extract
# data from the page. Parsers are by name in %parsers, and receive a
# HTML::TreeBuilder object.

our %pages = (
    homepage   => ['basic'],
    show_files => [qw/basic author_directory file_list/],
    delete_files => [qw/basic author_directory file_list/],
);

our %parsers = (
    author_directory => sub {
        my $tree = shift;
        my ($directory)
            = ( $tree->as_text =~ m!Files in directory (.+?) ! );
        return $directory;
    },
    basic => sub {
        my $tree = shift;
        my $status_box = $tree->find_by_attribute( class => 'statusunencr' )
            || $tree->find_by_attribute( class => 'statusencr' );

        my ( $username, $email ) = ( $status_box->as_text =~ m/(.+) <(.+)>/ );

        return {
            username => $username,
            email    => $email,
        };
    },
    file_list => sub {
        my $tree  = shift;
        my $pre   = $tree->look_down( _tag => 'pre' );
        return [] unless $pre;
        my @files = map {
            my $line = $_;
            if ( $line =~ m/([^ ]+)\s+(\d+)\s+([^<]+)/ ) {
                { filename => $1, size => $2, date => $3 };
            }
            else {
                ();
            }
        } split( m!<br />|\n!, $pre->as_HTML );
        return \@files;
    },
);

sub parse {
    my $self = shift;

    my $url = $self->mech->uri;
    $url =~ s!http://[^/]+!!;

    # Check we know how to parse this page
    my $page_spec;
    if ( $url =~ m!/pause/authenquery\?ACTION=(.+)! ) {
        $page_spec = $pages{$1}
            || die "Don't know how to autoparse [$url] ($1)";
    }
    elsif ( $url eq '/pause/authenquery' ) {
        $page_spec = $pages{'homepage'};
    }
    else {
        die "Don't know how to autoparse [$url]";
    }

    # Get the TreeBuilder for ir
    my $tree = HTML::TreeBuilder->new();
    $tree->parse( $self->mech->content );
    $tree->eof();
    $tree->elementify();

    my %result = map {
        my $parser = $parsers{$_} || die "Unknown parser [$_]";
        $_ => $parser->($tree);
    } @$page_spec;

    return \%result;
}

1;

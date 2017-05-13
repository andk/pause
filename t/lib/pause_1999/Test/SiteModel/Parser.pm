package pause_1999::Test::SiteModel::Parser;

use Moose::Role;
use HTML::TreeBuilder;
use YAML::XS qw/Load/;
requires 'mech';

# See the SiteModel for the basic justification
#
# Extend the SiteModel to be able to ->parse() certain pages
#
# Add the URL fragment to %pages, with a list of parsers to be used to extract
# data from the page. Parsers are by name in %parsers, and receive a
# HTML::TreeBuilder object.

our %pages = (
    homepage              => ['basic'],
    title_only            => ['title','header'],
    delete_files          => [qw/basic author_directory file_list/],
    email_for_admin       => [qw/basic email_for_admin/],
    email_for_admin__yaml => [qw/yaml/],
    show_files            => [qw/basic author_directory file_list/],
);

our %parsers = (
    author_directory => sub {
        my $tree = shift;
        my ($directory) = ( $tree->as_text =~ m!Files in directory (.+?) ! );
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
    email_for_admin => sub {
        my $tree           = shift;
        my @all_tables     = $tree->look_down( _tag => 'table' );
        my @content_tables = $all_tables[2]->look_down( _tag => 'table' );
        my $author_table   = $content_tables[2];
        my %authors
            = map { length $_->as_text == 0 ? undef : $_->as_text }
            $author_table->look_down( _tag => 'td' );
        return \%authors;
    },
    file_list => sub {
        my $tree = shift;
        my $pre = $tree->look_down( _tag => 'pre' );
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
    header => sub {
        my $tree = shift;
        my $status_box = $tree->find_by_attribute( _tag => 'h2', class => 'firstheader' );
        return $status_box->as_text;
    },
    title => sub {
        my $tree = shift;
        my $status_box = $tree->find_by_attribute( _tag => 'title' );
        return $status_box->as_text;
    },
    yaml => sub {
        my ( $tree, $content ) = @_;
        return scalar Load $content;
    },
);

sub parse {
    my $self = shift;

    my $url = $self->mech->uri;
    $url =~ s!http://[^/]+!!;

    # Check we know how to parse this page
    my $page_spec_force = shift;
    my $page_spec;

    if ( $page_spec_force ) {
        $page_spec = $pages{ $page_spec_force } || die "Unknown page spec [$page_spec_force]";
    }
    else {
        if ($url =~ m!/pause/authenquery\?ACTION=email_for_admin[;&]OF=YAML! )
        {
            $page_spec = $pages{'email_for_admin__yaml'};
        }
        elsif ( $url =~ m!/pause/authenquery\?ACTION=(.+)! ) {
            $page_spec = $pages{$1}
                || die "Don't know how to autoparse [$url] ($1)";
        }
        elsif ( $url eq '/pause/authenquery' ) {
            $page_spec = $pages{'homepage'};
        }
        else {
            die "Don't know how to autoparse [$url]";
        }
    }

    # Get the TreeBuilder for ir
    my $tree = HTML::TreeBuilder->new();
    $tree->parse( $self->mech->content );
    $tree->eof();
    $tree->elementify();

    my %result = map {
        my $parser = $parsers{$_} || die "Unknown parser [$_]";
        $_ => $parser->( $tree, $self->mech->content );
    } @$page_spec;

    return \%result;
}

1;

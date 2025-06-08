package PAUSE::Web2025::Plugin::EditUtils;

# XXX: Should be removed eventually

use Mojo::Base "Mojolicious::Plugin";
use ExtUtils::Manifest;
use Cwd ();

sub register {
  my ($self, $app, $conf) = @_;

  $app->helper(manifind => \&_manifind);
}

sub _manifind {
  my $c = shift;

  my $cwd = Cwd::cwd();
  warn "cwd[$cwd]";
  my %files = %{ExtUtils::Manifest::manifind()};
  if (keys %files == 1 && exists $files{""} && $files{""} eq "") {
    warn "ALERT: BUG in MANIFIND, falling back to zsh !!!";

    # This bug was caused by libc upgrade: perl and apache were
    # compiled with 2.1.3; upgrading to 2.2.5 and/or later
    # recompilation of apache has caused readdir() to return a list of
    # empty strings.

    open my $ls, "zsh -c 'ls **/*(.)' |" or die;
    %files = map { chomp; $_ => "" } <$ls>;
    close $ls;
  }

  %files;
}

1;

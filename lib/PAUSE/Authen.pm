package PAUSE::Authen;


=comment

Dead code. Is presumably not used anymore.

=cut

use Apache ();
use strict;
use Apache::Constants qw(OK AUTH_REQUIRED DECLINED);
use HTTPD::UserAdmin;

use lib '/home/k/PAUSE/lib';
use PAUSE ();

# $Id: Authen.pm,v 1.15 1999/10/24 11:11:08 k Exp k $

sub handler {
    my($r) = @_;
    die sprintf(
		"PAUSE::Authen::handler called for uri[%s]args[%s]",
		$r->uri,
		$r->args,
	       );
    return OK unless $r->is_initial_req; #only the first internal request
    my($res, $sent_pw) = $r->get_basic_auth_pw;
    # warn "res[$res]sent_pw[$sent_pw]";
    return $res if $res; #decline if not Basic

    my $user = $r->connection->user;
    # warn "user[$user]";

    my @args = @{$PAUSE::Config->{HTTPD_AUTHEN_CONF}};
    warn "args[@args]";
    my $u = HTTPD::UserAdmin->new(@args);

    # The famous PAUSE case-insensitive authentification:
    unless ($user eq uc $user or $u->exists($user)){
	$user = uc $user;
	$r->connection->user($user);
    }
    if ($u->exists($user)) {
      my $crypt_pw  = $u->password($user);
      my($crypt_got) = crypt($sent_pw,$crypt_pw);
      return OK if $crypt_got eq $crypt_pw;
      $r->log_reason("user[$user]crypt_pw[$crypt_pw]crypt_got[$crypt_got]",
		     $r->uri);
    }

    # the famous one-time password for first time registrations
    return OK if try_one_time_passwd($user,$sent_pw);
    $r->note_basic_auth_failure;
    return AUTH_REQUIRED;
}

sub try_one_time_passwd {
  my($user,$sent_pw) = @_;
  for my $pass ("twice","once") {
    my %args = @{$PAUSE::Config->{HTTPD_AUTHEN_CONF_ONCE}};
    $args{DB} =~ s/XXX/$pass/;
    my $u = HTTPD::UserAdmin->new(%args) or return;
    if ($u->exists($user)) {
      my $crypt_pw  = $u->password($user);
      my($crypt_got) = crypt($sent_pw,$crypt_pw);
      if ($crypt_got eq $crypt_pw){
	$u->delete($user);
	# warn "pass[$pass]user[$user]crypt_pw[$crypt_pw]crypt_got[$crypt_got]";
	if ($pass eq "twice") {
	  my %args = @{$PAUSE::Config->{HTTPD_AUTHEN_CONF_ONCE}};
	  $args{DB} =~ s/XXX/once/;
	  $u = HTTPD::UserAdmin->new(%args) or return;
	  $u->add($user,$sent_pw);
	}
	return 1;
      } else {
	return;
      }
    }
  }
  return;
}

1;

=head1 MEMO for PAUSE::Authen

    .htaccess:

PerlSetVar AuthUserFile /usr/local/etc/httpd/etc/passwd
AuthName PAUSE
AuthType Basic
<Limit GET POST>
require valid-user
</Limit>

=cut

package PAUSE::Web::Controller::User::Cred;

use Mojo::Base "Mojolicious::Controller";
use Email::Address;
use PAUSE::Web::Util::Encode;
use Text::Unidecode;

sub edit {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my ($u, $nu); # user, newuser
  $u = $c->active_user_record;

  # @allmeta *must* be the union of meta and secmeta
  my @meta = qw( fullname asciiname email homepage cpan_mail_alias ustatus);
  my @secmeta = qw(secretemail);
  my @allmeta = qw( fullname asciiname email secretemail homepage cpan_mail_alias ustatus);

  my $cpan_alias = lc($u->{userid}) . '@cpan.org';

  my %meta = map {$_ => 1} @allmeta;

  my $consistentsubmit = 0;
  if (uc $req->method eq 'POST' and $req->param("pause99_edit_cred_sub")) {
    my $wantemail = $req->param("pause99_edit_cred_email");
    my $wantsecretemail = $req->param("pause99_edit_cred_secretemail");
    my $wantalias = $req->param("pause99_edit_cred_cpan_mail_alias");
    my $addr_spec = $Email::Address::addr_spec;
    if ($wantemail=~/^\s*$/ && $wantsecretemail=~/^\s*$/) {
      $pause->{error}{no_email} = 1;
    } elsif ($wantalias eq "publ" && $wantemail=~/^\s*$/) {
      $pause->{error}{no_public_email} = 1;
    } elsif ($wantalias eq "publ" && $wantemail=~/\Q$cpan_alias\E/i) {
      $pause->{error}{public_is_cpan_alias} = 1;
    } elsif ($wantalias eq "secr" && $wantsecretemail=~/^\s*$/) {
      $pause->{error}{no_secret_email} = 1;
    } elsif ($wantalias eq "secr" && $wantsecretemail=~/\Q$cpan_alias\E/i) {
      $pause->{error}{secret_is_cpan_alias} = 1;
    } elsif (defined $wantsecretemail && $wantsecretemail!~/^\s*$/ && $wantsecretemail!~/^\s*$addr_spec\s*$/) {
      $pause->{error}{invalid_secret} = 1;
    } elsif (defined $wantemail && $wantemail!~/^\s*$/ && $wantemail!~/^\s*$addr_spec\s*$/ && $wantemail ne 'CENSORED') {
      $pause->{error}{invalid_public} = 1;
    } else {
      $consistentsubmit = 1;
    }

    if ($consistentsubmit) {
      # more testing: make sure that we have in asciiname only ascii
      if (my $wantasciiname = $req->param("pause99_edit_cred_asciiname")) {
        if ($wantasciiname =~ /[^\040-\177]/) {
          $pause->{error}{not_ascii} = 1;
          $consistentsubmit = 0;
        } else {
          # set asciiname to empty if it equals fullname
          my $wantfullname = $req->param("pause99_edit_cred_fullname");
          if ($wantfullname eq $wantasciiname) {
            $req->param("pause99_edit_cred_asciiname", "");
          }
        }
      } else {
        # set asciiname on our own if they don't supply it
        my $wantfullname = $req->param("pause99_edit_cred_fullname");
        if ($wantfullname =~ /[^\040-\177]/) {
          $wantfullname = PAUSE::Web::Util::Encode::any2utf8($wantfullname);
          $wantasciiname = Text::Unidecode::unidecode($wantfullname);
          $req->param("pause99_edit_cred_asciiname", $wantasciiname);
        }
      }
    }
  } else {
    for my $field (@allmeta) {
      unless ($meta{$field}){
        warn "Someone tried strange field[$field], ignored";
        next;
      }
      if ( $field eq "ustatus" ) {
        if ( $u->{"ustatus"} eq "active" ) {
          next;
        }
      }
      $req->param("pause99_edit_cred_$field" => $u->{$field});
    }
  }

  if ($consistentsubmit) {
    $pause->{consistentsubmit} = 1;
    my $saw_a_change;
    my $now = time;

    # We once duplicated nearly exactly the same code of 100 lines.
    # Once for secretemail, once for the other attributes. Lines
    # marked with four hashmarks are the ones that differ. Why not
    # make it a function? Well, that function would have to take at
    # least 5 arguments and we want some variables in the lexical
    # scope. So I made it a loop for two complicated arrays.
    for my $quid (
                  [
                   "connect",
                   \@meta,
                   "users",
                   "userid",
                   1
                  ],
                  ["authen_connect",
                   \@secmeta,
                   $PAUSE::Config->{AUTHEN_USER_TABLE},
                   $PAUSE::Config->{AUTHEN_USER_FLD},
                   0
                  ]
                 ) {
      my($connect,$atmeta,$table,$column,$mailto_admins) = @$quid;
      my(@set,@mailblurb);
      my $dbh = $mgr->$connect(); #### the () for older perls
      for my $field (@$atmeta) { ####
        # warn "field[$field]";
        # Ignore fields we do not intend to change
        unless ($meta{$field}){
          warn "Someone tried strange field[$field], ignored";
          next;
        }
        # find out the form field name
        my $form_field = "pause99_edit_cred_$field";
        if ( $field eq "ustatus" ) {
          if ( $u->{"ustatus"} eq "active" ) {
            next;
          } elsif (!$req->param($form_field)) {
            $req->param($form_field,"unused");
          }
        }
        # $s is the value they entered
        my $s_raw = $req->param($form_field) || "";
        # we're in edit_cred
        my $s;
        $s = PAUSE::Web::Util::Encode::any2utf8($s_raw);
        $s =~ s/^\s+//;
        $s =~ s/\s+\z//;
        if ($s ne $s_raw) {
          $req->param($form_field,$s);
        }
        $nu->{$field} = $s;
        $u->{$field} = "" unless defined $u->{$field};
        my $mb; # mailblurb
        if ($u->{$field} ne $s) {
          $saw_a_change = 1;
          # No UTF8 running before we have the system walking
          #        my $utf = $mgr->formfield_as_utf8($s);
          #        unless ( $s eq $utf ) {
          #          $req->param($form_field, $utf);
          #          $s = $utf;
          #        }
          #        next if $pause->{User}{$field} eq $s;

          # not ?-ising this as rely on quote() method
          push @set, "$field = " . $dbh->quote($s);
          $mb = {field => $field, value => $s, was => $u->{$field}};
          if ($field eq "ustatus") {
            push @set, "ustatus_ch = NOW()";
          }
          $u->{$field} = $s;
        } else {
          $mb = {field => $field, value => $s};
        }
        if ($field eq "secretemail") {
          $mb = {field => $field, value => "CENSORED"};
        }
        push @mailblurb, $mb;
      }

      if (@set) {
        my @query_params = ($now, $pause->{User}{userid}, $u->{userid});
        my $sql = "UPDATE $table SET " . ####
            join(", ", @set, "changed = ?, changedby=?") .
                " WHERE $column = ?"; ####
        $pause->{mailblurb} = \@mailblurb;
        my $mailblurb = $c->render_to_string("email/user/cred/edit", format => "email");
        # warn "sql[$sql]mailblurb[$mailblurb]";
        # die;
        if ($dbh->do($sql, undef, @query_params)) {
          $pause->{registered}{$table} = 1;
          $nu = $c->active_user_record($u->{userid});
          if ($nu->{userid} && $nu->{userid} eq $pause->{User}{userid}) {
            $pause->{User} = $nu;
          }
          # Send separate emails to user and public places because
          # CC leaks secretemail to others
          my @to;
          my %umailset;
          for my $lu ($u, $nu) {
            for my $att (qw(secretemail email)) {
              if ($lu->{$att}){
                $umailset{qq{<$lu->{$att}>}} = 1;
                last;
              }
            }
          }
          push @to, join ", ", keys %umailset;
          push @to, $mgr->config->mailto_admins if $mailto_admins;
          my $header = {Subject => "User update for $u->{userid}"};
          $mgr->send_mail_multi(\@to,$header, $mailblurb);
        } else {
# FIXME
          push @{$pause->{ERROR}}, sprintf(qq{Could not enter the data
        into the database: <i>%s</i>.},$dbh->errstr);
        }
      }
    } # end of quid loop

    if ($saw_a_change) {
      $pause->{saw_a_change} = 1;
      # expire temporary token to free mailpw for immediate use
      my $sql = qq{DELETE FROM abrakadabra
                   WHERE user = ?};
      my $dbh = $mgr->authen_connect();
      $dbh->do($sql,undef,$u->{userid});
    }
  }
}

1;

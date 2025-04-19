package PAUSE::Web::Controller::Admin;

use Mojo::Base "Mojolicious::Controller";

sub email_for_admin {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my %ALL;
  {
    my $dba = $mgr->authen_connect;
    my $dbm = $mgr->connect;
    my $sth1 = $dbm->prepare(qq{SELECT userid, email
                                FROM   users
                                WHERE  isa_list = ''
                                  AND  (
                                        cpan_mail_alias='publ'
                                        OR
                                        cpan_mail_alias='secr'
                                       )});
    $sth1->execute;
    while (my($id,$mail) = $sth1->fetchrow_array) {
      $ALL{$id} = $mail; # we store public email even for those who want
                         # secret, because we never know if we will find a
                         # secret one
    }
    $sth1->finish;
    my $sth2 = $dbm->prepare(qq{SELECT userid
                                FROM   users
                                WHERE  cpan_mail_alias='secr'
                                  AND  isa_list = ''});
    $sth2->execute;
    my $sth3 = $dba->prepare(qq{SELECT secretemail
                                FROM   usertable
                                WHERE  user=?});
    while (my($id) = $sth2->fetchrow_array) {
      $sth3->execute($id);
      next unless $sth3->rows;
      my($mail) = $sth3->fetchrow_array or next;
      $ALL{$id} = $mail;
    }
    $sth2->finish;
    $sth3->finish;
  };
  my $output_format = $req->param("OF");
  if ($output_format){
    if ($output_format eq "YAML") {
      return $c->render_yaml(\%ALL);
    } else {
      die "not supported OF=$output_format"
    }
  } else {
    my @list;
    for my $id (sort keys %ALL) {
      push @list, {id => $id, mail => $ALL{$id}};
    }
    $pause->{list} = \@list;
  }
}

sub edit_ml {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;
  my $u = $c->active_user_record;

  my $selectedid = "";
  my $selectedrec = {};

  my $param;
  if ($param = $req->param("pause99_edit_ml_3")) {  # upper selectbox
    $selectedid = $param;
  } elsif ($param = $req->param("HIDDENNAME")) {
    $selectedid = $param;
    $req->param("pause99_edit_ml_3" => $param);
  }

  warn sprintf(
               "selectedid[%s]IsMR[%s]",
               $selectedid,
               join(":",
                    keys(%{$pause->{IsMailinglistRepresentative}})
                   )
              );

  my($sql,@bind);
  if (exists $pause->{IsMailinglistRepresentative}{$selectedid}) {
    $sql = qq{SELECT users.userid
              FROM   users JOIN list2user
                           ON   users.userid = list2user.maillistid
              WHERE  users.isa_list > ''
                 AND list2user.userid = ?
              ORDER BY users.userid
};
    @bind = $pause->{User}{userid};
  } else {
    $sql = qq{SELECT userid FROM users WHERE isa_list > '' ORDER BY userid};
    @bind = ();
  }

  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);
  my @all_mls;
  my %mls_lab;
  if ($sth->rows) {
    my $sth2 = $dbh->prepare(qq{SELECT * FROM maillists WHERE maillistid=?});
    while (my($id) = $mgr->fetchrow($sth, "fetchrow_array")) {
      # register this mailinglist for the selectbox
      push @all_mls, $id;
      # query for more info about it
      $sth2->execute($id);
      my($rec) = $mgr->fetchrow($sth2, "fetchrow_hashref");
      # we will display the name along the ID
      $mls_lab{$id} = "$id ($rec->{maillistname})";
      if ($id eq $selectedid) {
        # if this is the selected one, we just store it immediately
        $selectedrec = $rec;
      }
    }
  }
  $pause->{mls} = [map {[$mls_lab{$_} => $_]} @all_mls];

  if ($selectedid) {
    $pause->{selected} = $selectedrec;
    my $force_sel = $req->param('pause99_edit_ml_2');
    my $update_sel = $req->param('pause99_edit_ml_4');

    $pause->{updated_sel} = $update_sel;

    my $saw_a_change;
    my $now = time;

    for my $field (qw(maillistname address subscribe)) {
      my $fieldname = "pause99_edit_ml_$field";
      if ($force_sel){
        $req->param($fieldname => $selectedrec->{$field}||"");
      } elsif ($update_sel) {
        my $param = $req->param($fieldname);
        if ($param ne $selectedrec->{$field}) {
          my $sql = qq{UPDATE maillists
                       SET $field=?,
                           changed=?,
                           changedby=?
                       WHERE maillistid=?};
          my $usth = $dbh->prepare($sql);
          my $ret = $usth->execute($param, $now, $u->{userid}, $selectedrec->{maillistid});
          $saw_a_change = 1 if $ret > 0;
          $usth->finish;
        }
      }
    }
    if ($saw_a_change) {
      $pause->{changed} = 1;
      my $mailblurb = $c->render_to_string("email/admin/edit_ml", format => "email");
      my @to = ($u->{secretemail}||$u->{email}, $mgr->config->mailto_admins);
      warn "sending to[@to]";
      warn "mailblurb[$mailblurb]";
      my $header = {
                    Subject => "Mailinglist update for $selectedrec->{maillistid}"
                   };
      $mgr->send_mail_multi(\@to, $header, $mailblurb);
    }
  }
}

sub select_user {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  if (my $action = $req->param("ACTIONREQ")) {
    if (
        $mgr->config->has_action($action)
       ) {
      $req->param("ACTION" => $action);
      $pause->{Action} = $action;
      return $c->delegate($action);
    } else {
      die "cannot action[$action]";
    }
  }

  my %user_meta = $c->user_meta;
  my $labels = $user_meta{userid}{args}{labels};
  $pause->{hidden_name_list} = [map {[
    $labels->{$_} => $_,
    ($_ eq $pause->{User}{userid} ? (selected => "selected") : ()),
  ]} sort keys %$labels];

  my $action_map = $mgr->config->action_map_to_verb($mgr->config->allow_admin_takeover);
  $pause->{action_req_list} = [map {[
    $action_map->{$_} => $_,
    ($_ eq 'edit_cred' ? (selected => "selected") : ()),
  ]} sort keys %$action_map];
}

1;

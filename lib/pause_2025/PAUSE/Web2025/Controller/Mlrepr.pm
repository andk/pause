package PAUSE::Web2025::Controller::Mlrepr;

use Mojo::Base "Mojolicious::Controller";

sub select_ml_action {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  my $dbh = $mgr->connect;
  if (my $action = $req->param("ACTIONREQ")) {
    if (
        $mgr->config->has_action($action)
        &&
        grep { $_ eq $action } $mgr->config->allow_mlrepr_takeover
       ) {
      $req->param(ACTION => $action);
      $pause->{Action} = $action;
      return $c->delegate($action);
    } else {
      die "cannot or want not action[$action]";
    }
  }

  my ($sql, @bind);
  if (exists $pause->{UserGroups}{admin}) {
    $sql = qq{SELECT users.userid
              FROM users, list2user
              WHERE isa_list > ''
                AND users.userid = list2user.maillistid
              ORDER BY users.userid
    };
  } else {
    $sql = qq{SELECT users.userid
              FROM users, list2user
              WHERE isa_list > ''
                AND users.userid = list2user.maillistid
                AND list2user.userid = ?
              ORDER BY users.userid
    };
    @bind = $pause->{User}{userid};
  }

  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);
  my %u;
  while (my @row = $mgr->fetchrow($sth, "fetchrow_array")) {
    $u{$row[0]} = $row[0];
  }

  my $action_map = $mgr->config->action_map_to_verb($mgr->config->allow_mlrepr_takeover);
  my @action_reqs = map {[$action_map->{$_} => $_]} sort keys %$action_map;
  $pause->{users} = [sort {lc($u{$a}) cmp lc($u{$b})} keys %u];
  $pause->{action_reqs} = \@action_reqs;
}

sub show_ml_repr {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;

  my $dbh = $mgr->connect;
  my $sth = $dbh->prepare("SELECT maillistid, userid
    FROM list2user
    ORDER BY maillistid, userid");
  $sth->execute;

  my @lists;
  while (my $rec = $mgr->fetchrow($sth, "fetchrow_hashref")) {
    push @lists, $rec;
  }
  $sth->finish;

  $pause->{lists} = \@lists;
}

1;

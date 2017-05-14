package PAUSE::Web::Controller::Admin::ManageId;

use Mojo::Base "Mojolicious::Controller";
use Storable;
use File::Find;
use JSON::XS; # used in the template

sub manage {
  my $c = shift;
  my $pause = $c->stash(".pause");
  my $mgr = $c->app->pause;
  my $req = $c->req;

  return unless exists $pause->{UserGroups}{admin};

  return unless -d $c->session_data_dir;

  my %ALL;
  my $delete;
  if ($req->param("subaction") && $req->param("subaction") eq "delete") {
    $delete = $req->param("USERID");
  }
  my $dbh = $mgr->connect;
  my $sthu = $dbh->prepare("SELECT userid from users where userid=?");

  find
      (
       {wanted => sub {
          my $path = $_;
          my @stat = stat $path or die "Could not stat '$path': $!";
          return unless -f _;
          my $mtime = $stat[9];
          open my $fh, "<", $path or die "Couldn't open '$path': $!";
          local $/;
          my $content = <$fh>;
          my $session = Storable::thaw $content;
          # warn "DEBUG: mtime[$mtime]stat[@stat]session[$session]";
          my $userid = $session->{APPLY}{userid} or return;
          if ($delete && $session->{_session_id} eq $delete) {
            unlink $path or die "Could not unlink '$path': $!";
            return;
          }
          my $type;
          if (exists $session->{APPLY}{fullname}) {
            $sthu->execute($userid);
            return if $sthu->rows > 0;
            $type = "user";
          }
          if ($session->{APPLY}{rationale} =~ /\b(?:BLONDE\s+NAKED|NAKED\s+SEXY|FREE\s+CUMSHOT|CUMSHOT\s+VIDEOS|FREE\s+SEX|FREE\s+TUBE|GROUP\s+SEX|FREE\s+PORN|SEX\s+VIDEO|SEX\s+MOVIES?|SEX\s+TUBE|SEX\s+MATURE|STREET\s+BLOWJOBS|SEX\s+PUBLIC|TUBE\s+PORN|PORN\s+TUBE|TUBE\s+VIDEOS|VIDEO\s+TUBE|XNXX\s+VIDEOS|XXX\s+FREE|ANIMAL\s+SEX|GIRLS\s+SEX|PORN\s+VIDEOS?|PORN\s+MOVIES|TITS\s+PORN|RAW\s+SEX|DEEPTHROAT\s+TUBE|celeb\s+porn|PREGNANT\s+TUBE|picture\s+sex|NAKED\s+WOMEN|WOMEN\s+MOVIES|MATURE\s+NAKED|SEX\s+ANIME|hot\s+nude|nude\s+celebs|ANIME\s+TUBES|SEX\s+DOG|MATURE\s+SEX|MATURE\s+PUSSY|Rape\s+Porn|brutal\s+fuck|rape\s+video|ANIMAL\s+TUBE|SHEMALE\s+CUMSHOT|ANIMAL\s+PORN|ANIMAP\s+CLIP|CLIP\s+SEX|PUBLIC\s+BLOWJOB|free\s+lesbian|lesbian\s+sex|SEX\s+ZOO|tv-adult|numismata.org|www.soulcommune.com|www.petsusa.org|www.csucssa.org|www.thisis50.com|www.comunidad-latina.net|www.singlefathernetwork.com|www.freetoadvertise.biz|gayforum.dk|www.purevolume.com|playgroup.themouthpiece.com|www.bananacorp.cl|party.thebamboozle.com|blog.tellurideskiresort.com|www.pethealthforums.com|www.burropride.com|lpokemon.19.forumer.com|Zootube365|Eskimotube|xtube-1|phentermine without a prescription)\b/i) {
            unlink $path or die "Could not unlink '$path': $!";
            return;
          }
          $ALL{$path} = {
                         session => $session,
                         mtime   => $mtime,
                         type    => $type,
                        };
        },
        no_chdir => 1,
       },
       $c->session_data_dir,
      );
  $pause->{all} = \%ALL;
}

1;

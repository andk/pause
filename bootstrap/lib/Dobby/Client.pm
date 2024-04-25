use v5.32.0;
use warnings;

package Dobby::Client;

use experimental 'signatures';
use parent 'IO::Async::Notifier';

use Carp ();
use Future::AsyncAwait;
use Future::Utils qw(repeat);
use IO::Async::Loop;
use JSON::MaybeXS;
use Net::Async::HTTP;

sub configure ($self, %param) {
  my @missing;

  KEY: for my $key (qw( bearer_token )) {
    unless (defined $param{$key}) {
      push @missing, $key;
      next KEY;
    }

    $self->{"__dobby_$key"} = $param{$key};
  }

  if (@missing) {
    Carp::confess("missing required Dobby::Client parameters: @missing");
  }

  return;
}

sub api_base {
  return 'https://api.digitalocean.com/v2';
}

sub bearer_token { $_[0]{__dobby_bearer_token} }

sub http ($self) {
  return $self->{__dobby_http} //= do {
    my $http = Net::Async::HTTP->new(
      user_agent => 'Dobby/0',
    );

    $self->loop->add($http);

    $http;
  };
}

async sub json_get ($self, $path) {
  my $res = await $self->http->do_request(
    method => 'GET',
    uri    => $self->api_base . $path,
    headers => {
      'Authorization' => "Bearer " . $self->bearer_token,
    },
  );

  unless ($res->is_success) {
    die "error getting $path at DigitalOcean: " . $res->as_string;
  }

  my $json = $res->decoded_content(charset => undef);
  decode_json($json);
}

async sub json_get_pages_of ($self, $path, $key) {
  my $url = $self->api_base . $path;

  my @items;

  while ($url) {
    my $res = await $self->http->do_request(
      method => 'GET',
      uri    => $url,
      headers => {
        'Authorization' => "Bearer " . $self->bearer_token,
      },
    );

    unless ($res->is_success) {
      die "error getting $path at DigitalOcean: " . $res->as_string;
    }

    my $json = $res->decoded_content(charset => undef);
    my $data = decode_json($json);

    die "no entry for $key in returned page"
      unless exists $data->{$key};

    push @items, $data->{$key}->@*;
    $url = $data->{links}{pages}{next};
  }

  return \@items;
}

async sub _json_req_with_body ($self, $method, $path, $payload) {
  my $res = await $self->http->do_request(
    method => $method,
    uri    => $self->api_base . $path,
    headers => {
      'Authorization' => "Bearer " . $self->bearer_token,
    },

    content_type => 'application/json',
    content      => encode_json($payload),
  );

  unless ($res->is_success) {
    die "error making $method to $path at DigitalOcean: " . $res->as_string;
  }

  my $json = $res->decoded_content(charset => undef);
  decode_json($json);
}

async sub json_post ($self, $path, $payload) {
  await $self->_json_req_with_body('POST', $path, $payload);
}

async sub json_put ($self, $path, $payload) {
  await $self->_json_req_with_body('PUT', $path, $payload);
}

async sub delete_url ($self, $path) {
  my $res = await $self->http->do_request(
    method => 'DELETE',
    uri    => $self->api_base . $path,
    headers => {
      'Authorization' => "Bearer " . $self->bearer_token,
    },
  );

  unless ($res->is_success) {
    die "error deleting resource at $path in DigitalOcean: " . $res->as_string;
  }

  return;
}

async sub create_droplet ($self, $arg) {
  state @required_keys = qw( name region size tags image ssh_keys );

  my @missing;
  KEY: for my $key (@required_keys) {
    unless (defined $arg->{$key}) {
      push @missing, $key;
      next KEY;
    }
  }

  if (@missing) {
    Carp::confess("missing required Dobby::Client parameters: @missing");
  }

  my $create_res = await $self->json_post(
    "/droplets",
    {
      $arg->%{ @required_keys },
    },
  );

  my $droplet   = $create_res->{droplet};

  unless ($droplet) {
    Carp::confess("Error creating Droplet.");
  }

  my $action_id = $create_res->{links}{actions}[0]{id};

  unless (defined $action_id) {
    Carp::confess(
      "no action id from droplet action: " . encode_json($create_res)
    );
  }

  my $waited = await $self->_do_action_status_f("/actions/$action_id");

  return $droplet;
}

async sub take_droplet_action ($self, $droplet_id, $action, $payload = {}) {
  my $action_res = await $self->json_post("/droplets/$droplet_id/actions", {
    %$payload,
    type => $action,
  });

  my $action_id = $action_res->{action}{id};

  unless (defined $action_id) {
    Carp::confess(
      "no action id from droplet action: " . encode_json($action_res)
    );
  }

  await $self->_do_action_status_f("/droplets/$droplet_id/actions/$action_id");

  return;
}

async sub destroy_droplet ($self, $droplet_id) {
  my $delete_res = await $self->delete_url("/droplets/$droplet_id");
  return;
}

async sub _do_action_status_f ($self, $action_url) {
  TRY: while (1) {
    my $action = await $self->json_get($action_url);
    my $status = $action->{action}{status};

    # ugh, DO is now sometimes returning empty string in the status field
    # -- michael, 2021-04-16
    $status = 'completed' if ! $status && $action->{action}{completed_at};

    if ($status eq 'in-progress') {
      await $self->loop->delay_future(after => 5);
      next TRY;
    }

    if ($status eq 'completed') {
      return;
    }

    if ($status eq 'errored') {
      Carp::confess("action $action_url failed: " .  encode_json($action->{action}));
    }

    Carp::confess("action $action_url in unknown state: $status");
  }
}

async sub _get_droplets ($self, $arg = {}) {
  my $path = '/droplets?per_page=200';
  $path .= "&tag_name=$arg->{tag}" if $arg->{tag};

  my $droplets_data = await $self->json_get($path);

  # TODO Obviously, this should lazily fetch etc.
  if ($droplets_data->{links}{pages}{forward_links}) {
    Carp::cluck("Single-page fetch did not find all droplets!");
  }

  unless ($droplets_data->{droplets}) {
    Carp::cluck(
      "getting /droplets didn't supply droplets: " . encode_json($droplets_data)
    );
  }

  return $droplets_data->{droplets}->@*;
}

async sub get_all_droplets ($self) {
  await $self->_get_droplets;
}

async sub get_droplets_with_tag ($self, $tag) {
  await $self->_get_droplets({ tag => $tag });
}

async sub add_droplet_to_project ($self, $droplet_id, $project_id) {
  my $path = "/projects/$project_id/resources";

  await $self->json_post($path, {
    resources => [ "do:droplet:$droplet_id" ],
  });
}

async sub get_all_domain_records_for_domain ($self, $domain) {
  my $path = '/domains/' . $domain . '/records';

  # TODO Obviously, this should lazily fetch etc.
  my $record_res = await $self->json_get("$path?per_page=200");
  return unless $record_res->{domain_records};
  return $record_res->{domain_records}->@*;
}

async sub remove_domain_records_for_ip ($self, $domain, $ip) {
  my $path = '/domains/' . $domain . '/records';

  my @records   = await $self->get_all_domain_records_for_domain($domain);
  my @to_delete = grep {; $_->{data} eq $ip } @records;
  my @deletions = map {; $self->delete_url("$path/$_->{id}") } @to_delete;

  return await Future->wait_all(@deletions);
}

async sub point_domain_record_at_ip ($self, $domain, $name, $ip) {
  my $path = '/domains/' . $domain . '/records';

  my @records = await $self->get_all_domain_records_for_domain($domain);

  my (@existing) = grep {; $_->{name} eq $name && $_->{type} eq 'A' } @records;

  if (@existing) {
    my @to_update = map {; $self->json_put("$path/$_->{id}", { data => $ip }) }
                    @existing;
    await Future->wait_all(@to_update);
    return;
  }

  await $self->json_post($path, {
    type => 'A',
    name => $name,
    data => $ip,
    ttl  => 30,
  });

  return;
}

1;

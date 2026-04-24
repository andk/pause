package PAUSE::Web2026::Config;

use Mojo::Base "PAUSE::Web::Config";

my %new_actions = (
  list_tokens => {
    x_mojo_to => "user-tokens#list",
    verb => "List Tokens",
    priv => "user",
    cat => "User/06Account/03",
    desc => "Manage your tokens for client scripts.",
    method => 'POST',
    x_csrf_protection => 1,
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      revoke_tokens_sub => {form_type => "submit_button"},
      revoke_tokens => {form_type => "check_box"},
    }
  },
  new_token => {
    x_mojo_to => "user-tokens#generate",
    verb => "Generate a New Token",
    priv => "user",
    cat => "User/06Account/04",
    desc => "Generate a new token for client scripts.",
    method => 'POST',
    x_csrf_protection => 1,
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      new_token_description => {form_type => "text_field"},
      new_token_scope => {form_type => "select_field"},
      new_token_expires_in => {form_type => "text_field"},
      new_token_ip_ranges => {form_type => "text_area"},
      new_token_sub => {form_type => "submit_button"},
    },
  },
  pause_logout => {
    x_mojo_to => "user#pause_logout",
    verb => "About Logging Out",
    priv => "user",
    cat => "User/06Account/05",
  },
);

%PAUSE::Web::Config::Actions = ( %PAUSE::Web::Config::Actions, %new_actions );

push @PAUSE::Web::Config::AllowAdminTakeover, "list_tokens";

1;

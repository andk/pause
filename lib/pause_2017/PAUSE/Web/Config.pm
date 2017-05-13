package PAUSE::Web::Config;

use Mojo::Base -base;
use PAUSE;

our $DO_UTF8 = 1;

our %Actions = (
  # PUBLIC
  request_id => {
    x_mojo_to => "public-request_id#request",
    verb => "Request PAUSE account",
    priv => "public",
    cat => "00reg/01",
    desc => "Apply for a PAUSE account.",
    x_form => {
      pause99_request_id_fullname => {form_type => "text_field"},
      pause99_request_id_email => {form_type => "text_field"},
      pause99_request_id_homepage => {form_type => "text_field"},
      pause99_request_id_userid => {form_type => "text_field"},
      pause99_request_id_rationale => {form_type => "text_area"},
      SUBMIT_pause99_request_id_sub => {form_type => "submit_button"},
      url => {form_type => "text_field"}, # bot-trap
    },
  },
  mailpw => {
    x_mojo_to => "public#mailpw",
    verb => "Forgot Password?",
    priv => "public",
    cat => "00urg/01",
    desc => "A passwordmailer that sends you a password that enables you to set a new password.",
    x_form => {
      ABRA => {form_type => "hidden_field"},
      pause99_mailpw_1 => {form_type => "text_field"},
      pause99_mailpw_sub => {form_type => "submit_button"},
    },
  },
  pause_04about => {
    x_mojo_to => "public#about",
    verb => "About PAUSE",
    priv => "public",
    cat => "01self/04a",
    desc => "Same as modules/04pause.html on any CPAN server",
  },
  pause_04imprint => {
    x_mojo_to => "public#imprint",
    verb => "Imprint/Impressum",
    priv => "public",
    cat => "01self/06b",
  },
  pause_05news => {
    x_mojo_to => "public#news",
    verb => "PAUSE News",
    priv => "public",
    cat => "01self/05",
    desc => "What's going on on PAUSE",
  },
  pause_06history => {
    x_mojo_to => "public#history",
    verb => "PAUSE History",
    priv => "public",
    cat => "01self/06",
    desc => "Old News",
  },
  pause_namingmodules => {
    x_mojo_to => "public#naming",
    verb => "On The Naming of Modules",
    priv => "public",
    cat => "01self/04b",
    desc => "A couple of suggestions that hopefully get you on track",
  },
  who_pumpkin => {
    x_mojo_to => "public#pumpkin",
    verb => "List of pumpkins",
    priv => "public",
    cat => "02serv/05",
    desc => "A list, also available as YAML",
  },
  who_admin => {
    x_mojo_to => "public#admin",
    verb => "List of admins",
    priv => "public",
    cat => "02serv/06",
    desc => "A list, also available as YAML",
  },

  # USER
  # USER/FILES

  add_uri => {
    x_mojo_to => "user-uri#add",
    verb => "Upload a file to CPAN",
    priv => "user",
    cat => "User/01Files/01up",
    desc => "This is the heart of the <b>Upload Server</b>, the page most heavily used on PAUSE.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      CAN_MULTIPART => {form_type => "hidden_field"},
      pause99_add_uri_subdirscrl => {form_type => "select_field"},
      pause99_add_uri_subdirtext => {form_type => "text_field"},
      pause99_add_uri_httpupload => {form_type => "file_field"},
      SUBMIT_pause99_add_uri_httpupload => {form_type => "submit_button"},
      pause99_add_uri_uri => {form_type => "text_field"},
      SUBMIT_pause99_add_uri_uri => {form_type => "submit_button"},
    },
  },
  show_files => {
    x_mojo_to => "user-files#show",
    verb => "Show my files",
    priv => "user",
    cat => "User/01Files/02show",
    desc => "find . -ls resemblance",
  },
  edit_uris => {
    x_mojo_to => "user#edit_uris",
    verb => "Repair a Pending Upload",
    priv => "user",
    cat => "User/01Files/03rep",
    desc => "When an upload you requested hangs for some reason, you can go here and edit the file to be uploaded.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      pause99_edit_uris_3 => {form_type => "select_field"}, # distributions
      pause99_edit_uris_2 => {form_type => "submit_button"}, # select target
      pause99_edit_uris_uri => {form_type => "text_field"}, # file to upload
      pause99_edit_uris_4 => {form_type => "submit_button"}, # upload
    },
  },
  delete_files => {
    x_mojo_to => "user-files#delete",
    verb => "Delete Files",
    priv => "user",
    cat => "User/01Files/04del",
    desc => "Schedule files for deletion. There is a delay until the deletion really happens. Until then you can also undelete files here.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      SUBMIT_pause99_delete_files_delete => {form_type => "submit_button"},
      SUBMIT_pause99_delete_files_undelete => {form_type => "submit_button"},
      pause99_delete_files_FILE => {form_type => "check_box"},
    }
  },

  # User/Permissions

  peek_perms => {
    x_mojo_to => "user-perms#peek",
    verb => "View Permissions",
    priv => "user",
    cat => "User/04Permissions/01",
    desc => "Whose uploads of what are being indexed on PAUSE",
    x_form => {
      pause99_peek_perms_by => {form_type => "select_field"},
      pause99_peek_perms_query => {form_type => "text_field"},
      pause99_peek_perms_sub => {form_type => "submit_button"},
    },
  },
  share_perms => {
    x_mojo_to => "user-perms#share",
    verb => "Change Permissions",
    priv => "user",
    cat => "User/04Permissions/02",
    desc => "Enable other users to upload a module for any of your namespaces, manage your own permissions.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      lsw => {form_type => "hidden_field"},
      # pause99_edit_mod_3 => {form_type => "select_field"},
      pause99_share_perms_pr_m => {form_type => "select_field"},
      weaksubmit_pause99_share_perms_movepr => {form_type => "submit_button"},
      weaksubmit_pause99_share_perms_remopr => {form_type => "submit_button"},
      pause99_share_perms_makeco_m => {form_type => "select_field"},
      weaksubmit_pause99_share_perms_makeco => {form_type => "submit_button"},
      weaksubmit_pause99_share_perms_remocos => {form_type => "submit_button"},
      pause99_share_perms_remome_m => {form_type => "select_field"},
      weaksubmit_pause99_share_perms_remome => {form_type => "submit_button"},
    },
    x_form_movepr => {
      pause99_share_perms_pr_m => {form_type => "select_field"},
      pause99_share_perms_movepr_a => {form_type => "text_field"},
      SUBMIT_pause99_share_perms_movepr => {form_type => "submit_button"},
    },
    x_form_remopr => {
      pause99_share_perms_pr_m => {form_type => "select_field"},
      SUBMIT_pause99_share_perms_remopr => {form_type => "select_field"},
    },
    x_form_makeco => {
      pause99_share_perms_makeco_m => {form_type => "select_field"},
      pause99_share_perms_makeco_a => {form_type => "text_field"},
      SUBMIT_pause99_share_perms_makeco => {form_type => "submit_button"},
    },
    x_form_remocos => {
      pause99_share_perms_remocos_tuples => {form_type => "select_field"},
      SUBMIT_pause99_share_perms_remocos => {form_type => "submit_button"},
    },
    x_form_remome => {
      pause99_share_perms_remome_m => {form_type => "select_field"},
      SUBMIT_pause99_share_perms_remome => {form_type => "submit_button"},
    },
  },

  # User/Util

  tail_logfile => {
    x_mojo_to => "user#tail_logfile",
    verb => "Tail Daemon Logfile",
    priv => "user",
    cat => "User/05Utils/06",
    x_form => {
      pause99_tail_logfile_1 => {form_type => "select_field"}, # how many lines to tail
      pause99_tail_logfile_sub => {form_type => "submit_button"},
    }
  },
  reindex => {
    x_mojo_to => "user#reindex",
    verb => "Force Reindexing",
    priv => "user",
    cat => "User/05Utils/02",
    desc => "Tell the indexer to index a file again (e.g. after a change in the perms table)",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      SUBMIT_pause99_reindex_delete => {form_type => "submit_button"},
      pause99_reindex_FILE => {form_type => "check_box"},
    },
  },
  reset_version => {
    x_mojo_to => "user#reset_version",
    verb => "Reset Version",
    priv => "user",
    cat => "User/05Utils/02",
    desc => "Overrule the record of the current version number of a module that the indexer uses and set it to 'undef'",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      SUBMIT_pause99_reset_version_forget => {form_type => "submit_button"},
      pause99_reset_version_PKG => {form_type => "check_box"},
    },
  },

  # User/Account

  change_passwd => {
    x_mojo_to => "user#change_passwd",
    verb => "Change Password",
    priv => "user",
    cat => "User/06Account/02",
    desc => "Change your password any time you want.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      ABRA => {form_type => "hidden_field"},
      pause99_change_passwd_pw1 => {form_type => "password_field"},
      pause99_change_passwd_pw2 => {form_type => "password_field"},
      pause99_change_passwd_sub => {form_type => "submit_button"},
    },
  },
  edit_cred => {
    x_mojo_to => "user-cred#edit",
    verb => "Edit Account Info",
    priv => "user",
    cat => "User/06Account/01",
    desc => "Edit your user name, your email addresses (both public and secret one), change the URL of your homepage.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      pause99_edit_cred_fullname => {form_type => "text_field"},
      pause99_edit_cred_asciiname => {form_type => "text_field"},
      pause99_edit_cred_email => {form_type => "text_field"},
      pause99_edit_cred_secretemail => {form_type => "text_field"},
      pause99_edit_cred_homepage => {form_type => "text_field"},
      pause99_edit_cred_cpan_mail_alias => {form_type => "radio_button"},
      pause99_edit_cred_ustatus => {form_type => "check_box"}, # to delete
      pause99_edit_cred_sub => {form_type => "submit_button"},
    },
  },
  pause_logout => {
    x_mojo_to => "user#pause_logout",
    verb => "About Logging Out",
    priv => "user",
    cat => "User/06Account/04",
  },

  # ADMIN+mlrep+modlistmaint

  select_ml_action => {
    x_mojo_to => "mlrepr#select_ml_action",
    verb => "Select Mailinglist/Action",
    priv => "mlrepr",
    cat => "09root/02",
    desc => "Representatives of mailing lists have their special menu here.",
    x_form => {
      HIDDENNAME => {form_type => "select_field"},
      ACTIONREQ => {form_type => "select_field"},
      pause99_select_ml_action_sub => {form_type => "submit_button"},
    },
  },
  show_ml_repr => {
    x_mojo_to => "mlrepr#show_ml_repr",
    verb => "Show Mailinglist Reps",
    priv => "mlrepr",
    cat => "09root/04",
    desc => "Admins and the representatives themselves can lookup who is elected to be representative of a mailing list.",
  },

  add_user => {
    x_mojo_to => "admin-user#add",
    verb => "Add a User or Mailinglist",
    priv => "admin",
    cat => "01usr/01add",
    desc => "Admins can add users or mailinglists.",
    x_form => {
      SUBMIT_pause99_add_user_Soundex => {form_type => "submit_button"},
      SUBMIT_pause99_add_user_Metaphone => {form_type => "submit_button"},
      SUBMIT_pause99_add_user_Definitely => {form_type => "submit_button"},
      pause99_add_user_userid => {form_type => "text_field"},
      pause99_add_user_fullname => {form_type => "text_field"},
      pause99_add_user_email => {form_type => "text_field"},
      pause99_add_user_homepage => {form_type => "text_field"},
      pause99_add_user_subscribe => {form_type => "text_field"},
      pause99_add_user_memo => {form_type => "text_area"},
    },
  },
  manage_id_requests => {
    x_mojo_to => "admin-manage_id#manage",
    verb => "Manage a registration request (alpha)",
    priv => "admin",
    cat => "01usr/01rej",
    desc => "show/reject open registration requests",
  },
  edit_ml => {
    x_mojo_to => "admin#edit_ml",
    verb => "Edit a Mailinglist",
    priv => "admin",
    cat => "01usr/02",
    desc => "Admins and mailing list representatives can change the name, address and description of a mailing list.",
    x_form => {
      HIDDENNAME => {form_type => "hidden_field"},
      pause99_edit_ml_3 => {form_type => "select_field"}, # mailing lists
      pause99_edit_ml_2 => {form_type => "submit_button"}, # select ml
      pause99_edit_ml_maillistname => {form_type => "text_field"},
      pause99_edit_ml_address => {form_type => "text_field"},
      pause99_edit_ml_subscribe => {form_type => "text_area"},
      pause99_edit_ml_4 => {form_type => "submit_button"}, # update
    },
  },
  email_for_admin => {
    x_mojo_to => "admin#email_for_admin",
    verb => "Look up the forward email address",
    priv => "admin",
    cat => "01usr/01look",
    desc => "Admins can look where email should go",
  },
  select_user => {
    x_mojo_to => "admin#select_user",
    verb => "Select User/Action",
    priv => "admin",
    cat => "01usr/03",
    desc => "Admins can access PAUSE as-if they were somebody else. Here they select a user/action pair.",
    x_form => {
      HIDDENNAME => {form_type => "select_field"},
      ACTIONREQ => {form_type => "select_field"},
      pause99_select_user_sub => {form_type => "submit_button"},
    },
  },
);

our @AllowAdminTakeover = qw(
  add_uri
  change_passwd
  delete_files
  edit_cred
  edit_ml
  edit_uris
  reindex
  reset_version
  share_perms
);

our @AllowMlreprTakeover = qw(
  edit_ml
  reset_version
  share_perms
);

sub allow_admin_takeover { @AllowAdminTakeover }
sub allow_mlrepr_takeover { @AllowMlreprTakeover }

sub action_names_for {
  my ($self, $priv) = @_;
  grep {$Actions{$_}{priv} eq $priv} keys %Actions;
}

sub action {
  my ($self, $name) = @_;
  $name && exists $Actions{$name} ? $Actions{$name} : {};
}

sub has_action {
  my ($self, $name) = @_;
  exists $Actions{$name} ? 1 : 0;
}

sub action_map_to_verb {
  my ($self, @actions) = @_;
  my %action_map;
  for my $action (@actions) {
    next unless exists $Actions{$action};
    my $verb = $Actions{$action}{verb} or next;
    $action_map{$action} = $verb;
  }
  \%action_map;
}

sub sort_allowed_group_actions {
  my ($self, $group, $names) = @_;
  map {$Actions{$_}{name} = $_; $Actions{$_}}
  sort {$Actions{$a}{cat} cmp $Actions{$b}{cat}}
  grep {$Actions{$_}{priv} eq $group}
  @{$names || []};
}

our %GroupLabel = (
  public => "Public",
  user => "User",
  mlrepr => "Mailinglists",
  admin => "Admin",
);

our @PublicGroups = qw/public/;
our @AllGroups = qw/public user mlrepr admin/;
our @ExtraGroups = qw/mlrepr admin/;

sub public_groups { @PublicGroups }
sub extra_groups { @ExtraGroups }
sub all_groups { @AllGroups }

sub group_label {
  my ($self, $group) = @_;
  exists $GroupLabel{$group} ? $GroupLabel{$group} : Carp::confess "no label for $group";
}

our $Valid_Userid = qr/^[A-Z]{3,9}$/;

sub valid_userid { $Valid_Userid }

sub mailto_admins { join(",", @{$PAUSE::Config->{ADMINS}}) }

1;

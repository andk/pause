package Email::Sender::Transport::KeepDeliveries;
use Moo;
extends 'Email::Sender::Transport::Wrapper';

# Wrap whatever transport that the user wants to really use, and provide a
# passthrough interface to Email::Sender::Transport::Test, which will also
# be given each message to 'send'.
#
# Usage:
#
#   $ENV{EMAIL_SENDER_TRANSPORT} = 'KeepDeliveries';
#
#   $ENV{EMAIL_SENDER_TRANSPORT_transport_class} = 'Maildir';
#   $ENV{EMAIL_SENDER_TRANSPORT_transport_arg_dir} = 'some-mail-dir';
#   ... other args as necessary

use Email::Sender::Transport::Test;

has 'test' => (
  is      => 'ro',
  isa     => sub { ref $_[0] eq 'Email::Sender::Transport::Test' },
  default => sub { Email::Sender::Transport::Test->new() },
  handles => [ qw(
    delivery_count
    deliveries
    shift_deliveries
    clear_deliveries
  ) ],
);

around send_email => sub {
  my ($orig, $self, $email, $env, @rest) = @_;

  $self->$orig($email, $env, @rest);

  $self->test->send_email($email, $env, @rest);
};

no Moo;
1;

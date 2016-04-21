package Email::Sender::Transport::KeepDeliveries;
use Moo;
extends 'Email::Sender::Transport::Wrapper';

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

has 'transport_class' => (
  is       => 'ro',
  required => 1,
  init_arg => 'transport',
);

around send_email => sub {
  my ($orig, $self, $email, $env, @rest) = @_;

  $self->$orig($email, $env, @rest);

  $self->test->send_email($email, $env, @rest);
};

no Moo;
1;

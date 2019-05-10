package Plack::App::GraphQL;

use Plack::Util;
use Plack::Request;
use GraphQL::Execution;
use Moo;

extends 'Plack::Component';

our $VERSION = '0.001';

has schema => (
  is => 'ro',
  required => 1,
  coerce => sub {
    my $schema_proto = shift;
    return ref($schema_proto) ?
      $schema_proto :
      Plack::Util::load_class("GraphQL::Schema")
       ->from_doc($schema_proto); 
  }
);

has path => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_PATH',
);

  our $DEFAULT_PATH = '/';
  sub DEFAULT_PATH { $DEFAULT_PATH }

has context_class => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_CONTEXT_CLASS',
  coerce => sub { Plack::Util::load_class($_[0]) },
);

  our $DEFAULT_CONTEXT_CLASS = 'Plack::App::GraphQL::Context';
  sub DEFAULT_CONTEXT_CLASS { $DEFAULT_CONTEXT_CLASS }

has ui_template_class => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_UI_TEMPLATE_CLASS',
  coerce => sub { Plack::Util::load_class(shift) },
);

  our $DEFAULT_UI_TEMPLATE_CLASS = 'Plack::App::GraphQL::UITemplate';
  sub DEFAULT_UI_TEMPLATE_CLASS { $DEFAULT_UI_TEMPLATE_CLASS }

has ui_template => (
  is => 'ro',
  required => 1,
  builder => '_build_ui_template',
  lazy => 1,
);

  sub _build_ui_template {
    my $self = shift;
    $self->ui_template_class->new(json_encoder => $self->json_encoder);
  }

has root_value => (
  is => 'ro',
  required => 1,
  lazy => 1,
  builder => '_build_root_value',
);

  sub _build_root_value { return shift }

has ui => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_UI',
);

  our $DEFAULT_UI = 0;
  sub DEFAULT_UI { $DEFAULT_UI }

has resolver => (
  is => 'ro',
  required => 0,
  predicate => 'has_resolver',
);

has json_encoder => (
  is => 'ro',
  required => 1,
  handles => {
    json_encode => 'encode',
    json_decode => 'decode',
  },
  default => sub {
    Plack::Util::load_class('JSON::MaybeXS')
      ->new
      ->utf8
      ->allow_nonref;
  }
);

sub build_context {
  my ($self, $req) = @_;
  my $context_class = $self->context_class;
  return $context_class->new(
    request => $req, 
    app => $self
  );
}

sub matches_path {
  my ($self, $req) = @_;
  return $req->env->{PATH_INFO} eq $self->path ? 1:0;
}

sub allow_graphql_ui {
  my ($self, $req) = @_;

  return 1  if $self->ui
            and (($req->env->{HTTP_ACCEPT}||'') =~ /^text\/html\b/)
            and (!defined($req->body_parameters->{'raw'}));
  return 0;
}

sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  if($self->matches_path($req)) {
    if($self->allow_graphql_ui($req)) {
      warn "Returning UI";
      return $self->respond_graphql_ui($req);
    } else {
      warn "Doing real GraphQL";
      return $self->respond_graphql($req);
    }
  } else {
    return $self->respond_404;
  }
}

sub respond_graphql_ui {
  my ($self, $req) = @_;
  my $body = $self->ui_template->process($req);
  return $self->graphql_ui_psgi($body)
}

sub graphql_ui_psgi {
  my ($self, $body) = @_;
  my $cl = Plack::Util::content_length([$body]);
  return [
      200,
      [
        'Content-Type'   => 'text/html',
        'Content-Length' => $cl,
      ],
      [$body],
  ];
}

sub respond_graphql {
  my ($self, $req) = @_;
  my $results = $self->prepare_results($req);
  return $self->graphql_psgi($results);
}

sub prepare_results {
  my ($self, $req) = @_;
  my $root_value = $self->prepare_root_value($req);
  my $resolver = $self->prepare_resolver($req);
  my $context = $self->prepare_context($req);
  my $json_body = $self->prepare_body($req);

  return my $results = GraphQL::Execution::execute(
    $self->schema,
    $json_body->{query},
    $root_value,
    $context,
    $json_body->{variables},
    $json_body->{operationName},
    $resolver,
  );
}

sub prepare_root_value {
  my ($self, $req) = @_;
  return my $root_value = $req->env->{'plack.graphql.root_value'} ||= $self->root_value;
}

sub prepare_resolver {
  my ($self, $req) = @_;
  return my $resolver = $req->env->{'plack.graphql.resolver'} ||= $self->resolver;
}

sub prepare_context {
  my ($self, $req) = @_;
  return my $context = $req->env->{'plack.graphql.context'} ||= $self->build_context($req);
}

sub prepare_body {
  my ($self, $req) = @_;
  my $json_body = eval {
    $self->json_decode($req->raw_body());
  } || do {
    $self->respond_400;
  };
  return $json_body;
}

sub graphql_psgi {
  my ($self, $results) = @_;
  my $body = [ $self->json_encode($results) ];
  my $cl = Plack::Util::content_length($body);
  return [
      200,
      [
        'Content-Type'   => 'application/json',
        'Content-Length' => $cl,
      ],
      $body,
  ];
}

sub respond_404 {
  return [
    404,
    ['Content-Type' => 'text/plain', 'Content-Length' => 9], 
    ['Not Found']
  ];
}

sub respond_400 {
  return [
    400,
    ['Content-Type' => 'text/plain', 'Content-Length' => 11], 
    ['Bad Request']
  ];
}

1;

=head1 NAME
 
Plack::App::File - Serve static files from root directory
 
=head1 SYNOPSIS
 
    use Plack::App::GraphQL;

    my $schema = q|
      type Query {
        hello: String
      }
    |;

    my %root_value = (
      hello => sub {
        return 'Hello World!'
      }
    );

    my $app = Plack::App::GraphQL
      ->new(schema => $schema, root_value => \%root_value)
      ->to_app;

Or mount under a given URL:

    use Plack::Builder;
    use Plack::App::GraphQL;

    # $schema and %root_value as above

    my $app = Plack::App::GraphQL
      ->new(schema => $schema, root_value => \%root_value)
      ->to_app;

    builder {
      mount "/graphql" => $app;
    };

You can also use the 'path' configuration option to set a root path to match.
(See documentation below).

=head1 DESCRIPTION
 
Serve GraphQL with Plack.

    TODO

    -- examples
    -- make sure people know how to override per request root value if they 
        really need that.

=head1 CONFIGURATION
 
=over 4
 
=item root
 
Document root directory. Defaults to C<.> (current directory)
  
=back

=head2 METHODS
 
=head1 AUTHOR
 
John Napiorkowski

=head1 SEE ALSO
 
L<GraphQL> L<Plack>
 
=cut

package Plack::App::GraphQL;

use Plack::Util;
use Plack::Request;
use GraphQL::Execution;
use Safe::Isa;
use Moo;

extends 'Plack::Component';

our $VERSION = '0.001';

has convert => (
  is => 'ro',
  isa => sub { ref($_[0]) ? 1:0 },
  predicate => 'has_convert',
  coerce => sub {
    if(ref($_[0]) eq 'ARRAY') {
      my ($class_proto, @args) = @{$_[0]};
      return normalize_convert_class($class_proto)->to_graphql(@args);
    } else {
      return $_[0]; # assume its a hashref already.
    }
  },
);

  sub normalize_convert_class {
    my $class_proto = shift;
    my $class = $class_proto =~m/^\+(.+)$/ ?
      $1 :
      "GraphQL::Plugin::Convert::$class_proto";
    return Plack::Util::load_class($class);
  }

has schema => (
  is => 'ro',
  lazy => 1,
  required => 1,
  builder => '_build_schema',
  coerce => sub {
    my $schema_proto = shift;
    return ref($schema_proto) ?
      $schema_proto :
      coerce_schema($schema_proto);
  }
);

  sub coerce_schema {
    return Plack::Util::load_class("GraphQL::Schema")
       ->from_doc(shift); 
  }

  sub _build_schema {
    my $self = shift;
    return $self->has_convert ? 
      $self->convert->{schema} :
      undef;
  }

has endpoint => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_ENDPOINT',
);

  our $DEFAULT_ENDPOINT = '/';
  sub DEFAULT_ENDPOINT { $DEFAULT_ENDPOINT }

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

  sub _build_root_value {
    my $self = shift;
    return $self->has_convert ? 
      $self->convert->{root_value} :
      undef;
  }

has graphiql => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_GRAPHIQL',
);

  our $DEFAULT_GRAPHIQL = 0;
  sub DEFAULT_GRAPHIQL { $DEFAULT_GRAPHIQL }

has resolver => (
  is => 'ro',
  required => 0,
  lazy => 1,
  builder => '_build_resolver',
);

  sub _build_resolver {
    my $self = shift;
    return $self->has_convert ? 
      $self->convert->{resolver} :
      undef;
  }

has promise_code => (
  is => 'ro',
  required => 0,
  lazy => 1,
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

has handler => (
  is => 'ro',
  required => 1,
  builder => '_build_handler',
);

  sub _build_handler {
    return sub {
      my ($self, $execute, $schema, $json_body, $root_value, $context, $resolver, $promise_code) = @_;
      return my $results = $execute->(
        $schema,
        $json_body->{query},
        $root_value,
        $context,
        $json_body->{variables},
        $json_body->{operationName},
        $resolver,
        $promise_code,
      );
    };
  }

has exceptions_class => (
  is => 'ro',
  required => 1,
  builder => 'DEFAULT_EXCEPTIONS_CLASS',
  coerce => sub { Plack::Util::load_class(shift) },
);

  our $DEFAULT_EXCEPTIONS_CLASS = 'Plack::App::GraphQL::Exceptions';
  sub DEFAULT_EXCEPTIONS_CLASS { $DEFAULT_EXCEPTIONS_CLASS }

has exceptions => (
  is => 'ro',
  required => 1,
  lazy => 1,
  handles => [qw(respond_415 respond_404 respond_400)],
  builder => '_build_exceptions',
);

  sub _build_exceptions {
    my $self = shift;
    return $self->exceptions_class->new(psgi_app=>$self);
  } 

sub matches_endpoint {
  my ($self, $req) = @_;
  return $req->env->{PATH_INFO} eq $self->endpoint ? 1:0;
}

sub accepts_graphiql {
  my ($self, $req) = @_;
  return 1  if $self->graphiql
            and (($req->env->{HTTP_ACCEPT}||'') =~ /^text\/html\b/)
            and (!defined($req->body_parameters->{'raw'}));
  return 0;
}

sub accepts_graphql {
  my ($self, $req) = @_;
  return 1 if  (($req->env->{HTTP_ACCEPT}||'') =~ /^application\/json\b/);
  return 0;
}

sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  if($self->matches_endpoint($req)) {
    if($self->accepts_graphiql($req)) {
      return $self->respond_graphiql($req);
    } elsif($self->accepts_graphql($req)) {
      return $self->respond_graphql($req);
    } else {
      return $self->respond_415($req);
    }
  } else {
    return $self->respond_404($req);
  }
}

sub respond_graphiql {
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
  return sub {
    my $responder = shift;
    my $results = $self->prepare_results($req);
    my $psgi_streaming = sub {
      my $body = $self->json_encode(shift);
      my $cl = Plack::Util::content_length([$body]);
      my $writer = $responder->([
        200,
        [
          'Content-Type'   => 'application/json',
          'Content-Length' => $cl,
        ],
      ]);
      $writer->write($body);
      $writer->close;
    };

    if(ref($results)=~m/Future/) {
      $results->on_done(sub {
        $psgi_streaming->(shift);
      });
    } else {
      $psgi_streaming->($results);
    }
  };
}

sub prepare_results {
  my ($self, $req) = @_;
  
  my $schema = $self->prepare_schema($req);
  my $json_body = $self->prepare_body($req);
  my $root_value = $self->prepare_root_value($req);
  my $context = $self->prepare_context($req);
  my $resolver = $self->prepare_resolver($req);
  my $promise_code = $self->prepare_promise_code($req);
  my $handler = $self->prepare_handler($req);

  return my $results = $handler->(
    $self,
    sub { $self->execute(@_) },
    $schema,
    $json_body,
    $root_value,
    $context,
    $resolver,
    $promise_code,
  );
}

sub prepare_schema { 
  my ($self, $req) = @_;
  return my $schema = $req->env->{'plack.graphql.schema'} ||= $self->schema;
}

sub prepare_root_value {
  my ($self, $req) = @_;
  return my $root_value = $req->env->{'plack.graphql.root_value'} ||= $self->root_value;
}

sub prepare_resolver {
  my ($self, $req) = @_;
  return my $resolver = $req->env->{'plack.graphql.resolver'} ||= $self->resolver;
}

sub prepare_promise_code {
  my ($self, $req) = @_;
  return my $promise_code = $req->env->{'plack.graphql.promise_code'} ||= $self->promise_code;
}

sub prepare_context {
  my ($self, $req) = @_;
  return my $context = $req->env->{'plack.graphql.context'} ||= $self->build_context($req);
}

sub build_context {
  my ($self, $req) = @_;
  my $context_class = $self->context_class;
  return $context_class->new(
    request => $req, 
    app => $self
  );
}

sub prepare_body {
  my ($self, $req) = @_;
  my $json_body = eval {
    $self->json_decode($req->raw_body());
  } || do {
    $self->respond_400($req);
  };
  return $json_body;
}

sub prepare_handler {
  my ($self, $req) = @_;
  return $req->env->{'plack.graphql.handler'} ||= $self->handler;
}

sub execute {
  my ($self, $schema, $query, $root_value, $context, $variables, $operation_name, $resolver, $promise_code) = @_;
  return my $results = GraphQL::Execution::execute(
    $schema,
    $query,
    $root_value,
    $context,
    $variables,
    $operation_name,
    $resolver,
    $promise_code,
  );
}

1;

=head1 NAME
 
Plack::App::GraphQL - Serve GraphQL from Plack / PSGI
 
=head1 SYNOPSIS
 
    use Plack::App::GraphQL;

    my $schema = q|
      type Query {
        hello: String
      }
    |;

    my %root_value = (
      hello => 'Hello World!',
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

You can also use the 'endpoint' configuration option to set a root path to match.
This is the most simple option if you application is not serving other endpoints
or applications (See documentation below).

=head1 DESCRIPTION
 
Serve GraphQL with Plack.

Please note this is an early access / no documentation release.  You should already
be familiar with L<GraphQL>.  There's some examples in C</examples> but no real test
cases.  If you are not confortable using this based on reading the source code and
can't accept the possibility that the underlying code might change (although I expect
the configuration options are pretty set now) then you shouldn't use this. I recommend
looking at official plugins for Dancer and Mojolicious: L<Dancer2::Plugin::GraphQL>,
L<Mojolicious::Plugin::GraphQL>.

This currently doesnt support an asychronous response.  Patchs and discussion welcomed!

=head1 CONFIGURATION
 
=over 4
 
=item schema
 
The L<GraphQL::Schema>
  
=back

=head2 METHODS
 
=head1 AUTHOR
 
John Napiorkowski

=head1 SEE ALSO
 
L<GraphQL> L<Plack>
 
=cut

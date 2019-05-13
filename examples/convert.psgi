use Plack::App::GraphQL;

return my $app = Plack::App::GraphQL
  ->new(
      path => '/graphql',
      convert => ['Test'],
      ui => 1 )
  ->to_app;

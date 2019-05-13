use Plack::App::GraphQL;

my $schema = q|
  type Query {
    hello: String
  }
|;

my %root_value = (
  hello =>  'Hello World!',
);

return my $app = Plack::App::GraphQL
  ->new(
      path => '/graphql',
      schema => $schema, 
      root_value => \%root_value, 
      ui => 1 )
  ->to_app;

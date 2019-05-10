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

return my $app = Plack::App::GraphQL
  ->new(
      schema => $schema, 
      root_value => \%root_value, 
      ui=>1,
      path=>'/graphql')
  ->to_app;

use Plack::App::GraphQL;
use Future;

my $schema = q|
  type Query {
    hello: String
  }
|;

my %root_value = (
  hello => sub {
    my ($args, $context, $info) = @_;
    return Future->done('world!!')
  }
);

return my $app = Plack::App::GraphQL
  ->new(
      schema => $schema, 
      root_value => \%root_value, 
      graphiql=>1,
      endpoint=>'/graphql')
  ->to_app;

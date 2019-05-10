use Test::Most;
use Plack::App::GraphQL;

ok my $schema = q|
  type Query {
    hello: String
  }
|;

ok my %root_value = (
  hello => sub {
    return 'Hello World!'
  }
);

ok my $app = Plack::App::GraphQL
  ->new(
      schema => $schema, 
      root_value => \%root_value)
  ->to_app;

done_testing;

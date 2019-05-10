package Plack::App::GraphQL::Context;

use Moo;

has ['request', 'app'] => (is=>'ro', required=>1);

sub req { shift->request }

1;

=head1 NAME
 
Plack::App::GraphQL::Context - The Default Context

=head1 SYNOPSIS
 
    TBD

=head1 DESCRIPTION
 
    TBD
 
=head1 AUTHOR
 
John Napiorkowski

=head1 SEE ALSO
 
L<Plack::App::GraphQL>
 
=cut

package Syntax::Keyword::Forall;

use strict;
use warnings;

our $VERSION = '0.001';

require XSLoader;
XSLoader::load( __PACKAGE__, $VERSION );

=head1 NAME

C<Syntax::Keyword::Forall> - magical looping construct

=head1 SYNOPSIS

   use Syntax::Keyword::Forall;

   ...

   forall my ($x, $y, $z) (@data) {
       push @points, {x => $x, y => $y, z => $z};
   }

   ...

   forall my ($key, $value) (%hash) {
       if ($key eq '...') {
           print "$value \n";
       }
   }

=head1 DESCRIPTION

This module provides a new looping construct for perl, C<forall>, that lets
you bundle multiple values from a list easily.  Importantly this gives a good
alternative to using C<each> with a hash and it's pitfalls.

The design, parsing, and other semantics of this are all completely undecided.
Use of this module in production code as it currently stands will result in me
getting a plane ticket to your $WORK to denounce you as insane.

=head2 C<forall>

=cut

sub import
{
   my $class = shift;
   my $caller = caller;

   $class->import_into( $caller, @_ );
}

sub import_into
{
   my $class = shift;
   my ( $caller, @syms ) = @_;

   @syms or @syms = qw( forall );

   my %syms = map { $_ => 1 } @syms;
   $^H{"Syntax::Keyword::Forall/forall"}++ if delete $syms{async};

   croak "Unrecognised import symbols @{[ keys %syms ]}" if keys %syms;
}

=head1 SEE ALSO

  SEE TODO

=head1 TODO

=over 4

=item *

  Make it work

=item *

  Make it work with non-lexical loop variables

=item *

  Add a SEE ALSO section

=back

=head1 KNOWN BUGS

=head1 ACKNOWLEDGEMENTS

With thanks to C<mst>, C<Leonerd> and others from C<irc.perl.org/#perl> for the
idea and lots of help with the XS side of things.  Also for letting me "borrow"
code to help implement this module.

=head1 AUTHOR

Ryan Voots.

=cut

"0e0"
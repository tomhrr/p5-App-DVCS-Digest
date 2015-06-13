package App::DVCS::Digest::DVCS::Factory;

use strict;
use warnings;

use App::DVCS::Digest::DVCS::Git;
use App::DVCS::Digest::DVCS::Hg;

sub new
{
    my ($class, $name) = @_;

    my $pkg = 'App::DVCS::Digest::DVCS::'.(ucfirst (lc $name));
    return $pkg->new();
}

1;

__END__

=head1 NAME

App::DVCS::Digest::DVCS::Factory

=head1 DESCRIPTION

Factory class for L<App::DVCS::Digest::DVCS> implementations.

=head1 CONSTRUCTOR

=over 4

=item B<new>

Takes an implementation name (e.g. 'git', 'hg') as its single
argument.  Returns an instance of the specified implementation.

=back

=cut

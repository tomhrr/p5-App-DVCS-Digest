package App::SCM::Digest::Utils;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(system_ad system_ad_op);

sub _system_ad
{
    my ($cmd) = @_;

    my $res = system("$cmd");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }

    return 1;
}

sub system_ad
{
    my ($cmd) = @_;

    my $redirect =
        ($ENV{'APP_SCM_DIGEST_DEBUG'}
            ? ''
            : '>/dev/null');

    return _system_ad("$cmd $redirect 2>&1");
}

sub system_ad_op
{
    my ($cmd) = @_;

    return _system_ad("$cmd 2>&1");
}

1;

__END__

=head1 NAME

App::SCM::Digest::Utils

=head1 DESCRIPTION

Utility functions for use with L<App::SCM::Digest> modules.

=head1 PUBLIC FUNCTIONS

=over 4

=item B<system_ad>

Takes a system command as its single argument.  Executes that command,
suppressing C<stdout> and C<stderr>.  Dies if the command returns a
non-zero exit status, and returns a true value otherwise.  (The name
is short for 'system autodie'.)

=item B<system_ad_op>

As per C<system_ad>, except that C<stdout> and C<stderr> are merged,
and not suppressed.  (The name is short for 'system autodie output'.)

=back

=cut

package TestFunctions;

use warnings;
use strict;

use base qw(Exporter);
our @EXPORT_OK = qw(tf_system tf_system_np);

sub tf_system
{
    my ($cmd) = @_;

    my $res = system("$cmd >/dev/null 2>&1");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }
}

sub tf_system_np
{
    my ($cmd) = @_;

    my $res = system("$cmd 2>&1");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }
}

1;

package App::DVCS::Digest::DVCS::Hg;

use strict;
use warnings;

use autodie;

sub new
{
    my ($class) = @_;

    my $res = system("hg --version >/dev/null");
    if ($res != 0) {
        die "Unable to find hg executable.";
    }

    my $self = {};
    bless $self, $class;
    return $self;
}

sub open_repository
{
    my ($self, $path) = @_;

    chdir $path;

    return 1;
}

sub branches
{
    my ($self) = @_;

    my $current = $self->branch_name();
    my @data = `hg branches`;
    my @results;
    for my $d (@data) {
        chomp $d;
        my ($entry, $commit) = ($d =~ /^(\S+?)\s+(\S+)/);
        $self->checkout($entry);
        $commit = `hg log --limit 1 --template '{node}'`;
        chomp $commit;
        push @results, [ $entry => $commit ];
    }
    $self->checkout($current);

    return \@results;
}

sub branch_name
{
    my ($self) = @_;

    my $branch = `hg branch`;
    chomp $branch;

    return $branch;
}

sub checkout
{
    my ($self, $branch) = @_;

    system("hg checkout $branch >/dev/null 2>&1");

    return 1;
}

sub commits_from
{
    my ($self, $branch, $from) = @_;

    my @new_commits =
        map { chomp; $_ }
            `hg log -b $branch --template "{node}\n" -r $from:tip`;

    if (@new_commits and ($new_commits[0] eq $from)) {
        shift @new_commits;
    }

    return \@new_commits;
}

sub show
{
    my ($self, $id) = @_;

    my @data = `hg log --rev $id`;

    return \@data;
}

sub show_all
{
    my ($self, $id) = @_;

    my @data = `hg log --patch --rev $id`;

    return \@data;
}

1;

__END__

=head1 NAME

App::DVCS::Digest::DVCS::Git

=head1 DESCRIPTION

Git L<App::DVCS::Digest::DVCS> implementation.

=cut

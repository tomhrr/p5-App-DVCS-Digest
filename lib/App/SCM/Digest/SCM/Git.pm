package App::SCM::Digest::SCM::Git;

use strict;
use warnings;

use App::SCM::Digest::Utils qw(system_ad);

use autodie;

sub new
{
    my ($class) = @_;

    my $res = system("git --version >/dev/null");
    if ($res != 0) {
        die "Unable to find git executable.";
    }

    my $self = {};
    bless $self, $class;
    return $self;
}

sub clone
{
    my ($self, $url, $name) = @_;

    my $res = system_ad("git clone $url $name");

    return 1;
}

sub open_repository
{
    my ($self, $path) = @_;

    chdir $path;

    return 1;
}

sub pull
{
    my ($self) = @_;

    system_ad("git pull");

    return 1;
}

sub branches
{
    my ($self) = @_;

    my @branches =
        map  { s/^\s+.*\///; s/\s+$//; $_ }
        grep { !/ -> / }
        map  { chomp; $_ }
            `git branch -r`;

    my @results;
    my $current_branch = $self->branch_name();
    for my $branch (@branches) {
        $self->checkout($branch);
        $self->pull();
        my $commit = `git log -1 --format="%H" $branch`;
        chomp $commit;
        push @results, [ $branch => $commit ];
    }
    if ($current_branch ne 'HEAD') {
        $self->checkout($current_branch);
    }

    return \@results;
}

sub branch_name
{
    my ($self) = @_;

    # todo: This prints a warning if there are no branches; there is
    # probably a better way of dealing with this problem.
    my $branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`;
    chomp $branch;

    return $branch;
}

sub checkout
{
    my ($self, $branch) = @_;

    system_ad("git checkout $branch");

    return 1;
}

sub commits_from
{
    my ($self, $branch, $from) = @_;

    $self->checkout($branch);
    my @new_commits = map { chomp; $_ } `git rev-list $from..HEAD`;

    return \@new_commits;
}

sub show
{
    my ($self, $id) = @_;

    my @data = `git show -s $id`;

    return \@data;
}

sub show_all
{
    my ($self, $id) = @_;

    my @data = (`git show $id`);

    return \@data;
}

1;

__END__

=head1 NAME

App::SCM::Digest::SCM::Git

=head1 DESCRIPTION

Git L<App::SCM::Digest::SCM> implementation.

=cut

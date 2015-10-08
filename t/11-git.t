#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 10;

use App::SCM::Digest::SCM::Git;
use File::Temp qw(tempdir);

sub _system
{
    my ($cmd) = @_;

    my $res = system("$cmd >/dev/null 2>&1");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }
}

sub _system_np
{
    my ($cmd) = @_;

    my $res = system("$cmd");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }
}

SKIP: {
    my $git = eval { App::SCM::Digest::SCM::Git->new(); };
    if ($@) {
        skip 'Git not available', 9;
    }

    my $repo_dir = tempdir(CLEANUP => 1);
    chdir $repo_dir;
    _system("git init .");

    $git->open_repository($repo_dir);
    my @branches = @{$git->branches()};
    is_deeply(\@branches, [],
              'No branches found in repository');

    _system("git checkout -b new-branch");
    _system_np("echo 'asdf' > out");
    _system("git add out");
    _system("git commit -m 'out'");

    my $repo_holder = tempdir(CLEANUP => 1);
    chdir $repo_holder;
    my $git2 = App::SCM::Digest::SCM::Git->new();
    $git2->clone("file://".$repo_dir, "repo");
    $git2->open_repository("repo");

    @branches = @{$git2->branches()};
    my @branch_names = map { $_->[0] } @branches;
    is_deeply(\@branch_names, [qw(new-branch)],
              'New branch found in repository');

    is($git2->branch_name(), 'new-branch',
        'Current branch name is correct');

    _system("git checkout -b new-branch2");
    _system_np("echo 'asdf2' > out2");
    _system("git add out2");
    _system("git commit -m 'out2'");

    is($git2->branch_name(), 'new-branch2',
        'Current branch name is correct (switched)');

    $git2->checkout('new-branch');

    is($git2->branch_name(), 'new-branch',
        'Current branch name is correct (switched back)');

    @branches = sort { $a->[0] cmp $b->[0] } @{$git2->branches()};
    is_deeply($git2->commits_from($branches[0]->[0], $branches[0]->[1]),
              [],
              'No commits found since most recent commit');

    _system_np("echo 'asdf3' > out3");
    _system("git add out3");
    _system("git commit -m 'out3'");

    my @commits = @{$git2->commits_from($branches[0]->[0], $branches[0]->[1])};
    is(@commits, 1, 'Found one commit since original commit');
    @branches = sort { $a->[0] cmp $b->[0] } @{$git2->branches()};
    is($commits[0], $branches[0]->[1],
        'The found commit has the correct ID');

    my $info = join '', @{$git2->show($commits[0])};
    like($info, qr/out3/,
        'Log information contains log message');

    $info = join '', @{$git2->show_all($commits[0])};
    like($info, qr/\+.*asdf3/,
        'Diff contains changed text');

    chdir("/tmp");
}

1;

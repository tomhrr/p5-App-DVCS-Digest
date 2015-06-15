#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 9;

use App::DVCS::Digest::DVCS::Git;
use File::Temp qw(tempdir);

sub _system
{
    my ($cmd) = @_;

    my $res = system("$cmd >/dev/null 2>&1");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }
}

SKIP: {
    my $git = eval { App::DVCS::Digest::DVCS::Git->new(); };
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
    _system("echo 'asdf' > out");
    _system("git add out");
    _system("git commit -m 'out'");

    @branches = @{$git->branches()};
    my @branch_names = map { $_->[0] } @branches;
    is_deeply(\@branch_names, [qw(new-branch)],
              'New branch found in repository');

    is($git->branch_name(), 'new-branch',
        'Current branch name is correct');

    _system("git checkout -b new-branch2");
    _system("echo 'asdf2' > out2");
    _system("git add out2");
    _system("git commit -m 'out2'");

    is($git->branch_name(), 'new-branch2',
        'Current branch name is correct (switched)');

    $git->checkout('new-branch');

    is($git->branch_name(), 'new-branch',
        'Current branch name is correct (switched back)');

    @branches = sort { $a->[0] cmp $b->[0] } @{$git->branches()};
    is_deeply($git->commits_from($branches[0]->[0], $branches[0]->[1]),
              [],
              'No commits found since most recent commit');

    _system("echo 'asdf3' > out3");
    _system("git add out3");
    _system("git commit -m 'out3'");

    my @commits = @{$git->commits_from($branches[0]->[0], $branches[0]->[1])};
    is(@commits, 1, 'Found one commit since original commit');
    @branches = sort { $a->[0] cmp $b->[0] } @{$git->branches()};
    is($commits[0], $branches[0]->[1],
        'The found commit has the correct ID');

    my $info = join '', @{$git->show($commits[0])};
    like($info, qr/out3/,
        'Log information contains log message');

#    todo: how to display new files properly.
#    $info = join '', @{$git->show_all($commits[0])};
#    like($info, qr/\+.*asdf3/,
#        'Diff contains changed text');
}

1;

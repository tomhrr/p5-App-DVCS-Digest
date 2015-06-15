#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 2;

use App::DVCS::Digest;
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
    eval { App::DVCS::Digest::DVCS::Git->new(); };
    if ($@) {
        skip 'Git not available', 9;
    }

    my $repo_dir = tempdir(CLEANUP => 1);
    chdir $repo_dir;
    _system("git init .");
    _system("git checkout -b new-branch");
    _system("echo 'asdf' > out");
    _system("git add out");
    _system("git commit -m 'out'");
    _system("git checkout -b new-branch2");
    _system("echo 'asdf2' > out2");
    _system("git add out2");
    _system("git commit -m 'out2'");

    eval { *{'Email::Sender::Simple::send_email'} = sub { 1; }; };

    my $db_path = tempdir(CLEANUP => 1);

    my %config = (
        db_path => $db_path,
        headers => {
            from => 'Test User <test@example.org>',
            to   => 'Test User <test@example.org>',
        },
        repositories => [
            { name => 'test',
              path => $repo_dir,
              type => 'git' }
        ],
    );

    my $digest = eval { App::DVCS::Digest->new(\%config); };
    ok($digest, 'Got new digest object');
    diag $@ if $@;

    eval {
        $digest->update();
        $digest->send_email();
    };
    ok((not $@), 'Updated database and sent mail');
}

1;

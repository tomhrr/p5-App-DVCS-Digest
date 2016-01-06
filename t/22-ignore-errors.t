#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 4;

use App::SCM::Digest;
use App::SCM::Digest::Utils qw(system_ad system_ad_op);

use File::Temp qw(tempdir);
use IO::Capture::Stderr;

SKIP: {
    eval { App::SCM::Digest::SCM::Git->new(); };
    if ($@) {
        skip 'Git not available', 2;
    }

    my $db_path   = tempdir(CLEANUP => 1);
    my $repo_path = tempdir(CLEANUP => 1);

    my %config = (
        db_path => $db_path,
        repository_path => $repo_path,
        headers => {
            from => 'Test User <test@example.org>',
            to   => 'Test User <test@example.org>',
        },
        repositories => [
            { name => 'test',
              url  => 'invalid url',
              type => 'git' },
        ],
    );

    my $digest = eval { App::SCM::Digest->new(\%config); };
    ok($digest, 'Got new digest object');
    diag $@ if $@;

    eval { $digest->update(); };
    ok($@, 'Invalid repository causes failure, by default');

    $config{'ignore_errors'} = 1;
    my $c = IO::Capture::Stderr->new();
    $c->start();
    eval { $digest->update(); };
    $c->stop();
    ok((not $@), 'Invalid repository is ignored');
    diag $@ if $@;

    my @lines = $c->read();
    ok(@lines, 'Invalid repository caused standard error output');

    chdir('/tmp');
}

1;

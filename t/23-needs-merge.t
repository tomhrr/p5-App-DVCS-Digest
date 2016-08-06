#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 8;

use App::SCM::Digest;
use App::SCM::Digest::Utils qw(system_ad system_ad_op);

use File::Temp qw(tempdir);

use lib './t/lib';
use TestFunctions qw(initialise_git_repository);

SKIP: {
    eval { App::SCM::Digest::SCM::Git->new(); };
    if ($@) {
        skip 'Git not available', 41;
    }

    my $repo_dir = tempdir(CLEANUP => 1);
    chdir $repo_dir;
    initialise_git_repository();
    system_ad_op("echo 'asdf' > outm");
    system_ad("git add outm");
    system_ad("git commit -m 'outm'");
    system_ad("git checkout -b new-branch");
    system_ad_op("echo 'asdf' > out");
    system_ad("git add out");
    system_ad("git commit -m 'out'");
    system_ad("git checkout -b new-branch2/test");
    system_ad_op("echo 'asdf2' > out2");
    system_ad("git add out2");
    system_ad("git commit -m 'out2'");

    sleep(1);

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
              url  => "file://$repo_dir",
              type => 'git' },
        ],
    );

    my $digest = eval { App::SCM::Digest->new(\%config); };
    ok($digest, 'Got new digest object');
    diag $@ if $@;

    my $email;
    eval {
        $digest->update();
        $email = $digest->get_email();
    };
    ok((not $@), 'Updated database and attempted to generate email');
    diag $@ if $@;
    ok($email, 'Email generated for initial commit');
    my $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/asdf\s*$/m,
        'Email contains content from initial commit (git)');

    # Make a change to the local repository, without committing, and
    # ensure that it is ignored on later update.

    chdir("$repo_path");
    chdir("test");
    system_ad_op("echo 'local' > out3");
    system_ad("git add out3");
    system_ad("git commit -m 'out3 local'");

    chdir("$repo_dir");
    system_ad_op("echo 'remote' > out3");
    system_ad("git add out3");
    system_ad("git commit -m 'out3 remote'");
 
    eval {
        $digest->update();
        $email = $digest->get_email();
    };
    ok((not $@), 'Updated database and attempted to generate email');
    diag $@ if $@;
    ok($email, 'Email generated for subsequent commit');
    $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/remote\s*$/m,
        'Email contains content from remote repository');
    unlike($email_content, qr/local\s*$/m,
        'Email does not contain content from local repository');

    chdir('/tmp');
}

1;

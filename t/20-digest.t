#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 31;

use App::SCM::Digest;
use File::Temp qw(tempdir);
use lib './t/lib';
use TestFunctions qw(tf_system tf_system_np);

SKIP: {
    eval { App::SCM::Digest::SCM::Git->new(); };
    if ($@) {
        skip 'Git not available', 9;
    }

    my $repo_dir = tempdir(CLEANUP => 1);
    chdir $repo_dir;
    tf_system("git init .");
    tf_system("git checkout -b new-branch");
    tf_system_np("echo 'asdf' > out");
    tf_system("git add out");
    tf_system("git commit -m 'out'");
    tf_system("git checkout -b new-branch2");
    tf_system_np("echo 'asdf2' > out2");
    tf_system("git add out2");
    tf_system("git commit -m 'out2'");

    my $other_remote_dir = tempdir(CLEANUP => 1);
    chdir $other_remote_dir;
    tf_system("git clone file://$repo_dir ord");
    my $other_remote_repo = "$other_remote_dir/ord";
    chdir $other_remote_repo;
    tf_system("git checkout -b new-branch4");
    tf_system_np("echo 'asdf4' > out4");
    tf_system("git add out4");
    tf_system("git commit -m 'out4'");
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
              type => 'git' }
        ],
    );

    my $digest = eval { App::SCM::Digest->new(\%config); };
    ok($digest, 'Got new digest object');
    diag $@ if $@;

    eval { $digest->get_email() };
    ok($@, 'Died trying to get email pre-initialisation');
    like($@, qr/Unable to open repository 'test'/,
        'Got correct error message');

    eval { $digest->_update() };
    ok($@, 'Died trying to update pre-initialisation');
    like($@, qr/Unable to open repository 'test'/,
        'Got correct error message');

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
        'Email contains content from initial commit');

    eval {
        $digest->update();
        $email = $digest->get_email();
    };
    ok((not $@), 'Updated database and attempted to generate email (2)');
    diag $@ if $@;
    ok($email, 'Email generated for initial commit (2)');

    chdir $repo_dir;
    tf_system("git checkout new-branch");
    tf_system_np("echo 'asdf3' > out3");
    tf_system("git add out3");
    tf_system("git commit -m 'out3'");

    eval {
        $digest->update();
        $email = $digest->get_email();
    };
    ok((not $@), 'Updated database and generated email');
    diag $@ if $@;
    ok($email, 'Email generated');

    $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');

    sleep(1);
    my $from = POSIX::strftime('%FT%T', gmtime(time()));
    $email = undef;
    chdir $other_remote_repo;
    tf_system("git push -u origin new-branch4");

    eval {
        $digest->update();
        $email = $digest->get_email($from);
    };
    ok((not $@), "Updated database and generated email ('from' provided)");
    diag $@ if $@;
    ok($email, 'Email generated');

    $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/asdf4\s*$/m,
        'Email contains changed content');
    unlike($email_content, qr/asdf3\s*$/m,
        'Email does not contain previous changed content');

    $email = undef;
    eval {
        $email = $digest->get_email('0000-01-01T00:00:00');
    };
    ok((not $@), "Generated email for all commits (zero 'from' provided)");
    diag $@ if $@;
    ok($email, 'Email generated');

    $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    like($email_content, qr/asdf\s*$/m,
        'Email contains initialisation content');

    $email = undef;
    eval {
        $email = $digest->get_email(undef, '9999-01-01T00:00:00');
    };
    ok((not $@), 'Generated email for all commits (to provided)');
    diag $@ if $@;
    ok($email, 'Email generated');

    $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    like($email_content, qr/asdf\s*$/m,
        'Email contains initialisation content');

    $email = undef;
    eval {
        $email =
            $digest->get_email('0000-01-01T00:00:00', '9999-01-01T00:00:00')
    };
    ok((not $@), 'Generated email for all commits (both provided)');
    diag $@ if $@;
    ok($email, 'Email generated');

    $email_content = join "\n", map { $_->body_str() } $email->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    like($email_content, qr/asdf\s*$/m,
        'Email contains initialisation content');

    open my $fh, '>', $db_path."/test/new-branch2" or die $!;
    print $fh "";
    close $fh;

    eval {
        $digest->update();
        $digest->get_email();
    };
    ok($@, 'Unable to process when database corrupt');
    like($@, qr/Unable to find commit ID in database/,
        'Got correct error message');

    chdir('/tmp');
}

1;

#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 27;

use App::SCM::Digest;
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

    my $res = system("$cmd 2>&1");
    if ($res != 0) {
        die "Command ($cmd) failed: $res";
    }
}

SKIP: {
    eval { App::SCM::Digest::SCM::Git->new(); };
    if ($@) {
        skip 'Git not available', 9;
    }

    my $repo_dir = tempdir(CLEANUP => 1);
    chdir $repo_dir;
    _system("git init .");
    _system("git checkout -b new-branch");
    _system_np("echo 'asdf' > out");
    _system("git add out");
    _system("git commit -m 'out'");
    _system("git checkout -b new-branch2");
    _system_np("echo 'asdf2' > out2");
    _system("git add out2");
    _system("git commit -m 'out2'");

    my @emails;
    {
        no warnings;
        no strict 'refs';
        *{'App::SCM::Digest::sendmail'} = sub {
            push @emails, $_[0];
        };
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
              url  => "file://$repo_dir",
              type => 'git' }
        ],
    );

    my $digest = eval { App::SCM::Digest->new(\%config); };
    ok($digest, 'Got new digest object');
    diag $@ if $@;

    eval { $digest->send_email() };
    ok($@, 'Died trying to send email pre-initialisation');
    like($@, qr/Unable to open repository 'test'/,
        'Got correct error message');

    eval { $digest->_update() };
    ok($@, 'Died trying to update pre-initialisation');
    like($@, qr/Unable to open repository 'test'/,
        'Got correct error message');

    eval {
        $digest->update();
        $digest->send_email();
    };
    ok((not $@), 'Updated database and attempted to send mail');
    diag $@ if $@;
    is_deeply(\@emails, [],
              'No mail sent (no commits since initialisation)');

    eval {
        $digest->update();
        $digest->send_email();
    };
    ok((not $@), 'Updated database and attempted to send mail (2)');
    diag $@ if $@;
    is_deeply(\@emails, [],
              'No mail sent (no commits since initialisation) (2)');

    chdir $repo_dir;
    _system("git checkout new-branch");
    _system_np("echo 'asdf3' > out3");
    _system("git add out3");
    _system("git commit -m 'out3'");

    eval {
        $digest->update();
        $digest->send_email();
    };
    ok((not $@), 'Updated database and sent mail');
    diag $@ if $@;
    is(@emails, 1, 'Email sent');

    my $email_content = join "\n", map { $_->body_str() } $emails[0]->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    unlike($email_content, qr/asdf\s*$/m,
        'Email does not contain initialisation content');

    @emails = ();
    eval {
        $digest->send_email('0000-00-00T00:00:00');
    };
    ok((not $@), 'Sent email for all commits (from provided)');
    diag $@ if $@;
    is(@emails, 1, 'Email sent');

    $email_content = join "\n", map { $_->body_str() } $emails[0]->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    like($email_content, qr/asdf\s*$/m,
        'Email contains initialisation content');

    @emails = ();
    eval {
        $digest->send_email(undef, '9999-00-00T00:00:00');
    };
    ok((not $@), 'Sent email for all commits (to provided)');
    diag $@ if $@;
    is(@emails, 1, 'Email sent');

    $email_content = join "\n", map { $_->body_str() } $emails[0]->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    like($email_content, qr/asdf\s*$/m,
        'Email contains initialisation content');

    @emails = ();
    eval {
        $digest->send_email('0000-00-00T00:00:00', '9999-00-00T00:00:00');
    };
    ok((not $@), 'Sent email for all commits (both provided)');
    diag $@ if $@;
    is(@emails, 1, 'Email sent');

    $email_content = join "\n", map { $_->body_str() } $emails[0]->parts();
    like($email_content, qr/asdf3\s*$/m,
        'Email contains changed content');
    like($email_content, qr/asdf\s*$/m,
        'Email contains initialisation content');

    open my $fh, '>', $db_path."/test/new-branch2" or die $!;
    print $fh "";
    close $fh;

    eval {
        $digest->update();
        $digest->send_email();
    };
    ok($@, 'Unable to process when database corrupt');
    like($@, qr/Unable to find commit ID in database/,
        'Got correct error message');

    chdir('/tmp');
}

1;

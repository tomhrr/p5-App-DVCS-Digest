package App::SCM::Digest;

use strict;
use warnings;

use App::SCM::Digest::SCM::Factory;

use autodie;
use DateTime;
use DateTime::Format::Strptime;
use Getopt::Long;
use Email::MIME;
use File::Temp;
use List::Util qw(first);
use POSIX qw();

our $VERSION = 0.01;

sub new
{
    my ($class, $config) = @_;
    my $self = { config => $config };
    bless $self, $class;
    return $self;
}

sub _impl
{
    my ($name) = @_;

    return App::SCM::Digest::SCM::Factory->new($name);
}

sub _slurp
{
    my ($path) = @_;

    open my $fh, '<', $path;
    my @lines;
    while (my $line = <$fh>) {
        push @lines, $line;
    }
    return join '', @lines;
}

sub _init
{
    my ($self) = @_;

    my $config = $self->{'config'};

    my $repo_path = $config->{'repository_path'};
    my $db_path = $config->{'db_path'};
    my $repositories = $config->{'repositories'};
    for my $repository (@{$repositories}) {
        chdir $repo_path or die $!;
        my ($name, $url, $type) = @{$repository}{qw(name url type)};
        my $impl = _impl($type);
        my $pre_existing = (-e $name);
        if (not $pre_existing) {
            mkdir "$db_path/$name";
            $impl->clone($url, $name);
        }
        $impl->open_repository($name);
        if ($pre_existing) {
            $impl->pull();
        }
        my @branches = @{$impl->branches()};
        for my $branch (@branches) {
            my ($branch_name, $commit) = @{$branch};
            my $branch_db_path = "$db_path/$name/$branch_name";
            if (-e $branch_db_path) {
                next;
            }
            open my $fh, '>', $branch_db_path;
            print $fh POSIX::strftime('%FT%T', gmtime(time())).".$commit\n";
            close $fh;
        }
    }

    return 1;
}

sub _update
{
    my ($self) = @_;

    my $config = $self->{'config'};

    my $repo_path = $config->{'repository_path'};
    my $db_path = $config->{'db_path'};
    my $repositories = $config->{'repositories'};
    my $current_branch;
    for my $repository (@{$repositories}) {
        chdir $repo_path or die $!;
        my ($name, $type) = @{$repository}{qw(name type)};
        my $impl = _impl($type);
        eval { $impl->open_repository($name); };
        if (my $error = $@) {
            die "Unable to open repository '$name': $error";
        }
        $impl->pull();
        my $current_branch = $impl->branch_name();
        my @branches = @{$impl->branches()};
        for my $branch (@branches) {
            my ($branch_name, undef) = @{$branch};
            my $branch_db_path = "$db_path/$name/$branch_name";
            if (not -e $branch_db_path) {
                die "Unable to find branch database ($branch_db_path).";
            }
            my ($last) = `tail -n 1 $branch_db_path` || '';
            chomp $last;
            my (undef, $commit) = split /\./, $last;
            if (not $commit) {
                die "Unable to find commit ID in database.";
            }
            my @new_commits = @{$impl->commits_from($branch_name, $commit)};
            my $time = POSIX::strftime('%FT%T', gmtime(time()));
            open my $fh, '>>', $branch_db_path;
            for my $new_commit (@new_commits) {
                print $fh "$time.$new_commit\n";
            }
            close $fh;
        }
        $impl->checkout($current_branch);
    }
}

sub update
{
    my ($self) = @_;

    $self->_init();
    $self->_update();

    return 1;
}

sub get_email
{
    my ($self, $from, $to) = @_;

    my $time = time();
    if (not defined $from and not defined $to) {
        $from = POSIX::strftime('%FT%T', gmtime($time - 86400));
        $to   = POSIX::strftime('%FT%T', gmtime($time));
    } elsif (not defined $from) {
        $from = POSIX::strftime('%FT%T', gmtime(0));
    } elsif (not defined $to) {
        $to = POSIX::strftime('%FT%T', gmtime($time));
    }

    my $ft = File::Temp->new();
    my @commit_data;
    my $config = $self->{'config'};

    my $tz = $config->{'timezone'} || 'UTC';
    my $strp =
        DateTime::Format::Strptime->new(pattern   => '%FT%T',
                                        time_zone => $tz);
    my $from_dt = $strp->parse_datetime($from);
    my $to_dt   = $strp->parse_datetime($to);
    if (not $from_dt) {
        die "Invalid 'from' time provided.";
    }
    if (not $to_dt) {
        die "Invalid 'to' time provided.";
    }
    $from_dt->set_time_zone('UTC');
    $to_dt->set_time_zone('UTC');
    $from = $from_dt->strftime('%FT%T');
    $to = $to_dt->strftime('%FT%T');

    my $repo_path = $config->{'repository_path'};
    my $db_path = $config->{'db_path'};
    my $repositories = $config->{'repositories'};
    for my $repository (@{$repositories}) {
        chdir $repo_path or die $!;
        my ($name, $type) = @{$repository}{qw(name type)};
        my $impl = _impl($type);
        eval { $impl->open_repository($name); };
        if (my $error = $@) {
            die "Unable to open repository '$name': $error";
        }
        my $current_branch = $impl->branch_name();

        my @branches = @{$impl->branches()};
        for my $branch (@branches) {
            my ($branch_name, $commit) = @{$branch};
            my $branch_db_path = "$db_path/$name/$branch_name";
            if (not -e $branch_db_path) {
                die "Unable to find branch database ($branch_db_path).";
            }
            open my $fh, '<', $branch_db_path;
            my @commits;
            while (my $entry = <$fh>) {
                chomp $entry;
                my ($time, $id) = split /\./, $entry;
                if (($time ge $from) and ($time le $to)) {
                    push @commits, [ $time, $id ];
                }
            }
            if (not @commits) {
                next;
            }
            print $ft "Repository: $name\n".
                      "Branch:     $branch_name\n\n";
            for my $commit (@commits) {
                my ($time, $id) = @{$commit};
                $time =~ s/T/ /;
                print $ft "Pulled at: $time\n";
                print $ft @{$impl->show($id)};
                print $ft "\n";
                my $att_ft = File::Temp->new();
                push @commit_data, [$name, $branch_name, $id, $att_ft];
                print $att_ft @{$impl->show_all($id)};
                $att_ft->flush();
            }
            print $ft "\n";
        }
        $impl->checkout($current_branch);
    }
    $ft->flush();

    if (not @commit_data) {
        return;
    }

    my $email = Email::MIME->create(
        header_str => [ %{$config->{'headers'} || {}} ],
        parts => [
            Email::MIME->create(
                attributes => {
                    content_type => 'text/plain',
                    disposition  => 'attachment',
                    charset      => 'UTF-8',
                    encoding     => 'quoted-printable',
                    filename     => 'log.txt',
                },
                body_str => _slurp($ft)
            ),
            map {
                my ($name, $entry, $id, $att_ft) = @{$_};
                my $email = Email::MIME->create(
                    attributes => {
                        content_type => 'text/plain',
                        disposition  => 'attachment',
                        charset      => 'UTF-8',
                        encoding     => 'quoted-printable',
                        filename     => "$name-$entry-$id.diff",
                    },
                    body_str => _slurp($att_ft)
                );
                $email
            } @commit_data
        ]
    );

    return $email;
}

1;

__END__

=head1 NAME

App::SCM::Digest

=head1 SYNOPSIS

    my $digest = App::SCM::Digest->new($config);
    $digest->update();
    $digest->send();

=head1 DESCRIPTION

Provides for sending source control management (SCM) repository commit
digest emails.  It does this based on the time when the commit was
pulled into the local repository, rather than when the commit was
committed, so that for a particular time period, the relevant set of
commits remains the same.

=head1 CONFIGURATION

The configuration hashref is like so:

    db_path         => "/path/to/db",
    repository_path => "/path/to/local/repositories",
    timezone        => "local",
    headers => {
        from => "From Address <from@example.org>",
        to   => "To Address <to@example.org>",
        ...
    },
    repositories => [
        { name => 'test',
          url  => 'http://example.org/path/to/repository',
          type => ['git'|'hg'] },
        { name => 'local-test',
          url  => 'file:///path/to/repository',
          type => ['git'|'hg'] },
        ...
    ]

The commit pull times for each of the repositories are stored in
C<db_path>, which must be a directory.

The local copies of the repositories are stored in C<repository_path>,
which must also be a directory.

C<repository_path>

The C<timezone> entry is optional, and defaults to 'UTC'.  It must be
a valid constructor value for L<DateTime::TimeZone>.  See
L<DateTime::TimeZone::Catalog> for a list of valid options.

L<App::SCM::Digest> clones local copies of the repositories into the
C<repository_path> directory.  These local copies should not be used
except by L<App::SCM::Digest>.

=head1 CONSTRUCTOR

=over 4

=item B<new>

Takes a configuration hashref, as per L<CONFIGURATION> as its single
argument.  Returns a new instance of L<App::SCM::Digest>.

=back

=head1 PUBLIC METHODS

=over 4

=item B<update>

Initialises and updates the local commit databases for each
repository-branch pair.  These databases record the time at which each
commit was received.

When initialising a particular database, only the latest commit is
stored.  Subsequent updates record all subsequent commits.

=item B<get_email>

Takes two date strings with the format '%Y-%m-%dT%H:%M:%S',
representing the lower and upper bounds of a time period, as its
arguments.  Returns an L<Email::MIME> object containing all of the
commits pulled within that time period, using the details from the
C<headers> entry in the configuration to construct the email.

=back

=head1 AUTHOR

Tom Harrison, C<< <tomhrr at cpan.org> >>

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2015 Tom Harrison

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

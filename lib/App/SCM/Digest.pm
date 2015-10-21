package App::SCM::Digest;

use strict;
use warnings;

use App::SCM::Digest::Utils qw(system_ad);
use App::SCM::Digest::SCM::Factory;

use autodie;
use DateTime;
use DateTime::Format::Strptime;
use Getopt::Long;
use Email::MIME;
use File::ReadBackwards;
use File::Temp;
use List::Util qw(first);
use POSIX qw();

use constant PATTERN => '%FT%T';
use constant EMAIL_ATTRIBUTES => (
    content_type => 'text/plain',
    disposition  => 'attachment',
    charset      => 'UTF-8',
    encoding     => 'quoted-printable',
);

our $VERSION = '0.02';

sub new
{
    my ($class, $config) = @_;
    my $self = { config => $config };
    bless $self, $class;
    return $self;
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

sub _strftime
{
    my ($time) = @_;

    return POSIX::strftime(PATTERN, gmtime($time));
}

sub _impl
{
    my ($name) = @_;

    return App::SCM::Digest::SCM::Factory->new($name);
}

sub _load_repository
{
    my ($repository) = @_;

    my ($name, $url, $type) = @{$repository}{qw(name url type)};
    my $impl = _impl($type);

    return ($name, $impl);
}

sub _load_and_open_repository
{
    my ($repository) = @_;

    my ($name, $impl) = _load_repository($repository);
    eval { $impl->open_repository($name) };
    if (my $error = $@) {
        die "Unable to open repository '$name': $error";
    }

    return ($name, $impl);
}

sub _init
{
    my ($self) = @_;

    my $config = $self->{'config'};

    my ($repo_path, $db_path, $repositories) =
        @{$config}{qw(repository_path db_path repositories)};

    for my $repository (@{$repositories}) {
        chdir $repo_path;
        my ($name, $impl) = _load_repository($repository);
        my $pre_existing = (-e $name);
        if (not $pre_existing) {
            mkdir "$db_path/$name";
            $impl->clone($repository->{'url'}, $name);
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
            my @branch_db_segments = split /\//, $branch_db_path;
            pop @branch_db_segments;
            my $branch_db_parent = join '/', @branch_db_segments;
            if (not -e $branch_db_parent) {
                system_ad("mkdir -p $branch_db_parent");
            }
            open my $fh, '>', $branch_db_path;
            print $fh _strftime(time()).".$commit\n";
            close $fh;
        }
    }

    return 1;
}

sub _update
{
    my ($self) = @_;

    my $config = $self->{'config'};

    my ($repo_path, $db_path, $repositories) =
        @{$config}{qw(repository_path db_path repositories)};

    for my $repository (@{$repositories}) {
        chdir $repo_path;
        my ($name, $impl) = _load_and_open_repository($repository);
        $impl->pull();
        my $current_branch = $impl->branch_name();
        my @branches = @{$impl->branches()};
        for my $branch (@branches) {
            my ($branch_name, undef) = @{$branch};
            my $branch_db_path = "$db_path/$name/$branch_name";
            if (not -e $branch_db_path) {
                die "Unable to find branch database ($branch_db_path).";
            }
            my $branch_db_file =
                File::ReadBackwards->new($branch_db_path)
                    or die "Unable to load branch database ".
                           "($branch_db_path).";
            my $last = $branch_db_file->readline() || '';
            chomp $last;
            my (undef, $commit) = split /\./, $last;
            if (not $commit) {
                die "Unable to find commit ID in database.";
            }
            my @new_commits = @{$impl->commits_from($branch_name, $commit)};
            my $time = _strftime(time());
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

sub _process_bounds
{
    my ($self, $from, $to) = @_;

    my $config = $self->{'config'};
    my $tz = $config->{'timezone'} || 'UTC';

    if (not defined $from and not defined $to) {
        $from = DateTime->now(time_zone => $tz)
                        ->subtract(days => 1)
                        ->strftime(PATTERN);
        $to   = DateTime->now(time_zone => $tz)
                        ->strftime(PATTERN);
    } elsif (not defined $from) {
        $from = '0000-01-01T00:00:00';
    } elsif (not defined $to) {
        $to   = '9999-12-31T23:59:59';
    }

    my $strp =
        DateTime::Format::Strptime->new(pattern   => PATTERN,
                                        time_zone => $tz);

    my ($from_dt, $to_dt) =
        map { $strp->parse_datetime($_) }
            ($from, $to);
    if (not $from_dt) {
        die "Invalid 'from' time provided.";
    }
    if (not $to_dt) {
        die "Invalid 'to' time provided.";
    }

    ($from, $to) =
        map { $_->set_time_zone('UTC');
              $_->strftime(PATTERN) }
            ($from_dt, $to_dt);

    return ($from, $to);
}

sub _utc_to_tz
{
    my ($self, $datetime) = @_;

    my $config = $self->{'config'};
    my $tz = $config->{'timezone'};
    if ((not $tz) or ($tz eq 'UTC')) {
        return $datetime;
    }

    my $strp =
        DateTime::Format::Strptime->new(pattern   => PATTERN,
                                        time_zone => 'UTC');

    my $dt = $strp->parse_datetime($datetime);
    $dt->set_time_zone($tz);
    return $dt->strftime(PATTERN);
}

sub _load_commits
{
    my ($branch_db_path, $from, $to) = @_;

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

    return @commits;
}

sub _make_email_mime
{
    my ($ft, $filename) = @_;

    return
        Email::MIME->create(
            attributes => { EMAIL_ATTRIBUTES,
                            filename => $filename },
            body_str   => _slurp($ft)
        );
}

sub get_email
{
    my ($self, $from, $to) = @_;

    my $config = $self->{'config'};

    my ($repo_path, $db_path, $repositories) =
        @{$config}{qw(repository_path db_path repositories)};

    ($from, $to) = $self->_process_bounds($from, $to);

    my $output_ft = File::Temp->new();
    my @commit_data;

    for my $repository (@{$repositories}) {
        chdir $repo_path;
        my ($name, $impl) = _load_and_open_repository($repository);
        my $current_branch = $impl->branch_name();

        my @branches = @{$impl->branches()};
        for my $branch (@branches) {
            my ($branch_name, $commit) = @{$branch};
            my $branch_db_path = "$db_path/$name/$branch_name";
            my @commits = _load_commits($branch_db_path, $from, $to);
            if (not @commits) {
                next;
            }
            print $output_ft "Repository: $name\n".
                             "Branch:     $branch_name\n\n";
            for my $commit (@commits) {
                my ($time, $id) = @{$commit};
                $time = $self->_utc_to_tz($time);
                $time =~ s/T/ /;
                print $output_ft "Pulled at: $time\n".
                                 (join '', @{$impl->show($id)}).
                                 "\n";

                my $att_ft = File::Temp->new();
                print $att_ft @{$impl->show_all($id)};
                $att_ft->flush();

                push @commit_data, [$name, $branch_name, $id, $att_ft];
            }
            print $output_ft "\n";
        }
        $impl->checkout($current_branch);
    }

    $output_ft->flush();

    if (not @commit_data) {
        return;
    }

    my $email = Email::MIME->create(
        header_str => [ %{$config->{'headers'} || {}} ],
        parts => [
            _make_email_mime($output_ft, 'log.txt'),
            map {
                my ($name, $branch_name, $id, $att_ft) = @{$_};
                _make_email_mime($att_ft,
                                 "$name-$branch_name-$id.diff"),
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

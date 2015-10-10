## App-SCM-Digest

Provides for sending source control management (SCM) repository commit
digest emails for a given period of time.  It does this based on the
time when the commit was pulled into the local repository, rather than
when the commit was committed.  This means that, with scheduled
digests, commits aren't omitted from the digest due to their having
originally occurred at some other time.

### Installation

To install this module, run the following commands:

```
perl Makefile.PL
make
make test
make install
```

Alternatively, run `cpanm .` from within the checkout directory.  This
will fetch and install module dependencies, if required.  See
https://cpanmin.us.

### Usage

```
scm-digest [ options ]
```

Options:

 * `--conf {config}`
    * Set configuration path (defaults to /etc/scm-digest.conf).
 * `--update`
    * Initialise and update local repositories.
 * `--get-email`
    * Print digest email to standard output.
 * `--send-email`
    * Send digest email.
 * `--from {time}`
    * Only include commits made after this time in digest.
 * `--to {time}`
    * Only include commits made before this time in digest.

Time format is `%Y-%m-%dT%H:%M:%S`, e.g. `2000-12-25T22:00:00`.

The configuration file must be in YAML format.  Options that may be
specified are as follows:

```
  db_path:          /path/to/db
  repository_path:  /path/to/local/repositories
  timezone:         UTC
  headers:
    from: From Address <from@example.org>
    to:   To Address <to@example.org>
    ...
  repositories:
    - name: test
      url: http://example.org/path/to/repository
      type: [git|hg]
    - name: local-test
      url: file:///path/to/repository
      type: [git|hg]
      ...
```

`db_path`, `repository_path`, and `repositories` are mandatory options.

`timezone` is optional, and defaults to 'UTC'.  See
`DateTime::TimeZone::Catalog` for a list of valid timezones.

### Copyright and licence

Copyright (C) 2015 Tom Harrison

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

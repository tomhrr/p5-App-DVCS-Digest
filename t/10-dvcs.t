#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 14;

use App::SCM::Digest::SCM;

{
    my @methods = qw(open_repository
                     branches
                     branch
                     checkout
                     commits_from
                     show
                     show_all);

    for my $method (@methods) {
        eval { App::SCM::Digest::SCM->$method() };
        ok($@, 'Died on calling unimplemented method');
        like($@, qr/Not implemented/, 'Got correct error message');
    }
}

1;

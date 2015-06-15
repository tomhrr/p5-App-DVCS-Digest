#!perl

use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 14;

use App::DVCS::Digest::DVCS;

{
    my @methods = qw(open_repository
                     branches
                     branch
                     checkout
                     commits_from
                     show
                     show_all);

    for my $method (@methods) {
        eval { App::DVCS::Digest::DVCS->$method() };
        ok($@, 'Died on calling unimplemented method');
        like($@, qr/Not implemented/, 'Got correct error message');
    }
}

1;

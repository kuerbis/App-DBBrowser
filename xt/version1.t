use 5.016;
use strict;
use warnings;
use Test::More;


use Test::Version qw( version_all_ok ), {
    is_strict   => 1,
    has_version => 1,
};

version_all_ok( 'bin', 'lib' );

done_testing;

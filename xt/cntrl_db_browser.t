use 5.010000;
use strict;
use warnings;
use File::Basename qw( basename );
use Test::More tests => 12;


for my $file ( 'bin/db-browser', 'lib/App/DBBrowser/Browser.pm', 'lib/App/DBBrowser/Opt.pm', 'lib/App/DBBrowser/DB.pm' ) {
    my $data_dumper = 0;
    my $warnings    = 0;
    my $use_lib     = 0;

    open my $fh, '<', $file or die $!;
    while ( my $line = <$fh> ) {
        if ( $line =~ /^\s*use\s+Data::Dumper/s ) {
            $data_dumper++;
        }
        if ( $line =~ /^\s*use\s+warnings\s+FATAL/s ) {
            $warnings++;
        }
        if ( $line =~ /^\s*use\s+lib\s/s ) {
            $use_lib++;
        }
    }
    close $fh;

    is( $data_dumper, 0, 'OK - Data::Dumper in "'   . basename( $file ) . '" disabled.' );
    is( $warnings,    0, 'OK - warnings FATAL in "' . basename( $file ) . '" disabled.' );
    is( $use_lib,     0, 'OK - no "use lib" in "'   . basename( $file ) . '"' );
}

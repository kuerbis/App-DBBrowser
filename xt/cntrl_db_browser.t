use 5.010000;
use strict;
use warnings;
use File::Basename qw( basename );
use Test::More;


for my $file (
    'bin/db-browser',
    'lib/App/DBBrowser.pm',
    'lib/App/DBBrowser/Auxil.pm',
    'lib/App/DBBrowser/CreateDropAttach.pm',
    'lib/App/DBBrowser/CreateDropAttach/CreateTable.pm',
    'lib/App/DBBrowser/CreateDropAttach/DropTable.pm',
    'lib/App/DBBrowser/CreateDropAttach/AttachDB.pm',
    'lib/App/DBBrowser/Credentials.pm',
    'lib/App/DBBrowser/DB.pm',
    'lib/App/DBBrowser/DB/MariaDB.pm',
    'lib/App/DBBrowser/DB/mysql.pm',
    'lib/App/DBBrowser/DB/Pg.pm',
    'lib/App/DBBrowser/DB/SQLite.pm',
    'lib/App/DBBrowser/GetContent.pm',
    'lib/App/DBBrowser/GetContent/Filter.pm',
    'lib/App/DBBrowser/GetContent/Filter/SearchAndReplace.pm',
    'lib/App/DBBrowser/GetContent/Parse.pm',
    'lib/App/DBBrowser/GetContent/Source.pm',
    'lib/App/DBBrowser/Join.pm',
    'lib/App/DBBrowser/Opt/DBGet.pm',
    'lib/App/DBBrowser/Opt/DBSet.pm',
    'lib/App/DBBrowser/Opt/Get.pm',
    'lib/App/DBBrowser/Opt/Set.pm',
    'lib/App/DBBrowser/Subqueries.pm',
    'lib/App/DBBrowser/Table.pm',
    'lib/App/DBBrowser/Table/Case.pm',
    'lib/App/DBBrowser/Table/CommitWriteSQL.pm',
    'lib/App/DBBrowser/Table/Extensions.pm',
    'lib/App/DBBrowser/Table/InsertUpdateDelete.pm',
    'lib/App/DBBrowser/Table/ScalarFunctions.pm',
    'lib/App/DBBrowser/Table/ScalarFunctions/SQL.pm',
    'lib/App/DBBrowser/Table/Substatements.pm',
    'lib/App/DBBrowser/Table/Substatements/Operators.pm',
    'lib/App/DBBrowser/Table/WindowFunctions.pm',
    'lib/App/DBBrowser/Union.pm' ) {

    my $data_dumper   = 0;
    my $warnings      = 0;
    my $use_lib       = 0;
    my $warn_to_fatal = 0;

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
        if ( $line =~ /__WARN__.+die/s ) {
            $warn_to_fatal++;
        }
    }
    close $fh;

    is( $data_dumper,   0, 'OK - Data::Dumper in "'         . basename( $file ) . '" disabled.' );
    is( $warnings,      0, 'OK - warnings FATAL in "'       . basename( $file ) . '" disabled.' );
    is( $use_lib,       0, 'OK - no "use lib" in "'         . basename( $file ) . '"' );
    is( $warn_to_fatal, 0, 'OK - no "warn to fatal" in "'   . basename( $file ) . '"' );
}


done_testing();

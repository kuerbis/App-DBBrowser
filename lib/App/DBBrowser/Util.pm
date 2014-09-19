package # hide from PAUSE
App::DBBrowser::Util;

use warnings;
use strict;
use 5.010000;

our $VERSION = '0.040_01';
use Exporter 'import';
our @EXPORT_OK = qw( print_error_message reset_sql );

use Term::Choose qw( choose );



sub print_error_message {
    my ( $info, $message ) = @_;
    utf8::decode( $message );
    print $message;
    choose(
        [ 'Press ENTER to continue' ],
        { %{$info->{lyt_stop}}, prompt => '' }
    );
}


sub reset_sql {
    my ( $sql ) = @_;
    $sql->{select_type} = '*';
    @{$sql->{print}}{ @{$sql->{strg_keys}} } = ( '' ) x  @{$sql->{strg_keys}};
    @{$sql->{quote}}{ @{$sql->{strg_keys}} } = ( '' ) x  @{$sql->{strg_keys}};
    @{$sql->{print}}{ @{$sql->{list_keys}} } = map{ [] } @{$sql->{list_keys}};
    @{$sql->{quote}}{ @{$sql->{list_keys}} } = map{ [] } @{$sql->{list_keys}};
    $sql->{pr_col_with_hidd_func} = [];
    delete $sql->{pr_backup_in_hidd};
}



1;

__END__

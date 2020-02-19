package # hide from PAUSE
App::DBBrowser::DropTable;

use warnings;
use strict;
use 5.010001;

use Term::Choose       qw();
use Term::Choose::Util qw( insert_sep );
use Term::TablePrint   qw();

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $data
    }, $class;
}


sub drop_table {
    my ( $sf ) = @_;
    return $sf->__choose_drop_item( 'table' );
}


sub drop_view {
    my ( $sf ) = @_;
    return $sf->__choose_drop_item( 'view' );
}


sub __choose_drop_item {
    my ( $sf, $type ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $sql = {};
    $ax->reset_sql( $sql );
    my $tables = [ grep { $sf->{d}{tables_info}{$_}[3] eq uc $type } @{$sf->{d}{user_tables}} ];
    my $prompt = $sf->{d}{db_string} . "\n" . 'Drop ' . $type;
    # Choose
    my $table = $tc->choose(
        [ undef, map { "- $_" } sort @$tables ],
        { %{$sf->{i}{lyt_v_clear}}, prompt => $prompt, undef => '  <=' }
    );
    if ( ! defined $table || ! length $table ) {
        return;
    }
    $table =~ s/\-\s//;
    $sql->{table} = $ax->quote_table( $sf->{d}{tables_info}{$table} );
    my $drop_ok = $sf->__drop( $sql, $type );
    return $drop_ok;
}


sub __drop {
    my ( $sf, $sql, $type ) = @_;
    if ( $type ne 'view' ) {
        $type = 'table';
    }
    my $stmt_type = 'Drop_' . $type;
    $sf->{i}{stmt_types} = [ $stmt_type ];
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    $ax->print_sql( $sql );
    # Choose
    my $ok = $tc->choose(
        [ undef, $sf->{i}{_confirm} . ' Stmt'],
        { %{$sf->{i}{lyt_v}} }
    );
    if ( ! $ok ) {
        return;
    }
    $ax->print_sql( $sql );
    my $prompt = '';
    if ( ! eval {
        my $sth = $sf->{d}{dbh}->prepare( "SELECT * FROM " . $sql->{table} );
        $sth->execute();
        my $col_names = $sth->{NAME}; # mysql: $sth->{NAME} before fetchall_arrayref
        my $all_arrayref = $sth->fetchall_arrayref;
        my $row_count = @$all_arrayref;
        unshift @$all_arrayref, $col_names;
        my $prompt_pt = sprintf "DROP %s %s     (on last look at the %s)\n", uc $type, $sql->{table}, $type;
        my $tp = Term::TablePrint->new( $sf->{o}{table} );
        $tp->print_table(
            $all_arrayref,
            { grid => 2, prompt => $prompt_pt, max_rows => 0, keep_header => 1,
              table_expand => $sf->{o}{G}{info_expand} }
        );
        $prompt = sprintf 'DROP %s %s  (%s %s)', uc $type, $sql->{table}, insert_sep( $row_count, $sf->{o}{G}{thsd_sep} ), $row_count == 1 ? 'row' : 'rows';
        1; }
    ) {
        $ax->print_error_message( $@ );
        $prompt = sprintf 'DROP %s %s', uc $type, $sql->{table};
    }
    $prompt .= "\n\nCONFIRM:";
    # Choose
    my $choice = $tc->choose(
        [ undef, 'YES' ],
        { prompt => $prompt, undef => 'NO', clear_screen => 1 }
    );
    $ax->print_sql( $sql );
    if ( defined $choice && $choice eq 'YES' ) {
        my $stmt = $ax->get_stmt( $sql, $stmt_type, 'prepare' );
        $sf->{d}{dbh}->do( $stmt ) or die "$stmt failed!";
        return 1;
    }
    return;
}





1;

__END__

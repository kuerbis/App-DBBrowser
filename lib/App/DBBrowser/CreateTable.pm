package # hide from PAUSE
App::DBBrowser::CreateTable;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_01';

use File::Basename qw( basename );
use List::Util     qw( none any );

use Term::Choose       qw();
use Term::Choose::Util qw( choose_a_number );
use Term::Form         qw();
use Term::TablePrint   qw( print_table );

use App::DBBrowser::DB;
use App::DBBrowser::Auxil;
use App::DBBrowser::Opt;
use App::DBBrowser::Table;
use App::DBBrowser::Table::Insert;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { i => $info, o => $opt }, $class;
}


sub delete_table {
    my ( $sf, $dbh, $data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $lyt_3 = Term::Choose->new( $sf->{i}{lyt_3} );
    my $sql = {};
    my $prompt = '"' . basename( $data->{db} ) . '"' . "\n" . 'Drop table';
    # Choose
    my $table = $lyt_3->choose(
        [ undef, map { "- $_" } @{$data->{user_tbls}} ],
        { undef => $sf->{i}{_back}, prompt => $prompt }
    );
    if ( ! defined $table || ! length $table ) {
        return;
    }
    $table =~ s/\-\s//;
    $sql->{table} = $ax->quote_table( $dbh, $data->{tables}{$table} );
    my $sth = $dbh->prepare( "SELECT * FROM " . $sql->{table} );
    $sth->execute();
    my $all_arrayref = $sth->fetchall_arrayref;
    my $row_count = @$all_arrayref;
    unshift @$all_arrayref, $sth->{NAME};
    my $prompt_pt = 'The table to be deleted  -  press enter to continue.';
    print_table( $all_arrayref, { %{$sf->{o}{table}}, prompt => $prompt_pt, max_rows => 0, table_expand => 0 } );
    $prompt = sprintf 'Drop table %s (%d %s)?', $sql->{table}, $row_count, $row_count == 1 ? 'row' : 'rows';
    $ax->print_sql( $sql, [ 'Drop_table' ] );
    # Choose
    my $choice = $lyt_3->choose(
        [ undef, 'YES' ],
        { prompt => $prompt, undef => 'NO', layout => 1, clear_screen => 0 }
    );
    if ( defined $choice && $choice eq 'YES' ) {
        $dbh->do( "DROP TABLE $sql->{table}" ) or die "DROP TABLE $sql->{table} failed!";
        return 1;
    }
    return;
}




sub __table_name {
    my ( $sf, $sql, $dbh, $sql_typeS, $data ) = @_;
    my $lyt_h = Term::Choose->new( $sf->{i}{lyt_stmt_h} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $table;
    my $c = 0;

    TABLENAME: while ( 1 ) {
        my $trs = Term::Form->new( 'tn' );
        my $info = 'DB: ' . basename( $data->{db} );
        # Readline
        $table = $trs->readline( 'Table name: ' );
        if ( ! length $table ) {
            return;
        }
        my $tmp_td = [ undef, $data->{schema}, $table ];
        $sql->{table} = $ax->quote_table( $dbh, $tmp_td );
        if ( none { $sql->{table} eq $ax->quote_table( $dbh, $data->{tables}{$_} ) } keys %{$data->{tables}} ) {
            return 1;
        }
        $ax->print_sql( $sql, $sql_typeS );
        my $prompt = "Table $sql->{table} already exists.";
        my $choice = $lyt_h->choose( [ undef, 'New name' ], { prompt => $prompt, undef => 'BACK', layout => 3, justify => 0 } );
        if ( ! defined $choice ) {
            return;
        }
    }
}

sub create_new_table {
    my ( $sf, $dbh, $data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $lyt_h = Term::Choose->new( $sf->{i}{lyt_stmt_h} );
    my $sql = {};
    $ax->reset_sql( $sql ); #
    my @cu_keys = ( qw/create_plain create_copy create_file settings/ );
    my %cu = ( create_plain  => '- plain',
               create_copy   => '- CopyPaste',
               create_file   => '- from File',
               settings      => '  Settings'
    );
    my $old_idx = 0;

    MENU: while ( 1 ) {
        my $sql_typeS = [ 'Create_table' ];
        my $choices = [ undef, @cu{@cu_keys} ];
        my $prompt = 'DB: "' . basename( $data->{db} ) . '"' . "\n" . 'Create table';
        # Choose
        my $idx = $lyt_h->choose(
            $choices,
            { %{$sf->{i}{lyt_stmt_v}}, index => 1, default => $old_idx,
            undef => '  ' . $sf->{i}{back}, prompt => $prompt, clear_screen => 1 }
        );
        if ( ! defined $idx || ! defined $choices->[$idx] ) {
            return;
        }
        my $custom = $choices->[$idx];
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 0;
                next MENU;
            }
            $old_idx = $idx;
        }
        if ( $custom eq $cu{settings} ) {
            my $obj_opt = App::DBBrowser::Opt->new( $sf->{i}, $sf->{o} );
            $obj_opt->config_insert();
            next MENU;
        }
        $ax->reset_sql( $sql ); #
        if ( $custom eq $cu{create_plain} ) {
            my $ok = $sf->__data_from_plain( $sql, $dbh, $sql_typeS, $data );
            next MENU if ! $ok;
        }
        elsif ( $custom eq $cu{create_copy} ) { # name
            push @$sql_typeS, 'Insert';
            my $tbl_in = App::DBBrowser::Table::Insert->new( $sf->{i}, $sf->{o} );
            my $ok = $tbl_in->from_copy_and_paste( $sql, $sql_typeS );
            if ( ! $ok ) {
                next MENU;
            }
        }
        elsif ( $custom eq $cu{create_file} ) { # name
            push @$sql_typeS, 'Insert';
            my $tbl_in = App::DBBrowser::Table::Insert->new( $sf->{i}, $sf->{o} );
            my $ok = $tbl_in->from_file( $sql, $sql_typeS );
            if ( ! $ok ) {
                next MENU;
            }
        }
        if ( $sql_typeS->[-1] eq 'Insert' ) {
            my $ok = $sf->__table_name( $sql, $dbh, $sql_typeS, $data );
            if ( ! $ok ) {
                next MENU;
            }
            # Columns
            my ( $first_row, $user_input ) = ( 'Use first row', 'User input' );
            $ax->print_sql( $sql, $sql_typeS );
            # Choose
            my $choice = $lyt_h->choose(
                [ undef, $first_row, $user_input ],
                { prompt => 'Column names:', undef => '<<', layout => 3, justify => 0 } #
            );
            if ( ! defined $choice ) {
                $sql->{insert_into_args} = [];
                next MENU;
            }
            if ( $choice eq $first_row ) {
                $sql->{insert_into_cols} = shift @{$sql->{insert_into_args}};  # not quoted
            }
            else {
                my $c = 0;
                $sql->{insert_into_cols} = [ map { 'c' . ++$c } @{$sql->{insert_into_args}->[0]} ]; # not quoted
            }
        }
        #### not col by col
        my $trs = Term::Form->new( 'cols' );
        $ax->print_sql( $sql, $sql_typeS );
        # Fill_form
        my $c = 0;
        my $form = $trs->fill_form(
            [ map { [ ++$c, defined $_ ? "$_" : '' ] } @{$sql->{insert_into_cols}} ],
            { prompt => 'Col names:', auto_up => 2, confirm => '  CONFIRM', back => '  BACK   ' }
        );
        if ( ! $form ) {
            $sql->{insert_into_cols} = [];
            next MENU;
        }
        #####
        my @cols = ( map { $_->[1] } @$form );
        die "Column with no name!" if any { ! length } @cols;
        $sql->{insert_into_cols} = $ax->quote_simple_many( $dbh, \@cols ); #
        # Datatypes
        $ax->print_sql( $sql, $sql_typeS );
        # Fill_form
        my $col_name_and_type = $trs->fill_form( # look
            [ map { [ $_, $sf->{o}{insert}{default_data_type} ] } @cols ],
            { prompt => 'Data types:', auto_up => 2, confirm => 'CONFIRM', back => 'BACK        ' }
        );
        if ( ! $col_name_and_type ) {
            next MENU;
        }
        my $qt_table = $sql->{table};
        for my $i ( 0 .. $#{$sql->{insert_into_cols}} ) {
            $sql->{create_table_cols}[$i] = $sql->{insert_into_cols}[$i] . ' ' . $col_name_and_type->[$i][1];
        }
        # Create table
        $ax->print_sql( $sql, $sql_typeS );
        # Choose
        my $create_table_ok = $lyt_h->choose(
            [ undef, 'YES' ],
            { prompt => "Create table $qt_table?", undef => 'NO', index => 1, clear_screen => 0 }
        );
        if ( ! defined $create_table_ok || ! $create_table_ok ) {
            next MENU;
        }
        my $ct = sprintf "CREATE TABLE $qt_table ( %s )", join( ', ', @{$sql->{create_table_cols}} );
        $dbh->do( $ct ) or die "$ct failed!";
        delete $sql->{create_table_cols};
        my $sth = $dbh->prepare( "SELECT * FROM $qt_table LIMIT 0" );
        $sth->execute() if $sf->{i}{driver} ne 'SQLite';
        if ( $sql_typeS->[-1] eq 'Insert' ) {
            $sql_typeS = [ $sql_typeS->[-1] ];
            my @columns = @{$sth->{NAME}};
            $sth->finish();
            $sql->{insert_into_cols} = $ax->quote_simple_many( $dbh, \@columns );
            my $obj_table = App::DBBrowser::Table->new( $sf->{i}, $sf->{o} );
            my $commit_ok = $obj_table->commit_sql( $sql, $sql_typeS, $dbh );
        }
        return 1;
    }
}


sub __data_from_plain {
    my ( $sf, $sql, $dbh, $sql_typeS, $data ) = @_;
    my $ok = $sf->__table_name( $sql, $dbh, $sql_typeS, $data );
    if ( ! $ok ) {
        return;
    }
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    $ax->print_sql( $sql, $sql_typeS );
    my $col_count = choose_a_number( 3, { small_on_top => 1, confirm => 'Confirm', back => 'Back',
                                            name => 'Number of columns:', clear_screen => 0 } );
    if ( ! $col_count ) {
        return;
    }
    $ax->print_sql( $sql, $sql_typeS );
    my $info = 'Enter column names:';
    my $trs = Term::Form->new();
    my $col_names = $trs->fill_form(
        [ map { [ $_, ] } 1 .. $col_count ],
        { info => $info, confirm => 'OK', back => '<<' }
    );
    if ( ! defined $col_names ) {
        return;
    }
    $sql->{insert_into_cols} = [ map { $_->[1] } @$col_names ]; # insert_into_cos # not quoted
    $ax->print_sql( $sql, $sql_typeS );
    return 1;
}




1;

__END__

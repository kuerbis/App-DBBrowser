package # hide from PAUSE
App::DBBrowser::CreateTable;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.016_02';

use List::Util qw( none any );

use Term::Choose     qw();
use Term::TablePrint qw( print_table );

use App::DBBrowser::DB;
use App::DBBrowser::Auxil;
use App::DBBrowser::Opt;
use App::DBBrowser::Table;
use App::DBBrowser::Table::Insert;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __delete_table {
    my ( $self, $sql, $dbh ) = @_;
    my $sql_type = 'Drop_table';
    my $schema = $sql->{print}{schema};
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my $lyt_3 = Term::Choose->new( $self->{info}{lyt_3} );
    my $backup_opt_metadata = $self->{metadata};
    $self->{metadata} = 0;
    my ( $user_tbl, $system_tbl ) = $obj_db->get_table_names( $dbh, $schema );
    $self->{metadata} = $backup_opt_metadata;
    # Choose
    my $table = $lyt_3->choose(
        [ undef, map { "* $_" } @$user_tbl ],
        { undef => $self->{info}{_back} }
    );
    return if ! length $table;
    $table =~ s/.\s//;
    my $qt_table = $dbh->quote_identifier( undef, $schema, $table );
    $sql->{print}{table} = $table;
    $sql->{quote}{table} = $qt_table;
    my $delete_ok = $self->__delete_table_confirm( $sql, $dbh, $table, $qt_table, $sql_type );
    if ( $delete_ok ) {
        $obj_db->drop_table( $dbh, $qt_table );
    }
    return 1;
}


sub __delete_table_confirm {
    my ( $self, $sql, $dbh, $table, $qt_table, $sql_type ) = @_;
    my $stmt = "SELECT * FROM " . $qt_table;
    $stmt .= " LIMIT " . $self->{opt}{table}{max_rows};
    my $sth = $dbh->prepare( $stmt );
    $sth->execute();
    my $col_names = $sth->{NAME};
    my $all_arrayref = $sth->fetchall_arrayref;
    my $table_rows = @$all_arrayref;
    unshift @$all_arrayref, $col_names;
    print_table( $all_arrayref, $self->{opt}{table} );
    my $auxil = App::DBBrowser::Auxil->new( $self->{info} );
    $auxil->__print_sql_statement( $sql, $sql_type );
    my $lyt_1 = Term::Choose->new( $self->{info}{lyt_1} );
    my $action = $sql_type eq 'Drop_table' ? 'DROP' : 'CREATE';
    my $prompt = sprintf "%s table \"%s\" (%d rows)?", $action, $table, $table_rows;
    # Choose
    my $choice = $lyt_1->choose(
        [ undef, 'YES' ],
        { prompt => $prompt, undef => 'NO', clear_screen => 0 }
    );
    if ( defined $choice && $choice eq 'YES' ) {
        return 1;
    }
    else {
        return;
    }
}


sub __create_new_table {
    my ( $self, $sql, $dbh ) = @_;
    my $auxil = App::DBBrowser::Auxil->new( $self->{info} );
    my $lyt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my $sql_type = 'Create_table';
    my $db_plugin = $self->{info}{db_plugin};
    my $schema = $sql->{print}{schema};
    my $old_idx = 1;
    $sql->{list_keys} = [ qw( chosen_cols insert_into_args ) ];
    $auxil->__reset_sql( $sql );
    $sql->{print}{table} = '...';
    print "\n";
    my $table;
    my $overwrite_ok;
    my $c = 0;

    TABLENAME: while ( 1 ) {
        $auxil->__print_sql_statement( $sql, $sql_type );
        my $trs = Term::ReadLine::Simple->new( 'tn' );
        # Readline
        $table = $trs->readline( 'Table name: ' );
        return if ! length $table;
        my $backup_opt_metadata = $self->{metadata};
        $self->{metadata} = 1;
        my ( $user_tables, $system_tables ) = $obj_db->get_table_names( $dbh, $schema );
        $self->{metadata} = $backup_opt_metadata;
        my $qt_table = $dbh->quote_identifier( undef, $schema, $table );
        if ( none { $_ eq $table } @$user_tables, @$system_tables ) {
            $sql->{print}{table} = $table;
            $sql->{quote}{table} = $qt_table;
            last TABLENAME;
        }
        $auxil->__print_sql_statement( $sql, $sql_type );
        my $prompt .= 'Overwrite existing table "' . $table . '"?';
        # Choose
        $overwrite_ok = $lyt_h->choose(
            [ undef, 'YES' ],
            { prompt => $prompt, undef => 'NO', layout => 1 }
        );
        if ( $overwrite_ok ) {
            $overwrite_ok = $self->__delete_table_confirm( $sql, $dbh, $table, $qt_table, $sql_type );
            if ( $overwrite_ok ) {
                $sql->{print}{table} = $table;
                $sql->{quote}{table} = $qt_table;
                last TABLENAME;
            }
        }
        else {
            $c++;
            return if $c > 3;
        }
    }

    MENU: while ( 1 ) {
        $auxil->__print_sql_statement( $sql, $sql_type );
        my ( $hidden, $commit, $create ) = ( 'Customize:', '  Confirm SQL', '  Form    SQL' );
        my $choices = [ $hidden, undef, $commit, $create ];
        # Choose
        my $idx = $lyt_h->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => '', index => 1, default => $old_idx,
            undef => $self->{info}{back} }
        );
        if ( ! defined $idx || ! defined $choices->[$idx] ) {
            return;
        }
        my $choice = $choices->[$idx];
        if ( $self->{opt}{G}{menu_sql_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 1;
                next MENU;
            }
            else {
                $old_idx = $idx;
            }
        }
        if ( $choice eq $hidden ) {
            my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt}, {} );
            $obj_opt->__config_insert();
            next MENU;
        }
        elsif ( $choice eq $create ) {
            my $tbl_in = App::DBBrowser::Table::Insert->new( $self->{info}, $self->{opt} );
            my $ok = $tbl_in->__get_insert_values( $sql, $sql_type );
            next MENU if ! $ok;

            # columns
            my $first_row_to_colnames = $lyt_h->choose(
                [ undef, 'YES' ],
                { prompt => 'Use first row as column names?', undef => 'NO' }
            );
            if ( $first_row_to_colnames ) {
                $sql->{print}{chosen_cols} = shift @{$sql->{quote}{insert_into_args}};
            }
            else {
                my $c = 1;
                $sql->{print}{chosen_cols} = [ map { 'col_' . $c++ } @{$sql->{quote}{insert_into_args}->[0]} ];
            }
            $auxil->__print_sql_statement( $sql, $sql_type );
            if ( any { ! defined } @{$sql->{print}{chosen_cols}} ) {
                die "Undefined column name!";
            }
            if ( any { ! length } @{$sql->{print}{chosen_cols}} ) {
                die "Empty string as column name!";
            }
            my $c = 1;
            my $tmp_cols = [ map { [ $c++, defined $_ ? "$_" : '' ] } @{$sql->{print}{chosen_cols}} ];
            my $add_primary_key;
            my $id_auto = "Id";
            my $auto_stmt = $obj_db->primary_key_auto();
            my $prompt = 'Add primary key?';
            if ( $auto_stmt ) {
                $add_primary_key = $lyt_h->choose(
                    [ undef, 'YES' ],
                    { prompt => $prompt, undef => 'NO' }
                );
                if ( $add_primary_key ) {
                    unshift @$tmp_cols, [ 0, $id_auto ];
                    $sql->{print}{primary_key_auto} = $id_auto;
                }
            }
            $auxil->__print_sql_statement( $sql, $sql_type );
            my $trs = Term::ReadLine::Simple->new( 'cols' );
            # Fill_form
            my $cols = $trs->fill_form(
                $tmp_cols,
                { prompt => 'Column names:',auto_up => 2, confirm => '- OK -', back => '- << -' }
            );
            if ( ! $cols ) {
                $auxil->__reset_sql( $sql );
                next MENU;
            }
            if ( ! length $cols->[1] ) {
                $add_primary_key = 0;
            }
            if ( $add_primary_key ) {
                ( $sql->{print}{primary_key_auto} ) = map { $_->[1] } shift @$cols;
            }
            $sql->{print}{chosen_cols} = [ grep { length } map { $_->[1] } @$cols ];

            # datatypes
            my $datatype = "TEXT";
            $auxil->__print_sql_statement( $sql, $sql_type );
            my $choices = [ map { [ $dbh->quote_identifier( $_ ), $datatype ] } @{$sql->{print}{chosen_cols}} ];
            if ( $add_primary_key ) {
                unshift @$choices, [ $id_auto, $auto_stmt ];
            }
            # Fill_form
            my $col_type = $trs->fill_form(
                $choices,
                { prompt => 'Column data-types:', auto_up => 2, confirm => '- OK -', back => '- << -' }
            );
            return if ! $col_type;

            # create table
            if ( $overwrite_ok ) {
                my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
                $obj_db->drop_table( $dbh, $sql->{quote}{table} );
            }
            $obj_db->create_table( $dbh, $table, $col_type );
            $sql->{print}{chosen_cols} = [];
            my $sth = $dbh->prepare( "SELECT * FROM " . $sql->{quote}{table} . " LIMIT 0" );
            $sth->execute();
            my @columns = @{$sth->{NAME}};
            if ( $col_type->[0][1] eq $auto_stmt  ) {
                $sql->{print}{primary_key_auto} = shift @columns;
            }
            $auxil->__print_sql_statement( $sql, $sql_type );
            for my $col ( @columns ) {
                push @{$sql->{print}{chosen_cols}}, $col;
                push @{$sql->{quote}{chosen_cols}}, $dbh->quote_identifier( $col );
            }
            $sql->{quote}{col_stmt} = "*";
            $sql->{from_stmt_type} = 'single';
        }
        elsif ( $choice eq $commit ) {
            my $obj_table = App::DBBrowser::Table->new( $self->{info}, $self->{opt} );
            my $sql_type = 'Insert';
            my $ok = $obj_table->__commit_sql( $sql, $sql_type, $dbh );
            delete $sql->{print}{primary_key_auto};
            if ( ! $ok ) {
                $auxil->__reset_sql( $sql );
                next MENU;
            }
            last MENU;
        }
    }
    return $table;
}


1;

__END__

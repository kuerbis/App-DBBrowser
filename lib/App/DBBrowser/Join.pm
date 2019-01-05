package # hide from PAUSE
App::DBBrowser::Join;

use warnings;
use strict;
use 5.008003;

use List::MoreUtils qw( any );

use Term::Choose           qw( choose );
use Term::Choose::LineFold qw( line_fold );
use Term::Choose::Util     qw( term_width );
use Term::TablePrint       qw( print_table );

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $data
    }, $class;
}


sub join_tables {
    my ( $sf ) = @_;
    my $stmt_v = Term::Choose->new( $sf->{i}{lyt_stmt_v} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $j = $sf->{d}; # ###
    my $tables = [ sort keys %{$j->{tables_info}} ];
    ( $j->{col_names}, $j->{col_types} ) = $ax->column_names_and_types( $tables );
    my $join = {};

    MASTER: while ( 1 ) {
        $join = {};
        $join->{stmt} = "SELECT * FROM";
        $join->{primary_keys}     = [];
        $join->{foreign_keys}     = [];
        $join->{idxs_used_tables} = [];
        my $info   = '  INFO';
        my @pre = ( undef );
        my $choices = [ @pre, map( "- $_", @$tables ), $info ];
        $sf->__print_join_statement( $join->{stmt} );
        # Choose
        my $idx = $stmt_v->choose(
            $choices,
            { prompt => 'Choose MASTER table:', index => 1 } # jt
        );
        if ( ! $idx ) {
            return;
        }
        if ( $idx == $#{$choices} ) {
            $sf->__get_join_info();
            $sf->__print_join_info();
            next MASTER;
        }
        $idx -= @pre;
        ( my $master = $tables->[$idx] ) =~ s/^-\s//;
        push @{$join->{idxs_used_tables}}, $idx;
        $join->{default_alias} = $sf->{d}{driver} eq 'Pg' ? 'a' : 'A';
        my $qt_master = $ax->quote_table( $j->{tables_info}{$master} );
        $join->{stmt} = "SELECT * FROM " . $qt_master;
        $sf->__print_join_statement( $join->{stmt} );
        my $alias = $ax->alias( 'join', $qt_master . ' AS: ', $join->{default_alias}, ' ' );
        push @{$join->{alias}{$master}}, $alias;
        $join->{stmt} .= " AS " . $ax->quote_col_qualified( [ $alias ] );
        my $backup_master = $ax->backup_href( $join ); ###

        JOIN: while ( 1 ) {
            my $backup_join = $ax->backup_href( $join );
            my $slave = $sf->__choose_slave_table( $join, $tables, $info );
            if ( ! defined $slave ) {
                next MASTER if @{$join->{idxs_used_tables}} == 1;
                $join = $backup_master;
                next JOIN;
            }
            elsif ( ! $slave ) {
                return if @{$join->{idxs_used_tables}} == 1;
                last JOIN;
            }
            my $qt_slave = $ax->quote_table( $j->{tables_info}{$slave} );
            $join->{stmt} .= " LEFT OUTER JOIN " . $qt_slave;
            $sf->__print_join_statement( $join->{stmt} );
            my $alias = $ax->alias( 'join', $qt_slave . ' AS: ', ++$join->{default_alias}, ' ' );
            push @{$join->{alias}{$slave}}, $alias;
            $join->{stmt} .= " AS " . $ax->quote_col_qualified( [ $alias ] );
            my $ok = $sf->__add_join_predicate( $j, $join, $tables, $slave, $alias );
            if ( ! $ok ) {
                $join = $backup_join;
                next JOIN;
            }
            push @{$join->{used_tables}}, $slave;
        }
        last MASTER;
    }

    my $qt_columns = [];
    for my $idx ( @{$join->{idxs_used_tables}} ) {
        my $table = $tables->[$idx];
        for my $alias ( @{$join->{alias}{$table}} ) {
            for my $col ( @{$j->{col_names}{$table}} ) {
                my $col_qt = $ax->quote_col_qualified( [ undef, $alias, $col ] );
                #if ( any { $_ eq $col_qt } @{$join->{foreign_keys}} ) {
                #    next;
                #}
                if ( any { $_ eq $col_qt } @$qt_columns ) {
                    next;
                }
                push @$qt_columns, $col_qt;
            }
        }
    }
    my ( $qt_table ) = $join->{stmt} =~ /^SELECT\s\*\sFROM\s(.*)\z/;
    return $qt_table, $qt_columns;
}


sub __choose_slave_table {
    my ( $sf, $join, $tables, $info ) = @_;
    my $stmt_v = Term::Choose->new( $sf->{i}{lyt_stmt_v} );
    my $idx;
    my @pre = ( undef, '  Enough TABLES' );

    SLAVE: while ( 1 ) {
        my @tmp;
        for my $idx ( 0 .. $#{$tables} ) {
            if ( any { $_ == $idx } @{$join->{idxs_used_tables}} ) {
                push @tmp, $tables->[$idx] . ' (used)';
            }
            else {
                push @tmp, $tables->[$idx];
            }
        }
        my $choices = [ @pre, map( "- $_", @tmp ), $info ];
        $sf->__print_join_statement( $join->{stmt} );
        # Choose
        $idx = $stmt_v->choose(
            $choices,
            { prompt => 'Add a SLAVE table:', index => 1, undef => $sf->{i}{_reset} }
        );
        if ( ! $idx ) {
            return;
        }
        elsif ( $idx == 1 ) {
            return 0;
        }
        elsif ( $idx == $#$choices ) {
            $sf->__get_join_info();
            $sf->__print_join_info();
            next SLAVE;
        }
        else {
            last SLAVE;
        }
    }
    $idx -= @pre;
    ( my $slave = $tables->[$idx] ) =~ s/^-\s//;
    push @{$join->{idxs_used_tables}}, $idx;
    return $slave;
}


sub __add_join_predicate {
    my ( $sf, $j, $join, $tables, $slave, $slave_alias ) = @_; #slave_alias
    my $stmt_v = Term::Choose->new( $sf->{i}{lyt_stmt_v} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my %avail_pk_cols;
    for my $idx ( @{$join->{idxs_used_tables}} ) {
        my $used_table = $tables->[$idx];
        for my $alias ( @{$join->{alias}{$used_table}} ) {
            #next if $used_table eq $slave && $alias eq $slave_alias;
            for my $col ( @{$j->{col_names}{$used_table}} ) {
                $avail_pk_cols{ $alias . '.' . $col } = $ax->quote_col_qualified( [undef, $alias, $col ] ); #
            }
        }
    }
    my %avail_fk_cols;
    for my $col ( @{$j->{col_names}{$slave}} ) {
        $avail_fk_cols{ $slave_alias . '.' . $col } = $ax->quote_col_qualified( [ $slave_alias, $col ] );
    }
    my $AND = '';
    $join->{stmt} .= " ON";
    my @backup_predicate;

    ON: while ( 1 ) {
        $sf->__print_join_statement( $join->{stmt} );
        my @pre = ( undef );
        push @pre, $sf->{i}{_continue} if $AND && @{$join->{primary_keys}} == @{$join->{foreign_keys}}; # confirm
        # Choose
        my $pk_col = $stmt_v->choose(
            [ @pre, map( "- $_", sort keys %avail_pk_cols ) ],
            { prompt => 'Choose PRIMARY KEY column:', index => 0, undef => $sf->{i}{_back} }
        );
        if ( ! defined $pk_col ) {
            if ( @backup_predicate ) {
                ( $join->{stmt}, $join->{primary_keys}, $join->{foreign_keys}, $AND ) = @{pop @backup_predicate};
                next ON;
            }
            return;
        }
        if ( $pk_col eq $sf->{i}{_continue} ) {
            if ( ! $AND ) {
                return;
            }
            return 1;
        }
        push @backup_predicate, [ $join->{stmt}, [ @{$join->{primary_keys}} ], [ @{$join->{foreign_keys}} ], $AND ];
        $pk_col =~ s/^-\s//;
        push @{$join->{primary_keys}}, $avail_pk_cols{$pk_col};
        $join->{stmt} .= $AND;
        $join->{stmt} .= ' ' . $avail_pk_cols{$pk_col};
        $sf->__print_join_statement( $join->{stmt} );
        # Choose
        my $fk_col = $stmt_v->choose(
            [ undef, map( "- $_", sort keys %avail_fk_cols ) ],
            { prompt => 'Choose FOREIGN KEY column:', index => 0, undef => $sf->{i}{_back} }
        );
        if ( ! defined $fk_col ) {
            ( $join->{stmt}, $join->{primary_keys}, $join->{foreign_keys}, $AND ) = @{pop @backup_predicate};
            next ON;
        }
        push @backup_predicate, [ $join->{stmt}, [ @{$join->{primary_keys}} ], [ @{$join->{foreign_keys}} ], $AND ];
        $fk_col =~ s/^-\s//;
        push @{$join->{foreign_keys}}, $avail_fk_cols{$fk_col};
        $join->{stmt} .= " = " . $avail_fk_cols{$fk_col};
        $AND = " AND";
    }
}


sub __print_join_statement {
    my ( $sf, $join_stmt_pr ) = @_;
    $join_stmt_pr =~ s/(?=\sLEFT\sOUTER\sJOIN)/\n\ /g; ##
    $join_stmt_pr .= "\n\n";
    print $sf->{i}{clear_screen};
    print line_fold( $join_stmt_pr, term_width() - 2, '', ' ' x $sf->{i}{stmt_init_tab} );
}


sub __print_join_info {
    my ( $sf ) = @_;
    my $pk = $sf->{d}{pk_info};
    my $fk = $sf->{d}{fk_info};
    my $aref = [ [ qw(PK_TABLE PK_COLUMN), ' ', qw(FK_TABLE FK_COLUMN) ] ];
    my $r = 1;
    for my $t ( sort keys %$pk ) {
        $aref->[$r][0] = $pk->{$t}{TABLE_NAME};
        $aref->[$r][1] = join( ', ', @{$pk->{$t}{COLUMN_NAME}} );
        if ( defined $fk->{$t}->{FKCOLUMN_NAME} && @{$fk->{$t}{FKCOLUMN_NAME}} ) {
            $aref->[$r][2] = 'ON';
            $aref->[$r][3] = $fk->{$t}{FKTABLE_NAME};
            $aref->[$r][4] = join( ', ', @{$fk->{$t}{FKCOLUMN_NAME}} );
        }
        else {
            $aref->[$r][2] = '';
            $aref->[$r][3] = '';
            $aref->[$r][4] = '';
        }
        $r++;
    }
    print_table( $aref, { keep_header => 0, tab_width => 3, grid => 1 } );
}


sub __get_join_info {
    my ( $sf ) = @_;
    return if $sf->{d}{pk_info};
    my $td = $sf->{d}{tables_info};
    my $tables = $sf->{d}{user_tables}; ###
    my $pk = {};
    for my $table ( @$tables ) {
        my $sth = $sf->{d}{dbh}->primary_key_info( @{$td->{$table}} );
        next if ! defined $sth;
        while ( my $ref = $sth->fetchrow_hashref() ) {
            next if ! defined $ref;
            #$pk->{$table}{TABLE_SCHEM} =        $ref->{TABLE_SCHEM};
            $pk->{$table}{TABLE_NAME}  =        $ref->{TABLE_NAME};
            push @{$pk->{$table}{COLUMN_NAME}}, $ref->{COLUMN_NAME};
            #push @{$pk->{$table}{KEY_SEQ}},     defined $ref->{KEY_SEQ} ? $ref->{KEY_SEQ} : $ref->{ORDINAL_POSITION};
        }
    }
    my $fk = {};
    for my $table ( @$tables ) {
        my $sth = $sf->{d}{dbh}->foreign_key_info( @{$td->{$table}}, undef, undef, undef );
        next if ! defined $sth;
        while ( my $ref = $sth->fetchrow_hashref() ) {
            next if ! defined $ref;
            #$fk->{$table}{FKTABLE_SCHEM} =        defined $ref->{FKTABLE_SCHEM} ? $ref->{FKTABLE_SCHEM} : $ref->{FK_TABLE_SCHEM};
            $fk->{$table}{FKTABLE_NAME}  =        defined $ref->{FKTABLE_NAME}  ? $ref->{FKTABLE_NAME}  : $ref->{FK_TABLE_NAME};
            push @{$fk->{$table}{FKCOLUMN_NAME}}, defined $ref->{FKCOLUMN_NAME} ? $ref->{FKCOLUMN_NAME} : $ref->{FK_COLUMN_NAME};
            #push @{$fk->{$table}{KEY_SEQ}},       defined $ref->{KEY_SEQ}       ? $ref->{KEY_SEQ}       : $ref->{ORDINAL_POSITION};
        }
    }
    $sf->{d}{pk_info} = $pk;
    $sf->{d}{fk_info} = $fk;
}




1;

__END__

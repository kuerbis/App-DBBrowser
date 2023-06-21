package # hide from PAUSE
App::DBBrowser::Table::Substatements;

use warnings;
use strict;
use 5.014;

use Term::Choose       qw();
use Term::Choose::Util qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Extensions;
use App::DBBrowser::Table::Substatements::Operators;


sub new {
    my ( $class, $info, $options, $d ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $d,
    };
    $sf->{i}{avail_aggr} = [ "AVG(X)", "COUNT(X)", "COUNT(*)", "MAX(X)", "MIN(X)", "SUM(X)" ];
    if    ( $info->{driver} =~ /^(?:SQLite|mysql|MariaDB)\z/ ) {
        push @{$sf->{i}{avail_aggr}}, "GROUP_CONCAT(X)";
    }
    elsif ( $info->{driver} eq 'Pg' ) {
        push @{$sf->{i}{avail_aggr}}, "STRING_AGG(X)";
    }
    elsif ( $info->{driver} eq 'Firebird' ) {
        push @{$sf->{i}{avail_aggr}}, "LIST(X)";
    }
    elsif ( $info->{driver} =~ /^(?:DB2|Oracle)\z/ ) {
        push @{$sf->{i}{avail_aggr}}, "LISTAGG(X)";
    }
    $sf->{i}{menu_addition} = '%%';
    bless $sf, $class;
}


sub select {
    my ( $sf, $sql ) = @_;
    my $clause = 'select';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $menu = [];
    my @pre = ( undef, $sf->{i}{ok} );
    if ( $sf->{o}{enable}{col_menu_addition} ) {
        push @pre, $sf->{i}{menu_addition};
    }
    if ( @{$sql->{group_by_cols}} || @{$sql->{aggr_cols}} ) {
        $menu = [ @pre, @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} ];
    }
    else {
        $menu = [ @pre, @{$sql->{cols}} ];
    }
    $sql->{selected_cols} = [];
    my @bu;

    COLUMNS: while ( 1 ) {
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my @idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, info => $info, meta_items => [ 0 .. $#pre - 1 ], no_spacebar => [ $#pre ],
              include_highlighted => 2, index => 1 }
        );
        $ax->print_sql_info( $info );
        if ( ! $idx[0] ) {
            if ( @bu ) {
                ( $sql->{selected_cols}, $sql->{alias} ) = @{pop @bu};
                next COLUMNS;
            }
            return;
        }
        push @bu, [ [ @{$sql->{selected_cols}} ], { %{$sql->{alias}} } ];
        if ( $menu->[$idx[0]] eq $sf->{i}{ok} ) {
            shift @idx;
            push @{$sql->{selected_cols}}, @{$menu}[@idx];
            if ( ! @{$sql->{selected_cols}} ) {
                return 0;
            }
            return 1;
        }
        elsif ( $menu->[$idx[0]] eq $sf->{i}{menu_addition} ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_col = $ext->complex_unit( $sql, $clause );
            if ( ! defined $complex_col ) {
                ( $sql->{selected_cols}, $sql->{alias} ) = @{pop @bu};
            }
            else {
                my $alias = $ax->alias( $sql, 'select_func_sq', $complex_col );
                if ( length $alias ) {
                    $sql->{alias}{$complex_col} = $ax->prepare_identifier( $alias );
                }
                push @{$sql->{selected_cols}}, $complex_col;
            }
        }
        else {
            push @{$sql->{selected_cols}}, @{$menu}[@idx];
        }
    }
}


sub distinct {
    my ( $sf, $sql ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef, $sf->{i}{ok} );
    $sql->{distinct_stmt} = '';

    DISTINCT: while ( 1 ) {
        my $menu = [ @pre, "ALL", "DISTINCT" ];
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my $select_distinct = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $select_distinct ) {
            if ( $sql->{distinct_stmt} ) {
                $sql->{distinct_stmt} = '';
                next DISTINCT;
            }
            return;
        }
        elsif ( $select_distinct eq $sf->{i}{ok} ) {
            if ( ! length $sql->{distinct_stmt} ) {
                return 0;
            }
            return 1;
        }
        $sql->{distinct_stmt} = ' ' . $select_distinct;
    }
}


sub aggregate {
    my ( $sf, $sql ) = @_;
    my $clause = 'aggregate';
    $sql->{aggr_cols} = [];
    $sql->{selected_cols} = [];

    AGGREGATE: while ( 1 ) {
        my $ret = $sf->__add_aggregate_substmt( $sql, $clause );
        if ( ! $ret ) {
            if ( @{$sql->{aggr_cols}} ) {
                my $aggr = pop @{$sql->{aggr_cols}};
                delete $sql->{alias}{$aggr} if exists $sql->{alias}{$aggr};
                next AGGREGATE;
            }
            return;
        }
        elsif ( $ret eq $sf->{i}{ok} ) {
            if ( ! @{$sql->{aggr_cols}} ) {
                return 0;
            }
            return 1;
        }
    }
}

sub __add_aggregate_substmt {
    my ( $sf, $sql, $clause ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my @pre = ( undef, $sf->{i}{ok} );
    my $GROUP_CONCAT;
    if ( defined $sf->{i}{avail_aggr}[6] ) {
        $GROUP_CONCAT = $sf->{i}{avail_aggr}[6] =~ s/\(\X\)\z//r;
    }
    else {
        $GROUP_CONCAT = '';
    }
    my $i = @{$sql->{aggr_cols}};
    my $info = $ax->get_sql_info( $sql );
    # Choose
    my $aggr = $tc->choose(
        [ @pre, @{$sf->{i}{avail_aggr}} ],
        { %{$sf->{i}{lyt_h}}, info => $info }
    );
    $ax->print_sql_info( $info );
    if ( ! defined $aggr ) {
        return;
    }
    elsif ( $aggr eq $sf->{i}{ok} ) {
        return $aggr;
    }
    if ( $aggr eq 'COUNT(*)' ) {
        $sql->{aggr_cols}[$i] = $aggr;
    }
    else {
        $aggr =~ s/\(\X\)\z//;
        $sql->{aggr_cols}[$i] = $aggr . "(";
        my $is_distinct;
        if ( $aggr =~ /^(?:COUNT|$GROUP_CONCAT)\z/ ) {
            my $info = $ax->get_sql_info( $sql );
            my ( $ALL, $DISTINCT ) = ( "ALL", "DISTINCT" );
            # Choose
            my $all_or_distinct = $tc->choose(
                [ undef, $ALL, $DISTINCT ],
                { %{$sf->{i}{lyt_h}}, info => $info }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $all_or_distinct ) {
                return;
            }
            if ( $all_or_distinct eq $DISTINCT ) {
                $sql->{aggr_cols}[$i] .= $DISTINCT . " ";
                $is_distinct = 1;
            }
        }
        my @pre = ( undef );
        if ( $sf->{o}{enable}{col_menu_addition} ) {
            push @pre, $sf->{i}{menu_addition};
        }
        my $qt_col;

        COLUMN: while ( 1 ) {
            my $info = $ax->get_sql_info( $sql );
            # Choose
            $qt_col = $tc->choose(
                [ @pre, @{$sql->{cols}} ],
                { %{$sf->{i}{lyt_h}}, info => $info }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $qt_col ) {
                return;
            }
            elsif ( $qt_col eq $sf->{i}{menu_addition} ) {
                my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
                my $complex_column = $ext->complex_unit( $sql, $clause );
                if ( ! defined $complex_column ) {
                    next COLUMN;
                }
                else {
                    $qt_col = $complex_column;
                }
            }
            last COLUMN;
        }
        if ( $aggr =~ /^$GROUP_CONCAT\z/ ) {
            if ( $sf->{i}{driver} eq 'Pg' ) {
                # Pg, STRING_AGG: separator mandatory
                $sql->{aggr_cols}[$i] .= "${qt_col}::text,',')";
            }
            elsif ( $sf->{i}{driver} =~ /^(?:DB2|Oracle)\z/ ) {
                # DB2, LISTAGG: no default separator
                $sql->{aggr_cols}[$i] .= "$qt_col,',')";
            }
            else {
                # https://sqlite.org/forum/info/221c2926f5e6f155
                # SQLite: GROUP_CONCAT with DISTINCT and custom seperator does not work
                $sql->{aggr_cols}[$i] .= "$qt_col)";
            }
            #my $sep = ',';
            #if ( $sf->{i}{driver} eq 'SQLite' ) {
            #    if ( $is_distinct ) {
            #        # https://sqlite.org/forum/info/221c2926f5e6f155
            #        # SQLite: GROUP_CONCAT with DISTINCT and custom seperator does not work
            #        # default separator is ','
            #        $sql->{aggr_cols}[$i] .= "$qt_col)";
            #    }
            #    else {
            #        $sql->{aggr_cols}[$i] .= "$qt_col,'$sep')";
            #    }
            #}
            #elsif ( $sf->{i}{driver} =~ /^(?:mysql|MariaDB)\z/ ) {
            #    $sql->{aggr_cols}[$i] .= "$qt_col ORDER BY $qt_col SEPARATOR '$sep')";
            #}
            #elsif ( $sf->{i}{driver} eq 'Pg' ) {
            #    # Pg, STRING_AGG:
            #    # separator mandatory
            #    # expects text type as argument
            #    # with DISTINCT the STRING_AGG col and the ORDER BY col must be identical
            #    $sql->{aggr_cols}[$i] .= "${qt_col}::text,'$sep' ORDER BY ${qt_col}::text)";
            #}
            #elsif ( $sf->{i}{driver} eq 'Firebird' ) {
            #    $sql->{aggr_cols}[$i] .= "$qt_col,'$sep')";
            #}
            #elsif ( $sf->{i}{driver} =~ /^(?:DB2|Oracle)\z/ ) {
            #    if ( $is_distinct ) {
            #        # DB2 codes: error code -214 - error caused by:
            #        # DISTINCT is specified in the SELECT clause, and a column name or sort-key-expression in the
            #        # ORDER BY clause cannot be matched exactly with a column name or expression in the select list.
            #        $sql->{aggr_cols}[$i] .= "$qt_col,'$sep')";
            #    }
            #    else {
            #        $sql->{aggr_cols}[$i] .= "$qt_col,'$sep') WITHIN GROUP (ORDER BY $qt_col)";
            #    }
            #}
            #else {
            #    return;
            #}
        }
        else {
            $sql->{aggr_cols}[$i] .= "$qt_col)";
        }
    }
    my $alias = $ax->alias( $sql, 'select_func_sq', $sql->{aggr_cols}[$i] );
    if ( length $alias ) {
        $sql->{alias}{$sql->{aggr_cols}[$i]} = $ax->prepare_identifier( $alias );
    }
    return 1;
}


sub set {
    my ( $sf, $sql ) = @_;
    my $clause = 'set';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $so = App::DBBrowser::Table::Substatements::Operators->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $col_sep = ' ';
    $sql->{set_args} = [];
    $sql->{set_stmt} = "SET";
    my @bu_col;
    my @pre = ( undef, $sf->{i}{ok} );

    COL: while ( 1 ) {
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my $quote_col = $tc->choose(
            [ @pre, @{$sql->{cols}} ],
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $quote_col ) {
            if ( @bu_col ) {
                ( $sql->{set_stmt}, $sql->{set_args}, $col_sep ) = @{pop @bu_col};
                next COL;
            }
            return;
        }
        if ( $quote_col eq $sf->{i}{ok} ) {
            if ( $col_sep eq ' ' ) {
                $sql->{set_stmt} = '';
            }
            if ( ! length $sql->{set_stmt} ) {
                return 0;
            }
            return 1;
        }
        push @bu_col, [ $sql->{set_stmt}, [@{$sql->{set_args}}], $col_sep ];
        $sql->{set_stmt} .= $col_sep . $quote_col;

        OPERATOR: while ( 1 ) {
            my $bu_op = [ $sql->{set_stmt}, [@{$sql->{set_args}}] ];
            my ( $op, $is_complex_value ) = $so->choose_and_add_operator( $sql, $clause, $quote_col );
            if ( ! defined $op ) {
                ( $sql->{set_stmt}, $sql->{set_args}, $col_sep ) = @{pop @bu_col};
                next COL;
            }

            VALUE: while ( 1 ) {
                my $ok = $so->read_and_add_value( $sql, $clause, $op, $is_complex_value );
                if ( ! $ok ) {
                    ( $sql->{set_stmt}, $sql->{set_args} ) = @$bu_op;
                    next OPERATOR;
                }
                last VALUE;
            }
            last OPERATOR;
        }
        $col_sep = ', ';
    }
}


sub where {
    my ( $sf, $sql ) = @_;
    my $clause = 'where';
    $sql->{where_args} = [];
    $sql->{where_stmt} = "WHERE";
    my $items = [ @{$sql->{cols}} ];
    $sf->__add_condition( $sql, $clause, $items );
}


sub group_by {
    my ( $sf, $sql ) = @_;
    my $clause = 'group_by';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    $sql->{group_by_stmt} = "GROUP BY";
    $sql->{group_by_cols} = [];
    $sql->{selected_cols} = [];
    my @pre = ( undef, $sf->{i}{ok} );
    if ( $sf->{o}{enable}{col_menu_addition} ) {
        push @pre, $sf->{i}{menu_addition};
    }
    my $menu = [ @pre, @{$sql->{cols}} ];

    GROUP_BY: while ( 1 ) {
        $sql->{group_by_stmt} = "GROUP BY " . join ', ', @{$sql->{group_by_cols}};
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my @idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, info => $info, meta_items => [ 0 .. $#pre - 1 ], no_spacebar => [ $#pre ],
              include_highlighted => 2, index => 1 }
        );
        $ax->print_sql_info( $info );
        if ( ! $idx[0] ) {
            if ( @{$sql->{group_by_cols}} ) {
                pop @{$sql->{group_by_cols}};
                next GROUP_BY;
            }
            $sql->{group_by_stmt} = "GROUP BY " . join ', ', @{$sql->{group_by_cols}};
            return;
        }
        elsif ( $menu->[$idx[0]] eq $sf->{i}{ok} ) {
            shift @idx;
            push @{$sql->{group_by_cols}}, @{$menu}[@idx];
            if ( ! @{$sql->{group_by_cols}} ) {
                $sql->{group_by_stmt} = '';
            }
            else {
                $sql->{group_by_stmt} = "GROUP BY " . join ', ', @{$sql->{group_by_cols}};
            }
            if ( ! length $sql->{group_by_stmt} ) {
                return 0;
            }
            return 1;
        }
        elsif ( $menu->[$idx[0]] eq $sf->{i}{menu_addition} ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_column = $ext->complex_unit( $sql, $clause );
            if ( defined $complex_column ) {
                push @{$sql->{group_by_cols}}, $complex_column;
            }
            next GROUP_BY;
        }
        push @{$sql->{group_by_cols}}, @{$menu}[@idx];
    }
}


sub having {
    my ( $sf, $sql ) = @_;
    my $clause = 'having';
    $sql->{having_args} = [];
    $sql->{having_stmt} = "HAVING";
    my $items = [ @{$sf->{i}{avail_aggr}}, map( '@' . $_, @{$sql->{aggr_cols}} ) ];
    $sf->__add_condition( $sql, $clause, $items );
}


sub order_by {
    my ( $sf, $sql ) = @_;
    my $clause = 'order_by';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef, $sf->{i}{ok} );
    if ( $sf->{o}{enable}{col_menu_addition} ) {
        push @pre, $sf->{i}{menu_addition};
    }
    my @cols;
    if ( @{$sql->{aggr_cols}} || @{$sql->{group_by_cols}} ) {
        @cols = ( @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} );
    }
    else {
        @cols = @{$sql->{cols}};
    }
    my $col_sep = ' ';
    $sql->{order_by_stmt} = "ORDER BY";
    my @bu;

    ORDER_BY: while ( 1 ) {
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my $col = $tc->choose(
            [ @pre, @cols ],
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $col ) {
            if ( @bu ) {
                ( $sql->{order_by_stmt}, $col_sep ) = @{pop @bu};
                next ORDER_BY;
            }
            return
        }
        if ( $col eq $sf->{i}{ok} ) {
            if ( $col_sep eq ' ' ) {
                $sql->{order_by_stmt} = '';
            }
            if ( ! length $sql->{order_by_stmt} ) {
                return 0;
            }
            return 1;
        }
        elsif ( $col eq $sf->{i}{menu_addition} ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_column = $ext->complex_unit( $sql, $clause );
            if ( ! defined $complex_column ) {
                if ( @bu ) {
                    ( $sql->{order_by_stmt}, $col_sep ) = @{pop @bu};
                }
                next ORDER_BY;
            }
            $col = $complex_column;
        }
        push @bu, [ $sql->{order_by_stmt}, $col_sep ];
        $sql->{order_by_stmt} .= $col_sep . $col;
        $info = $ax->get_sql_info( $sql );
        # Choose
        my $direction = $tc->choose(
            [ undef, "ASC", "DESC" ],
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $direction ){
            ( $sql->{order_by_stmt}, $col_sep ) = @{pop @bu};
            next ORDER_BY;
        }
        $sql->{order_by_stmt} .= ' ' . $direction;
        $col_sep = ', ';
    }
}


sub limit_offset {
    my ( $sf, $sql ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $driver = $sf->{i}{driver};
    my @pre = ( undef, $sf->{i}{ok} );
    $sql->{limit_stmt}  = '';
    $sql->{offset_stmt} = '';
    my @bu;

    LIMIT: while ( 1 ) {
        my ( $limit, $offset ) = ( 'LIMIT', 'OFFSET' );
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my $choice = $tc->choose(
            [ @pre, $limit, $offset ],
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $choice ) {
            if ( @bu ) {
                ( $sql->{limit_stmt}, $sql->{offset_stmt} )  = @{pop @bu};
                next LIMIT;
            }
            return;
        }
        if ( $choice eq $sf->{i}{ok} ) {
            if ( ! length $sql->{limit_stmt} && ! length $sql->{offset_stmt} ) {
                return 0;
            }
            return 1;
        }
        push @bu, [ $sql->{limit_stmt}, $sql->{offset_stmt} ];
        my $digits = 7;
        if ( $choice eq $limit ) {
            if ( $driver =~ /^(?:Firebird|DB2|Oracle)\z/ ) {
                # https://www.ibm.com/docs/en/db2-for-zos/12?topic=subselect-fetch-clause
                $sql->{limit_stmt} = "FETCH NEXT";
            }
            else {
                $sql->{limit_stmt} = "LIMIT";
            }
            my $info = $ax->get_sql_info( $sql );
            # Choose_a_number
            my $limit = $tu->choose_a_number( $digits,
                { info => $info, cs_label => 'LIMIT: ' }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $limit ) {
                ( $sql->{limit_stmt}, $sql->{offset_stmt} ) = @{pop @bu};
                next LIMIT;
            }
            $sql->{limit_stmt} .=  sprintf ' %d', $limit;
            if ( $driver =~ /^(?:Firebird|DB2|Oracle)\z/ ) {
                $sql->{limit_stmt} .= " ROWS ONLY";
            }
        }
        if ( $choice eq $offset ) {
            if ( $driver eq 'Informix' ) {
                $tc->choose( [ 'BACK' ], { prompt => 'Informix: OFFSET not supported.' } );
                next LIMIT;
            }
            if ( ! $sql->{limit_stmt} ) {
                # SQLite/mysql/MariaDB: no offset without limit
                $sql->{limit_stmt} = "LIMIT " . '9223372036854775807'  if $driver eq 'SQLite';   # 2 ** 63 - 1
                $sql->{limit_stmt} = "LIMIT " . '18446744073709551615' if $driver =~ /^(?:mysql|MariaDB)\z/;    # 2 ** 64 - 1
                # MySQL 8.0 Reference Manual - SQL Statements/Data Manipulation Statements/Select Statement/Limit clause:
                #    SELECT * FROM tbl LIMIT 95,18446744073709551615;   -> all rows from the 95th to the last
            }
            $sql->{offset_stmt} = "OFFSET";
            my $info = $ax->get_sql_info( $sql );
            # Choose_a_number
            my $offset = $tu->choose_a_number( $digits,
                { info => $info, cs_label => 'OFFSET: ' }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $offset ) {
                ( $sql->{limit_stmt}, $sql->{offset_stmt} ) = @{pop @bu};
                next LIMIT;
            }
            $sql->{offset_stmt} .= sprintf ' %d', $offset;
            if ( $driver =~ /^(?:Firebird|DB2|Oracle)\z/ ) {
                $sql->{offset_stmt} .= " ROWS";
            }
        }
    }
}


sub __add_condition {
    my ( $sf, $sql, $clause, $items ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $so = App::DBBrowser::Table::Substatements::Operators->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $args = $clause . '_args';
    my $stmt = $clause . '_stmt';
    my $AND_OR = '';
    my $unclosed = 0;
    my $count = 0;
    my @bu_col;
    my @pre = ( undef, $sf->{i}{ok} );
    if ( $sf->{o}{enable}{col_menu_addition} ) {
        push @pre, $sf->{i}{menu_addition};
    }

    COL: while ( 1 ) {
        my @choices = ( @$items );
        if ( $sf->{o}{enable}{parentheses} ) {
            unshift @choices, $unclosed ? ')' : '(';
        }
        my $info = $ax->get_sql_info( $sql );
        # Choose
        my $qt_col = $tc->choose( ## name
            [ @pre, @choices ],
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $qt_col ) {
            if ( @bu_col ) {
                ( $sql->{$stmt}, $sql->{$args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }
            return;
        }
        if ( $qt_col eq $sf->{i}{ok} ) {
            if ( $count == 0 ) {
                $sql->{$stmt} = '';
            }
            if ( $unclosed == 1 ) { # close an open parentheses automatically on OK
                $sql->{$stmt} .= ")";
                $unclosed = 0;
            }
            if ( ! length $sql->{$stmt} ) {
                return 0;
            }
            return 1;
        }
        if ( $qt_col eq $sf->{i}{menu_addition} ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_column = $ext->complex_unit( $sql, $clause );
            if ( ! defined $complex_column ) {
                if ( @bu_col ) {
                    ( $sql->{where_stmt}, $sql->{where_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                }
                next COL;
            }
            $qt_col = $complex_column;
        }
        if ( $qt_col eq ')' ) {
            push @bu_col, [ $sql->{$stmt}, [@{$sql->{$args}}], $AND_OR, $unclosed, $count ];
            $sql->{$stmt} .= ")";
            $unclosed--;
            next COL;
        }
        if ( $count > 0 && $sql->{$stmt} !~ /\(\z/ ) {
            my $info = $ax->get_sql_info( $sql );
            # Choose
            $AND_OR = $tc->choose(
                [ undef, "AND", "OR" ],
                { %{$sf->{i}{lyt_h}}, info => $info }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $AND_OR ) {
                next COL;
            }
            $AND_OR = ' ' . $AND_OR;
        }
        if ( $qt_col eq '(' ) {
            push @bu_col, [ $sql->{$stmt}, [@{$sql->{$args}}], $AND_OR, $unclosed, $count ];
            $sql->{$stmt} .= $AND_OR . " (";
            $AND_OR = '';
            $unclosed++;
            next COL;
        }
        push @bu_col, [ $sql->{$stmt}, [@{$sql->{$args}}], $AND_OR, $unclosed, $count ];
        if ( $clause eq 'having' ) {
            $qt_col = $so->build_having_col( $sql, $clause, $qt_col );
            if ( ! defined $qt_col ) {
                ( $sql->{$stmt}, $sql->{$args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }
        }
        $sql->{$stmt} .= $AND_OR . ' ' . $qt_col;

        OPERATOR: while ( 1 ) {
            my $bu_op = [ $sql->{$stmt}, [@{$sql->{$args}}] ];
            my ( $op, $is_complex_value ) = $so->choose_and_add_operator( $sql, $clause, $qt_col );
            if ( ! defined $op ) {
                ( $sql->{$stmt}, $sql->{$args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }

            VALUE: while ( 1 ) {
                my $ok = $so->read_and_add_value( $sql, $clause, $op, $is_complex_value );
                if ( ! $ok ) {
                    ( $sql->{$stmt}, $sql->{$args} ) = @$bu_op;
                    next OPERATOR;
                }
                last VALUE;
            }
            last OPERATOR;
        }
        $count++;
    }
}



1;


__END__

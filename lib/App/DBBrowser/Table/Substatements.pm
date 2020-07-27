package # hide from PAUSE
App::DBBrowser::Table::Substatements;

use warnings;
use strict;
use 5.010001;

use Term::Choose       qw();
use Term::Choose::Util qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Extensions;
use App::DBBrowser::Table::Substatements::Operators;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data,
        # SQLite: GROUP_CONCAT(DISTINCT "Col")  or  GROUP_CONCAT("Col",",");
        aggregate     => [ "AVG(X)", "COUNT(X)", "COUNT(*)", "GROUP_CONCAT(X)", "MAX(X)", "MIN(X)", "SUM(X)" ],
        distinct      => "DISTINCT",
        all           => "ALL",
        asc           => "ASC",
        desc          => "DESC",
        and           => "AND",
        or            => "OR",
    };
    if ( $info->{driver} eq 'Pg' ) {
        $sf->{aggregate}[3] = "STRING_AGG(X)";
    }
    $sf->{i}{menu_additions}     = [ '',  'f()', 'SQ',       '%%' ];
    $sf->{i}{menu_additions_set} = [ '',  'f()', 'SQ', '=N', '%%' ];
    bless $sf, $class;
}


sub select {
    my ( $sf, $sql ) = @_;
    my $clause = 'select';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $menu = [];
    my $i = $sf->{o}{enable}{'expand_' . $clause};
    my $menu_addition = $sf->{i}{menu_additions}[$i];
    my @pre = ( undef, $sf->{i}{ok}, $menu_addition ? $menu_addition : () );
    if ( @{$sql->{group_by_cols}} || @{$sql->{aggr_cols}} ) {
        $menu = [ @pre, @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} ];
    }
    else {
        $menu = [ @pre, @{$sql->{cols}} ];
    }
    $sql->{select_cols} = [];
    #$sql->{alias} = { %{$sql->{alias}} };
    my @bu;

    COLUMNS: while ( 1 ) {
        $ax->print_sql( $sql );
        # Choose
        my @idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, meta_items => [ 0 .. $#pre - 1 ], no_spacebar => [ $#pre ], include_highlighted => 2,
              index => 1 }
        );
        if ( ! $idx[0] ) {
            if ( @bu ) {
                ( $sql->{select_cols}, $sql->{alias} ) = @{pop @bu};
                next COLUMNS;
            }
            return;
        }
        push @bu, [ [ @{$sql->{select_cols}} ], { %{$sql->{alias}} } ];
        if ( $menu->[$idx[0]] eq $sf->{i}{ok} ) {
            shift @idx;
            push @{$sql->{select_cols}}, @{$menu}[@idx];
            return 1;
        }
        elsif ( $menu->[$idx[0]] eq $menu_addition ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_column = $ext->complex_unit( $sql, $clause );
            if ( ! defined $complex_column ) {
                ( $sql->{select_cols}, $sql->{alias} ) = @{pop @bu};
            }
            else {
                push @{$sql->{select_cols}}, $complex_column;
            }
            next COLUMNS;
        }
        push @{$sql->{select_cols}}, @{$menu}[@idx];
    }
}


sub distinct {
    my ( $sf, $sql ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef, $sf->{i}{ok} );
    $sql->{distinct_stmt} = '';

    DISTINCT: while ( 1 ) {
        my $menu = [ @pre, $sf->{distinct}, $sf->{all} ];
        $ax->print_sql( $sql );
        # Choose
        my $select_distinct = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}} }
        );
        if ( ! defined $select_distinct ) {
            if ( $sql->{distinct_stmt} ) {
                $sql->{distinct_stmt} = '';
                next DISTINCT;
            }
            return;
        }
        elsif ( $select_distinct eq $sf->{i}{ok} ) {
            return 1;
        }
        $sql->{distinct_stmt} = ' ' . $select_distinct;
    }
}


sub aggregate {
    my ( $sf, $sql ) = @_;
    $sql->{aggr_cols} = [];
    $sql->{select_cols} = [];

    AGGREGATE: while ( 1 ) {
        my $ret = $sf->__add_aggregate_substmt( $sql );
        if ( ! $ret ) {
            if ( @{$sql->{aggr_cols}} ) {
                my $aggr = pop @{$sql->{aggr_cols}};
                delete $sql->{alias}{$aggr} if exists $sql->{alias}{$aggr};
                next AGGREGATE;
            }
            return;
        }
        elsif ( $ret eq $sf->{i}{ok} ) {
            return 1;
        }
    }
}

sub __add_aggregate_substmt {
    my ( $sf, $sql ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my @pre = ( undef, $sf->{i}{ok} );
    my $i = @{$sql->{aggr_cols}};
    $ax->print_sql( $sql );
    # Choose
    my $aggr = $tc->choose(
        [ @pre, @{$sf->{aggregate}} ],
        { %{$sf->{i}{lyt_h}} }
    );
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
        $aggr =~ s/\(\S\)\z//; #
        $sql->{aggr_cols}[$i] = $aggr . "(";
        if ( $aggr =~ /^(?:COUNT|GROUP_CONCAT|STRING_AGG)\z/ ) {
            $ax->print_sql( $sql );
            # Choose
            my $all_or_distinct = $tc->choose(
                [ undef, $sf->{all}, $sf->{distinct} ],
                { %{$sf->{i}{lyt_h}} }
            );
            if ( ! defined $all_or_distinct ) {
                return;
            }
            if ( $all_or_distinct eq $sf->{distinct} ) {
                $sql->{aggr_cols}[$i] .= $sf->{distinct};
            }
        }
        $ax->print_sql( $sql );
        # Choose
        my $f_col = $tc->choose(
            [ undef, @{$sql->{cols}} ],
            { %{$sf->{i}{lyt_h}} }
        );
        if ( ! defined $f_col ) {
            return;
        }
        if ( $aggr eq 'STRING_AGG' ) {
            # pg: the separator is mandatory in STRING_AGG(DISTINCT, "Col", ',')
            $sql->{aggr_cols}[$i] .= ' ' . $f_col . ", ',' )";
        }
        else {
            $sql->{aggr_cols}[$i] .= ' ' . $f_col . " )";
        }
    }
    my $alias = $ax->alias( 'aggregate', $sql->{aggr_cols}[$i] );
    if ( defined $alias && length $alias ) {
        $sql->{alias}{$sql->{aggr_cols}[$i]} = $ax->quote_col_qualified( [ $alias ] );
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
        $ax->print_sql( $sql );
        # Choose
        my $quote_col = $tc->choose(
            [ @pre, @{$sql->{cols}} ],
            { %{$sf->{i}{lyt_h}} }
        );
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
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $so = App::DBBrowser::Table::Substatements::Operators->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @cols = @{$sql->{cols}};
    my $AND_OR = '';
    $sql->{where_args} = [];
    $sql->{where_stmt} = "WHERE";
    my $unclosed = 0;
    my $count = 0;
    my @bu_col;
    my $i = $sf->{o}{enable}{'expand_' . $clause};
    my $menu_addition = $sf->{i}{menu_additions}[$i];
    my @pre = ( undef, $sf->{i}{ok}, $i ? $menu_addition : () );

    COL: while ( 1 ) {
        my @choices = ( @cols );
        if ( $sf->{o}{enable}{parentheses} ) {
            unshift @choices, $unclosed ? ')' : '(';
         }
        $ax->print_sql( $sql );
        # Choose
        my $quote_col = $tc->choose(
            [ @pre, @choices ],
            { %{$sf->{i}{lyt_h}} }
        );
        if ( ! defined $quote_col ) {
            if ( @bu_col ) {
                ( $sql->{where_stmt}, $sql->{where_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }
            return;
        }
        if ( $quote_col eq $sf->{i}{ok} ) {
            if ( $count == 0 ) {
                $sql->{where_stmt} = '';
            }
            if ( $unclosed == 1 ) { # close an open parentheses automatically on OK
                $sql->{where_stmt} .= " )";
                $unclosed = 0;
            }
            return 1;
        }
        if ( $quote_col eq $menu_addition ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_column = $ext->complex_unit( $sql, $clause );
            if ( ! defined $complex_column ) {
                if ( @bu_col ) {
                    ( $sql->{where_stmt}, $sql->{where_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                }
                next COL;
            }
            $quote_col = $complex_column;
        }
        if ( $quote_col eq ')' ) {
            push @bu_col, [ $sql->{where_stmt}, [@{$sql->{where_args}}], $AND_OR, $unclosed, $count ];
            $sql->{where_stmt} .= " )";
            $unclosed--;
            next COL;
        }
        if ( $count > 0 && $sql->{where_stmt} !~ /\(\z/ ) { #
            $ax->print_sql( $sql );
            # Choose
            $AND_OR = $tc->choose(
                [ undef, $sf->{and}, $sf->{or} ],
                { %{$sf->{i}{lyt_h}} }
            );
            if ( ! defined $AND_OR ) {
                next COL;
            }
            $AND_OR = ' ' . $AND_OR;
        }
        if ( $quote_col eq '(' ) {
            push @bu_col, [ $sql->{where_stmt}, [@{$sql->{where_args}}], $AND_OR, $unclosed, $count ];
            $sql->{where_stmt} .= $AND_OR . " (";
            $AND_OR = '';
            $unclosed++;
            next COL;
        }
        push @bu_col, [ $sql->{where_stmt}, [@{$sql->{where_args}}], $AND_OR, $unclosed, $count ];
        $sql->{where_stmt} .= $AND_OR . ' ' . $quote_col;

        OPERATOR: while ( 1 ) {
            my $bu_op = [ $sql->{where_stmt}, [@{$sql->{where_args}}] ];
            my ( $op, $is_complex_value ) = $so->choose_and_add_operator( $sql, $clause, $quote_col );
            if ( ! defined $op ) {
                ( $sql->{where_stmt}, $sql->{where_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }

            VALUE: while ( 1 ) {
                my $ok = $so->read_and_add_value( $sql, $clause, $op, $is_complex_value );
                if ( ! $ok ) {
                    ( $sql->{where_stmt}, $sql->{where_args} ) = @$bu_op;
                    next OPERATOR;
                }
                last VALUE;
            }
            last OPERATOR;
        }
        $count++;
    }
}


sub group_by {
    my ( $sf, $sql ) = @_;
    my $clause = 'group_by';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    $sql->{group_by_stmt} = "GROUP BY";
    $sql->{group_by_cols} = [];
    $sql->{select_cols} = [];
    my $i = $sf->{o}{enable}{'expand_' . $clause};
    my $menu_addition = $sf->{i}{menu_additions}[$i];
    my @pre = ( undef, $sf->{i}{ok}, $menu_addition ? $menu_addition : () );
    my $menu = [ @pre, @{$sql->{cols}} ];

    GROUP_BY: while ( 1 ) {
        $sql->{group_by_stmt} = "GROUP BY " . join ', ', @{$sql->{group_by_cols}};
        $ax->print_sql( $sql );
        # Choose
        my @idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, meta_items => [ 0 .. $#pre - 1 ], no_spacebar => [ $#pre ], include_highlighted => 2,
              index => 1 }
        );
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
            return 1;
        }
        elsif ( $menu->[$idx[0]] eq $menu_addition ) {
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
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $so = App::DBBrowser::Table::Substatements::Operators->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef, $sf->{i}{ok} );
    my $AND_OR = '';
    $sql->{having_args} = [];
    $sql->{having_stmt} = "HAVING";
    my $unclosed = 0;
    my $count = 0;
    my @bu_col;

    COL: while ( 1 ) {
        my @choices = (
            @{$sf->{aggregate}},
            map( '@' . $_, @{$sql->{aggr_cols}} )
        );
        if ( $sf->{o}{enable}{parentheses} ) {
            unshift @choices, $unclosed ? ')' : '(';
        }
        $ax->print_sql( $sql );
        # Choose
        my $aggr = $tc->choose(
            [ @pre, @choices ],
            { %{$sf->{i}{lyt_h}} }
        );
        if ( ! defined $aggr ) {
            if ( @bu_col ) {
                ( $sql->{having_stmt}, $sql->{having_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }
            return;
        }
        if ( $aggr eq $sf->{i}{ok} ) {
            if ( $count == 0 ) {
                $sql->{having_stmt} = '';
            }
            if ( $unclosed == 1 ) { # close an open parentheses automatically on OK
                $sql->{having_stmt} .= ")";
                $unclosed = 0;
            }
            return 1;
        }
        if ( $aggr eq ')' ) {
            push @bu_col, [ $sql->{having_stmt}, [@{$sql->{having_args}}], $AND_OR, $unclosed, $count ];
            $sql->{having_stmt} .= ")";
            $unclosed--;
            next COL;
        }
        if ( $count > 0 && $sql->{having_stmt} !~ /\(\z/ ) {
            $ax->print_sql( $sql );
            # Choose
            $AND_OR = $tc->choose(
                [ undef, $sf->{and}, $sf->{or} ],
                { %{$sf->{i}{lyt_h}} }
            );
            if ( ! defined $AND_OR ) {
                next COL;
            }
            $AND_OR = ' ' . $AND_OR;
        }
        if ( $aggr eq '(' ) {
            push @bu_col, [ $sql->{having_stmt}, [@{$sql->{having_args}}], $AND_OR, $unclosed, $count ];
            $sql->{having_stmt} .= $AND_OR . " (";
            $AND_OR = '';
            $unclosed++;
            next COL;
        }
        push @bu_col, [ $sql->{having_stmt}, [@{$sql->{having_args}}], $AND_OR, $unclosed, $count ];
        $sql->{having_stmt} .= $AND_OR;
        my $quote_aggr = $so->build_having_col( $sql, $aggr );
        if ( ! defined $quote_aggr ) {
            ( $sql->{having_stmt}, $sql->{having_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
            next COL;
        }

        OPERATOR: while ( 1 ) {
            my $bu_op = [ $sql->{having_stmt}, [@{$sql->{having_args}}] ];
            my ( $op, $is_complex_value ) = $so->choose_and_add_operator( $sql, $clause, $quote_aggr );
            if ( ! defined $op ) {
                ( $sql->{having_stmt}, $sql->{having_args}, $AND_OR, $unclosed, $count ) = @{pop @bu_col};
                next COL;
            }

            VALUE: while ( 1 ) {
                my $ok = $so->read_and_add_value( $sql, $clause, $op, $is_complex_value );
                if ( ! $ok ) {
                    ( $sql->{having_stmt}, $sql->{having_args} ) = @$bu_op;
                    next OPERATOR;
                }
                last VALUE;
            }
            last OPERATOR;
        }
        $count++;
    }
}


sub order_by {
    my ( $sf, $sql ) = @_;
    my $clause = 'order_by';
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $i = $sf->{o}{enable}{'expand_' . $clause};
    my $menu_addition = $sf->{i}{menu_additions}[$i];
    my @pre = ( undef, $sf->{i}{ok}, $menu_addition ? $menu_addition : () );
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
        $ax->print_sql( $sql );
        # Choose
        my $col = $tc->choose(
            [ @pre, @cols ],
            { %{$sf->{i}{lyt_h}} }
        );
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
            return 1;
        }
        elsif ( $col eq $menu_addition ) {
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
        $ax->print_sql( $sql );
        # Choose
        my $direction = $tc->choose(
            [ undef, $sf->{asc}, $sf->{desc} ],
            { %{$sf->{i}{lyt_h}} }
        );
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
    my @pre = ( undef, $sf->{i}{ok} );
    $sql->{limit_stmt}  = '';
    $sql->{offset_stmt} = '';
    my @bu;

    LIMIT: while ( 1 ) {
        my ( $limit, $offset ) = ( 'LIMIT', 'OFFSET' );
        $ax->print_sql( $sql );
        # Choose
        my $choice = $tc->choose(
            [ @pre, $limit, $offset ],
            { %{$sf->{i}{lyt_h}} }
        );
        if ( ! defined $choice ) {
            if ( @bu ) {
                ( $sql->{limit_stmt}, $sql->{offset_stmt} )  = @{pop @bu};
                next LIMIT;
            }
            return;
        }
        if ( $choice eq $sf->{i}{ok} ) {
            return 1;
        }
        push @bu, [ $sql->{limit_stmt}, $sql->{offset_stmt} ];
        my $digits = 7;
        if ( $choice eq $limit ) {
            #$sql->{limit_stmt} = " LIMIT";
            $sql->{limit_stmt} = "LIMIT";
            $ax->print_sql( $sql );
            # Choose_a_number
            my $limit = $tu->choose_a_number( $digits,
                { cs_label => 'LIMIT: ' }
            );
            if ( ! defined $limit ) {
                ( $sql->{limit_stmt}, $sql->{offset_stmt} ) = @{pop @bu};
                next LIMIT;
            }
            $sql->{limit_stmt} .=  sprintf ' %d', $limit;
        }
        if ( $choice eq $offset ) {
            if ( ! $sql->{limit_stmt} ) {
                $sql->{limit_stmt} = "LIMIT " . ( $sf->{o}{G}{max_rows} || '9223372036854775807'  ) if $sf->{i}{driver} eq 'SQLite';   # 2 ** 63 - 1
                # MySQL 5.7 Reference Manual - SELECT Syntax - Limit clause: SELECT * FROM tbl LIMIT 95,18446744073709551615;
                $sql->{limit_stmt} = "LIMIT " . ( $sf->{o}{G}{max_rows} || '18446744073709551615' ) if $sf->{i}{driver} eq 'mysql';    # 2 ** 64 - 1
            }
            $sql->{offset_stmt} = "OFFSET";
            $ax->print_sql( $sql );
            # Choose_a_number
            my $offset = $tu->choose_a_number( $digits,
                { cs_label => 'OFFSET: ' }
            );
            if ( ! defined $offset ) {
                ( $sql->{limit_stmt}, $sql->{offset_stmt} ) = @{pop @bu};
                next LIMIT;
            }
            $sql->{offset_stmt} .= sprintf ' %d', $offset;
        }
    }
}






1;


__END__

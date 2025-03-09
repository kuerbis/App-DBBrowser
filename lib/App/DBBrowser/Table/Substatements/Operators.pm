package # hide from PAUSE
App::DBBrowser::Table::Substatements::Operators;

use warnings;
use strict;
use 5.014;

use List::MoreUtils qw( any uniq );

use Term::Choose         qw();
use Term::Form::ReadLine qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Extensions;


sub new {
    my ( $class, $info, $options, $d ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $d
    };
    bless $sf, $class;
}


sub add_operator_and_value {
    my ( $sf, $sql, $clause, $stmt, $col, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @operators = @{$sf->{o}{G}{operators}};
    my $not_equal = ( any { $_ =~ /^\s?!=\s?\z/ } @operators ) ? "!=" : "<>";
    if ( ! length $col ) {
        $sql->{$stmt} =~ s/\s\z//;
        @operators = ( "EXISTS", "NOT EXISTS" );
    }
    elsif ( $sf->{i}{driver} eq 'SQLite' ) {
        @operators = grep { ! /^(?:ANY|ALL)\z/ } @operators;
    }
    elsif ( $sf->{i}{driver} eq 'Firebird' ) {
        @operators = uniq map { s/REGEXP(?:_i)?\z/SIMILAR TO/; $_ } @operators;
    }
    elsif ( $sf->{i}{driver} eq 'Informix' ) {
        @operators = uniq map { s/REGEXP(?:_i)?\z/MATCHES/; $_ } @operators;
    }
    elsif ( $sf->{i}{driver} eq 'ODBC' ) {
        @operators = grep { ! /REGEXP/ } @operators;
    }
    my $bu_stmt = $sql->{$stmt};

    OPERATOR: while( 1 ) {
        my $operator;
        #if ( @operators == 1 ) { ##
        #    $operator = $operators[0];
        #}
        #else {
            my @pre = ( undef );
            my $info = $sf->info_add_condition( $sql, $clause, $stmt, $r_data );
            # Choose
            $operator = $tc->choose(
                [ @pre, @operators ],
                { %{$sf->{i}{lyt_h}}, info => $info }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $operator ) {
                $sql->{$stmt} = $bu_stmt;
                return;
            }
        #}
        $operator =~ s/^\s+|\s+\z//g;
        if ( $operator =~ /(?:REGEXP(?:_i)?|SIMILAR\sTO)\z/ ) {
            my $not_match = $operator =~ /^NOT/ ? 1 : 0;
            my $case_sensitive = $operator =~ /REGEXP_i\z/ ? 0 : 1;
            my $regex_op = $sf->__pattern_match( $col, $not_match, $case_sensitive );
            if ( ! $regex_op ) {
                next OPERATOR if @operators > 1;
                return;
            }
            $sql->{$stmt} =~ s/ (?: (?<=\() | \s ) \Q$col\E \z //x;
            if ( $sql->{$stmt} =~ /\(\z/ ) {
                $regex_op =~ s/^\s//;
            }
            $sql->{$stmt} .= $regex_op;
        }
        elsif ( $operator =~ /^(?:ALL|ANY)\z/) {
            my @comb_op = ( "= $operator", "$not_equal $operator", "> $operator", "< $operator", ">= $operator", "<= $operator" );
            my @pre = ( undef );
            my $info = $sf->info_add_condition( $sql, $clause, $stmt, $r_data );
            # Choose
            $operator = $tc->choose(
                [ @pre, @comb_op ],
                { %{$sf->{i}{lyt_h}}, info => $info }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $operator ) {
                next OPERATOR if @operators > 1;
                return;
            }
            $sql->{$stmt} .= ' ' . $operator;
        }
        elsif ( $operator =~ /^(?:NOT )?EXISTS\z/ ) {
            if ( $sql->{$stmt} =~ /\(\z/ ) {
                $sql->{$stmt} .= $operator;
            }
            else {
                $sql->{$stmt} .= ' ' . $operator;
            }
        }
        else {
            $sql->{$stmt} .= ' ' . $operator;
        }
        my $ok = $sf->read_and_add_value( $sql, $clause, $stmt, $col, $operator, $r_data );
        if ( $ok ) {
            return 1;
        }
        else {
            $sql->{$stmt} = $bu_stmt;
            next OPERATOR if @operators > 1;
            return;
        }
    }
}


sub info_add_condition {
    my ( $sf, $sql, $clause, $stmt, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $info;
    if ( @{$r_data//[]} ) {
        $info = $ax->get_sql_info( $sql );
        my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
        $r_data->[-1][-1] = $sql->{$stmt};
        $info .= $ext->nested_func_info( $r_data );
    }
    else {
        $info = $ax->get_sql_info( $sql );
    }
    return $info;
}


sub read_and_add_value {
    my ( $sf, $sql, $clause, $stmt, $col, $operator, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $is_numeric = $ax->is_numeric_datatype( $sql, $col );
    $r_data->[-1][-1] = $sql->{$stmt} if @{$r_data//[]};
    if ( $operator =~ /^IS\s(?:NOT\s)?NULL\z/ ) {
        return 1;
    }
    elsif ( $operator =~ /^(?:NOT\s)?IN\z/ ) {
        my $bu_stmt = $sql->{$stmt};
        $sql->{$stmt} .= ' (';
        my @args;

        IN: while ( 1 ) {
            # Readline
            my $value = $ext->value( $sql, $clause, $r_data, $operator, { is_numeric => $is_numeric } );
            if ( ! defined $value ) {
                if ( ! @args ) {
                    $sql->{$stmt} = $bu_stmt;
                    return;
                }
                pop @args;
                $sql->{$stmt} = $bu_stmt . ' ('  . join ',', @args;
                next IN;
            }
            if ( ! length $value || $value eq "''" ) {
                if ( ! @args ) {
                    $sql->{$stmt} = $bu_stmt;
                    return;
                }
                if ( @args == 1 && $args[0] =~ /^\s*\((.+)\)\s*\z/ ) {
                    # if the only argument is a subquery:
                    # remove the parenthesis around the subquery
                    # because "IN ((subquery))" is not alowed
                    $sql->{$stmt} = $bu_stmt . ' (' . $1;
                }
                $sql->{$stmt} .= ')';
                return 1;
            }
            push @args, $value;
            $sql->{$stmt} = $bu_stmt . ' ('  . join ',', @args;
            $r_data->[-1][-1] = $sql->{$stmt} if @{$r_data//[]};
        }
    }
    elsif ( $operator =~ /^(?:NOT\s)?BETWEEN\z/ ) {
        # Readline
        my $value_1 = $ext->value( $sql, $clause, $r_data, $operator, { is_numeric => $is_numeric } );
        if ( ! defined $value_1 ) {
            return;
        }
        my $bu_stmt = $sql->{$stmt};
        $sql->{$stmt} .= ' ' . $value_1 . ' AND';
        $r_data->[-1][-1] = $sql->{$stmt} if @{$r_data//[]};
        # Readline
        my $value_2 = $ext->value( $sql, $clause, $r_data, $operator, { is_numeric => $is_numeric } );
        if ( ! defined $value_2 ) {
            $sql->{$stmt} = $bu_stmt;
            return;
        }
        $sql->{$stmt} .= ' ' . $value_2;
        return 1;
    }
    elsif ( $operator =~ /(?:REGEXP(?:_i)?|SIMILAR\sTO|MATCHES|LIKE)\z/ ) {
        # Readline
        my $value = $ext->value( $sql, $clause, $r_data, $operator, { is_numeric => 0 } );
        if ( ! defined $value ) {
            return;
        }
        #if ( ! length $value ) {
        #    $value = "''";
        #}
        if ( $operator =~ /SIMILAR\sTO\z/ ) {
            $sql->{$stmt} =~ s/ \? (?=\sESCAPE\s'\\'\z) /$value/x;
        }
        elsif ( $operator =~ /REGEXP(?:_i)?\z/ ) {
            if ( $sf->{i}{driver} eq 'SQLite' ) {
                $sql->{$stmt} =~ s/ (?<=\sREGEXP\() \? (?=,\Q$col\E,[01]\)\z) /$value/x;
            }
            elsif ( $sf->{i}{driver} =~ /^(?:DB2|Oracle)\z/ ) {
                $sql->{$stmt} =~ s/ \?  (?=,'[ci]'\)\z) /$value/x;
            }
            else {
                $sql->{$stmt} .= ' ' . $value;
            }
        }
        else {
            $sql->{$stmt} .= ' ' . $value;
        }
        return 1;
    }
    else {
        my $value;
        if ( $clause eq 'on' ) {
            $value = $sf->__choose_a_column( $sql, $clause, $stmt, $r_data );
        }
        else {
            # Readline
            $value = $ext->value( $sql, $clause, $r_data, $operator, { is_numeric => $is_numeric } );
        }
        if ( ! defined $value ) {
            return;
        }
        $sql->{$stmt} .= ' ' . $value;
        return 1;
    }
}


sub __choose_a_column {
    my ( $sf, $sql, $clause, $stmt, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef );
    if ( $sf->{o}{enable}{extended_cols} ) {
        push @pre, $sf->{i}{menu_addition};
    }
    my @choices = @{$sql->{cols_join_condition}};

    COL: while ( 1 ) {
        my $info = $sf->info_add_condition( $sql, $clause, $stmt, $r_data );
        # Choose
        my $col = $tc->choose(
            [ @pre, @choices ],
            { %{$sf->{i}{lyt_h}}, info => $info }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $col ) {
            return;
        }
        if ( $col eq $sf->{i}{menu_addition} ) {
            if ( @{$r_data//[]} ) {
                $r_data->[-1][-1] = $sql->{$stmt};
            }
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_col = $ext->column( $sql, $clause, $r_data );
            if ( ! defined $complex_col ) {
                next COL;
            }
            $col = $complex_col;
        }
        return $col;
    }
}


sub __pattern_match {
    my ( $sf, $col, $not_match, $case_sensitive ) = @_;
    my $driver = $sf->{i}{driver};
    if ( $driver eq 'SQLite' ) {
        if ( $not_match ) {
            return sprintf " NOT REGEXP(?,%s,%d)", $col, $case_sensitive;
        }
        else {
            return sprintf " REGEXP(?,%s,%d)", $col, $case_sensitive;
        }
    }
    elsif ( $driver =~ /^(?:mysql|MariaDB)\z/ ) {
        if ( $not_match ) {
            return " $col NOT REGEXP"        if ! $case_sensitive;
            return " $col NOT REGEXP BINARY" if   $case_sensitive;
        }
        else {
            return " $col REGEXP"        if ! $case_sensitive;
            return " $col REGEXP BINARY" if   $case_sensitive;
        }
    }
    elsif ( $driver eq 'Pg' ) {
        if ( $not_match ) {
            return " ${col}::text !~*" if ! $case_sensitive; ##
            return " ${col}::text !~"  if   $case_sensitive;
        }
        else {
            return " ${col}::text ~*" if ! $case_sensitive;
            return " ${col}::text ~"  if   $case_sensitive;
        }
    }
    elsif ( $driver eq 'Firebird' ) {
        if ( $not_match ) {
            return " $col NOT SIMILAR TO ? ESCAPE '\\'";
        }
        else {
            return " $col SIMILAR TO ? ESCAPE '\\'";
        }
    }
    elsif ( $driver =~ /^(?:DB2|Oracle)\z/ ) {
        if ( $not_match ) {
            return " NOT REGEXP_LIKE($col,?,'i')" if ! $case_sensitive;
            return " NOT REGEXP_LIKE($col,?,'c')" if   $case_sensitive;
        }
        else {
            return " REGEXP_LIKE($col,?,'i')" if ! $case_sensitive;
            return " REGEXP_LIKE($col,?,'c')" if   $case_sensitive;
        }
    }
}


# The pattern must match the entire string:
#
# SIMILAR TO:   %   _       no default Escape
# MATCHES:      *   ?       \
# LIKE:         %   _       \    SQLite, Firebird, DB2 and Oracle no default Escape




1;

__END__

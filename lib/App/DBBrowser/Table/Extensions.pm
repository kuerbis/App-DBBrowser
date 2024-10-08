package # hide from PAUSE
App::DBBrowser::Table::Extensions;

use warnings;
use strict;
use 5.014;

use Term::Choose qw();

use App::DBBrowser::Auxil;
#use App::DBBrowser::Subqueries;                          # required
#use App::DBBrowser::Table::Extensions::Maths;            # required
#use App::DBBrowser::Table::Extensions::Case;             # required
#use App::DBBrowser::Table::Extensions::ColumnAliases     # required
#use App::DBBrowser::Table::Extensions::ScalarFunctions;  # required
#use App::DBBrowser::Table::Extensions::WindowFunctions;  # required


sub new {
    my ( $class, $info, $options, $d ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $d
    };
    $sf->{const} = 'Value';
    $sf->{subquery} = 'SQ';
    $sf->{scalar_func} = 'func()';
    $sf->{window_func} = 'win()';
    $sf->{case} = 'case';
    $sf->{math} = 'math';
    $sf->{col} = 'column';
    $sf->{null} = 'NULL';
    $sf->{close_in} = ')end';
    $sf->{par_open} = '(';
    $sf->{par_close} = ')';
    $sf->{col_aliases} = 'alias';
    bless $sf, $class;
}


sub column {
    my ( $sf, $sql, $clause, $r_data, $opt ) = @_;
    my $extensions = [];
    if ( $clause =~ /^(?:select|order_by)\z/i ) {
        # Window functions are permitted only in SELECT and ORDER BY
        $extensions = [ $sf->{subquery}, $sf->{scalar_func}, $sf->{window_func}, $sf->{case}, $sf->{math} ];
        if ( $clause eq 'select' ) {
            push @$extensions, $sf->{col_aliases};
        }
    }
    else {
        $extensions = [ $sf->{subquery}, $sf->{scalar_func}, $sf->{case}, $sf->{math} ];
    }
    if ( $opt->{add_parentheses} ) {
        push @$extensions, $sf->{par_open}, $sf->{par_close};
        delete $opt->{add_parentheses};
    }
    if ( length $opt->{from} ) {
        # no recursion:
        if ( $opt->{from} eq 'maths' ) {
            $extensions = [ grep { ! /^\Q$sf->{math}\E\z/ } @$extensions ];
        }
        elsif ( $opt->{from} eq 'window_function' ) {
            $extensions = [ grep { ! /^\Q$sf->{window_func}\E\z/ } @$extensions ];
        }
    }
    return $sf->__choose_extension( $sql, $clause, $r_data, $extensions, $opt );
}


sub value {
    my ( $sf, $sql, $clause, $r_data, $operator, $opt ) = @_;
    my $ext_express = $sf->{o}{enable}{extended_values};
    my $extensions = [];
    if ( $ext_express ) {
        if ( $clause =~ /^(?:select|order_by)\z/i ) {
            $extensions = [ $sf->{const}, $sf->{subquery}, $sf->{scalar_func}, $sf->{window_func}, $sf->{case}, $sf->{math}, $sf->{col} ];
        }
        else {
            $extensions = [ $sf->{const}, $sf->{subquery}, $sf->{scalar_func}, $sf->{case}, $sf->{math}, $sf->{col} ];
        }
        if ( $clause eq 'set' ) {
            push @$extensions, $sf->{null};
        }
        if ( $operator =~ /\s(?:ALL|ANY)\z/ ) {
            $extensions = [ $sf->{subquery} ];
        }
        elsif ( $operator =~ /^(?:NOT\s)?IN\z/ ) {
            push @$extensions, $sf->{close_in};
        }
    }
    else {
        if ( $operator =~ /\s(?:ALL|ANY)\z/ ) {
            $extensions = [ $sf->{subquery} ];
        }
        else {
            $extensions = [ $sf->{const} ];
        }
    }
    return $sf->__choose_extension( $sql, $clause, $r_data, $extensions, $opt );
}


sub argument {
    my ( $sf, $sql, $clause, $opt ) = @_;
    my $ext_express = $sf->{o}{enable}{extended_args};
    my $extensions = [];
    if ( $ext_express ) {
        $extensions = [ $sf->{const}, $sf->{subquery}, $sf->{scalar_func}, $sf->{case}, $sf->{math}, $sf->{col} ]; ##
    }
    else {
        $extensions = [ $sf->{const} ];
    }
    return $sf->__choose_extension( $sql, $clause, {}, $extensions, $opt );
}


sub enable_extended_arguments {
    my ( $sf, $info ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $prompt = 'Extended arguments:';
    my $yes = '- YES';
    # Choose
    my $choice = $tc->choose(
        [ undef, '- NO', $yes ],
        { %{$sf->{i}{lyt_v}}, info => $info, prompt => $prompt, undef => '<=' }
    );
    if ( ! defined $choice ) {
        return;
    }
    if ( $choice eq $yes ) {
        $sf->{o}{enable}{extended_args} = 1;
    }
    else {
        $sf->{o}{enable}{extended_args} = 0;
    }
}


sub __choose_extension {
    my ( $sf, $sql, $clause, $r_data, $extensions, $opt ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $qt_cols;
    if ( $sql->{aggregate_mode} && $clause eq 'select' ) {
        $qt_cols = [ @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} ];
    }
    elsif ( $sql->{aggregate_mode} && $clause eq 'having' ) {
        $qt_cols = [ map( '@' . $_, @{$sql->{aggr_cols}} ), @{$sf->{i}{avail_aggr}} ];
    }
    elsif ( $sql->{aggregate_mode} && $clause eq 'order_by' ) {
        $qt_cols = [ @{$sql->{group_by_cols}}, map( '@' . $_, @{$sql->{aggr_cols}} ), @{$sf->{i}{avail_aggr}} ];
    }
    else {
        $qt_cols = [ @{$sql->{columns}} ];
    }
    my $old_idx = 0;

    EXTENSION: while ( 1 ) {
        my $info = $opt->{info} || $ax->get_sql_info( $sql );
        my $extension;
        if ( @$extensions == 1 ) {
            $extension = $extensions->[0];
        }
        else {
            my @pre = ( undef );
            # Choose
            my $idx = $tc->choose(
                [ @pre, @$extensions ],
                { %{$sf->{i}{lyt_h}}, info => $info, index => 1, default => $old_idx, prompt => $opt->{prompt}, undef => '<<' }
            );
            $ax->print_sql_info( $info );
            if ( ! $idx ) { ##
                return;
            }
            if ( $sf->{o}{G}{menu_memory} ) {
                if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                    $old_idx = 0;
                    next EXTENSION;
                }
                $old_idx = $idx;
            }
            $extension = $extensions->[$idx-@pre];
        }
        if ( $extension eq $sf->{const} ) {
            my $prompt = $opt->{prompt} // 'Value: ';
            # Readline
            my $value = $tr->readline(
                $prompt,
                { info => $info, history => $opt->{history} }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $value ) {
                return if @$extensions = 1;
                next EXTENSION;
            }
            # return if ! length $value; ##
            if ( $opt->{is_numeric} ) {
                #  1 numeric
                # -1 unkown
                return $ax->quote_constant( $value );
            }
            else {
                return $sf->{d}{dbh}->quote( $value );
            }
        }
        elsif ( $extension eq $sf->{subquery} ) {
            require App::DBBrowser::Subqueries;
            my $new_sq = App::DBBrowser::Subqueries->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $subq = $new_sq->subquery( $sql, $opt );
            if ( ! defined $subq ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $subq;
        }
        elsif ( $extension eq $sf->{scalar_func} ) {
            require App::DBBrowser::Table::Extensions::ScalarFunctions;
            my $new_func = App::DBBrowser::Table::Extensions::ScalarFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $scalar_func_stmt = $new_func->col_function( $sql, $clause, $qt_cols, $r_data, $opt ); # recursion yes
            if ( ! defined $scalar_func_stmt ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $scalar_func_stmt;
        }
        elsif ( $extension eq $sf->{window_func} ) {
            require App::DBBrowser::Table::Extensions::WindowFunctions;
            my $wf = App::DBBrowser::Table::Extensions::WindowFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $win_func_stmt = $wf->window_function( $sql, $clause, $qt_cols, $opt );
            if ( ! defined $win_func_stmt ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $win_func_stmt;
        }
        elsif ( $extension eq $sf->{case}  ) {
            require App::DBBrowser::Table::Extensions::Case;
            my $new_cs = App::DBBrowser::Table::Extensions::Case->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $case_stmt = $new_cs->case( $sql, $clause, $qt_cols, $r_data, $opt ); # recursion yes
            if ( ! defined $case_stmt ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $case_stmt;
        }
        elsif ( $extension eq $sf->{math}  ) {
            require App::DBBrowser::Table::Extensions::Maths;
            my $new_math = App::DBBrowser::Table::Extensions::Maths->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $arith = $new_math->maths( $sql, $clause, $qt_cols, $opt );
            if ( ! defined $arith ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $arith;
        }
        elsif ( $extension eq $sf->{col} ) {
            my $prompt = defined $opt->{prompt} ? $opt->{prompt} : '';
            my @pre = ( undef );
            # Choose
            my $col = $tc->choose(
                [ @pre, @$qt_cols ],
                { %{$sf->{i}{lyt_h}}, info => $info, prompt => $prompt, undef => '<<' }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $col ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $col =~ s/^- //r;
        }
        elsif ( $extension eq $sf->{null} ) {
            return "NULL";
        }
        elsif ( $extension eq $sf->{close_in} ) {
            return "''";
        }
        elsif ( $extension eq $sf->{par_open} ) {
            return "(";
        }
        elsif ( $extension eq $sf->{par_close} ) {
            return ")";
        }
        elsif ( $extension eq $sf->{col_aliases}  ) {
            require App::DBBrowser::Table::Extensions::ColumnAliases;
            my $new_ca = App::DBBrowser::Table::Extensions::ColumnAliases->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $col_aliases = $new_ca->column_aliases( $sql, $qt_cols );
            if ( ! defined $col_aliases ) {
                return if @$extensions == 1;
                next EXTENSION;
            }
            return $col_aliases;
        }
    }
}






1;


__END__

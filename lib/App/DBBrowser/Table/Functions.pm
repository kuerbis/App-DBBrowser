package # hide from PAUSE
App::DBBrowser::Table::Functions;

use warnings;
use strict;
use 5.014;

use Scalar::Util qw( looks_like_number );

use List::MoreUtils qw( all minmax uniq );

use Term::Choose           qw();
use Term::Choose::LineFold qw( line_fold );
use Term::Choose::Util     qw( unicode_sprintf get_term_height get_term_width );
use Term::Form             qw();
use Term::Form::ReadLine   qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Functions::SQL;


sub new {
    my ( $class, $info, $options, $d ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $d
    }, $class;
}


sub __choose_columns {
    my ( $sf, $sql, $clause, $qt_cols, $info, $nested_func ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $const = '[c]'; # ### 
    my @pre = ( undef, $sf->{i}{ok}, $sf->{i}{menu_addition}, $const );
    my $menu = [ @pre, @$qt_cols ];
    my $subset = [];
    my @bu;

    COLUMNS: while ( 1 ) {
        my $fill_string = join( ',', @$subset );
        my $tmp_info = $info . "\n" . $sf->__nested_func_info( $nested_func, $fill_string );
        # Choose
        my @idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, info => $tmp_info, prompt => 'Columns:', meta_items => [ 0 .. $#pre - 1 ],
              no_spacebar => [ $#pre ], include_highlighted => 2, index => 1 }
        );
        if ( ! $idx[0] ) {
            if ( @bu ) {
                $subset = pop @bu;
                next COLUMNS;
            }
            return;
        }
        push @bu, [ @$subset ];
        if ( $menu->[$idx[0]] eq $sf->{i}{ok} ) {
            shift @idx;
            push @$subset, @{$menu}[@idx];
            if ( ! @$subset ) {
                return;
            }
            return $subset;
        }
        elsif ( $menu->[$idx[0]] eq $sf->{i}{menu_addition} ) {
            # recursion
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_col = $ext->complex_unit( $sql, $clause,  [ [ $sf->__nested_func_info( $nested_func, $fill_string ) ] ] );
            if ( ! defined $complex_col ) {
                next COLUMNS;
            }
            push @$subset, $complex_col;
        }
        elsif ( $menu->[$idx[0]] eq $const ) {
            my $rl_info = $tmp_info =~ s/\)\z/,?)/r;
            my $value = $tr->readline(
                'Value: ',
                { info => $rl_info }
            );
            if ( ! defined $value ) {
                next COLUMNS;
            }
            if ( ! looks_like_number $value ) {
                $value = $sf->{d}{dbh}->quote( $value );
            }
            push @$subset, $value;
        }
        else {
            push @$subset, @{$menu}[@idx];
        }
    }
}


sub __choose_a_column {
    my ( $sf, $sql, $clause, $qt_cols, $info, $nested_func ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    $info .= "\n" . $sf->__nested_func_info( $nested_func, '?' );
    my @pre = ( undef, $sf->{i}{menu_addition} );

    while ( 1 ) {
        # Choose
        my $choice = $tc->choose(
            [ @pre, @$qt_cols ],
            { %{$sf->{i}{lyt_h}}, info => $info, prompt => 'Col:' }
        );
        if ( ! defined $choice ) {
            return;
        }
        elsif ( $choice eq $sf->{i}{menu_addition} ) {
            # recursion
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_col = $ext->complex_unit( $sql, $clause, $nested_func );
            if ( ! defined $complex_col ) {
                next;
            }
            return $complex_col;
        }
        return $choice;
    }
}


sub __nested_func_info {
    my ( $sf, $nested_func, $fill_string ) = @_;
    return join( '', map { $_ . '(' } @$nested_func ) . ( $fill_string // '' ) . ( ')' x @$nested_func );
}


sub col_function {
    my ( $sf, $sql, $clause, $nested_func ) = @_;
    $nested_func //= [];
    my $parent;
    if ( ref $nested_func->[0] eq 'ARRAY' ) {
        $parent = ( shift @$nested_func )->[0];
    }
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $driver = $sf->{i}{driver};
    my $qt_cols;
    if ( $clause eq 'select' && ( @{$sql->{group_by_cols}} || @{$sql->{aggr_cols}} ) ) {
        $qt_cols = [ @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} ];
    }
    elsif ( $clause eq 'having' ) {
        $qt_cols = [ @{$sql->{aggr_cols}} ];
    }
    else {
        $qt_cols = [ @{$sql->{cols}} ];
    }
    my @one_col_functions = ( 'TRIM', 'LTRIM', 'RTRIM', 'UPPER', 'LOWER', 'OCTET_LENGTH', 'CHAR_LENGTH' );
    my $Now               = 'NOW';
    my $Cast              = 'CAST';
    my $Concat            = 'CONCAT';
    my $Coalesce          = 'COALESCE';
    my $Epoch_to_Date     = 'EPOCH_TO_DATE';
    my $Epoch_to_DateTime = 'EPOCH_TO_DATETIME';
    my $Replace           = 'REPLACE';
    my $Substr            = 'SUBSTR';
    my $Round             = 'ROUND';
    my $Truncate          = 'TRUNCATE';
    my @functions = ( @one_col_functions, $Now, $Cast, $Concat, $Coalesce, $Epoch_to_Date, $Epoch_to_DateTime, $Replace, $Substr, $Round, $Truncate );
    my $joined_one_col_functions = join( '|', @one_col_functions );
    my $prefix = '- ';
    my @pre = ( undef );
    my $menu = [ @pre, map( $prefix . lc $_, @functions ) ];
    my $info = $ax->get_sql_info( $sql );

    SCALAR_FUNCTION: while( 1 ) {
        my $tmp_info = $info;
        if ( length $parent ) {
            $tmp_info .= "\n" . $parent;
        }
        if ( @$nested_func ) {
            $tmp_info .= "\n" . $sf->__nested_func_info( $nested_func, '?' );
        }
        # Choose
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, info => $tmp_info, prompt => '', index => 1, undef => '<=' }
        );
        if ( ! defined $idx || ! defined $menu->[$idx] ) {
            return;
        }
        my $func = $functions[$idx-@pre];
        push @$nested_func, $func;

        my $function_stmt;
        if ( $func eq $Now ) {
            $function_stmt =  $sf->__func_with_no_col( $func );
        }
        elsif ( $func eq $Concat || $func eq $Coalesce ) {
            my $chosen_cols = $sf->__choose_columns( $sql, $clause, $qt_cols, $info, $nested_func );
            if ( ! defined $chosen_cols ) {
                if ( @$nested_func == 1 ) {
                    $nested_func = [];
                    next SCALAR_FUNCTION;
                }
                pop @$nested_func;
                return;
            }
            if ( $func eq $Concat ) {
                $function_stmt = $sf->__func_Concat( $sql, $chosen_cols, $func, $info );
            }
            elsif ( $func eq $Coalesce ) {
                $function_stmt = $sf->__func_Coalesce( $sql, $chosen_cols, $func );
            }
        }
        else {
            my $chosen_col = $sf->__choose_a_column( $sql, $clause, $qt_cols, $info, $nested_func );
            if ( ! defined $chosen_col ) {
                if ( @$nested_func == 1 ) {
                    $nested_func = [];
                    next SCALAR_FUNCTION;
                }
                pop @$nested_func;
                return;
            }
            if ( $func =~ /^(?:$joined_one_col_functions)\z/ ) {
                $function_stmt = $sf->__func_with_col( $sql, $chosen_col, $func );
            }
            elsif ( $func eq $Cast ) {
                my $prompt = 'Data type';
                my $history = [ 'VARCHAR', 'INT', 'NUMBER' ];
                $function_stmt = $sf->__func_with_col_and_arg( $sql, $chosen_col, $func, $info, $prompt, $history );
            }
            elsif ( $func =~ /^(?:$Round|$Truncate)\z/ ) {
                my $prompt = 'Decimal places';
                my $history = [ 0 .. 9 ];
                $function_stmt = $sf->__func_with_col_and_arg( $sql, $chosen_col, $func, $info, $prompt, $history );
            }
            elsif ( $func eq $Replace ) {
                my $prompts = [ 'From string', 'To string' ];
                $function_stmt = $sf->__func_with_col_and_2args( $sql, $chosen_col, $func, $info, $prompts );
            }
            elsif ( $func eq $Substr ) {
                my $prompts = [ 'StartPos', 'Length' ];
                my $history = [ [ 1 .. 100 ], [ 1 .. 100 ] ];
                $function_stmt = $sf->__func_with_col_and_2args( $sql, $chosen_col, $func, $info, $prompts, $history );
            }
            elsif ( $func =~ /^(?:$Epoch_to_Date|$Epoch_to_DateTime)\z/ ) {
                $function_stmt = $sf->__func_Date_Time( $sql, $chosen_col, $func, $info );
            }
        }
        if ( ! $function_stmt ) {
            return;
        }
        return $function_stmt;
    }
}

sub __func_with_no_col {
    my ( $sf, $func ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $function_stmt = $fsql->function_with_no_col( $func );
    return $function_stmt;
}


sub __func_with_col {
    my ( $sf, $sql, $chosen_col, $func ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $function_stmt = $fsql->function_with_col( $func, $chosen_col );
    return $function_stmt;
}


sub __func_with_col_and_arg {
    my ( $sf, $sql, $chosen_col, $func, $info, $prompt, $history ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    $info .= "\n" . $func . '(' . $chosen_col . ',?)';
    my $value = $tr->readline(
        $prompt . ': ',
        { info => $info, history => $history }
    );
    if ( ! length $value ) {
        return;
    }
    my $function_stmt = $fsql->function_with_col_and_arg( $func, $chosen_col, $value );
    return $function_stmt;
}


sub __func_with_col_and_2args {
    my ( $sf, $sql, $chosen_col, $func, $info, $prompts, $history ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my ( $arg1, $arg2 );
    my $count = 0;

    while( 1 ) {
        my $tmp_info = $info . "\n" . $func . '(' . $chosen_col . ',?,?)';
        #my $tmp_info = $info . "\n" . sprintf "%s(%s,%s,%s)", $func, $chosen_col, $prompts->[0], $prompts->[1];
        if ( ++$count > 3 ) {
            $arg1 = undef;
        }
        $arg1 = $tr->readline(
            $prompts->[0] . ': ',
            { info => $tmp_info, history => $history->[0], default => $arg1 }
        );
        if ( ! length $arg1 ) {
            return;
        }
        $tmp_info =~ s/\?,\?\)\z/$arg1,?)/;
        #$tmp_info .= "\n" . $prompts->[0] . ': ' . $arg1;
        $arg2 = $tr->readline(
            $prompts->[1] . ': ',
            { info => $tmp_info, history => $history->[1] }
        );
        if ( ! length $arg2 ) {
            next;
        }
        last;
    }
    my $function_stmt = $fsql->function_with_col_and_2args( $func, $chosen_col, $arg1, $arg2 );
    return $function_stmt;
}


sub __func_Concat {
    my ( $sf, $sql, $chosen_cols, $func, $info ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    $info .= "\n" . 'Concat(' . join( ',', @$chosen_cols ) . ')';
    my $sep = $tr->readline(
        'Separator: ',
        { info => $info }
    );
    if ( ! defined $sep ) {
        return;
    }
    my $function_stmt = $fsql->concatenate( $chosen_cols, $sep );
    return $function_stmt;
}


sub __func_Coalesce {
    my ( $sf, $sql, $chosen_cols, $func ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $function_stmt = $fsql->coalesce( $chosen_cols );
    return $function_stmt;
}


sub __func_Date_Time {
    my ( $sf, $sql, $chosen_col, $func, $info ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $stmt = $sf->__select_stmt( $sql, $chosen_col, $chosen_col );
    my $epochs = $sf->{d}{dbh}->selectcol_arrayref( $stmt, { Columns => [1], MaxRows => 500 }, @{$sql->{where_args}//[]} );
    my $avail_h = get_term_height() - ( $info =~ tr/\n// + 10 ); # 10 = "\n" + col_name +  '...' + prompt + (4 menu) + empty row + footer
    my $max_examples = 50;
    $max_examples = ( minmax $max_examples, $avail_h, scalar( @$epochs ) )[0];
    my ( $function_stmt, $example_results ) = $sf->__guess_interval( $sql, $func, $chosen_col, $epochs, $max_examples, $info );

    while ( 1 ) {
        if ( ! defined $function_stmt ) {
            ( $function_stmt, $example_results ) = $sf->__choose_interval( $sql, $func, $chosen_col, $epochs, $max_examples, $info );
            if ( ! defined $function_stmt ) {
                return;
            }
            return $function_stmt;
        }
        my @info_rows = ( $chosen_col );
        push @info_rows, @$example_results;
        if ( @$epochs > $max_examples ) {
            push @info_rows, '...';
        }
        my $tmp_info = $info . "\n" . join( "\n", @info_rows );
        # Choose
        my $choice = $tc->choose(
            [ undef, $sf->{i}{_confirm} ],
            { %{$sf->{i}{lyt_v}}, info => $tmp_info, layout => 2, keep => 3 }
        );
        if ( ! defined $choice ) {
            $function_stmt = undef;
            $example_results = undef;
            next;
        }
        else {
            return $function_stmt;
        }
    }
}


sub __select_stmt {
    my ( $sf, $sql, $select_col, $where_col ) = @_;
    my $stmt;
    if ( length $sql->{where_stmt} ) {
        $stmt = "SELECT $select_col FROM $sql->{table} " . $sql->{where_stmt} . " AND $where_col IS NOT NULL";
    }
    else {
        $stmt = "SELECT $select_col FROM $sql->{table} WHERE $where_col IS NOT NULL";
    }
    if ( $sf->{i}{driver} =~ /^(?:Firebird|DB2|Oracle)\z/ ) {
        $stmt .= " " . $sql->{offset_stmt} if $sql->{offset_stmt};
        $stmt .= " " . $sql->{limit_stmt}  if $sql->{limit_stmt};
    }
    else {
        $stmt .= " " . $sql->{limit_stmt}  if $sql->{limit_stmt};
        $stmt .= " " . $sql->{offset_stmt} if $sql->{offset_stmt};
    }
    return $stmt;
}


sub __interval_to_converted_epoch {
    my ( $sf, $sql, $func, $max_examples, $chosen_col, $interval ) = @_;
    my $fsql = App::DBBrowser::Table::Functions::SQL->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $function_stmt;
    if ( $func eq 'EPOCH_TO_DATETIME' ) {
        $function_stmt = $fsql->epoch_to_datetime( $chosen_col, $interval );
    }
    else {
        $function_stmt = $fsql->epoch_to_date( $chosen_col, $interval );
    }
    my $stmt = $sf->__select_stmt( $sql, $function_stmt, $chosen_col );
    my $example_results = $sf->{d}{dbh}->selectcol_arrayref(
        $stmt,
        { Columns => [1], MaxRows => $max_examples },
        @{$sql->{where_args}//[]}
    );
    return $function_stmt, [ map { $_ // 'undef' } @$example_results ];
}


sub __guess_interval {
    my ( $sf, $sql, $func, $chosen_col, $epochs, $max_examples ) = @_;
    my ( $function_stmt, $example_results );
    if ( ! eval {
        my %count;

        for my $epoch ( @$epochs ) {
            if ( ! looks_like_number( $epoch ) ) {
                return;
            }
            ++$count{length( $epoch )};
        }
        if ( keys %count != 1 ) {
            return;
        }
        my $epoch_w = ( keys %count )[0];
        my $interval;
        if ( $epoch_w <= 10 ) {
            $interval = 1;
        }
        elsif ( $epoch_w <= 13 ) {
            $interval = 1_000;
        }
        else {
            $interval = 1_000_000;
        }
        ( $function_stmt, $example_results ) = $sf->__interval_to_converted_epoch( $sql, $func, $max_examples, $chosen_col, $interval );

        1 }
    ) {
        return;
    }
    else {
        return $function_stmt, $example_results;
    }
}


sub __choose_interval {
    my ( $sf, $sql, $func, $chosen_col, $epochs, $max_examples, $info  ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $epoch_formats = [
        [ '      Seconds',  1             ],
        [ 'Milli-Seconds',  1_000         ],
        [ 'Micro-Seconds',  1_000_000     ],
    ];
    my $old_idx = 0;

    CHOOSE_INTERVAL: while ( 1 ) {
        my @example_epochs = ( $chosen_col );
        if ( @$epochs > $max_examples ) {
            push @example_epochs, @{$epochs}[0 .. $max_examples - 1];
            push @example_epochs, '...';
        }
        else {
            push @example_epochs, @$epochs;
        }
        my $epoch_info = $info . "\n" . join( "\n", @example_epochs );
        my @pre = ( undef );
        my $menu = [ @pre, map( $_->[0], @$epoch_formats ) ];
        # Choose
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, prompt => 'Choose interval:', info => $epoch_info, default => $old_idx,
                index => 1, keep => @$menu + 1, layout => 2, undef => '<<' }
        );
        if ( ! $idx ) {
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx = 0;
                next SCALAR_FUNCTION;
            }
            $old_idx = $idx;
        }
        my $interval = $epoch_formats->[$idx-@pre][1];
        my ( $function_stmt, $example_results );
        if ( ! eval {
            ( $function_stmt, $example_results ) = $sf->__interval_to_converted_epoch( $sql, $func, $max_examples, $chosen_col, $interval );
            if ( ! $function_stmt || ! $example_results ) {
                die "No results!";
            }
            1 }
        ) {
            my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
            $ax->print_error_message( $@ );
            next CHOOSE_INTERVAL;
        }
        unshift @$example_results, $chosen_col;
        if ( @$epochs > $max_examples ) {
            push @$example_results, '...';
        }
        my $result_info = $info . "\n" . join( "\n", @$example_results );
        # Choose
        my $choice = $tc->choose(
            [ undef, $sf->{i}{_confirm} ],
            { %{$sf->{i}{lyt_v}}, info => $result_info, layout => 2, keep => 3 }
        );
        if ( ! $choice ) {
            next CHOOSE_INTERVAL;
        }
        return $function_stmt, $example_results;
    }
}




1;


__END__

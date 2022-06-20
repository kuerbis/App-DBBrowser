package # hide from PAUSE
App::DBBrowser::Table::Functions;

use warnings;
use strict;
use 5.014;

use List::MoreUtils qw( all );

use Term::Choose           qw();
use Term::Choose::LineFold qw( print_columns line_fold );
use Term::Choose::Util     qw( unicode_sprintf get_term_height get_term_width );
use Term::Form             qw();
use Term::Form::ReadLine   qw();

use App::DBBrowser::DB;
#use App::DBBrowser::Opt::Set; # required


sub new {
    my ( $class, $info, $options, $data ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $data
    }, $class;
}


sub __choose_columns {
    my ( $sf, $func, $cols, $multi_col ) = @_;
    if ( $multi_col ) {
        my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
        # Choose
        my $subset = $tu->choose_a_subset(
            $cols,
            { info => 'Function: ' . $func . "\n", cs_label => 'Columns: ', layout => 1, cs_separator => ',', keep_chosen => 1, confirm => $sf->{i}{ok}, back => '<<' }
        );
        if ( ! @{$subset//[]} ) {
            return;
        }
        return $subset;
    }
    else {
        my $tc = Term::Choose->new( $sf->{i}{tc_default} );
        # Choose
        my $choice = $tc->choose(
            [ undef, @$cols ],
            { %{$sf->{i}{lyt_h}}, info => 'Function: ' . $func . "\n", prompt => 'Choose column: ' }
        );
        if ( ! defined $choice ) {
            return;
        }
        return [ $choice ];
    }
}

sub __get_multi_col_info_rows {
    my ( $sf, $chosen_cols ) = @_;
    my $multi_col_info_rows = [];
    if ( @$chosen_cols > 1 ) {
        push @$multi_col_info_rows, line_fold( 'Columns: ' . join( ', ', @$chosen_cols ), get_term_width, { subseq_tab => ' ' x 13 } );
        push @$multi_col_info_rows, ''; #
    }
    return $multi_col_info_rows;
}


sub __get_info_string {
    my ( $sf, $chosen_cols, $func, $col_with_func, $incomplete ) = @_;
    my @tmp_info = ();
    my $multi_col_info_rows = $sf->__get_multi_col_info_rows( $chosen_cols );
    if ( @$multi_col_info_rows ) {
        push @tmp_info, @$multi_col_info_rows;
    }
    my $uc_func = uc $func;
    push @tmp_info, ( map { my $n = $_ =~ s/$uc_func/$func/re; ( ' ' x 10 ) . $n } @$col_with_func );
    if ( defined $incomplete ) {
        push @tmp_info, $incomplete;
    }
    else {
        $tmp_info[-1] =~ s/^\s{9}/Function:/;
    }
    push @tmp_info, ''; #
    my $info = join "\n", @tmp_info;
    return $info;
}


sub __confirm_all {
    my ( $sf, $chosen_cols, $info ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    if ( @$chosen_cols == 1 ) {
        return 1;
    }
    else {
        # Choose
        my $choice = $tc->choose(
            [ undef, $sf->{i}{_confirm} ],
            { %{$sf->{i}{lyt_v}}, info => $info, layout => 2, keep => 3 }
        );
        if ( ! $choice ) {
            return;
        }
        elsif ( $choice eq $sf->{i}{_confirm} ) {
            return 1;
        }
    }
}


sub col_function {
    my ( $sf, $sql, $clause ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $changed = 0;
    my $cols;
    if ( $clause eq 'select' && ( @{$sql->{group_by_cols}} || @{$sql->{aggr_cols}} ) ) {
        $cols = [ @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} ];
    }
    elsif ( $clause eq 'having' ) {
        $cols = [ @{$sql->{aggr_cols}} ];
    }
    else {
        $cols = [ @{$sql->{cols}} ];
    }
    my @simple_functions = (
        'Bit_Length',
        'Char_Length',
        'Upper',
        'Lower',
        'Trim',
        'LTrim',
        'RTrim'
    );
    my $Cast              = 'Cast';
    my $Concat            = 'Concat';
    my $Epoch_to_Date     = 'Epoch_to_Date';
    my $Epoch_to_DateTime = 'Epoch_to_DateTime';
    my $Replace           = 'Replace';
    my $Round             = 'Round';
    my $Truncate          = 'Truncate';
    my @functions = ( @simple_functions, $Cast, $Concat, $Epoch_to_Date, $Epoch_to_DateTime, $Replace, $Round, $Truncate );
    my $joined_simple_functions = join( '|', @simple_functions );
    my $prefix = '  ';
    my @pre = ( undef );
    my $menu = [ @pre, map( $prefix . $_, sort @functions ) ];
    my $old_idx = 0;

    CHOOSE_FUNCTION: while( 1 ) {
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, prompt => 'Funktion:', default => $old_idx, index => 1, undef => '  <=' } # <= BACK
        );
        if ( ! defined $idx || ! defined $menu->[$idx] ) {
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx = 0;
                next CHOOSE_FUNCTION;
            }
            $old_idx = $idx;
        }
        my $func = $menu->[$idx] =~ s/^\Q${prefix}\E//r;
        my $multi_col = 0;
        if (   $clause eq 'select'
            || $clause eq 'where' && $sql->{where_stmt} =~ /\s(?:NOT\s)?IN\s*\z/
            || $func eq $Concat
        ) {
            $multi_col = 1;
        }
        my $col_with_func = [];
        if ( $func =~ /^(?:$joined_simple_functions)\z/ ) {
            $col_with_func = $sf->__func_with_col( $sql, $cols, $func, $multi_col );
        }
        elsif ( $func eq $Cast ) {
            $col_with_func = $sf->__func_with_col_and_arg( $sql, $cols, $func, $multi_col, 'Data type: ', [] );
        }
        elsif ( $func =~ /^(?:$Round|$Truncate)\z/ ) {
            my $history = [ reverse 0 .. 9 ];
            $col_with_func = $sf->__func_with_col_and_arg( $sql, $cols, $func, $multi_col, 'Decimal places: ', $history  );
        }
        elsif ( $func eq $Concat ) {
            $col_with_func = $sf->__func_Concat( $sql, $cols, $func, $multi_col );
        }
        elsif ( $func eq $Replace ) {
            $col_with_func = $sf->__func_Replace( $sql, $cols, $func, $multi_col );
        }

        elsif ( $func eq $Epoch_to_Date || $func eq $Epoch_to_DateTime ) {
            $col_with_func = $sf->__func_Date_Time( $sql, $cols, $func, $multi_col );
        }
        if ( ! $col_with_func ) {
            next CHOOSE_FUNCTION;
        }
        return $col_with_func;
    }
}


sub __func_with_col {
    my ( $sf, $sql, $cols, $func, $multi_col ) = @_;
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $chosen_cols = $sf->__choose_columns( $func, $cols, $multi_col );
    if ( ! defined $chosen_cols ) {
        return;
    }
    my $col_with_func = [];
    for my $qt_col ( @$chosen_cols ) {
        push @$col_with_func, $plui->function_with_col( $func, $qt_col );
    }
    return $col_with_func;
}


sub __func_with_col_and_arg {
    my ( $sf, $sql, $cols, $func, $multi_col, $prompt, $history ) = @_;
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $chosen_cols = $sf->__choose_columns( $func, $cols, $multi_col );
    if ( ! defined $chosen_cols ) {
        return;
    }
    my $col_with_func = [];
    my $value;
    my $i = 0;

    COLUMN: while ( 1 ) {
        my $qt_col = $chosen_cols->[$i];
        my $incomplete = 'Function: ' . $func . '(' . $qt_col . ', ? )';
        my $info = $sf->__get_info_string( $chosen_cols, $func, $col_with_func, $incomplete );
        my $readline = $tr->readline( $prompt, { info => $info, history => $history } );
        if ( ! length $readline ) {
            if ( $i == 0 ) {
                return;
            }
            else {
                $i--;
                pop @$col_with_func;
                next COLUMN;
            }
        }
        else {
            $value = $readline;
            push @$col_with_func, $plui->function_with_col_and_arg( $func, $qt_col, $value );
            $i++;
            if ( $i > $#$chosen_cols ) {
                my $info = $sf->__get_info_string( $chosen_cols, $func, $col_with_func );
                my $ok = $sf->__confirm_all( $chosen_cols, $info );
                if ( ! $ok ) {
                    $value = undef;
                    $col_with_func = [];
                    $i = 0;
                    next COLUMN;
                }
                else {
                    return $col_with_func;
                }
            }
        }
    }
}


sub __func_Concat {
    my ( $sf, $sql, $cols, $func, $multi_col ) = @_;
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $subset = $sf->__choose_columns( $func, $cols, $multi_col );
    if ( ! defined $subset ) {
        return;
    }
    my $info = 'Function: Concat( ' . join( ',', @$subset ) . ' )' . "\n";
    my $sep = $tr->readline(
        'Separator: ',
        { info => $info }
    );
    if ( ! defined $sep ) {
        return;
    }
    my $col_with_func = [ $plui->concatenate( $subset, $sep ) ];
    return $col_with_func;
}


sub __func_Replace {
    my ( $sf, $sql, $cols, $func, $multi_col ) = @_;
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $fields = [
        [ 'from str', ],
        [ 'to   str', ],
    ];
    my $chosen_cols = $sf->__choose_columns( $func, $cols, $multi_col );
    if ( ! defined $chosen_cols ) {
        return;
    }
    my $col_with_func = [];
    my $i = 0;

    COLUMN: while ( 1 ) {
        my $qt_col = $chosen_cols->[$i];
        my $incomplete = 'Function: ' . $func . '(' . $qt_col . ', ? , ? )';
        my $info = $sf->__get_info_string( $chosen_cols, $func, $col_with_func, $incomplete );
        my $form = $tf->fill_form(
            $fields,
            { info => $info, prompt => '', auto_up => 2,
            confirm => 'CONFIRM  ', back => 'BACK     ' }
        );
        if ( ! $form ) { # if ( ! defined $form->[0][1] ) {
            if ( $i == 0 ) {
                return;
            }
            else {
                $i--;
                pop @$col_with_func;
                next COLUMN;
            }
        }
        else {
            my $string_to_replace =  $sf->{d}{dbh}->quote( $form->[0][1] );
            my $replacement_string = $sf->{d}{dbh}->quote( $form->[1][1] );
            push @$col_with_func, $plui->replace( $qt_col, $string_to_replace, $replacement_string );
            $fields = $form;
            $i++;
            if ( $i > $#$chosen_cols ) {
                my $info = $sf->__get_info_string( $chosen_cols, $func, $col_with_func );
                my $ok = $sf->__confirm_all( $chosen_cols, $info );
                if ( ! $ok ) {
                    $fields = [
                        [ 'from str', ],
                        [ 'to   str', ],
                    ];
                    $col_with_func = [];
                    $i = 0;
                    next COLUMN;
                }
                else {
                    return $col_with_func;
                }
            }
        }
    }
}


sub __func_Date_Time {
    my ( $sf, $sql, $cols, $func, $multi_col ) = @_;
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $chosen_cols = $sf->__choose_columns( $func, $cols, $multi_col );
    if ( ! defined $chosen_cols ) {
        return;
    }
    my @tmp_top = ();
    my $multi_col_info_rows = $sf->__get_multi_col_info_rows( $chosen_cols );
    if ( @$multi_col_info_rows ) {
        push @tmp_top, @$multi_col_info_rows;
    }
    push @tmp_top, 'Function: ' . $func;
    push @tmp_top, '';
    my $max_items_v_info_print = 20;
    my $len_epoch = {};
    my $auto_interval = {};
    my $longest_key = 0;
    # INTERVAL AUTOMATICALLY:

    for my $qt_col ( @$chosen_cols ) {
        my $first_epochs = $sf->{d}{dbh}->selectcol_arrayref(
            "SELECT $qt_col FROM $sql->{table} WHERE $qt_col IS NOT NULL",
            { Columns=>[1], MaxRows => 200 }
        );

        LEN_EPOCH: for my $epoch ( @$first_epochs ) {
            if ( $epoch !~ /^\d+\z/ ) {
                ++$len_epoch->{$qt_col}{not_an_integer};
                next LEN_EPOCH;
            }
            ++$len_epoch->{$qt_col}{ '1' x length( $epoch ) };
        }
    }

    for my $qt_col ( keys %$len_epoch ) {
        if ( keys %{$len_epoch->{$qt_col}} == 1 ) {
            my $key = ( keys %{$len_epoch->{$qt_col}} )[0];
            if ( $key eq 'not_an_integer' ) {
                next;
            }
            $auto_interval->{$qt_col} = $key;
            if ( print_columns( $qt_col ) > $longest_key ) {
                $longest_key = print_columns( $qt_col );
            }
        }
    }
    if ( $longest_key > 30 ) {
        $longest_key = 30;
    }
    my $maxrows = 25;
    if ( all { exists $auto_interval->{$_} } @$chosen_cols ) {
        # CONFIRM AUTOMATIC INTERVAL:
        my $col_with_func = [];
        my @tmp_info = @tmp_top;
        for my $qt_col ( @$chosen_cols ) {
            my $div = 10 ** ( length( $auto_interval->{$qt_col} ) - 10 );
            my ( $converted_epoch, $first_dates );
            if ( ! eval {
                ( $converted_epoch, $first_dates ) = $sf->__interval_to_converted_epoch( $sql, $func, $maxrows, $qt_col, $div );
                1 }
            ) {
                @tmp_info = @tmp_top;
                chomp( my $err = $@ );
                push @tmp_info, $err;
                $col_with_func = [];
                last;
            }
            push @$col_with_func, $converted_epoch;
            my $info_row = unicode_sprintf( $qt_col, $longest_key, { right_justify => 0 } ) . ': ';
            if ( @$first_dates > $max_items_v_info_print ) {
                $info_row .= join( ', ', @{$first_dates}[0 .. $max_items_v_info_print - 1] ) . ', ...';
            }
            else {
                $info_row .= join( ', ', @$first_dates );
            }
            push @tmp_info, $info_row;
        }
        push @tmp_info, '';
        my $info = join( "\n", @tmp_info );
        # Choose
        my $choice = $tc->choose(
            [ undef, $sf->{i}{_confirm} ],
            { %{$sf->{i}{lyt_v}}, info => $info, tabs_info => [ 0, $longest_key + 2 ], layout => 2, prompt => 'Choose:' }
        );
        if ( ! $choice ) {
            $auto_interval = {};
        }
        elsif ( $choice eq $sf->{i}{_confirm} ) {
            return $col_with_func;
        }
    }
    # INTERVAL MANUALLY:
    my $col_with_func = [];
    my @all_first_dates;
    my $i = 0;

    COLUMN: while ( 1 ) {
        my $qt_col = $chosen_cols->[$i];

        GET_INTERVAL: while ( 1 ) {
            my @top = @tmp_top;
            push @top, $qt_col . ':';
            my $info_rows_count = get_term_height() - ( @top + 8);
            my $div;
            if ( $auto_interval->{$qt_col} ) {
                my $interval = ( keys %{$len_epoch->{$qt_col}} )[0];
                $div = 10 ** ( length( $interval ) - 10 );
            }
            else {
                my $first_epochs = $sf->{d}{dbh}->selectcol_arrayref(
                    "SELECT $qt_col FROM $sql->{table} WHERE $qt_col IS NOT NULL",
                    { Columns=>[1], MaxRows => $maxrows }
                );
                if ( @$first_epochs < $info_rows_count ) {
                    $info_rows_count = @$first_epochs;
                }
                my @tmp_info = @top;
                push @tmp_info, @{$first_epochs}[0 .. $info_rows_count - 1];
                push @tmp_info, '...';
                my $epoch_formats = [
                    [ '      Seconds',  1             ],
                    [ 'Milli-Seconds',  1_000         ],
                    [ 'Micro-Seconds',  1_000_000     ],
                    [ ' Nano-Seconds',   1_000_000_000 ],
                ];
                my $menu = [ undef, map( $_->[0], @$epoch_formats ) ];
                my $info = join( "\n", @tmp_info );
                # Choose
                my $idx = $tc->choose( # menu-memory
                    $menu,
                    { %{$sf->{i}{lyt_v}}, prompt => 'Choose interval:', info => $info,
                      index => 1, keep => 7, layout => 2, undef => '<<' }
                );
                if ( ! $idx ) {
                    if ( $i == 0 ) {
                        return;
                    }
                    else {
                        $i--;
                        pop @$col_with_func;
                        pop @all_first_dates;
                        next COLUMN;
                    }
                }
                $div = $epoch_formats->[$idx-1][1];
            }
            # CONFIRM MANUAL INTERVAL:
            my ( $converted_epoch, $first_dates );
            if ( ! eval {
                ( $converted_epoch, $first_dates ) = $sf->__interval_to_converted_epoch( $sql, $func, $maxrows, $qt_col, $div );
                1 }
            ) {
                $ax->print_error_message( $@ );
                next GET_INTERVAL;
            }
            if ( @$first_dates < $info_rows_count ) {
                $info_rows_count = @$first_dates;
            }
            my @tmp_info = @top;
            push @tmp_info, @{$first_dates}[0 .. $info_rows_count - 1];
            push @tmp_info, '...';
            my $info = join( "\n", @tmp_info );
            # Choose
            my $choice = $tc->choose(
                [ undef, $sf->{i}{_confirm} ],
                { %{$sf->{i}{lyt_v}}, info => $info, layout => 2, keep => 3 }
            );
            if ( ! $choice ) {
                if ( exists $auto_interval->{$qt_col} ) {
                    delete $auto_interval->{$qt_col};
                }
                next GET_INTERVAL;
            }
            elsif ( $choice eq $sf->{i}{_confirm} ) {
                push @$col_with_func, $converted_epoch;
                push @all_first_dates, $first_dates;
                $i++;
                if ( $i > $#$chosen_cols ) {
                    if ( @$chosen_cols == 1 ) {
                        return $col_with_func;
                    }
                    else {
                        # CONFIRM ALL MANUAL INTERVALS:
                        my @tmp_info = @tmp_top;
                        for my $i ( 0 .. $#$chosen_cols ) {
                            my $qt_col = $chosen_cols->[$i];
                            my $first_dates = $all_first_dates[$i];
                            my $info_row = unicode_sprintf( $qt_col, $longest_key, { right_justify => 0 } ) . ': ';
                            if ( @$first_dates > $max_items_v_info_print ) {
                                $info_row .= join( ', ', @{$first_dates}[0 .. $max_items_v_info_print - 1] ) . ', ...';
                            }
                            else {
                                $info_row .= join( ', ', @$first_dates );
                            }
                            push @tmp_info, line_fold( $info_row, get_term_width, { subseq_tab => ' ' x ( $longest_key + 2 ) } );
                        }
                        push @tmp_info, '';
                        my $info = join( "\n", @tmp_info );
                        my $ok = $sf->__confirm_all( $chosen_cols, $info );
                        if ( ! $ok ) {
                            if ( exists $auto_interval->{$qt_col} ) {
                                delete $auto_interval->{$qt_col};
                            }
                            $col_with_func = [];
                            @all_first_dates = ();
                            $i = 0;
                            next COLUMN;
                        }
                        else {
                            return $col_with_func;
                        }
                    }
                }
                next COLUMN;
            }
        }
    }
}


sub __interval_to_converted_epoch { #
    my ( $sf, $sql, $func, $maxrows, $qt_col, $div ) = @_;
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $converted_epoch;
    if ( $func eq 'Epoch_to_DateTime' ) {
        $converted_epoch = $plui->epoch_to_datetime( $qt_col, $div );
    }
    else {
        $converted_epoch = $plui->epoch_to_date( $qt_col, $div );
    }
    my $first_dates = $sf->{d}{dbh}->selectcol_arrayref(
        "SELECT $converted_epoch FROM $sql->{table} WHERE $qt_col IS NOT NULL",
        { Columns=>[1], MaxRows => $maxrows }
    );
    return $converted_epoch, [ map { $_ // '__no_result__' } @$first_dates ];
}


1;


__END__

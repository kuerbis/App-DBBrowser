package # hide from PAUSE
App::DBBrowser::GetContent::Filter;

use warnings;
use strict;
use 5.010001;

use List::MoreUtils qw( any );

use Term::Choose           qw();
use Term::Choose::LineFold qw( line_fold print_columns );
use Term::Choose::Util     qw( insert_sep get_term_width unicode_sprintf );
use Term::Choose::Screen   qw( clear_screen );
use Term::Form             qw();

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data,
    };
    bless $sf, $class;
}


sub input_filter {
    my ( $sf, $sql ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $confirm       = '     OK';
    my $back          = '     <<';
    my $reset         = '    RESET';
    my $reparse       = '   REPARSE';
    my $choose_cols   = 'Choose_Cols';
    my $choose_rows   = 'Choose_Rows';
    my $range_rows    = 'Range_Rows';
    my $row_groups    = 'Row_Groups';
    my $remove_cell   = 'Remove_Cell';
    my $insert_cell   = 'Insert_Cell';
    my $append_col    = 'Append_Col';
    my $split_column  = 'Split_Column';
    my $s_and_replace = 'S_&_Replace';
    my $split_table   = 'Split_Table';
    my $merge_rows    = 'Merge_Rows';
    my $join_columns  = 'Join_Columns';
    my $fill_up_rows  = 'Fill_up_Rows';
    my $cols_to_rows  = 'Cols_to_Rows';
    my $empty_to_null = 'Empty_2_NULL';
    $sf->{empty_to_null} = $sf->{o}{insert}{'empty_to_null_' . $sf->{i}{gc}{source_type}};

    my $old_idx = 0;

    FILTER: while ( 1 ) {
        my $count_static_rows = 5; # prompt and 4 menu rows (fix width)
        $sf->__print_filter_info( $sql, $count_static_rows, undef );
        my $menu = [
            undef,    $choose_cols,   $choose_rows,  $range_rows, $row_groups,
            $confirm, $remove_cell,   $insert_cell,  $append_col, $split_column,
            $reset,   $s_and_replace, $split_table,  $merge_rows, $join_columns,
            $reparse, $empty_to_null, $fill_up_rows, $cols_to_rows,
        ];
        # Choose
        my $idx = $tc->choose(
            $menu,
            { prompt => 'Filter:', layout => 0, order => 0, max_width => 78, index => 1, default => $old_idx,
              undef => $back }
        );
        #$sf->__print_filter_info( $sql, $count_static_rows, undef );
        if ( ! $idx ) {
            $sql->{insert_into_args} = []; #
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx = 0;
                next FILTER;
            }
            $old_idx = $idx;
        }
        my $filter = $menu->[$idx];
        my $filter_str = sprintf( "Filter: %s", $filter );
        if ( $filter eq $reset ) {
            $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
            $sql->{insert_into_args} = [ map { [ @$_ ] } @{$sf->{i}{gc}{bu_insert_into_args}} ];
            $sf->{empty_to_null} = $sf->{o}{insert}{'empty_to_null_' . $sf->{i}{gc}{source_type}};
            delete $sf->{i}{prev_chosen_cols};
            next FILTER
        }
        elsif ( $filter eq $confirm ) {
            if ( $sf->{empty_to_null} ) {
                $sf->__print_filter_info( $sql, $count_static_rows, undef );
                no warnings 'uninitialized';
                $sql->{insert_into_args} = [ map { [ map { length ? $_ : undef } @$_ ] } @{$sql->{insert_into_args}} ];
            }
            return 1;
        }
        elsif ( $filter eq $reparse ) {
            my $count_static_rows = 9; # bigges settings sub-menu 9 rows
            $sf->__print_filter_info( $sql, $count_static_rows, undef );
            return -1;
        }
        elsif ( $filter eq $choose_cols  ) {
            $sf->__choose_columns( $sql, $filter_str );
        }
        elsif ( $filter eq $choose_rows ) {
            $sf->__choose_rows( $sql, $filter_str );
        }
        elsif ( $filter eq $range_rows ) {
            $sf->__range_of_rows( $sql, $filter_str );
        }
        elsif ( $filter eq $row_groups ) {
            $sf->__row_groups( $sql, $filter_str );
        }
        elsif ( $filter eq $remove_cell ) {
            $sf->__remove_cell( $sql, $filter_str );
        }
        elsif ( $filter eq $insert_cell ) {
            $sf->__insert_cell( $sql, $filter_str );
        }
        elsif ( $filter eq $append_col ) {
            $sf->__append_col( $sql, $filter_str );
        }
        elsif ( $filter eq $split_column ) {
            $sf->__split_column( $sql, $filter_str );
        }
        elsif ( $filter eq $s_and_replace ) {
            require App::DBBrowser::GetContent::Filter::SearchAndReplace;
            my $sr = App::DBBrowser::GetContent::Filter::SearchAndReplace->new( $sf->{i}, $sf->{o}, $sf->{d} );
            $sr->__search_and_replace( $sql, $filter_str );
        }
        elsif ( $filter eq $split_table ) {
            $sf->__split_table( $sql, $filter_str );
        }
        elsif ( $filter eq $merge_rows ) {
            $sf->__merge_rows( $sql, $filter_str );
        }
        elsif ( $filter eq $join_columns ) {
            $sf->__join_columns( $sql, $filter_str );
        }
        elsif ( $filter eq $fill_up_rows ) {
            $sf->__fill_up_rows( $sql, $filter_str );
        }
        elsif ( $filter eq $cols_to_rows ) {
            $sf->__transpose_rows_to_cols( $sql, $filter_str );
        }
        elsif ( $filter eq $empty_to_null ) {
            $sf->__empty_to_null( $sql );
        }
        $sf->{i}{occupied_term_height} = undef;
    }
}


sub __print_filter_info {
    my ( $sf, $sql, $count_static_rows, $horizontal_choices ) = @_;
    # $count_static_rows not realy static count - some could be line-folded if too long
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    print $sf->{i}{working} . "\r";
    $sf->{i}{occupied_term_height}  = 1; # "DATA:" prompt
    # ... insert_into_args rows
    $sf->{i}{occupied_term_height} += 1; # empty row
    $sf->{i}{occupied_term_height} += $count_static_rows;
    if ( defined $horizontal_choices ) {
        my $term_w = get_term_width();
        my $longest = 0;
        my @tmp_cols = map{ ! length $_ ? '--' : $_ } @$horizontal_choices;
        for my $col ( @tmp_cols ) {
            my $col_w = print_columns( $col );
            $longest = $col_w if $col_w > $longest;
        }
        if ( $longest * 2 + 2 > $term_w ) {
            $sf->{i}{occupied_term_height} += @tmp_cols;
        }
        else {
            my $r = print_columns( join( ' ' x 2, @tmp_cols ) ) / $term_w;
            if ( $r <= 1 ) {
                $sf->{i}{occupied_term_height} += 1;
            }
            else {
                my $joined_cols = $longest;
                my $cols_in_a_row = 1;
                while ( $joined_cols < $term_w ) {
                    $joined_cols += 2 + $longest;
                    ++$cols_in_a_row;
                }
                my $row_count = int( @tmp_cols / $cols_in_a_row );
                $row_count++ if @tmp_cols % $cols_in_a_row;
                $sf->{i}{occupied_term_height} += $row_count;
            }
        }
    }
    #$sf->{i}{occupied_term_height} += 1; # to keep bottom line empty
    my $indent = '';
    my $bu_stmt_types = [ @{$sf->{i}{stmt_types}} ];
    $sf->{i}{stmt_types} = [];
    my $rows = $ax->insert_into_args_info_format( $sql, $indent );
    $sf->{i}{stmt_types} = $bu_stmt_types;
    print clear_screen();
    say "DATA:";
    say $_ for @$rows;
    say "";
    print $sf->{i}{working} . "\r";
}


sub __choose_columns {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $aoa = $sql->{insert_into_args};
    my $empty_cells_of_col_count = $sf->__count_empty_cells_of_cols( $aoa );
    my $header = $sf->__prepare_header( $aoa, $empty_cells_of_col_count );
    my $count_static_rows = 2; # filter_str and cs_label
    $sf->__print_filter_info( $sql, $count_static_rows, [ '<<', $sf->{i}{ok}, @$header ] );
    my $row_count = @$aoa;
    my $col_count = @{$aoa->[0]};
    my $mark = [];
    for my $col_idx ( 0 .. $col_count - 1 ) {
        if ( $empty_cells_of_col_count->[$col_idx] < $row_count ) {
            push @$mark, $col_idx;
        }
    }
    if ( @$mark == $col_count ) {
        $mark = undef; # no preselect if all cols have entries
    }
    my $prev_chosen = $sf->{i}{prev_chosen_cols}{db}{ $sf->{d}{db} } // [];
    if ( @$prev_chosen && @$prev_chosen < @$header ) {
        my $mark2 = [];
        for my $i ( 0 .. $#{$header} ) {
            push @$mark2, $i if any { $_ eq $header->[$i] } @$prev_chosen;
        }
        $mark = $mark2 if @$mark2 == @$prev_chosen;
    }
    my $col_idx = $tu->choose_a_subset(
        $header,
        { cs_label => 'Cols: ', layout => 0, order => 0, mark => $mark, all_by_default => 1, index => 1,
            confirm => $sf->{i}{ok}, back => '<<', info => $filter_str, busy_string => $sf->{i}{working} }
    );
    if ( ! defined $col_idx ) {
        return;
    }
    $sf->{i}{prev_chosen_cols}{db}{ $sf->{d}{db} } = [ @{$header}[@$col_idx] ];
    $sql->{insert_into_args} = [ map { [ @{$_}[@$col_idx] ] } @$aoa ];
    return 1;
}


sub __choose_rows {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 4 + @$aoa; # filter_str, prompt, back, confirm and aoa
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my @pre = ( undef, $sf->{i}{ok} );
    my @stringified_rows;
    my $mark;
    {
        no warnings 'uninitialized';
        for my $i ( 0 .. $#$aoa ) {
            push @$mark, $i + @pre if length join '', @{$aoa->[$i]};
            push @stringified_rows, join ',', @{$aoa->[$i]};
        }
    }
    if ( @$mark == @stringified_rows ) {
        $mark = undef;
    }
    my $prompt = 'Choose rows:';
    $sql->{insert_into_args} = []; # $sql->{insert_into_args} refers to a new new empty array - this doesn't delete $aoa

    while ( 1 ) {
        # Choose
        my @idx = $tc->choose(
            [ @pre, @stringified_rows ],
            { %{$sf->{i}{lyt_v}}, prompt => $prompt, info => $filter_str, meta_items => [ 0 .. $#pre ],
              include_highlighted => 2, index => 1, undef => '<<', busy_string => $sf->{i}{working}, mark => $mark }
        );
        $sf->__print_filter_info( $sql, $count_static_rows, undef );
        if ( ! $idx[0] ) {
            $sql->{insert_into_args} = $aoa;
            return;
        }
        if ( $idx[0] == $#pre ) {
            shift @idx;
            for my $i ( @idx ) {
                my $idx = $i - @pre;
                push @{$sql->{insert_into_args}}, $aoa->[$idx];
            }
            if ( ! @{$sql->{insert_into_args}} ) {
                $sql->{insert_into_args} = $aoa;
            }
            return 1;
        }
        for my $i ( @idx ) {
            my $idx = $i - @pre;
            push @{$sql->{insert_into_args}}, $aoa->[$idx];
        }
    }
}

sub __range_of_rows {
    my ( $sf, $sql, $filter_str ) = @_;
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 3 + @$aoa; # filter_str, prompt, back and aoa
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    # Choose
    my $prompt = "Choose first row:";
    # Choose
    my $idx_first_row = $sf->__choose_a_row_idx( $aoa, $filter_str, $prompt );
    if ( ! defined $idx_first_row ) {
        return;
    }
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    $prompt = "Choose last row:";
    # Choose
    my $idx_last_row = $sf->__choose_a_row_idx( [ @{$aoa}[$idx_first_row .. $#$aoa] ], $filter_str, $prompt );
    if ( ! defined $idx_last_row ) {
        return;
    }
    if ( ! defined $idx_first_row || ! defined $idx_last_row ) {
        return;
    }
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    $idx_last_row += $idx_first_row;
    $sql->{insert_into_args} = [ @{$aoa}[$idx_first_row .. $idx_last_row] ];
    return 1;
}


sub __row_groups {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $aoa = $sql->{insert_into_args};
    my %group; # group rows by the number of cols
    for my $row_idx ( 0 .. $#$aoa ) {
        my $col_count = scalar @{$aoa->[$row_idx]};
        push @{$group{$col_count}}, $row_idx;
    }
    # sort keys by group size
    my @keys_sorted = sort { scalar( @{$group{$b}} ) <=> scalar( @{$group{$a}} ) } keys %group;
    my @choices_groups;
    my $len = length insert_sep( scalar @{$group{$keys_sorted[0]}}, $sf->{o}{G}{thsd_sep} );
    for my $col_count ( @keys_sorted ) {
        my $row_count = scalar @{$group{$col_count}};
        my $row_str = $row_count == 1 ? 'row  has ' : 'rows have';
        my $col_str = $col_count == 1 ? 'column ' : 'columns';
        push @choices_groups, sprintf '  %*s %s %2d %s',
            $len, insert_sep( $row_count, $sf->{o}{G}{thsd_sep} ), $row_str,
            $col_count, $col_str;
    }
    my $count_static_rows = 7 + @choices_groups; # filter_str, prompt, cs_label x 2, cs_end, back, confirm and choices_groups
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $prompt = 'Choose group:';
    my $idxs = $tu->choose_a_subset(
        \@choices_groups,
        { info => $filter_str, prompt => $prompt, layout => 3, index => 1, confirm => $sf->{i}{ok},
          back => '<<', all_by_default => 1, cs_label => "Chosen groups:\n", cs_separator => "\n",
          cs_end => "\n", busy_string => $sf->{i}{working} }
    );
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    if ( ! defined $idxs ) {
        return;
    }
    else {
        my $row_idxs = [];
        for my $idx ( @$idxs ) {
            push @$row_idxs, @{$group{ $keys_sorted[$idx] }};
        }
        $sql->{insert_into_args} = [ @{$aoa}[sort { $a <=> $b } @$row_idxs] ];
        return;
    }
}


sub __remove_cell {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $aoa = $sql->{insert_into_args};

    while ( 1 ) {
        my $count_static_rows = 3 + @$aoa; # filter_str, prompt, back and aoa
        $sf->__print_filter_info( $sql, $count_static_rows, undef );
        my $prompt = "Choose row:";
        # Choose
        my $row_idx = $sf->__choose_a_row_idx( $aoa, $filter_str, $prompt );
        if ( ! defined $row_idx ) {
            return;
        }
        $prompt = "Choose cell:";
        $count_static_rows = 2; # filter_str and prompt
        $sf->__print_filter_info( $sql, $count_static_rows, [ '<<', @{$aoa->[$row_idx]} ] );
        # Choose
        my $col_idx = $sf->__choose_a_column_idx( [ @{$aoa->[$row_idx]} ], $filter_str, $prompt );
        if ( ! defined $col_idx ) {
            next;
        }
        splice( @{$aoa->[$row_idx]}, $col_idx, 1 );
        $sql->{insert_into_args} = $aoa;
        return;
    }
}

sub _stringify_row { # used only once
    my ( $row ) = @_;
    no warnings 'uninitialized';
    my $stringified_row = '"' . join( '", "', @$row ) . '"';
    return $stringified_row;
}


sub __insert_cell {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $aoa = $sql->{insert_into_args};

    while ( 1 ) {
        my $count_static_rows = 3 + @$aoa; # filter_str, prompt, back and aoa
        $sf->__print_filter_info( $sql, $count_static_rows, undef );
        my $prompt = "Choose row:";
        # Choose
        my $row_idx = $sf->__choose_a_row_idx( $aoa, $filter_str, $prompt );
        if ( ! defined $row_idx ) {
            return;
        }
        my $cols = [ @{$aoa->[$row_idx]}, 'END_of_Row' ];
        $count_static_rows = 2; # prompt and filter_str
        $sf->__print_filter_info( $sql, $count_static_rows, [ '<<', @$cols ] );
        $prompt = "Insert cell before:";
        # Choose
        my $col_idx = $sf->__choose_a_column_idx( $cols, $filter_str, $prompt );
        if ( ! defined $col_idx ) {
            next;
        }
        my @row = @{$aoa->[$row_idx]};
        splice( @row, $col_idx, 0, '<*>' );
        my $str_row_with_placeholder = _stringify_row( \@row );
        $str_row_with_placeholder =~ s/"<\*>"/<*>/;
        my $term_w = get_term_width();
        my $label = 'Row: ';
        my @info = ( $filter_str );
        push @info, line_fold(
            $label . $str_row_with_placeholder, $term_w,
            { subseq_tab => ' ' x length $label, join => 0 }
        );
        $prompt = "<*>: ";
        $count_static_rows = @info + 1; # info and readline
        $sf->__print_filter_info( $sql, $count_static_rows, undef );
        # Readline
        my $cell = $tf->readline( $prompt, { info => join( "\n", @info ) } );
        splice( @{$aoa->[$row_idx]}, $col_idx, 0, $cell );
        $sql->{insert_into_args} = $aoa;
        return;
    }
}


sub __fill_up_rows {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 4; # filter_str, prompt, back and confirm
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $prompt = 'Fill up shorter rows?';
    my $ok = $tc->choose(
        [ undef, '- YES' ],
        { info => $filter_str, prompt => $prompt, index => 1, undef => '- NO', layout => 3 }
    );
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    if ( ! $ok ) {
        return;
    }
    my $longest_row = 0;
    for my $row ( @$aoa ) {
        my $col_count = scalar @$row;
        if ( $col_count > $longest_row ) {
            $longest_row = $col_count;
        }
    }
    my $last_idx = $longest_row - 1;
    for my $row ( @$aoa ) {
        $#$row = $last_idx;
    }
    $sql->{insert_into_args} = $aoa;
    return;
}


sub __append_col {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 4; # filter_str, prompt, back and confirm
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $prompt = 'Append an empty column?';
    my $ok = $tc->choose(
        [ undef, '- YES' ],
        { info => $filter_str, prompt => $prompt, index => 1, undef => '- NO', layout => 3 }
    );
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    if ( $ok ) {
        my $new_last_idx = $#{$aoa->[0]} + 1;
        for my $row ( @$aoa ) {
            $#$row = $new_last_idx;
        }
        $sql->{insert_into_args} = $aoa;
    }
    return;
}

sub __split_column {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $aoa = $sql->{insert_into_args};
    my $empty_cells_of_col_count =  $sf->__count_empty_cells_of_cols( $aoa );
    my $header = $sf->__prepare_header( $aoa, $empty_cells_of_col_count );
    my $count_static_rows = 2; # filter_str and prompt
    $sf->__print_filter_info( $sql, $count_static_rows, [ '<<', @$header ] );
    my $prompt = 'Choose column:';
    # Choose
    my $idx = $sf->__choose_a_column_idx( $header, $filter_str, $prompt );
    if ( ! defined $idx ) {
        return;
    }
    my $info = $filter_str;
    $prompt = "Split column \"$header->[$idx]\"";
    my $fields = [
        [ 'Pattern', ],
        [ 'Limit', ],
        [ 'Left trim', '\s+' ],
        [ 'Right trim', '\s+' ]
    ];
    my $c;
    $count_static_rows = 4 + @$fields; # filter_str, prompt, back, confirm and fields
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    # Fill_form
    my $form = $tf->fill_form(
        $fields,
        { info => $info, prompt => $prompt,
        auto_up => 2, confirm => $sf->{i}{confirm}, back => $sf->{i}{back} . '   ' }
    );
    if ( ! $form ) {
        return;
    }
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    my ( $pattern, $limit, $left_trim, $right_trim ) = map { $_->[1] } @$form;
    $pattern //= '';

    for my $row ( @$aoa ) { # modifies $aoa
        my $col = splice @$row, $idx, 1;
        my @split_col;
        if ( length $limit ) {
            @split_col = split /$pattern/, $col, $limit;
        }
        else {
            @split_col = split /$pattern/, $col;
        }
        for my $c ( @split_col ) {
            $c =~ s/^$left_trim//   if length $left_trim;
            $c =~ s/$right_trim\z// if length $right_trim;
        }
        splice @$row, $idx, 0, @split_col;
    }
    $sql->{insert_into_args} = $aoa;
}


sub __split_table {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $aoa = $sql->{insert_into_args};
    my $digits = length( scalar @{$aoa->[0]} );
    my $count_static_rows = 4 + $digits; # filter_str, prompt, back, confirm and digits
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    # Choose
    my $col_count = $tu->choose_a_number(
        $digits,
        { info => $filter_str, cs_label => 'Number columns new table: ', small_first => 1 }
    );
    if ( ! defined $col_count ) {
        return;
    }
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    if ( @{$aoa->[0]} < $col_count ) {
        $tc->choose(
            [ 'Chosen number bigger than the available columns!' ],
            { prompt => 'Close with ENTER' }
        );
        return;
    }
    if ( @{$aoa->[0]} % $col_count ) {
        $tc->choose(
            [ 'The number of available columns cannot be divided by the chosen number without rest!' ],
            { prompt => 'Close with ENTER' }
        );
        return;
    }
    my $begin = 0;
    my $end   = $col_count - 1;
    my $tmp = [];

    while ( 1 ) {
        for my $row ( @$aoa ) {
            push @$tmp, [ @{$row}[ $begin .. $end ] ];
        }
        $begin = $end + 1;
        if ( $begin > $#{$aoa->[0]} ) {
            last;
        }
        $end = $end + $col_count;
    }
    $sql->{insert_into_args} = $tmp;
}


sub __merge_rows {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 4 + @$aoa; # filter_str, prompt, back, confirm and aoa
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $term_w = get_term_width();
    my @stringified_rows;
    {
        no warnings 'uninitialized';
        @stringified_rows = map {
            my $str_row = join( ',', @$_ );
            if ( print_columns( $str_row ) > $term_w ) {
                unicode_sprintf( $str_row, $term_w, { mark_if_trundated => $sf->{i}{dots}[ $sf->{o}{G}{dots} ] } );
            }
            else {
                $str_row;
            }
        } @$aoa;
    }
    my $prompt = 'Choose rows:';
    my $chosen_idxs = $tu->choose_a_subset(
        \@stringified_rows,
        { cs_separator => "\n", cs_end => "\n", layout => 3, order => 0, all_by_default => 0, prompt => $prompt,
          index => 1, confirm => $sf->{i}{ok}, back => '<<', info => $filter_str, busy_string => $sf->{i}{working} }
    );
    if ( ! defined $chosen_idxs || ! @$chosen_idxs ) {
        return;
    }
    $count_static_rows = 4 + @{$aoa->[$chosen_idxs->[0]]}; # filter_str, prompt, back, confirm and chosen_subset
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $merged = [];
    for my $col ( 0 .. $#{$aoa->[$chosen_idxs->[0]]} ) {
        my @tmp;
        for my $row ( @$chosen_idxs ) {
            next if ! defined $aoa->[$row][$col];
            next if $aoa->[$row][$col] =~ /^\s*\z/;
            $aoa->[$row][$col] =~ s/^\s+|\s+\z//g;
            push @tmp, $aoa->[$row][$col];
        }
        $merged->[$col] = join ' ', @tmp;
    }
    my $col_number = 0;
    my $fields = [ map { [ ++$col_number, defined $_ ? "$_" : '' ] } @$merged ];
    # Fill_form
    my $form = $tf->fill_form(
        $fields,
        { info => $filter_str, prompt => 'Edit cells of merged rows:',
          auto_up => 2, confirm => $sf->{i}{_confirm}, back => $sf->{i}{_back} . '   ' }
    );
    if ( ! $form ) {
        return;
    }
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    $merged = [ map { $_->[1] } @$form ];
    my $first_idx = shift @$chosen_idxs;
    $aoa->[$first_idx] = $merged; # modifies $aoa
    for my $idx ( sort { $b <=> $a } @$chosen_idxs ) {
        splice @$aoa, $idx, 1;
    }
    $sql->{insert_into_args} = $aoa;
    return;
}


sub __join_columns {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $aoa = $sql->{insert_into_args};
    my $empty_cells_of_col_count =  $sf->__count_empty_cells_of_cols( $aoa );
    my $header = $sf->__prepare_header( $aoa, $empty_cells_of_col_count );
    my $count_static_rows = 2; # filter_str and cs_label
    $sf->__print_filter_info( $sql, $count_static_rows, [ '<<', $sf->{i}{ok}, @$header ] );
    # Choose
    my $chosen_idxs = $tu->choose_a_subset(
        $header,
        { cs_label => 'Cols: ', layout => 0, order => 0, index => 1, confirm => $sf->{i}{ok},
          back => '<<', info => $filter_str, busy_string => $sf->{i}{working} }
    );
    if ( ! defined $chosen_idxs || ! @$chosen_idxs ) {
        return;
    }
    my @info = ( $filter_str );
    my $label = 'Cols: ';
    push @info, line_fold(
        $label . '"' . join( '", "', @{$header}[@$chosen_idxs] ) . '"', get_term_width(),
        { subseq_tab => ' ' x length $label, join => 0 }
    );
    $count_static_rows = @info + 1; # info_rows and readline
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    # Readline
    my $join_char = $tf->readline( 'Join-string: ', { info => join( "\n", @info ) } );
    if ( ! defined $join_char ) {
        return;
    }
    $count_static_rows = 4 + @$aoa; # filter_str, prompt, back, confirm and aoa
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $merged = [];
    for my $row ( 0 .. $#{$aoa} ) {
        my @tmp;
        for my $col ( @$chosen_idxs ) {
            next if ! defined $aoa->[$row][$col];
            next if $aoa->[$row][$col] =~ /^\s*\z/;
            $aoa->[$row][$col] =~ s/^\s+|\s+\z//g;
            push @tmp, $aoa->[$row][$col];
        }
        $merged->[$row] = join $join_char, @tmp;
    }
    my $col_number = 0;
    my $fields = [ map { [ ++$col_number, defined $_ ? "$_" : '' ] } @$merged ];
    # Fill_form
    my $form = $tf->fill_form(
        $fields,
        { info => $filter_str, prompt => 'Edit cells of joined cols:', auto_up => 2,
          confirm => $sf->{i}{_confirm}, back => $sf->{i}{_back} . '   ' }
    );
    if ( ! $form ) {
        return;
    }
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    $merged = [ map { $_->[1] } @$form ];
    my $first_idx = shift @$chosen_idxs;
    for my $row ( 0 .. $#{$aoa} ) { # modifies $aoa
        $aoa->[$row][$first_idx] = $merged->[$row];
        for my $idx ( sort { $b <=> $a } @$chosen_idxs ) {
            splice @{$aoa->[$row]}, $idx, 1 if $idx < @{$aoa->[$row]};
        }
    }
    $sql->{insert_into_args} = $aoa;
    return;
}


sub __transpose_rows_to_cols {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 4; # filter_str, prompt, back and confirm
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $prompt = 'Transpose columns to rows?';
    my $ok = $tc->choose(
        [ undef, '- YES' ],
        { info => $filter_str, prompt => $prompt, index => 1, undef => '- NO', layout => 3, busy_string => $sf->{i}{working} }
    );
    $sf->__print_filter_info( $sql, $count_static_rows, undef ); #
    if ( $ok ) {
        my $tmp_aoa = [];
        for my $row ( 0 .. $#$aoa ) {
            for my $col ( 0 .. $#{$aoa->[$row]} ) {
                $tmp_aoa->[$col][$row] = $aoa->[$row][$col];
            }
        }
        $sql->{insert_into_args} = $tmp_aoa;
    }
    return;
}

sub __empty_to_null {
    my ( $sf, $sql ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $menu_elements = [
        [ 'empty_to_null', "  Empty fields to NULL", [ 'NO', 'YES' ] ]
    ];
    my $count_static_rows = 3 + @$menu_elements; # prompt, back, confirm and menu_elements
    $sf->__print_filter_info( $sql, $count_static_rows, undef );
    my $tmp = { empty_to_null => $sf->{empty_to_null} };
    $tu->settings_menu(
        $menu_elements,
        $tmp,
        { back => $sf->{i}{_back}, confirm => $sf->{i}{_confirm} }
    );
    $sf->{empty_to_null} = $tmp->{empty_to_null};
}



sub __count_empty_cells_of_cols {
    my ( $sf, $aoa ) = @_;
    my $row_count = @$aoa;
    my $col_count = @{$aoa->[0]};
    my $empty_cells_of_col_count = [ ( 0 ) x $col_count ];
    COL: for my $col_idx ( 0 .. $col_count - 1 ) {
        for my $row_idx ( 0 .. $row_count - 1 ) {
            if ( length $aoa->[$row_idx][$col_idx] ) {
                next COL;
            }
            ++$empty_cells_of_col_count->[$col_idx];
        }
    }
    return $empty_cells_of_col_count;
}

sub __prepare_header {
    my ( $sf, $aoa, $empty_cells_of_col_count ) = @_;
    my $row_count = @$aoa;
    my $col_count = @{$aoa->[0]};
    my $header = [];
    for my $col_idx ( 0 .. $col_count - 1 ) {
        if ( $empty_cells_of_col_count->[$col_idx] == $row_count ) {
            $header->[$col_idx] = '--';
        }
        else {
            if ( length $aoa->[0][$col_idx] ) {
                $header->[$col_idx] = $aoa->[0][$col_idx];
            }
            else {
                $header->[$col_idx] = 'tmp_' . ( $col_idx + 1 );
            }
        }
    }
    return $header;
}

sub __choose_a_column_idx {
    my ( $sf, $columns, $filter_str, $prompt ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef );
    # Choose
    my $col_idx = $tc->choose(
        [ @pre, map( defined $_ ? $_ : '', @$columns ) ],
        { layout => 0, order => 0, index => 1, undef => '<<', info => $filter_str, prompt => $prompt, empty => '--', busy_string => $sf->{i}{working} } #
    );
    if ( ! $col_idx ) {
        return;
    }
    return $col_idx - @pre;
}

sub __choose_a_row_idx {
    my ( $sf, $aoa, $filter_str, $prompt ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @stringified_rows;
    {
        no warnings 'uninitialized';
        @stringified_rows = map { join ',', @$_ } @$aoa;
    }
    my @pre = ( undef );
    # Choose
    my $row_idx = $tc->choose(
        [ @pre, @stringified_rows ],
        { layout => 3, index => 1, undef => '<<', info => $filter_str, prompt => $prompt, busy_string => $sf->{i}{working} }
    );
    if ( ! $row_idx ) {
        return;
    }
    return $row_idx - @pre;
}



1;


__END__

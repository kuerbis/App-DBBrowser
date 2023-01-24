package # hide from PAUSE
App::DBBrowser::GetContent::Filter;

use warnings;
use strict;
use 5.014;

use List::MoreUtils qw( any minmax );

use Term::Choose           qw();
use Term::Choose::LineFold qw( line_fold print_columns );
use Term::Choose::Util     qw( insert_sep get_term_width get_term_height unicode_sprintf );
use Term::Choose::Screen   qw( clear_screen );
use Term::Form             qw();
use Term::Form::ReadLine   qw();

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info, $options, $d ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $d
    };
    $sf->{s_back} = '<<';
    bless $sf, $class;
}


sub input_filter {
    my ( $sf, $sql ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $confirm       = '     OK';
    my $back          = '     <<';
    my $reset         = '    RESET';
    my $reparse       = '   REPARSE';
    my $merge_rows    = 'Merge_Rows';
    my $range_rows    = 'Range_Rows';
    my $row_groups    = 'Row_Groups';
    my $choose_rows   = 'Choose_Rows';
    my $remove_cell   = 'Remove_Cell';
    my $insert_cell   = 'Insert_Cell';
    my $split_table   = 'Split_Table';
    my $split_column  = 'Split_Column';
    my $join_columns  = 'Join_Columns';
    my $fill_up_rows  = 'Fill_up_Rows';
    my $empty_to_null = ' Empty_2_NULL';
    my $choose_cols   = 'Choose_Columns';
    my $append_col    = 'Append_Columns';
    my $cols_to_rows  = 'Columns_to_Rows';
    my $s_and_replace = 'Search_&_Replace';
    my $field_count = @{$sql->{insert_into_args}} * @{$sql->{insert_into_args}[0]};
    my $bu_insert_into_args = [ map { [ @$_ ] } @{$sql->{insert_into_args}} ]; # copy the entire data
    $sf->{empty_to_null} = $sf->{o}{insert}{'empty_to_null_' . $sf->{d}{gc}{source_type}}; ##
    $sf->{working} = $field_count > 1_000_000 ? 'Working ... ' : undef;
    my $old_idx = 0;

    FILTER: while ( 1 ) {
        my $skip = ' ';
        my $regex = qr/^\Q$skip\E\z/;
        my $menu = [
            undef,          $choose_rows,   $range_rows,   $row_groups,
            $confirm,       $choose_cols,   $skip,         $skip,
            $reset,         $s_and_replace, $skip,         $skip,
            $reparse,       $remove_cell,   $insert_cell,  $skip,
            $empty_to_null, $join_columns,  $split_column, $append_col,
            $cols_to_rows,  $split_table,   $merge_rows,   $fill_up_rows,
        ];
        my $count_static_rows = 2; # prompt + trailing empty line
        my $max_cols = 4;
        my $count_items = @$menu;
        my $count_menu_rows = int( $count_items / $max_cols );
        if ( $count_items % $max_cols ) {
            $count_menu_rows += 1;
        }
        my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
        # Choose
        my $idx = $tc->choose(
            $menu,
            { info => $info, prompt => 'Filter:', layout => 0, order => 0, max_cols => $max_cols, index => 1,
              default => $old_idx, undef => $back, skip_items => $regex, busy_string => $sf->{working},
              keep => $keep }
        );
        $sf->__print_busy_string();
        if ( ! $idx ) {
            $sql->{insert_into_args} = [];
            delete $sf->{d}{fi};
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
            $sql->{insert_into_args} = [ map { [ @$_ ] } @{$bu_insert_into_args} ];
            $sf->{empty_to_null} = $sf->{o}{insert}{'empty_to_null_' . $sf->{d}{gc}{source_type}};
            next FILTER
        }
        elsif ( $filter eq $confirm ) {
            if ( $sf->{empty_to_null} ) {
                no warnings 'uninitialized';
                $sql->{insert_into_args} = [ map { [ map { length ? $_ : undef } @$_ ] } @{$sql->{insert_into_args}} ];
            }
            return 1;
        }
        elsif ( $filter eq $reparse ) {
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
            $sr->search_and_replace( $sql, $bu_insert_into_args, $filter_str, $sf->{s_back} );
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
        $sf->{d}{occupied_term_height} = undef;
    }
}


sub __print_busy_string {
    my ( $sf ) = @_;
    if ( $sf->{working} ) {
        print clear_screen();
        print $sf->{working} . "\r";
    }
}


sub __row_count_horinzontal_menu {
    my ( $sf, $menu ) = @_;
    my $count_menu_rows = 0;
    my $pad = 2; # the used default 'pad' value in Term::Choose
    my $term_w = get_term_width();
    my $longest = 0;
    my @tmp_cols = map{ ! length $_ ? '--' : $_ } @$menu;
    for my $col ( @tmp_cols ) {
        my $col_w = print_columns( $col );
        $longest = $col_w if $col_w > $longest;
    }
    my $r = print_columns( join( ' ' x $pad, @tmp_cols ) ) / $term_w;
    if ( $r <= 1 ) {
        $count_menu_rows = 1;
    }
    else {
        my $joined_cols = $longest;
        my $cols_in_a_row = 0;
        while ( $joined_cols < $term_w ) {
            $joined_cols += $pad + $longest;
            ++$cols_in_a_row;
        }
        $cols_in_a_row ||= 1;
        $count_menu_rows = int( @tmp_cols / $cols_in_a_row );
        if ( @tmp_cols % $cols_in_a_row ) {
            $count_menu_rows++;
        }
    }
    return $count_menu_rows;
}


sub __get_filter_info {
    my ( $sf, $sql, $count_static_rows, $count_menu_rows ) = @_;
    # $count_static_rows not realy static count - some could be line-folded if too long
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    $sf->{d}{occupied_term_height}  = 1; # "DATA:" prompt
    # ...                                # insert_into_args rows
    $sf->{d}{occupied_term_height} += 1; # empty row
    $sf->{d}{occupied_term_height} += $count_static_rows;
    $sf->{d}{occupied_term_height} += $count_menu_rows;
    my $keep = ( minmax( $count_menu_rows, 25, int( get_term_height() / 2 ) ) )[0];
    my $indent = '';
    my $bu_stmt_types = [ @{$sf->{d}{stmt_types}} ];
    $sf->{d}{stmt_types} = [];
    my $rows = $ax->info_format_insert_args( $sql, $indent );
    $sf->{d}{stmt_types} = $bu_stmt_types;
    my $info = join( "\n", 'DATA:', @$rows ) . "\n"; # "\n" == empty line after insert_args
    return $info, $keep;
}


sub __choose_columns {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $aoa = $sql->{insert_into_args};
    my $empty_cells_of_col_count = $sf->__count_empty_cells_of_cols( $aoa );
    my $header = $sf->__prepare_header( $aoa, $empty_cells_of_col_count );
    my $count_static_rows = 3; # filter_str + cs_label + trailing empty line
    my $row_count = @$aoa;
    my $col_count = @{$aoa->[0]};
    my $mark = []; # 
    for my $col_idx ( 0 .. $col_count - 1 ) {
        if ( $empty_cells_of_col_count->[$col_idx] < $row_count ) {
            push @$mark, $col_idx;
        }
    }
    if ( @$mark == $col_count ) {
        $mark = undef; # no preselect if all cols have entries
    }
    my $count_menu_rows = $sf->__row_count_horinzontal_menu( [ $sf->{s_back}, $sf->{i}{ok}, @$header ] );
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Choose
    my $col_idx = $tu->choose_a_subset(
        $header,
        { cs_label => 'Cols: ', layout => 0, order => 0, mark => $mark, all_by_default => 1, index => 1,
          confirm => $sf->{i}{ok}, back => $sf->{s_back}, info => $info, keep => $keep,
          busy_string => $sf->{working} }
    );
    $sf->__print_busy_string();
    if ( ! defined $col_idx ) {
        return;
    }
    $sql->{insert_into_args} = [ map { [ @{$_}[@$col_idx] ] } @$aoa ];
    return 1;
}


sub __choose_rows {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my @pre = ( undef, $sf->{i}{ok} ); # back, confirm
    my $stringified_rows = [];
    my $mark;
    {
        no warnings 'uninitialized';
        for my $i ( 0 .. $#$aoa ) {
            push @$mark, $i + @pre if length join '', @{$aoa->[$i]};
            push @$stringified_rows, join ',', @{$aoa->[$i]};
        }
    }
    if ( @$mark == @$stringified_rows ) {
        $mark = undef;
    }
    my $prompt = 'Choose rows:';
    $sql->{insert_into_args} = []; # $sql->{insert_into_args} refers to a new empty array - this doesn't delete $aoa

    while ( 1 ) {
        my $count_menu_rows = @pre + @$aoa;
        my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
        $info .= "\n" . $filter_str;
        # Choose
        my @idx = $tc->choose(
            [ @pre, @$stringified_rows ],
            { %{$sf->{i}{lyt_v}}, prompt => $prompt, info => $info, meta_items => [ 0 .. $#pre ], keep => $keep,
              include_highlighted => 2, index => 1, undef => $sf->{s_back}, busy_string => $sf->{working}, mark => $mark }
        );
        $sf->__print_busy_string();
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
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $count_menu_rows = 1 + @$aoa; # back
    $sql->{insert_into_args} = []; # temporarily: because the rows are the choices
    my $prompt = "Choose first row:";
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Stop
    my $idx_first_row = $sf->__choose_a_row_idx( $aoa, $info, $keep, $prompt, $sf->{s_back} );
    if ( ! defined $idx_first_row ) {
        $sql->{insert_into_args} = $aoa;
        return;
    }
    $sql->{insert_into_args} = [ $aoa->[$idx_first_row] ]; # temporarily for the info output
    $count_menu_rows = 1 + @$aoa; # back
    $prompt = "Choose last row:";
    ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Stop
    my $idx_last_row = $sf->__choose_a_row_idx( [ @{$aoa}[$idx_first_row .. $#$aoa] ], $info, $keep, $prompt, $sf->{s_back} );
    if ( ! defined $idx_last_row ) {
        $sql->{insert_into_args} = $aoa;
        return;
    }
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
    my $len = length insert_sep( scalar @{$group{$keys_sorted[0]}}, $sf->{i}{info_thsd_sep} );
    for my $col_count ( @keys_sorted ) {
        my $row_count = scalar @{$group{$col_count}};
        my $row_str = $row_count == 1 ? 'row  has ' : 'rows have';
        my $col_str = $col_count == 1 ? 'column ' : 'columns';
        push @choices_groups, sprintf '  %*s %s %2d %s',
            $len, insert_sep( $row_count, $sf->{i}{info_thsd_sep} ), $row_str,
            $col_count, $col_str;
    }
    my $count_static_rows = 6; # filter_str, prompt, 2 x cs_label, cs_end, trailing empty line
    my $count_menu_rows = 2 + @choices_groups; # back, confirm
    my $prompt = 'Choose group:';
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Choose
    my $idxs = $tu->choose_a_subset(
        \@choices_groups,
        { info => $info, prompt => $prompt, layout => 2, index => 1, confirm => $sf->{i}{ok},
          back => $sf->{s_back}, all_by_default => 1, cs_label => "Chosen groups:\n", cs_separator => "\n",
          cs_end => "\n", busy_string => $sf->{working}, keep => $keep }
    );
    $sf->__print_busy_string();
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
        my $prompt = "Choose row:";
        my $info = $filter_str;
        # Stop
        my $row_idx = $sf->__choose_a_row_idx( $aoa, $info, 5, $prompt, $sf->{s_back} ); # $keep ### 
        if ( ! defined $row_idx ) {
            return;
        }
        my $count_static_rows = 3; # filter_str and prompt, trailing empty line
        my $count_menu_rows = $sf->__row_count_horinzontal_menu( [ $sf->{s_back}, @{$aoa->[$row_idx]} ] );
        $prompt = "Choose cell:";
        ( $info, my $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
        $info .= "\n" . $filter_str;
        # Stop
        my $col_idx = $sf->__choose_a_column_idx( [ @{$aoa->[$row_idx]} ], $info, $keep, $prompt, $sf->{s_back} );
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
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $aoa = $sql->{insert_into_args};

    while ( 1 ) {
        my $prompt = "Choose row:";
        my $info = $filter_str;
        # Stop
        my $row_idx = $sf->__choose_a_row_idx( $aoa, $info, 5, $prompt, $sf->{s_back} ); # $keep ###
        if ( ! defined $row_idx ) {
            return;
        }
        my $cols = [ @{$aoa->[$row_idx]}, 'END_of_Row' ];
        my $count_static_rows = 3; # prompt, filter_str, trailing empty line
        my $count_menu_rows = $sf->__row_count_horinzontal_menu( [ $sf->{s_back}, @$cols ] );
        $prompt = "Insert cell before:";
        ( $info, my $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
        $info .= "\n" . $filter_str;
        # Stop
        my $col_idx = $sf->__choose_a_column_idx( $cols, $info, $keep, $prompt, $sf->{s_back} );
        if ( ! defined $col_idx ) {
            next;
        }
        my @row = @{$aoa->[$row_idx]};
        splice( @row, $col_idx, 0, '<*>' );
        my $str_row_with_placeholder = _stringify_row( \@row );
        $str_row_with_placeholder =~ s/"<\*>"/<*>/;
        my $term_w = get_term_width();
        my $label = 'Row: ';
        my @tmp_info = ( $filter_str );
        push @tmp_info, line_fold(
            $label . $str_row_with_placeholder, $term_w,
            { subseq_tab => ' ' x length $label, join => 0 }
        );
        $count_static_rows = @tmp_info + 2; # tmp_info, readline, trailing empty line
        $prompt = "<*>: ";
        ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, 0 );
        $info .=  "\n" . join( "\n", @tmp_info );
        # Readline
        my $cell = $tr->readline(
            $prompt,
            { info => $info }
        );
        $sf->__print_busy_string();
        splice( @{$aoa->[$row_idx]}, $col_idx, 0, $cell );
        $sql->{insert_into_args} = $aoa;
        return;
    }
}


sub __fill_up_rows {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $menu = [ undef, '- YES' ]; # back, confirm
    my $count_menu_rows = scalar @$menu;
    my $prompt = 'Fill up shorter rows?';
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Choose
    my $ok = $tc->choose(
        $menu,
        { info => $info, prompt => $prompt, index => 1, undef => '- NO', layout => 2, keep => $keep }
    );
    $sf->__print_busy_string();
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
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $menu = [ undef, '- YES' ]; # back, confirm
    my $count_menu_rows = scalar @$menu;
    my $prompt = 'Append an empty column?';
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Choose
    my $ok = $tc->choose(
        $menu,
        { info => $info, prompt => $prompt, index => 1, undef => '- NO', layout => 2, keep => $keep }
    );
    $sf->__print_busy_string();
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
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $count_menu_rows = $sf->__row_count_horinzontal_menu( [ $sf->{s_back}, @$header ] );
    my $prompt = 'Choose column:';
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Stop
    my $idx = $sf->__choose_a_column_idx( $header, $info, $keep, $prompt, $sf->{s_back} );
    if ( ! defined $idx ) {
        return;
    }
    my $fields = [
        [ 'Pattern', ],
        [ 'Limit', ],
        [ 'Left trim', '\s+' ],
        [ 'Right trim', '\s+' ]
    ];
    $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $back = $sf->{i}{back} . ' ' x 3;
    $count_menu_rows = 2 + @$fields; # back, confirm
    $prompt = "Split column \"$header->[$idx]\"";
    ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    my $c;
    # Fill_form
    my $form = $tf->fill_form(
        $fields,
        { info => $info, prompt => $prompt, auto_up => 2, confirm => $sf->{i}{confirm}, back => $back,
          keep => $keep }
    );
    $sf->__print_busy_string();
    if ( ! $form ) {
        return;
    }
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
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $count_menu_rows = 2 + $digits; # back, confirm;
    my $col_count;

    CHOOSE_A_NUMBER: while( 1 ) {
        # get_filter_info: if $max_cols == 1, only the element count of the array-references matters, so ( ' ' ) x $digits is ok
        my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
        $info .= "\n" . $filter_str;
        # Choose
        $col_count = $tu->choose_a_number(
            $digits,
            { info => $info, cs_label => 'Number columns new table: ', small_first => 1, keep => $keep }
        );
        $sf->__print_busy_string();
        if ( ! $col_count ) {
            return;
        }
        if ( @{$aoa->[0]} < $col_count ) {
            my $prompt = sprintf 'Chosen number(%d) bigger than the available columns(%d)!', $col_count, scalar( @{$aoa->[0]} );
            my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
            $info .= "\n" . $filter_str;
            $tc->choose(
                [ 'Continue with ENTER' ],
                { info => $info, prompt => $prompt, keep => $keep }
            );
            $sf->__print_busy_string();
            next CHOOSE_A_NUMBER;
        }
        if ( @{$aoa->[0]} % $col_count ) {
            my $prompt = sprintf 'The number of available columns(%d) cannot be divided by the selected number(%d) without remainder!', scalar( @{$aoa->[0]} ), $col_count;
            my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
            $info .= "\n" . $filter_str;
            $tc->choose(
                [ 'Continue with ENTER' ],
                { info => $info, prompt => $prompt, keep => $keep }
            );
            $sf->__print_busy_string();
            next CHOOSE_A_NUMBER;
        }
        last CHOOSE_A_NUMBER;
    }
    my $begin = 0;
    my $end = $col_count - 1;
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
    my $term_w = get_term_width();
    my $stringified_rows;
    {
        my $dots = $sf->{i}{dots};
        my $dots_w = print_columns( $dots );
        no warnings 'uninitialized';
        @$stringified_rows = map {
            my $str_row = join( ',', @$_ );
            if ( print_columns( $str_row ) > $term_w ) {
                unicode_sprintf( $str_row, $term_w, { mark_if_trundated => [ $dots, $dots_w ] } );
            }
            else {
                $str_row;
            }
        } @$aoa;
    }
    my $prompt = 'Choose rows:';
    my $info = $filter_str;
    # Choose
    my $chosen_idxs = $tu->choose_a_subset(
        $stringified_rows,
        { cs_separator => "\n", cs_end => "\n", layout => 2, order => 0, all_by_default => 0, prompt => $prompt,
          index => 1, confirm => $sf->{i}{ok}, back => $sf->{s_back}, info => $info, keep => 5, # $keep ### 
          busy_string => $sf->{working} }
    );
    $sf->__print_busy_string();
    if ( ! defined $chosen_idxs || ! @$chosen_idxs ) {
        return;
    }
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
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
    my $count_menu_rows = 2 + @$fields; # back, confirm
    ( $info, my $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Fill_form
    my $form = $tf->fill_form(
        $fields,
        { info => $info, prompt => 'Edit cells of merged rows:', keep => $keep,
          auto_up => 2, confirm => $sf->{i}{_confirm}, back => $sf->{i}{_back} . '   ' }
    );
    $sf->__print_busy_string();
    if ( ! $form ) {
        return;
    }
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
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $aoa = $sql->{insert_into_args};
    my $empty_cells_of_col_count =  $sf->__count_empty_cells_of_cols( $aoa );
    my $header = $sf->__prepare_header( $aoa, $empty_cells_of_col_count );
    my $count_static_rows = 3; # filter_str, cs_label, trailing empty line
    my $count_menu_rows = $sf->__row_count_horinzontal_menu( [ $sf->{s_back}, $sf->{i}{ok}, @$header ] );
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Choose
    my $chosen_idxs = $tu->choose_a_subset(
        $header,
        { cs_label => 'Cols: ', layout => 0, order => 0, index => 1, confirm => $sf->{i}{ok}, keep => $keep,
          back => $sf->{s_back}, info => $info, busy_string => $sf->{working} }
    );
    $sf->__print_busy_string();
    if ( ! defined $chosen_idxs || ! @$chosen_idxs ) {
        return;
    }
    my @tmp_info = ( $filter_str );
    my $label = 'Cols: ';
    push @tmp_info, line_fold(
        $label . '"' . join( '", "', @{$header}[@$chosen_idxs] ) . '"', get_term_width(),
        { subseq_tab => ' ' x length $label, join => 0 }
    );
    $count_static_rows = @tmp_info + 2; # tmp_info, readline, empty line
    ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, 0 );
    $info .= "\n" . join( "\n", @tmp_info );
    # Readline
    my $join_char = $tr->readline(
        'Join-string: ',
        { info => $info }
    );
    $sf->__print_busy_string();
    if ( ! defined $join_char ) {
        return;
    }
    $count_static_rows = 3; # filter_str, prompt, trailing empty line
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
    $count_menu_rows = 2 + @$fields; # back, confirm
    ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    # Fill_form
    my $form = $tf->fill_form(
        $fields,
        { info => $info, prompt => 'Edit cells of joined cols:', auto_up => 2, keep => $keep,
          confirm => $sf->{i}{_confirm}, back => $sf->{i}{_back} . '   ' }
    );
    $sf->__print_busy_string();
    if ( ! $form ) {
        return;
    }
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
    my $menu = [ undef, '- YES' ];
    my $count_static_rows = 3; # filter_str, prompt, trailing empty line
    my $count_menu_rows = scalar @$menu;
    my $prompt = 'Transpose columns to rows?';
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $info .= "\n" . $filter_str;
    my $ok = $tc->choose(
        $menu,
        { info => $info, prompt => $prompt, index => 1, undef => '- NO', layout => 2, busy_string => $sf->{working},
          keep => $keep }
    );
    $sf->__print_busy_string();
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
    my $count_static_rows = 2; # prompt, trailing empty line
    my $count_menu_rows = 2 + @$menu_elements; # back, confirm
    my $tmp = { empty_to_null => $sf->{empty_to_null} };
    my ( $info, $keep ) = $sf->__get_filter_info( $sql, $count_static_rows, $count_menu_rows );
    $tu->settings_menu(
        $menu_elements,
        $tmp,
        { info => $info, back => $sf->{i}{_back}, confirm => $sf->{i}{_confirm}, keep => $keep }
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
    my ( $sf, $columns, $info, $keep, $prompt, $back ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @pre = ( undef );
    # Choose
    my $col_idx = $tc->choose(
        [ @pre, map( defined $_ ? $_ : '', @$columns ) ],
        { layout => 0, order => 0, index => 1, undef => $back // '<<', info => $info, prompt => $prompt, empty => '--',
          keep => $keep, busy_string => $sf->{working} } #
    );
    $sf->__print_busy_string();
    if ( ! $col_idx ) {
        return;
    }
    return $col_idx - @pre;
}

sub __choose_a_row_idx {
    my ( $sf, $aoa, $info, $keep, $prompt, $back ) = @_;
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
        { layout => 2, index => 1, undef => $back // '<<', info => $info, prompt => $prompt, keep => $keep,
          busy_string => $sf->{working} }
    );
    $sf->__print_busy_string();
    if ( ! $row_idx ) {
        return;
    }
    return $row_idx - @pre;
}



1;


__END__

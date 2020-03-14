package # hide from PAUSE
App::DBBrowser::GetContent::Filter::SearchAndReplace;

use warnings;
use strict;
use 5.010001;

use List::MoreUtils qw( any none );

use Term::Choose       qw();
use Term::Choose::Util qw();
use Term::Form         qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::GetContent::Filter;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data,
    };
    bless $sf, $class;
}


sub __search_and_replace {
    my ( $sf, $sql, $filter_str ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $cf = App::DBBrowser::GetContent::Filter->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $aoa = $sql->{insert_into_args};
    my $empty_cells_of_col_count =  $cf->__count_empty_cells_of_cols( $aoa ); ##
    my $header = $cf->__prepare_header( $aoa, $empty_cells_of_col_count );
    my $saved = $ax->read_json( $sf->{i}{f_search_and_replace} ) // [];
    my $all_sr = [];
    my $used_names = [];
    my $header_changed = 0;
    my @bu;

    MENU: while ( 1 ) {
        my $sr_args = [];
        my @info = ( $filter_str );
        for my $sr_args ( @$all_sr ) {
            push @info, '  s/' . join( '/', @$sr_args ) . ';';
        }
        push @info, '';
        my ( $hidden, $select_cols, $add, $restore_header ) = ( 'Choose:', '  SELECT COLUMNS', '  ADD s_&_r', '  RESTORE header row' );
        my @pre = ( $hidden, undef, $add );
        if ( @$all_sr ) {
            splice @pre, 2, 0, $select_cols;
        }
        elsif ( $header_changed ) {
            splice @pre, 2, 0, $restore_header;
        }
        my $available = [];
        for my $e ( @$saved ) {
            if ( none { $e->[1] eq $_ } @$used_names ) {
                push @$available, $e;
            }
        }
        my $menu = [ @pre, map( '- ' . $_->[1], @$available ) ];
        my $count_static_rows = @info + @$menu; # @info and @$menu
        $cf->__print_filter_info( $sql, $count_static_rows, undef );
        # Choose
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, info => join( "\n", @info ), prompt => '', default => 1, index => 1, undef => '  <=' }
        );
        if ( ! defined $idx || ! defined $menu->[$idx] ) {
            if ( @bu ) {
                ( $used_names, $available, $all_sr ) = @{pop @bu};
                next;
            }
            return;
        }
        my $choice = $menu->[$idx];
        if ( $choice eq $hidden ) {
            $sf->__history( $sql );
            $saved = $ax->read_json( $sf->{i}{f_search_and_replace} ) // [];
            next MENU;
        }
        elsif ( $choice eq $select_cols ) {
            if ( ! @$all_sr ) {
                return;
            }
            my $ok = $sf->__apply_to_cols( $sql, \@info, $header, $all_sr );
            for my $i ( 0 .. $#$header ) {
                if ( $header->[$i] ne $sql->{insert_into_args}[0][$i] ) {
                    $header_changed = 1;
                    last;
                }
            }
            if ( $ok ) {
                $all_sr = [];
                $used_names = [];
                @bu = ();
            }
            next MENU;
        }
        elsif ( $choice eq $restore_header ) {
            $sql->{insert_into_args}[0] = $header;
            $header_changed = 0;
            next MENU;
        }
        push @bu, [ [ @$used_names ], [ @$available ], [ @$all_sr ] ];
        if ( $choice eq $add ) {
            my $prompt = 'Build s_&_r:';
            my $fields = [
                [ '  Pattern', ],
                [ '  Replacement', ],
                [ '  Modifiers', ]
            ];
            my $count_static_rows = @info + 3 + @$fields; # info, prompt, back, confirm and fields
            $cf->__print_filter_info( $sql, $count_static_rows, undef );
            # Fill_form
            my $form = $tf->fill_form(
                $fields,
                { info => join( "\n", @info ), prompt => $prompt, auto_up => 2, confirm => '  ' . $sf->{i}{confirm},
                back => '  ' . $sf->{i}{back} . '   ' }
            );
            if ( ! defined $form ) {
                next MENU;
            }
            my ( $pattern, $replacement, $modifiers ) = map { $_->[1] // '' } @$form;
            $modifiers = $sf->__filter_modifiers( $modifiers );
            $sr_args = [ $pattern, $replacement, $modifiers ];
        }
        else {
            $sr_args = $available->[$idx-@pre][0];
            push @$used_names, $available->[$idx-@pre][1];
        }
        push @$all_sr, $sr_args;
    }
}


sub __filter_modifiers {
    my ( $sf, $modifiers ) = @_;
    $modifiers =~ s/[^geis]+//g;
    $modifiers =~ tr/gis/gis/s; #;;
    return $modifiers;
}


sub __apply_to_cols {
    my ( $sf, $sql, $info, $header, $all_sr ) = @_;
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $cf = App::DBBrowser::GetContent::Filter->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $aoa = $sql->{insert_into_args};
    my $count_static_rows = @$info + 1; # info_count and cs_label
    $cf->__print_filter_info( $sql, $count_static_rows, [ '<<', $sf->{i}{ok}, @$header ] );
    my $key_1 = 'search&replace';
    my $key_2 = join( '', map { $_->[1] } @$all_sr );
    my $prev_chosen = $sf->{i}{prev_chosen_cols}{$key_1}{$key_2} // [];
    my $mark;
    if ( @$prev_chosen && @$prev_chosen < @$header ) {
        $mark = [];
        for my $i ( 0 .. $#{$header} ) {
            push @$mark, $i if any { $_ eq $header->[$i] } @$prev_chosen;
        }
        $mark = undef if @$mark != @$prev_chosen;
    }
    # Choose
    my $col_idx = $tu->choose_a_subset(
        $header,
        { cs_label => 'Columns: ', info => join( "\n", @$info ), layout => 0, all_by_default => 1, index => 1,
        confirm => $sf->{i}{ok}, back => '<<', busy_string => $sf->{i}{working}, mark => $mark }
    );
    if ( ! defined $col_idx ) {
        return;
    }
    $sf->{i}{prev_chosen_cols}{$key_1}{$key_2} = [ @{$header}[@$col_idx] ];
    $cf->__print_filter_info( $sql, $count_static_rows, [ '<<', $sf->{i}{ok}, @$header ] ); #

    my $c;
    for my $row ( @$aoa ) { # modifiers $aoa
        for my $i ( @$col_idx ) {
            for my $sr_args ( @$all_sr ) {
                my ( $pattern, $replacement, $modifiers ) = @$sr_args;
                my $regex = $modifiers =~ /i/ ? qr/(?i:${pattern})/ : qr/${pattern}/;
                my $replacement_code = sub { return $replacement };
                for ( grep { /^e\z/ } split( //, $modifiers ) ) {
                    my $recurse = $replacement_code;
                    $replacement_code = sub { return eval $recurse->() }; # execute (e) substitution
                }
                $c = 0;
                if ( ! defined $row->[$i] ) {
                    next;
                }
                elsif ( $modifiers =~ /g/ ) {
                    if ( $modifiers =~ /s/ ) { # s not documented
                        $row->[$i] =~ s/$regex/$replacement_code->()/gse;
                    }
                    else {
                        $row->[$i] =~ s/$regex/$replacement_code->()/ge;
                    }
                }
                else {
                    if ( $modifiers =~ /s/ ) { # s not documented
                        $row->[$i] =~ s/$regex/$replacement_code->()/se;
                    }
                    else {
                        $row->[$i] =~ s/$regex/$replacement_code->()/e;
                    }
                }
            }
        }
    }
    $sql->{insert_into_args} = $aoa;
    return 1;
}


sub __history {
    my ( $sf, $sql ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tf = Term::Form->new( $sf->{i}{tf_default} );
    my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $cf = App::DBBrowser::GetContent::Filter->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $old_idx_menu = 0;

    MENU: while ( 1 ) {
        my $saved = $ax->read_json( $sf->{i}{f_search_and_replace} ) // [];
        my @info = ( 'Saved s_&_r:' );
        push @info, map { ' ' . $_->[1] } @$saved;
        push @info, ' ';
        my ( $add, $edit, $remove ) = ( '- Add    s_&_r', '- Edit   s_&_r', '- Remove s_&_r' );
        my $menu = [ undef, $add, $edit, $remove ];
        # Choose
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, clear_screen => 1, info => join( "\n", @info ), undef => '  <=',
              index => 1, default => $old_idx_menu }
        );
        if ( ! defined $idx || ! defined $menu->[$idx] ) {
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx_menu == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx_menu = 0;
                next MENU;
            }
            $old_idx_menu = $idx;
        }
        my $choice = $menu->[$idx];
        if ( $choice eq $add || $choice eq $edit) {
            my ( $prompt, $pattern, $replacement, $modifiers, $name, $spliced );
            my $old_idx_edit = 0;

            EDIT: while ( 1 ) {
                if ( $choice eq $edit ) {
                    if ( ! @$saved ) {
                        next MENU;
                    }
                    $prompt = 'Edit s_&_r:';
                    my @pre = ( undef );
                    my $menu = [ @pre, map( '- ' . $_->[1], @$saved ) ];
                    # Choose
                    my $idx = $tc->choose(
                        $menu,
                        { %{$sf->{i}{lyt_v}}, clear_screen => 1, prompt => $prompt, index => 1,
                          undef => '  <=', default => $old_idx_edit }
                    );
                    if ( ! defined $idx || ! defined $menu->[$idx] ) {
                        next MENU;
                    }
                    if ( $sf->{o}{G}{menu_memory} ) {
                        if ( $old_idx_edit == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                            $old_idx_edit = 0;
                            next EDIT;
                        }
                        $old_idx_edit = $idx;
                    }
                    $spliced = splice @$saved, $idx - @pre, 1;
                    ( $pattern, $replacement, $modifiers ) = @{$spliced->[0]};
                    $name = $spliced->[1];
                }
                else {
                    $prompt = 'Add s_&_r:';
                }

                CODE: while ( 1 ) {
                    my $fields = [
                        [ '  Pattern',     $pattern     ],
                        [ '  Replacement', $replacement ],
                        [ '  Modifiers',   $modifiers   ]
                    ];
                    # Fill_form
                    my $form = $tf->fill_form(
                        $fields,
                        { info => join( "\n", @info ), prompt => $prompt, auto_up => 2, confirm => '  ' . $sf->{i}{confirm},
                        back => '  ' . $sf->{i}{back} . '   ', clear_screen => 1 }
                    );
                    if ( ! defined $form ) {
                        if ( $choice eq $edit ) {
                            push @$saved, $spliced;
                            $saved = [ sort { $a->[1] cmp $b->[1] } @$saved ];
                            next EDIT;
                        }
                        next MENU;
                    }
                    ( $pattern, $replacement, $modifiers ) = map { $_->[1] // '' } @$form;
                    $modifiers = $sf->__filter_modifiers( $modifiers );
                    my $sr_args = [ $pattern, $replacement, $modifiers ];
                    my $code = 's/' . join( '/', @$sr_args );
                    $name = $name // $code;
                    my $count = 1;

                    NAME: while ( 1 ) {
                        my $fields = [
                            [ '  Code', $code ],
                            [ '  Name', $name ]
                        ];
                        my $prompt = 'Edit name:';
                        # Fill_form
                        my $form = $tf->fill_form(
                            $fields,
                            { info => join( "\n", @info ), prompt => $prompt, auto_up => 2, confirm => '  ' . $sf->{i}{confirm},
                            back => '  ' . $sf->{i}{back} . '   ', clear_screen => 1, read_only => [ 0 ] }
                        );
                        if ( ! defined $form ) {
                            next CODE;
                        }
                        $name = $form->[1][1];
                        if ( ! length $name ) {
                            next CODE;
                        }
                        if ( any { $name eq $_ } map { $_->[1] } @$saved ) {
                            my $prompt = "\"$name\" already exists.";
                            my $choice = $tc->choose(
                                [ undef, '  New name' ],
                                { %{$sf->{i}{lyt_v}}, prompt => $prompt, info => join( "\n", @info ) }
                            );
                            if ( ! defined $choice ) {
                                next CODE;
                            }
                            if ( $count > 1 ) {
                                $name = undef;
                            }
                            $count++;
                            next NAME;
                        }
                        else {
                            last NAME;
                        }
                    }
                    push @$saved, [ $sr_args, $name ];
                    $saved = [ sort { $a->[1] cmp $b->[1] } @$saved ];
                    $ax->write_json( $sf->{i}{f_search_and_replace}, $saved );
                    next EDIT if $choice eq $edit;
                    next MENU;
                }
            }
        }
        elsif ( $choice eq $remove ) {
            my $list = [ map { $_->[1] } @$saved ];
            # Choose
            my $col_idx = $tu->choose_a_subset(
                $list,
                { prefix => '- ', cs_label => 'Saved s_&_r to remove:' . "\n  ", cs_separator => "\n  ", cs_end => "\n",
                  layout => 3, all_by_default => 0, index => 1, confirm => $sf->{i}{_confirm}, back => $sf->{i}{_back},
                  busy_string => $sf->{i}{working}, clear_screen => 1, prompt => 'Remove:' }
            );
            if ( ! defined $col_idx ) {
                next;
            }
            splice @$saved, $_, 1 for sort { $b <=> $a } @$col_idx;
            $ax->write_json( $sf->{i}{f_search_and_replace}, [ sort { $a->[1] cmp $b->[1] } @$saved ] );
        }
    }
}






1;


__END__

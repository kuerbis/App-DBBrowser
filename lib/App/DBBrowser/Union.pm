package # hide from PAUSE
App::DBBrowser::Union;

use warnings;
use strict;
use 5.014;

use List::MoreUtils qw( any );

use Term::Choose qw();
#use Term::Choose::Util qw()     # required

use App::DBBrowser::Auxil;
#use App::DBBrowser::Subqueries; # required

sub new {
    my ( $class, $info, $options, $d ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $d
    }, $class;
}


sub union_tables {
    my ( $sf ) = @_;
    $sf->{d}{stmt_types} = [ 'Union' ];
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tables;
    if ( $sf->{o}{G}{metadata} ) {
        $tables = [ @{$sf->{d}{user_table_keys}}, @{$sf->{d}{sys_table_keys}} ];
    }
    else {
        $tables = [ @{$sf->{d}{user_table_keys}} ];
    }
    ( $sf->{d}{col_names}, $sf->{d}{col_types} ) = $ax->tables_column_names_and_types( $tables );
    my $union = {
        used_tables    => [],
        subselect_data => [],
        saved_cols     => [],
        union_type     => '',
    };
    my $count_derived = 1;
    state $union_type = "UNION ALL";
    my @bu;
    my $old_idx_tbl = 0;

    UNION_TABLE: while ( 1 ) {
        my $enough_tables = '  Enough TABLES';
        my $from_subquery = '  Derived';
        my $all_tables    = '  All Tables';
        my $union_setting = '  Setting';
        my @pre  = ( undef, $enough_tables );
        my @post;
        push @post, $from_subquery if $sf->{o}{enable}{u_derived};
        push @post, $all_tables    if $sf->{o}{enable}{union_all};
        push @post, $union_setting;
        my $used = ' (used)';
        my @tmp_tables;
        for my $table ( @$tables ) {
            if ( any { $_ eq $table } @{$union->{used_tables}} ) {
                push @tmp_tables, '- ' . $table . $used;
            }
            else {
                push @tmp_tables, '- ' . $table;
            }
        }
        $union->{union_type} = $union_type;
        my $prompt = 'Choose ' . $union_type . ' table:';
        my $menu  = [ @pre, @tmp_tables, @post ];
        my $info = $ax->get_sql_info( $union );
        # Choose
        my $idx_tbl = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, info => $info, prompt => $prompt, index => 1, default => $old_idx_tbl }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $idx_tbl || ! defined $menu->[$idx_tbl] ) {
            if ( @bu ) {
                ( $union->{used_tables}, $union->{subselect_data}, $union->{saved_cols} ) = @{pop @bu};
                next UNION_TABLE;
            }
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx_tbl == $idx_tbl && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx_tbl = 0;
                next UNION_TABLE;
            }
            $old_idx_tbl = $idx_tbl;
        }
        my $union_table = $menu->[$idx_tbl];
        my $qt_union_table;
        if ( $union_table eq $enough_tables ) {
            if ( ! @{$union->{subselect_data}} ) {
                return;
            }
            last UNION_TABLE;
        }
        elsif ( $union_table eq $union_setting ) {
            my $types = [ 'UNION ALL', 'UNION', 'INTERSECT ALL', 'INTERSECT', 'EXCEPT ALL', 'EXCEPT' ];
            my $sub_menu = [
                [ 'union_type', "- Union type", $types ],
            ];
            my $config = {
                union_type => List::MoreUtils::firstidx { $_ eq $union_type } @$types,
            };
            require Term::Choose::Util; ##
            my $tu = Term::Choose::Util->new( $sf->{i}{tcu_default} );
            my $info = $ax->get_sql_info( $union );
            # Choose
            my $changed = $tu->settings_menu(
                $sub_menu, $config,
                { info => $info }
            );
            $ax->print_sql_info( $info );
            $union_type = $types->[$config->{union_type}];
            next UNION_TABLE;
        }
        elsif ( $union_table eq $all_tables ) {
            my $ok = $sf->__union_all_tables( $union );
            if ( ! $ok ) {
                next UNION_TABLE;
            }
            last UNION_TABLE;
        }
        elsif ( $union_table eq $from_subquery ) {
            require App::DBBrowser::Subqueries;
            my $sq = App::DBBrowser::Subqueries->new( $sf->{i}, $sf->{o}, $sf->{d} );
            $union_table = $sq->choose_subquery( $union );
            if ( ! defined $union_table ) {
                next UNION_TABLE;
            }
            my $alias = 'x' . $count_derived++;
            $qt_union_table = $union_table . $sf->{i}{" AS "} . $ax->prepare_identifier( $alias );
            $sf->{d}{col_names}{$union_table} = $ax->column_names( $qt_union_table );
        }
        else {
            $union_table =~ s/^-\s//;
            $union_table =~ s/\Q$used\E\z//;
            $qt_union_table = $ax->quote_table( $sf->{d}{tables_info}{$union_table} );
        }
        push @bu, [ [ @{$union->{used_tables}} ], [ @{$union->{subselect_data}} ], [ @{$union->{saved_cols}} ] ];
        push @{$union->{used_tables}}, $union_table;
        my $ok = $sf->__union_table_columns( $union, $union_table, $qt_union_table );
        if ( ! $ok ) {
            ( $union->{used_tables}, $union->{subselect_data}, $union->{saved_cols} ) = @{pop @bu};
            next UNION_TABLE;
        }
    }
    my $qt_table = $ax->get_stmt( $union, 'Union', 'prepare' );
    if ( $sf->{o}{alias}{table} || $sf->{i}{driver} =~ /^(?:mysql|MariaDB|Pg)\z/ ) {
        $qt_table .= $sf->{i}{" AS "} . $ax->prepare_identifier( 't1' );
    }
    # column names in the result-set of a UNION are taken from the first query.
    my $qt_columns = $union->{subselect_data}[0][1];
    return $qt_table, $qt_columns;
}


sub __union_table_columns {
    my ( $sf, $union, $union_table, $qt_union_table ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $privious_cols =  "'^'";
    my $next_idx = @{$union->{subselect_data}};
    my $table_cols = [];
    my @bu_cols;

    while ( 1 ) {
        my @pre = ( undef, $sf->{i}{ok}, @{$union->{saved_cols}} ? $privious_cols : () );
        my $info = $ax->get_sql_info( $union );
        # Choose
        my @chosen = $tc->choose(
            [ @pre, @{$sf->{d}{col_names}{$union_table}} ],
            { %{$sf->{i}{lyt_h}}, info => $info, prompt => 'Choose Column:',
              meta_items => [ 0 .. $#pre ], include_highlighted => 2 }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $chosen[0] ) {
            if ( @bu_cols ) {
                $table_cols = pop @bu_cols;
                $union->{subselect_data}[$next_idx] = [ $qt_union_table, $ax->quote_cols( $table_cols ) ];
                next;
            }
            $#{$union->{subselect_data}} = $next_idx - 1;
            return;
        }
        if ( $chosen[0] eq $privious_cols ) {
            push @{$union->{subselect_data}}, [ $qt_union_table, $ax->quote_cols( $union->{saved_cols} ) ];
            return 1;
        }
        elsif ( $chosen[0] eq $sf->{i}{ok} ) {
            shift @chosen;
            push @$table_cols, @chosen;
            if ( ! @$table_cols ) {
                $table_cols = [ @{$sf->{d}{col_names}{$union_table}} ];
            }
            $union->{subselect_data}[$next_idx] = [ $qt_union_table, $ax->quote_cols( $table_cols ) ];
            $union->{saved_cols} = $table_cols;
            return 1;
        }
        else {
            push @$table_cols, @chosen;
            $union->{subselect_data}[$next_idx] = [ $qt_union_table, $ax->quote_cols( $table_cols ) ];
            push @bu_cols, [ @$table_cols ];
        }
    }
}


sub __union_all_tables {
    my ( $sf, $union ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @tables_union_auto;
    for my $table ( @{$sf->{d}{user_table_keys}} ) {
        if ( $sf->{d}{tables_info}{$table}[3] ne 'TABLE' ) {
            next;
        }
        push @tables_union_auto, $table;
    }
    my $menu = [ undef, map( "- $_", @tables_union_auto ) ];

    while ( 1 ) {
        $union->{subselect_data} = [ map { [ $_, [ '?' ] ] } @tables_union_auto ];
        my $info = $ax->get_sql_info( $union );
        # Choose
        my $idx_tbl = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, info => $info, prompt => 'Table for column names:', index => 1 }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $idx_tbl || ! defined $menu->[$idx_tbl] ) {
            $union->{subselect_data} = [];
            return;
        }
        my $union_table = $menu->[$idx_tbl] =~ s/^-\s//r;
        my $qt_union_table = $ax->quote_table( $sf->{d}{tables_info}{$union_table} );
        my $ok = $sf->__union_table_columns( $union, $union_table, $qt_union_table );
        if ( $ok ) {
            last;
        }
    }
    my $qt_used_cols = $union->{subselect_data}[-1][1];
    $union->{subselect_data} = [];
    for my $union_table ( @tables_union_auto ) {
        push @{$union->{subselect_data}}, [ $ax->quote_table( $sf->{d}{tables_info}{$union_table} ), $qt_used_cols ];
    }
    return 1; ##
}






1;

__END__

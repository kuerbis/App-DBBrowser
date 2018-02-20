package # hide from PAUSE
App::DBBrowser::Table;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_02';

use Clone              qw( clone );
use List::MoreUtils    qw( any first_index );
use Term::Choose       qw( choose );
use Term::Choose::Util qw( choose_a_number insert_sep );
use Term::Form         qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::DBBrowser::DB;
#use App::DBBrowser::Table::Insert;  # "require"-d
use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Functions;


sub new {
    my ( $class, $info, $opt ) = @_;
    bless { i => $info, o => $opt }, $class;
}


sub on_table {
    my ( $sf, $sql, $dbh ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $stmt_h = Term::Choose->new( $sf->{i}{lyt_stmt_h} );
    my $sub_stmts = {
        Select => [ qw( print_tbl columns aggregate distinct where group_by having order_by limit functions lock ) ],
        Delete => [ qw( commit     where functions ) ],
        Update => [ qw( commit set where functions ) ],
        Insert => [ qw( commit insert ) ],
    };
    my $lk = [ '  Lk0', '  Lk1' ];
    my %cu = (
        insert          => 'Build   Stmt',
        commit          => 'Confirm Stmt',
        hidden          => 'Customize:',
        print_tbl       => 'Print TABLE',
        columns         => '- SELECT',
        set             => '- SET',
        aggregate       => '- AGGREGATE',
        distinct        => '- DISTINCT',
        where           => '- WHERE',
        group_by        => '- GROUP BY',
        having          => '- HAVING',
        order_by        => '- ORDER BY',
        limit           => '- LIMIT',
        lock            => $lk->[$sf->{i}{lock}],
        functions       => '  Func',
    );
    my @aggregate = ( "AVG(X)", "COUNT(X)", "COUNT(*)", "MAX(X)", "MIN(X)", "SUM(X)" );
    my ( $DISTINCT, $ALL, $ASC, $DESC, $AND, $OR ) = ( "DISTINCT", "ALL", "ASC", "DESC", "AND", "OR" );
    if ( $sf->{i}{lock} == 0 ) {
        $ax->reset_sql( $sql );
    }
    my $sql_type = 'Select';
    my $backup_sql;
    my $old_idx = 1;
    my @pre = ( undef, $sf->{i}{ok} );

    CUSTOMIZE: while ( 1 ) {
        $backup_sql = clone( $sql ) if $sql_type eq 'Select';
        $ax->print_sql( $sql, [ $sql_type ] );
        ###
        my $choices = [ $cu{hidden}, undef, @cu{@{$sub_stmts->{$sql_type}}} ];
        my $idx;
        if ( $sql_type eq 'Insert' ) {
            my $old_custom = $choices->[$old_idx];
            $idx = defined $old_custom && $old_custom eq $cu{'insert'}
                   ? first_index { defined $_ && $_ eq $cu{'commit'} } @$choices
                   : first_index { defined $_ && $_ eq $cu{'insert'} } @$choices;
        }
        else {
            # Choose
            $idx = choose(
                $choices,
                { %{$sf->{i}{lyt_stmt_v}}, prompt => '', index => 1, default => $old_idx,
                undef => $sql_type ne 'Select' ? $sf->{i}{_back} : $sf->{i}{back} } # lyt_m layout 3
            );
            if ( ! defined $idx || ! defined $choices->[$idx] ) {
                if ( $sql_type eq 'Select'  ) {
                    last CUSTOMIZE;
                }
                else {
                    if ( $sql->{where_stmt} || $sql->{set_stmt} ) {
                        $ax->reset_sql( $sql );
                        next CUSTOMIZE;
                    }
                    else {
                        $sql_type = 'Select';
                        $old_idx = 1;
                        $sql = clone $backup_sql;
                        next CUSTOMIZE;
                    }
                }
            }
        }
        my $custom = $choices->[$idx];
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 1;
                next CUSTOMIZE;
            }
            else {
                $old_idx = $idx;
            }
        }
        if ( $custom eq $cu{'lock'} ) {
            if ( $sf->{i}{lock} == 1 ) {
                $sf->{i}{lock} = 0;
                $cu{lock} = $lk->[0];
                $ax->reset_sql( $sql );
            }
            elsif ( $sf->{i}{lock} == 0 )   {
                $sf->{i}{lock} = 1;
                $cu{lock} = $lk->[1];
            }
        }
        elsif ( $custom eq $cu{'insert'} ) { # pos
            require App::DBBrowser::Table::Insert;
            my $tbl_in = App::DBBrowser::Table::Insert->new( $sf->{i}, $sf->{o} );
            $tbl_in->build_insert_stmt( $sql, [ $sql_type ], $dbh );
        }
        elsif ( $custom eq $cu{'columns'} ) {
            if ( ! ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) ) {
                $ax->reset_sql( $sql );
            }
            my @cols = ( @{$sql->{cols}} );
            $sql->{chosen_cols} = [];
            $sql->{select_type} = 'chosen_cols';

            COLUMNS: while ( 1 ) {
                my $choices = [ @pre, @cols ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my @qt_cols = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @qt_cols || ! defined $qt_cols[0] ) {
                    if ( @{$sql->{chosen_cols}} ) {
                        $sql->{chosen_cols} = [];
                        delete $sql->{orig_cols}{chosen_cols};
                        next COLUMNS;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last COLUMNS;
                    }
                }
                if ( $qt_cols[0] eq $sf->{i}{ok} ) {
                    shift @qt_cols;
                    for my $quote_col ( @qt_cols ) {
                        push @{$sql->{chosen_cols}}, $quote_col;
                    }
                    if ( ! @{$sql->{chosen_cols}} ) {
                        $sql->{select_type} = '*';
                    }
                    delete $sql->{orig_cols}{chosen_cols};
                    $sql->{modified_cols} = [];
                    last COLUMNS;
                }
                for my $quote_col ( @qt_cols ) {
                    push @{$sql->{chosen_cols}}, $quote_col;
                }
            }
        }
        elsif ( $custom eq $cu{'distinct'} ) {
            $sql->{distinct_stmt} = '';

            DISTINCT: while ( 1 ) {
                my $choices = [ @pre, $DISTINCT, $ALL ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $select_distinct = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $select_distinct ) {
                    if ( $sql->{distinct_stmt} ) {
                        $sql->{distinct_stmt} = '';
                        next DISTINCT;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last DISTINCT;
                    }
                }
                if ( $select_distinct eq $sf->{i}{ok} ) {
                    last DISTINCT;
                }
                $sql->{distinct_stmt} = ' ' . $select_distinct;
            }
        }
        elsif ( $custom eq $cu{'aggregate'} ) {
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                $ax->reset_sql( $sql );
            }
            my @cols = ( @{$sql->{cols}} );
            $sql->{aggr_cols} = [];
            $sql->{select_type} = 'aggr_cols';

            AGGREGATE: while ( 1 ) {
                my $choices = [ @pre, @aggregate ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $aggr = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $aggr ) {
                    if ( @{$sql->{aggr_cols}} ) {
                        $sql->{aggr_cols} = [];
                        delete $sql->{orig_cols}{aggr_cols};
                        next AGGREGATE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last AGGREGATE;
                    }
                }
                if ( $aggr eq $sf->{i}{ok} ) {
                    delete $sql->{orig_cols}{aggr_cols};
                    if ( ! @{$sql->{aggr_cols}} && ! @{$sql->{group_by_cols}} ) {
                        $sql->{select_type} = '*';
                    }
                    last AGGREGATE;
                }
                my $i = @{$sql->{aggr_cols}};
                if ( $aggr eq 'COUNT(*)' ) {
                    $sql->{aggr_cols}[$i] = $aggr;
                }
                else {
                    $aggr =~ s/\(\S\)\z//; #
                    $sql->{aggr_cols}[$i] = $aggr . "(";
                    if ( $aggr eq 'COUNT' ) {
                        my $choices = [ $ALL, $DISTINCT ];
                        $ax->print_sql( $sql, [ $sql_type ] );
                        # Choose
                        my $all_or_distinct = $stmt_h->choose(
                            $choices
                        );
                        if ( ! defined $all_or_distinct ) {
                            $sql->{aggr_cols} = [];
                            next AGGREGATE;
                        }
                        if ( $all_or_distinct eq $DISTINCT ) {
                            $sql->{aggr_cols}[$i] .= $DISTINCT . ' ';
                        }
                    }
                    my $choices = [ @cols ];
                    $ax->print_sql( $sql, [ $sql_type ] );
                    # Choose
                    my $quote_col = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $quote_col ) {
                        $sql->{aggr_cols} = [];
                        next AGGREGATE;
                    }
                    $sql->{aggr_cols}[$i] .= $quote_col . ")";
                }
            }
        }
        elsif ( $custom eq $cu{'set'} ) {
            my @cols = ( @{$sql->{cols}} );
            my $trs = Term::Form->new();
            my $col_sep = ' ';
            $sql->{set_args} = [];
            $sql->{set_stmt} = " SET";

            SET: while ( 1 ) {
                my $choices = [ @pre, @cols ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $quote_col = $stmt_h->choose( # copy ?
                    $choices,
                );
                if ( ! defined $quote_col ) {
                    if ( @{$sql->{set_args}} ) {
                        $sql->{set_args} = [];
                        $sql->{set_stmt} = " SET";
                        $col_sep = ' ';
                        next SET;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last SET;
                    }
                }
                if ( $quote_col eq $sf->{i}{ok} ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{set_stmt} = '';
                    }
                    last SET;
                }
                $sql->{set_stmt} .= $col_sep . $quote_col . ' =';
                $ax->print_sql( $sql, [ $sql_type ] );
                # Readline
                my $value = $trs->readline( $quote_col . ': ' );
                if ( ! defined $value ) {
                    if ( @{$sql->{set_args}} ) {
                        $sql->{set_args} = [];
                        $sql->{set_stmt} = " SET";
                        $col_sep = ' ';
                        next SET;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last SET;
                    }
                }
                $sql->{set_stmt} .= ' ' . '?';
                push @{$sql->{set_args}}, $value;
                $col_sep = ', ';
            }
        }
        elsif ( $custom eq $cu{'where'} ) {
            my @cols = ( @{$sql->{cols}}, @{$sql->{modified_cols}} );
            my $AND_OR = ' ';
            $sql->{where_args} = [];
            $sql->{where_stmt} = " WHERE";
            my $unclosed = 0;
            my $count = 0;

            WHERE: while ( 1 ) {
                my @choices = @cols;
                if ( $sf->{o}{G}{parentheses_w} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $quote_col = $stmt_h->choose(
                    [ @pre, @choices ]
                );
                if ( ! defined $quote_col ) {
                    if ( $sql->{where_stmt} ne " WHERE" ) {
                        $sql->{where_args} = [];
                        $sql->{where_stmt} = " WHERE";
                        $count = 0;
                        $AND_OR = ' ';
                        next WHERE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last WHERE;
                    }
                }
                if ( $quote_col eq $sf->{i}{ok} ) {
                    if ( $count == 0 ) {
                        $sql->{where_stmt} = '';
                    }
                    last WHERE;
                }
                if ( $quote_col eq ')' ) {
                    $sql->{where_stmt} .= ")";
                    $unclosed--;
                    next WHERE;
                }
                if ( $count > 0 && $sql->{where_stmt} !~ /\(\z/ ) { #
                    my $choices = [ undef, $AND, $OR ];
                    $ax->print_sql( $sql, [ $sql_type ] );
                    # Choose
                    $AND_OR = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $AND_OR ) { # (
                        #$sql->{where_args} = [];
                        #$sql->{where_stmt} = " WHERE";
                        #$count = 0;
                        #$AND_OR = ' ';
                        next WHERE;
                    }
                    $AND_OR = ' ' . $AND_OR . ' ';
                }
                if ( $quote_col eq '(' ) {
                    $sql->{where_stmt} .= $AND_OR . "(";
                    $AND_OR = '';
                    $unclosed++;
                    next WHERE;
                }
                $sql->{where_stmt} .= $AND_OR . $quote_col;
                $sf->__set_operator_sql( $sql, 'where', \@cols, $quote_col, $sql_type );
                if ( ! $sql->{where_stmt} ) {
                    $sql->{where_args} = [];
                    $sql->{where_stmt} = " WHERE";
                    $count = 0;
                    $AND_OR = ' ';
                    next WHERE;
                }
                $count++;
            }
        }
        elsif ( $custom eq $cu{'group_by'} ) {
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                $ax->reset_sql( $sql );
            }
            my @cols = ( @{$sql->{cols}} );
            my $col_sep = ' ';
            $sql->{group_by_stmt} = " GROUP BY";
            $sql->{group_by_cols} = [];
            $sql->{select_type} = 'group_by_cols';

            GROUP_BY: while ( 1 ) {
                my $choices = [ @pre, @cols ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my @qt_cols = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @qt_cols || ! defined $qt_cols[0] ) {
                    if ( @{$sql->{group_by_cols}} ) {
                        $sql->{group_by_stmt} = " GROUP BY";
                        $sql->{group_by_cols} = [];
                        $col_sep = ' ';
                        delete $sql->{orig_cols}{group_by_cols};
                        next GROUP_BY;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last GROUP_BY;
                    }
                }
                if ( $qt_cols[0] eq $sf->{i}{ok} ) {
                    shift @qt_cols;
                    for my $quote_col ( @qt_cols ) {
                        push @{$sql->{group_by_cols}}, $quote_col;
                        $sql->{group_by_stmt} .= $col_sep . $quote_col;
                        $col_sep = ', ';
                    }
                    if ( $col_sep eq ' ' ) {
                        $sql->{group_by_stmt} = '';
                        if ( ! @{$sql->{aggr_cols}} ) {
                            $sql->{select_type} = '*';
                        }
                        delete $sql->{orig_cols}{group_by_cols};
                    }
                    last GROUP_BY;
                }
                for my $quote_col ( @qt_cols ) {
                    push @{$sql->{group_by_cols}}, $quote_col;
                    $sql->{group_by_stmt} .= $col_sep . $quote_col;
                    $col_sep = ', ';
                }
            }
        }
        elsif ( $custom eq $cu{'having'} ) {
            my @cols = ( @{$sql->{cols}} );
            my $AND_OR = ' ';
            $sql->{having_args} = [];
            $sql->{having_stmt} = " HAVING";
            my $unclosed = 0;
            my $count = 0;

            HAVING: while ( 1 ) {
                my @choices = ( @aggregate, map( '@' . $_, @{$sql->{aggr_cols}} ) ); #####
                if ( $sf->{o}{G}{parentheses_h} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $aggr = $stmt_h->choose(
                    [ @pre, @choices ]
                );
                if ( ! defined $aggr ) {
                    if ( $sql->{having_stmt} ne " HAVING" ) {
                        $sql->{having_args} = [];
                        $sql->{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last HAVING;
                    }
                }
                if ( $aggr eq $sf->{i}{ok} ) {
                    if ( $count == 0 ) {
                        $sql->{having_stmt} = '';
                    }
                    last HAVING;
                }
                if ( $aggr eq ')' ) {
                    $sql->{having_stmt} .= ")";
                    $unclosed--;
                    next HAVING;
                }
                if ( $count > 0 && $sql->{having_stmt} !~ /\(\z/ ) { #
                    my $choices = [ undef, $AND, $OR ];
                    $ax->print_sql( $sql, [ $sql_type ] );
                    # Choose
                    $AND_OR = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $AND_OR ) {
                        #$sql->{having_args} = [];
                        #$sql->{having_stmt} = " HAVING";
                        #$count = 0;
                        #$AND_OR = ' ';
                        next HAVING;
                    }
                    $AND_OR = ' ' . $AND_OR . ' ';
                }
                if ( $aggr eq '(' ) {
                    $sql->{having_stmt} .= $AND_OR . "(";
                    $AND_OR = '';
                    $unclosed++;
                    next HAVING;
                }
                my ( $quote_col, $quote_aggr);
                if ( ( any { '@' . $_ eq $aggr } @{$sql->{aggr_cols}} ) ) { #
                    ( $quote_aggr = $aggr ) =~ s/^\@//; #
                    $sql->{having_stmt} .= $AND_OR . $quote_aggr;
                }
                elsif ( $aggr eq 'COUNT(*)' ) {
                    $quote_col = '*';
                    $quote_aggr = $aggr;
                    $sql->{having_stmt} .= $AND_OR . $quote_aggr;
                }
                else {
                    $aggr =~ s/\(\S\)\z//;
                    $sql->{having_stmt} .= $AND_OR . $aggr . "(";
                    $quote_aggr          =           $aggr . "(";
                    my $choices = [ @cols ];
                    $ax->print_sql( $sql, [ $sql_type ] );
                    # Choose
                    $quote_col = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $quote_col ) {
                        $sql->{having_args} = [];
                        $sql->{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    $sql->{having_stmt} .= $quote_col . ")";
                    $quote_aggr         .= $quote_col . ")";
                }
                $sf->__set_operator_sql( $sql, 'having', \@cols, $quote_aggr, $sql_type ); #
                if ( ! $sql->{having_stmt} ) {
                    $sql->{having_args} = [];
                    $sql->{having_stmt} = " HAVING";
                    $count = 0;
                    $AND_OR = ' ';
                    next HAVING;
                }
                $count++;
            }
        }
        elsif ( $custom eq $cu{'order_by'} ) {
            my @cols;
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                @cols = ( @{$sql->{cols}}, @{$sql->{modified_cols}} );
            }
            else {
                @cols = ( @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} );
                for my $stmt_type ( qw/group_by_cols aggr_cols/ ) { # offer order by unmodified columns
                    for my $i ( 0 .. $#{$sql->{$stmt_type}} ) {
                        next if ! exists $sql->{orig_cols}{$stmt_type};
                        if ( $sql->{orig_cols}{$stmt_type}[$i] ne $sql->{$stmt_type}[$i] ) {
                            push @cols, $sql->{orig_cols}{$stmt_type}[$i];
                        }
                    }
                }
            }
            my $col_sep = ' ';
            $sql->{order_by_stmt} = " ORDER BY";

            ORDER_BY: while ( 1 ) {
                my $choices = [ @pre, @cols ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $quote_col = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $quote_col ) {
                    if ( $sql->{order_by_stmt} ne " ORDER BY" ) {
                        $sql->{order_by_stmt} = " ORDER BY";
                        $col_sep = ' ';
                        next ORDER_BY;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last ORDER_BY;
                    }
                }
                if ( $quote_col eq $sf->{i}{ok} ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{order_by_stmt} = '';
                    }
                    last ORDER_BY;
                }
                $sql->{order_by_stmt} .= $col_sep . $quote_col;
                $choices = [ undef, $ASC, $DESC ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $direction = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $direction ){
                    #$sql->{order_by_stmt} = " ORDER BY";
                    #$col_sep = ' ';
                    $col_sep = ', ';
                    next ORDER_BY;
                }
                $sql->{order_by_stmt} .= ' ' . $direction;
                $col_sep = ', ';
            }
        }
        elsif ( $custom eq $cu{'limit'} ) {
            $sql->{limit_stmt} = " LIMIT";

            LIMIT: while ( 1 ) {
                my ( $only_limit, $offset_and_limit ) = ( 'LIMIT', 'OFFSET-LIMIT' );
                my $choices = [ @pre, $only_limit, $offset_and_limit ];
                $ax->print_sql( $sql, [ $sql_type ] );
                # Choose
                my $choice = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $choice ) {
                    if ( $sql->{limit_stmt} ne " LIMIT" ) {
                        $sql->{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last LIMIT;
                    }
                }
                if ( $choice eq $sf->{i}{ok} ) {
                    if ( $sql->{limit_stmt} eq " LIMIT" ) {
                        $sql->{limit_stmt} = '';
                    }
                    last LIMIT;
                }
                $sql->{limit_stmt} = " LIMIT";
                my $digits = 7;
                # Choose_a_number
                my $limit = choose_a_number( $digits, { name => '"LIMIT"', mouse => $sf->{o}{table}{mouse} } );
                next LIMIT if ! defined $limit || $limit eq '--';
                $sql->{limit_stmt} .= ' ' . sprintf '%d', $limit;
                if ( $choice eq $offset_and_limit ) {
                    # Choose_a_number
                    my $offset = choose_a_number( $digits, { name => '"OFFSET"', mouse => $sf->{o}{table}{mouse} } );
                    if ( ! defined $offset || $offset eq '--' ) {
                        $sql->{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    $sql->{limit_stmt} .= " OFFSET " . sprintf '%d', $offset;
                }
            }
        }
        elsif ( $custom eq $cu{'hidden'} ) { # [insert/update/delete]
            $sql_type = $sf->__table_write_access( $sql, $sql_type );
            $old_idx = 1;
        }
        elsif ( $custom eq $cu{'functions'} ) {
            my $nh = App::DBBrowser::Table::Functions->new( $sf->{i}, $sf->{o} );
            $nh->col_function( $dbh, $sql, $backup_sql, $sql_type ); #
        }
        elsif ( $custom eq $cu{'print_tbl'} ) {
            my $cols_sql = " ";
            if ( $sql->{select_type} eq '*' ) {
                if ( $sf->{i}{multi_tbl} eq 'join' ) {
                    $cols_sql .= join( ', ', @{$sql->{cols}} ); # ?
                }
                else {
                    $cols_sql .= "*";
                }
            }
            elsif ( $sql->{select_type} eq 'chosen_cols' ) {
                $cols_sql .= join( ', ', @{$sql->{chosen_cols}} );
            }
            elsif ( @{$sql->{aggr_cols}} || @{$sql->{group_by_cols}} ) {
                $cols_sql .= join( ', ', @{$sql->{group_by_cols}}, @{$sql->{aggr_cols}} );
            }
            #else {
            #    $cols_sql .= "*";
            #}
            my $select .= "SELECT" . $sql->{distinct_stmt} . $cols_sql;
            $select .= " FROM " . $sql->{table};
            $select .= $sql->{where_stmt};
            $select .= $sql->{group_by_stmt};
            $select .= $sql->{having_stmt};
            $select .= $sql->{order_by_stmt};
            $select .= $sql->{limit_stmt};
            if ( $sf->{o}{G}{max_rows} && ! $sql->{limit_stmt} ) {
                $select .= sprintf " LIMIT %d", $sf->{o}{G}{max_rows};
                $sf->{o}{table}{max_rows} = $sf->{o}{G}{max_rows};
            }
            else {
                $sf->{o}{table}{max_rows} = 0;
            }
            my @arguments = ( @{$sql->{where_args}}, @{$sql->{having_args}} );
            local $| = 1;
            print $sf->{i}{clear_screen};
            print 'Database : ...' . "\n" if $sf->{o}{table}{progress_bar};
            my $sth = $dbh->prepare( $select );
            $sth->execute( @arguments );
            my $col_names = $sth->{NAME}; # not quoted
            my $all_arrayref = $sth->fetchall_arrayref;
            unshift @$all_arrayref, $col_names;
            print $sf->{i}{clear_screen};
            # return $sql explicitly since after a `$sql = clone( $backup )` $sql refers to a different hash.
            return $all_arrayref, $sql;
        }
        elsif ( $custom eq $cu{'commit'} ) {
            my $ok = $sf->commit_sql( $sql, [ $sql_type ], $dbh );
            if ( ! $ok ) {
                $old_idx = 1 if $sql_type eq 'Insert'; #
                $ax->reset_sql( $sql );
                next CUSTOMIZE;
            }
            $sql_type = 'Select';
            $old_idx = 1;
            $sql = clone $backup_sql;
            next CUSTOMIZE;
        }
        else {
            die "$custom: no such value in the hash \%cu";
        }
    }
    return;
}


sub commit_sql {
    my ( $sf, $sql, $sql_typeS, $dbh ) = @_;
    my $ax  = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $stmt_v = Term::Choose->new( $sf->{i}{lyt_stmt_v} );
    local $| = 1;
    print $sf->{i}{clear_screen};
    print 'Database : ...' . "\n" if $sf->{o}{table}{progress_bar};
    my $transaction;
    eval { $transaction = $dbh->begin_work } or do { $dbh->{AutoCommit} = 1; $transaction = 0 };
    my $rows_to_execute = [];
    my $stmt;
    my $sql_type = $sql_typeS->[-1];
    if ( $sql_type eq 'Insert' ) {
        return 1 if ! @{$sql->{insert_into_args}}; #
        $stmt  = "INSERT INTO";
        $stmt .= ' ' . $sql->{table};
        $stmt .= " ( " . join( ', ', @{$sql->{insert_into_cols}} ) . " )";
        $stmt .= " VALUES( " . join( ', ', ( '?' ) x @{$sql->{insert_into_cols}} ) . " )";
        $rows_to_execute = $sql->{insert_into_args};
    }
    else {
        my %map_sql_types = (
            Update => "UPDATE",
            Delete => "DELETE",
        );
        $stmt  = $map_sql_types{$sql_type};
        $stmt .= " FROM"               if $map_sql_types{$sql_type} eq "DELETE";
        $stmt .= ' ' . $sql->{table};
        $stmt .= $sql->{set_stmt}      if $sql->{set_stmt};
        $stmt .= $sql->{where_stmt}    if $sql->{where_stmt};
        $rows_to_execute->[0] = [ @{$sql->{set_args}}, @{$sql->{where_args}} ];
    }
    if ( $transaction ) {
        my $rolled_back;
        if ( ! eval {
            my $sth = $dbh->prepare( $stmt );
            for my $values ( @$rows_to_execute ) {
                $sth->execute( @$values );
            }
            my $row_count   = $sql_type eq 'Insert' ? @$rows_to_execute : $sth->rows;
            my $commit_ok = sprintf qq(  %s %d "%s"), 'COMMIT', $row_count, $sql_type; # show count of affected rows
            $ax->print_sql( $sql, $sql_typeS );
            my $choices = [ undef,  $commit_ok ];
            # Choose
            my $choice = $stmt_v->choose(
                $choices
            );
            if ( defined $choice && $choice eq $commit_ok ) {;
                $dbh->commit;
            }
            else {
                $dbh->rollback;
                $rolled_back = 1;
            }
            1 }
        ) {
            $ax->print_error_message( "$@Rolling back ...\n", 'Commit' );
            $dbh->rollback;
            $rolled_back = 1;
        }
        if ( $rolled_back ) {
            return;
        }
    }
    else {
        my $row_count;
        if ( $sql_type eq 'Insert' ) {
            $row_count = @$rows_to_execute;
        }
        else {
            my $count_stmt;
            $count_stmt .= "SELECT COUNT(*) FROM " . $sql->{table};
            $count_stmt .= $sql->{where_stmt};
            ( $row_count ) = $dbh->selectrow_array( $count_stmt, undef, @{$sql->{where_args}} );
        }
        my $commit_ok = sprintf qq(  %s %d "%s"), 'EXECUTE', $row_count, $sql_type;
        $ax->print_sql( $sql, $sql_typeS ); #
        my $choices = [ undef,  $commit_ok ];
        # Choose
        my $choice = $stmt_v->choose(
            $choices,
            { prompt => '' }
        );
        if ( defined $choice && $choice eq $commit_ok ) {
            if ( ! eval {
                my $sth = $dbh->prepare( $stmt );
                for my $values ( @$rows_to_execute ) {
                    $sth->execute( @$values );
                }
                1 }
            ) {
                $ax->print_error_message( $@, 'Commit' );
                return;
            }
        }
        else {
            return;
        }
    }
    return 1;
}


sub __set_operator_sql {
    my ( $sf, $sql, $clause, $cols, $quote_col, $sql_type ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my ( $stmt, $args );
    my $stmt_h = Term::Choose->new( $sf->{i}{lyt_stmt_h} );
    if ( $clause eq 'where' ) {
        $stmt = 'where_stmt';
        $args = 'where_args';
    }
    elsif ( $clause eq 'having' ) {
        $stmt = 'having_stmt';
        $args = 'having_args';
    }
    my $choices = [ @{$sf->{o}{G}{operators}} ];
    $ax->print_sql( $sql, [ $sql_type ] );
    # Choose
    my $operator = $stmt_h->choose(
        $choices
    );
    if ( ! defined $operator ) {
        $sql->{$args} = [];
        $sql->{$stmt} = '';
        return;
    }
    $operator =~ s/^\s+|\s+\z//g;
    if ( $operator !~ /\s%?col%?\z/ ) {
        if ( $operator !~ /REGEXP(_i)?\z/ ) {
            $sql->{$stmt} .= ' ' . $operator;
        }
        my $trs = Term::Form->new();
        if ( $operator =~ /NULL\z/ ) { # add ^(?:NOT\s)?
            # do nothing
        }
        elsif ( $operator =~ /^(?:NOT\s)?IN\z/ ) {
            my $col_sep = '';
            $sql->{$stmt} .= '(';

            IN: while ( 1 ) {
                $ax->print_sql( $sql, [ $sql_type ] );
                # Readline
                my $value = $trs->readline( 'Value: ' );
                if ( ! defined $value ) {
                    $sql->{$args} = [];
                    $sql->{$stmt} = '';
                    return;
                }
                if ( $value eq '' ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{$args} = [];
                        $sql->{$stmt} = '';
                        return;
                    }
                    $sql->{$stmt} .= ')';
                    last IN;
                }
                $sql->{$stmt} .= $col_sep . '?';
                push @{$sql->{$args}}, $value;
                $col_sep = ',';
            }
        }
        elsif ( $operator =~ /^(?:NOT\s)?BETWEEN\z/ ) {
            $ax->print_sql( $sql, [ $sql_type ] );
            # Readline
            my $value_1 = $trs->readline( 'Value: ' );
            if ( ! defined $value_1 ) {
                $sql->{$args} = [];
                $sql->{$stmt} = '';
                return;
            }
            $sql->{$stmt} .= ' ' . '?' .      ' AND';
            push @{$sql->{$args}}, $value_1;
            $ax->print_sql( $sql, [ $sql_type ] );
            # Readline
            my $value_2 = $trs->readline( 'Value: ' );
            if ( ! defined $value_2 ) {
                $sql->{$args} = [];
                $sql->{$stmt} = '';
                return;
            }
            $sql->{$stmt} .= ' ' . '?';
            push @{$sql->{$args}}, $value_2;
        }
        elsif ( $operator =~ /REGEXP(_i)?\z/ ) {
            $ax->print_sql( $sql, [ $sql_type ] );
            # Readline
            my $value = $trs->readline( 'Pattern: ' );
            if ( ! defined $value ) {
                $sql->{$args} = [];
                $sql->{$stmt} = '';
                return;
            }
            $value = '^$' if ! length $value;
            $sql->{$stmt} =~ s/\s\Q$quote_col\E\z//;
            my $do_not_match_regexp = $operator =~ /^NOT/       ? 1 : 0;
            my $case_sensitive      = $operator =~ /REGEXP_i\z/ ? 0 : 1;
            if ( ! eval {
                my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
                $sql->{$stmt} .= $obj_db->regexp_sql( $quote_col, $do_not_match_regexp, $case_sensitive );
                push @{$sql->{$args}}, $value;
                1 }
            ) {
                $ax->print_error_message( $@, $operator );
                $sql->{$args} = [];
                $sql->{$stmt} = '';
                return;
            }
        }
        else {
            $ax->print_sql( $sql, [ $sql_type ] );
            my $prompt = $operator =~ /LIKE\z/ ? 'Pattern: ' : 'Value: ';
            # Readline
            my $value = $trs->readline( $prompt );
            if ( ! defined $value ) {
                $sql->{$args} = [];
                $sql->{$stmt} = '';
                return;
            }
            $sql->{$stmt} .= ' ' . '?';
            push @{$sql->{$args}}, $value;
        }
    }
    elsif ( $operator =~ /\s%?col%?\z/ ) {
        my $arg;
        if ( $operator =~ /^(.+)\s(%?col%?)\z/ ) {
            $operator = $1;
            $arg = $2;
        }
        $operator =~ s/^\s+|\s+\z//g;
        $sql->{$stmt} .= ' ' . $operator;
        my $choices = [ @$cols ];
        $ax->print_sql( $sql, [ $sql_type ] );
        # Choose
        my $quote_col = $stmt_h->choose(
            $choices,
            { prompt => "$operator:" }
        );
        if ( ! defined $quote_col ) {
            $sql->{$stmt} = '';
            return;
        }
        if ( $arg !~ /%/ ) {
            $sql->{$stmt} .= ' ' . $quote_col;
        }
        else {
            if ( ! eval {
                my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
                my @el = map { "'$_'" } grep { length $_ } $arg =~ /^(%?)(col)(%?)\z/g;
                my $qt_arg = $obj_db->concatenate( \@el );
                $qt_arg =~ s/'col'/$quote_col/;
                $sql->{$stmt} .= ' ' . $qt_arg;
                1 }
            ) {
                $ax->print_error_message( $@, $operator . ' ' . $arg );
                $sql->{$stmt} = '';
                return;
            }
        }
    }
    return;
}


sub __table_write_access {
    my ( $sf, $sql, $sql_type ) = @_;
    my @sql_types;
    if ( ! $sf->{i}{multi_tbl} ) {
        @sql_types = ( 'Insert', 'Update', 'Delete' );
    }
    elsif ( $sf->{i}{multi_tbl} eq 'join' && $sf->{i}{driver} eq 'mysql' ) {
        @sql_types = ( 'Update' );
    }
    else {
        @sql_types = ();
    }
    if ( ! @sql_types ) {
        return; ###
    }
    my $ch_types = [ undef, map( "- $_", @sql_types ) ];
    # Choose
    my $type_choice = choose(
        $ch_types,
        { %{$sf->{i}{lyt_3}}, prompt => 'Choose SQL type:', default => 0 }
    );
    if ( defined $type_choice ) {
        ( $sql_type = $type_choice ) =~ s/^-\ //;
        my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
        $ax->reset_sql( $sql );
    }
    return $sql_type;
}


1;


__END__

package # hide from PAUSE
App::DBBrowser::Table;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.040_05';

use Clone                  qw( clone );
use List::MoreUtils        qw( any first_index );
use Term::Choose           qw();
use Term::Choose::Util     qw( choose_a_number choose_multi insert_sep term_size );
use Term::ReadLine::Simple qw();
use Text::LineFold         qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::DBBrowser::DB;
#use App::DBBrowser::Table::Insert;  # "require"-d
use App::DBBrowser::Util;

sub CLEAR_SCREEN () { "\e[H\e[J" }



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __on_table {
    my ( $self, $sql, $dbh, $table, $select_from_stmt, $qt_columns, $pr_columns ) = @_;
    my $util = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my $sub_stmts = {
        Select => [ qw( print_table columns aggregate distinct where group_by having order_by limit lock ) ],
        Delete => [ qw( commit     where ) ], # order_by limit
        Update => [ qw( commit set where ) ],
        Insert => [ qw( commit insert    ) ],
    };
    my $sql_types = [ 'Delete', 'Update', 'Insert' ];
    my $sql_type = 'Select';
    my $lk = [ '  Lk0', '  Lk1' ];
    my %customize = (
        hidden          => 'Customize:',
        print_table     => 'Print TABLE',
        commit          => '  Confirm SQL',
        columns         => '- SELECT',
        set             => '- SET',
        insert          => '  Columns and values',
        aggregate       => '- AGGREGATE',
        distinct        => '- DISTINCT',
        where           => '- WHERE',
        group_by        => '- GROUP BY',
        having          => '- HAVING',
        order_by        => '- ORDER BY',
        limit           => '- LIMIT',
        lock            => $lk->[$self->{info}{lock}],
    );
    my ( $DISTINCT, $ALL, $ASC, $DESC, $AND, $OR ) = ( "DISTINCT", "ALL", "ASC", "DESC", "AND", "OR" );
    if ( $self->{info}{lock} == 0 ) {
        $util->__reset_sql( $sql );
    }
    my $backup_sql = clone( $sql );
    my $old_idx = 1;

    CUSTOMIZE: while ( 1 ) {
        $backup_sql = clone( $sql ) if $sql_type eq 'Select';
        $util->__print_sql_statement( $sql, $table, $sql_type );
        my $choices = [ $customize{hidden}, undef, @customize{@{$sub_stmts->{$sql_type}}} ];
        # Choose
        my $idx = $stmt_h->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => '', index => 1, default => $old_idx, undef => $self->{info}{back} }
        );
        last CUSTOMIZE if ! defined $idx;
        my $custom = $choices->[$idx];
        last CUSTOMIZE if ! defined $custom;
        #if ( ! defined $custom ) {
        #    last CUSTOMIZE if $sql_type eq 'Select';
        #    $sql_type = 'Select';
        #    $old_idx = 1;
        #    next CUSTOMIZE;
        #}
        if ( $self->{opt}{menu_sql_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 1;
                next CUSTOMIZE;
            }
            else {
                $old_idx = $idx;
            }
        }
        if ( $custom eq $customize{'lock'} ) {
            if ( $self->{info}{lock} == 1 ) {
                $self->{info}{lock} = 0;
                $customize{lock} = $lk->[0];
                $util->__reset_sql( $sql );
            }
            elsif ( $self->{info}{lock} == 0 )   {
                $self->{info}{lock} = 1;
                $customize{lock} = $lk->[1];
            }
        }
        elsif ( $custom eq $customize{'insert'} ) {

            require App::DBBrowser::Table::Insert;
            my $tbl_in = App::DBBrowser::Table::Insert->new( $self->{info}, $self->{opt} );
            $tbl_in->__insert_into( $sql, $table,$qt_columns, $pr_columns, $backup_sql );
        }
        elsif ( $custom eq $customize{'columns'} ) {
            if ( ! ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) ) {
                $util->__reset_sql( $sql );
            }
            my @cols = ( @$pr_columns );
            $sql->{quote}{chosen_cols} = [];
            $sql->{print}{chosen_cols} = [];
            $sql->{select_type} = 'chosen_cols';

            COLUMNS: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, @cols ];
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my @print_col = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @print_col || ! defined $print_col[0] ) {
                    if ( @{$sql->{quote}{chosen_cols}} ) {
                        $sql->{quote}{chosen_cols} = [];
                        $sql->{print}{chosen_cols} = [];
                        delete $sql->{pr_backup_in_hidd}{chosen_cols};
                        next COLUMNS;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last COLUMNS;
                    }
                }
                if ( $print_col[0] eq $self->{info}{ok} ) {
                    shift @print_col;
                    for my $print_col ( @print_col ) {
                        push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
                        push @{$sql->{print}{chosen_cols}}, $print_col;
                    }
                    if ( ! @{$sql->{quote}{chosen_cols}} ) {
                        $sql->{select_type} = '*';
                    }
                    delete $sql->{pr_backup_in_hidd}{chosen_cols};
                    $sql->{pr_col_with_hidd_func} = [];
                    last COLUMNS;
                }
                for my $print_col ( @print_col ) {
                    push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
                    push @{$sql->{print}{chosen_cols}}, $print_col;
                }
            }
        }
        elsif ( $custom eq $customize{'distinct'} ) {
            $sql->{quote}{distinct_stmt} = '';
            $sql->{print}{distinct_stmt} = '';

            DISTINCT: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, $DISTINCT, $ALL ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $select_distinct = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $select_distinct ) {
                    if ( $sql->{quote}{distinct_stmt} ) {
                        $sql->{quote}{distinct_stmt} = '';
                        $sql->{print}{distinct_stmt} = '';
                        next DISTINCT;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last DISTINCT;
                    }
                }
                if ( $select_distinct eq $self->{info}{ok} ) {
                    last DISTINCT;
                }
                $sql->{quote}{distinct_stmt} = ' ' . $select_distinct;
                $sql->{print}{distinct_stmt} = ' ' . $select_distinct;
            }
        }
        elsif ( $custom eq $customize{'aggregate'} ) {
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                $util->__reset_sql( $sql );
            }
            my @cols = ( @$pr_columns );
            $sql->{quote}{aggr_cols} = [];
            $sql->{print}{aggr_cols} = [];
            $sql->{select_type} = 'aggr_cols';

            AGGREGATE: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, @{$self->{info}{avail_aggregate}} ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $aggr = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $aggr ) {
                    if ( @{$sql->{quote}{aggr_cols}} ) {
                        $sql->{quote}{aggr_cols} = [];
                        $sql->{print}{aggr_cols} = [];
                        delete $sql->{pr_backup_in_hidd}{aggr_cols};
                        next AGGREGATE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last AGGREGATE;
                    }
                }
                if ( $aggr eq $self->{info}{ok} ) {
                    delete $sql->{pr_backup_in_hidd}{aggr_cols};
                    if ( ! @{$sql->{quote}{aggr_cols}} && ! @{$sql->{quote}{group_by_cols}} ) {
                        $sql->{select_type} = '*';
                    }
                    last AGGREGATE;
                }
                my $i = @{$sql->{quote}{aggr_cols}};
                if ( $aggr eq 'COUNT(*)' ) {
                    $sql->{print}{aggr_cols}[$i] = $aggr;
                    $sql->{quote}{aggr_cols}[$i] = $aggr;
                }
                else {
                    $aggr =~ s/\(\S\)\z//;
                    $sql->{quote}{aggr_cols}[$i] = $aggr . "(";
                    $sql->{print}{aggr_cols}[$i] = $aggr . "(";
                    if ( $aggr eq 'COUNT' ) {
                        my $choices = [ $ALL, $DISTINCT ];
                        unshift @$choices, undef if $self->{opt}{sssc_mode};
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Choose
                        my $all_or_distinct = $stmt_h->choose(
                            $choices
                        );
                        if ( ! defined $all_or_distinct ) {
                            $sql->{quote}{aggr_cols} = [];
                            $sql->{print}{aggr_cols} = [];
                            next AGGREGATE;
                        }
                        if ( $all_or_distinct eq $DISTINCT ) {
                            $sql->{quote}{aggr_cols}[$i] .= $DISTINCT . ' ';
                            $sql->{print}{aggr_cols}[$i] .= $DISTINCT . ' ';
                        }
                    }
                    my $choices = [ @cols ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Choose
                    my $print_col = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $print_col ) {
                        $sql->{quote}{aggr_cols} = [];
                        $sql->{print}{aggr_cols} = [];
                        next AGGREGATE;
                    }
                    ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    $sql->{print}{aggr_cols}[$i] .= $print_col . ")";
                    $sql->{quote}{aggr_cols}[$i] .= $quote_col . ")";
                }
                $sql->{print}{aggr_cols}[$i] = $self->__unambiguous_key( $sql->{print}{aggr_cols}[$i], $pr_columns );
                $sql->{quote}{aggr_cols}[$i] .= " AS " . $dbh->quote_identifier( $sql->{print}{aggr_cols}[$i] );
                my $print_aggr = $sql->{print}{aggr_cols}[$i];
                my $quote_aggr = $sql->{quote}{aggr_cols}[$i];
                ( $qt_columns->{$print_aggr} = $quote_aggr ) =~ s/\sAS\s\S+//;
            }
        }
        elsif ( $custom eq $customize{'set'} ) {
            my @cols = ( @$pr_columns );
            my $trs = Term::ReadLine::Simple->new();
            my $col_sep = ' ';
            $sql->{quote}{set_args} = [];
            $sql->{quote}{set_stmt} = " SET";
            $sql->{print}{set_stmt} = " SET";

            SET: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, @cols ];
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my @print_col = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @print_col || ! defined $print_col[0] ) {
                    if ( @{$sql->{quote}{set_args}} ) {
                        $sql->{quote}{set_args} = [];
                        $sql->{quote}{set_stmt} = " SET";
                        $sql->{print}{set_stmt} = " SET";
                        $col_sep = ' ';
                        #delete $sql->{pr_backup_in_hidd}{set_args};
                        next SET;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last SET;
                    }
                }
                if ( $print_col[0] eq $self->{info}{ok} ) {
                    shift @print_col;
                    for my $print_col ( @print_col ) {
                        ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                        $sql->{quote}{set_stmt} .= $col_sep . $quote_col . ' =';
                        $sql->{print}{set_stmt} .= $col_sep . $print_col . ' =';
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Readline
                        my $value = $trs->readline( $print_col . ': ' );
                        if ( ! defined $value ) {
                            $sql->{quote}{set_args} = [];
                            $sql->{quote}{set_stmt} = '';
                            $sql->{print}{set_stmt} = '';
                            return;
                        }
                        $sql->{quote}{set_stmt} .= ' ' . '?';
                        $sql->{print}{set_stmt} .= ' ' . "'$value'";
                        push @{$sql->{quote}{set_args}}, $value;
                        $col_sep = ', ';
                    }
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{set_stmt} = '';
                        $sql->{print}{set_stmt} = '';
                        #delete $sql->{pr_backup_in_hidd}{set_args};
                    }
                    last SET;
                }
                for my $print_col ( @print_col ) {
                    ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    $sql->{quote}{set_stmt} .= $col_sep . $quote_col . ' =';
                    $sql->{print}{set_stmt} .= $col_sep . $print_col . ' =';
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Readline
                    my $value = $trs->readline( $print_col . ': ' );
                    if ( ! defined $value ) {
                        $sql->{quote}{set_args} = [];
                        $sql->{quote}{set_stmt} = '';
                        $sql->{print}{set_stmt} = '';
                        return;
                    }
                    $sql->{quote}{set_stmt} .= ' ' . '?';
                    $sql->{print}{set_stmt} .= ' ' . "'$value'";
                    push @{$sql->{quote}{set_args}}, $value;
                    $col_sep = ', ';
                }
            }
        }
        elsif ( $custom eq $customize{'where'} ) {
            my @cols = ( @$pr_columns, @{$sql->{pr_col_with_hidd_func}} );
            my $AND_OR = ' ';
            $sql->{quote}{where_args} = [];
            $sql->{quote}{where_stmt} = " WHERE";
            $sql->{print}{where_stmt} = " WHERE";
            my $unclosed = 0;
            my $count = 0;

            WHERE: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my @choices = @cols;
                if ( $self->{opt}{parentheses_w} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                elsif ( $self->{opt}{parentheses_w} == 2 ) {
                    push @choices, $unclosed ? ')' : '(';
                }
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $print_col = $stmt_h->choose(
                    [ @pre, @choices ]
                );
                if ( ! defined $print_col ) {
                    if ( $sql->{quote}{where_stmt} ne " WHERE" ) {
                        $sql->{quote}{where_args} = [];
                        $sql->{quote}{where_stmt} = " WHERE";
                        $sql->{print}{where_stmt} = " WHERE";
                        $count = 0;
                        $AND_OR = ' ';
                        next WHERE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last WHERE;
                    }
                }
                if ( $print_col eq $self->{info}{ok} ) {
                    if ( $count == 0 ) {
                        $sql->{quote}{where_stmt} = '';
                        $sql->{print}{where_stmt} = '';
                    }
                    last WHERE;
                }
                if ( $print_col eq ')' ) {
                    $sql->{quote}{where_stmt} .= ")";
                    $sql->{print}{where_stmt} .= ")";
                    $unclosed--;
                    next WHERE;
                }
                if ( $count > 0 && $sql->{quote}{where_stmt} !~ /\(\z/ ) {
                    my $choices = [ $AND, $OR ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Choose
                    $AND_OR = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $AND_OR ) {
                        $sql->{quote}{where_args} = [];
                        $sql->{quote}{where_stmt} = " WHERE";
                        $sql->{print}{where_stmt} = " WHERE";
                        $count = 0;
                        $AND_OR = ' ';
                        next WHERE;
                    }
                    $AND_OR = ' ' . $AND_OR . ' ';
                }
                if ( $print_col eq '(' ) {
                    $sql->{quote}{where_stmt} .= $AND_OR . "(";
                    $sql->{print}{where_stmt} .= $AND_OR . "(";
                    $AND_OR = '';
                    $unclosed++;
                    next WHERE;
                }

                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $sql->{quote}{where_stmt} .= $AND_OR . $quote_col;
                $sql->{print}{where_stmt} .= $AND_OR . $print_col;
                $self->__set_operator_sql( $sql, 'where', $table, \@cols, $qt_columns, $quote_col, $sql_type ); #
                if ( ! $sql->{quote}{where_stmt} ) {
                    $sql->{quote}{where_args} = [];
                    $sql->{quote}{where_stmt} = " WHERE";
                    $sql->{print}{where_stmt} = " WHERE";
                    $count = 0;
                    $AND_OR = ' ';
                    next WHERE;
                }
                $count++;
            }
        }
        elsif ( $custom eq $customize{'group_by'} ) {
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                $util->__reset_sql( $sql );
            }
            my @cols = ( @$pr_columns );
            my $col_sep = ' ';
            $sql->{quote}{group_by_stmt} = " GROUP BY";
            $sql->{print}{group_by_stmt} = " GROUP BY";
            $sql->{quote}{group_by_cols} = [];
            $sql->{print}{group_by_cols} = [];
            $sql->{select_type} = 'group_by_cols';

            GROUP_BY: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, @cols ];
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my @print_col = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @print_col || ! defined $print_col[0] ) {
                    if ( @{$sql->{quote}{group_by_cols}} ) {
                        $sql->{quote}{group_by_stmt} = " GROUP BY";
                        $sql->{print}{group_by_stmt} = " GROUP BY";
                        $sql->{quote}{group_by_cols} = [];
                        $sql->{print}{group_by_cols} = [];
                        $col_sep = ' ';
                        delete $sql->{pr_backup_in_hidd}{group_by_cols};
                        next GROUP_BY;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last GROUP_BY;
                    }
                }
                if ( $print_col[0] eq $self->{info}{ok} ) {
                    shift @print_col;
                    for my $print_col ( @print_col ) {
                        ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                        push @{$sql->{quote}{group_by_cols}}, $quote_col;
                        push @{$sql->{print}{group_by_cols}}, $print_col;
                        $sql->{quote}{group_by_stmt} .= $col_sep . $quote_col;
                        $sql->{print}{group_by_stmt} .= $col_sep . $print_col;
                        $col_sep = ', ';
                    }
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{group_by_stmt} = '';
                        $sql->{print}{group_by_stmt} = '';
                        if ( ! @{$sql->{quote}{aggr_cols}} ) {
                            $sql->{select_type} = '*';
                        }
                        delete $sql->{pr_backup_in_hidd}{group_by_cols};
                    }
                    last GROUP_BY;
                }
                for my $print_col ( @print_col ) {
                    ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    push @{$sql->{quote}{group_by_cols}}, $quote_col;
                    push @{$sql->{print}{group_by_cols}}, $print_col;
                    $sql->{quote}{group_by_stmt} .= $col_sep . $quote_col;
                    $sql->{print}{group_by_stmt} .= $col_sep . $print_col;
                    $col_sep = ', ';
                }
            }
        }
        elsif ( $custom eq $customize{'having'} ) {
            my @cols = ( @$pr_columns );
            my $AND_OR = ' ';
            $sql->{quote}{having_args} = [];
            $sql->{quote}{having_stmt} = " HAVING";
            $sql->{print}{having_stmt} = " HAVING";
            my $unclosed = 0;
            my $count = 0;

            HAVING: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my @choices = ( @{$self->{info}{avail_aggregate}}, map( '@' . $_, @{$sql->{print}{aggr_cols}} ) );
                if ( $self->{opt}{parentheses_h} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                elsif ( $self->{opt}{parentheses_h} == 2 ) {
                    push @choices, $unclosed ? ')' : '(';
                }
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $aggr = $stmt_h->choose(
                    [ @pre, @choices ]
                );
                if ( ! defined $aggr ) {
                    if ( $sql->{quote}{having_stmt} ne " HAVING" ) {
                        $sql->{quote}{having_args} = [];
                        $sql->{quote}{having_stmt} = " HAVING";
                        $sql->{print}{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last HAVING;
                    }
                }
                if ( $aggr eq $self->{info}{ok} ) {
                    if ( $count == 0 ) {
                        $sql->{quote}{having_stmt} = '';
                        $sql->{print}{having_stmt} = '';
                    }
                    last HAVING;
                }
                if ( $aggr eq ')' ) {
                    $sql->{quote}{having_stmt} .= ")";
                    $sql->{print}{having_stmt} .= ")";
                    $unclosed--;
                    next HAVING;
                }
                if ( $count > 0 && $sql->{quote}{having_stmt} !~ /\(\z/ ) {
                    my $choices = [ $AND, $OR ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Choose
                    $AND_OR = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $AND_OR ) {
                        $sql->{quote}{having_args} = [];
                        $sql->{quote}{having_stmt} = " HAVING";
                        $sql->{print}{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    $AND_OR = ' ' . $AND_OR . ' ';
                }
                if ( $aggr eq '(' ) {
                    $sql->{quote}{having_stmt} .= $AND_OR . "(";
                    $sql->{print}{having_stmt} .= $AND_OR . "(";
                    $AND_OR = '';
                    $unclosed++;
                    next HAVING;
                }
                my ( $print_col,  $quote_col );
                my ( $print_aggr, $quote_aggr);
                if ( ( any { '@' . $_ eq $aggr } @{$sql->{print}{aggr_cols}} ) ) {
                    ( $print_aggr = $aggr ) =~ s/^\@//;
                    $quote_aggr = $qt_columns->{$print_aggr};
                    $sql->{quote}{having_stmt} .= $AND_OR . $quote_aggr;
                    $sql->{print}{having_stmt} .= $AND_OR . $print_aggr;
                    $quote_col = $qt_columns->{$print_aggr};
                }
                elsif ( $aggr eq 'COUNT(*)' ) {
                    $print_col = '*';
                    $quote_col = '*';
                    $print_aggr = $aggr;
                    $quote_aggr = $aggr;
                    $sql->{quote}{having_stmt} .= $AND_OR . $quote_aggr;
                    $sql->{print}{having_stmt} .= $AND_OR . $print_aggr;
                }
                else {
                    $aggr =~ s/\(\S\)\z//;
                    $sql->{quote}{having_stmt} .= $AND_OR . $aggr . "(";
                    $sql->{print}{having_stmt} .= $AND_OR . $aggr . "(";
                    $quote_aggr                 =           $aggr . "(";
                    $print_aggr                 =           $aggr . "(";
                    my $choices = [ @cols ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Choose
                    $print_col = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $print_col ) {
                        $sql->{quote}{having_args} = [];
                        $sql->{quote}{having_stmt} = " HAVING";
                        $sql->{print}{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    ( $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    $sql->{quote}{having_stmt} .= $quote_col . ")";
                    $sql->{print}{having_stmt} .= $print_col . ")";
                    $quote_aggr                .= $quote_col . ")";
                    $print_aggr                .= $print_col . ")";
                }
                $self->__set_operator_sql( $sql, 'having', $table, \@cols, $qt_columns, $quote_aggr, $sql_type ); #
                if ( ! $sql->{quote}{having_stmt} ) {
                    $sql->{quote}{having_args} = [];
                    $sql->{quote}{having_stmt} = " HAVING";
                    $sql->{print}{having_stmt} = " HAVING";
                    $count = 0;
                    $AND_OR = ' ';
                    next HAVING;
                }
                $count++;
            }
        }
        elsif ( $custom eq $customize{'order_by'} ) {
            my @functions = @{$self->{info}{hidd_func_pr}}{@{$self->{info}{keys_hidd_func_pr}}};
            my $f = join '|', map quotemeta, @functions;
            my @not_hidd = map { /^(?:$f)\((.*)\)\z/ ? $1 : () } @{$sql->{print}{aggr_cols}};
            my @cols =
                ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' )
                ? ( @$pr_columns, @{$sql->{pr_col_with_hidd_func}} )
                : ( @{$sql->{print}{group_by_cols}}, @{$sql->{print}{aggr_cols}}, @not_hidd );
            my $col_sep = ' ';
            $sql->{quote}{order_by_stmt} = " ORDER BY";
            $sql->{print}{order_by_stmt} = " ORDER BY";

            ORDER_BY: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, @cols ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $print_col = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $print_col ) {
                    if ( $sql->{quote}{order_by_stmt} ne " ORDER BY" ) {
                        $sql->{quote}{order_by_args} = [];
                        $sql->{quote}{order_by_stmt} = " ORDER BY";
                        $sql->{print}{order_by_stmt} = " ORDER BY";
                        $col_sep = ' ';
                        next ORDER_BY;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last ORDER_BY;
                    }
                }
                if ( $print_col eq $self->{info}{ok} ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{order_by_stmt} = '';
                        $sql->{print}{order_by_stmt} = '';
                    }
                    last ORDER_BY;
                }
                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $sql->{quote}{order_by_stmt} .= $col_sep . $quote_col;
                $sql->{print}{order_by_stmt} .= $col_sep . $print_col;
                $choices = [ $ASC, $DESC ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $direction = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $direction ){
                    $sql->{quote}{order_by_args} = [];
                    $sql->{quote}{order_by_stmt} = " ORDER BY";
                    $sql->{print}{order_by_stmt} = " ORDER BY";
                    $col_sep = ' ';
                    next ORDER_BY;
                }
                $sql->{quote}{order_by_stmt} .= ' ' . $direction;
                $sql->{print}{order_by_stmt} .= ' ' . $direction;
                $col_sep = ', ';
            }
        }
        elsif ( $custom eq $customize{'limit'} ) {
            $sql->{quote}{limit_args} = [];
            $sql->{quote}{limit_stmt} = " LIMIT";
            $sql->{print}{limit_stmt} = " LIMIT";
            my $digits = 7;
            my ( $only_limit, $offset_and_limit ) = ( 'LIMIT', 'OFFSET-LIMIT' );

            LIMIT: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, $only_limit, $offset_and_limit ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $choice = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $choice ) {
                    if ( @{$sql->{quote}{limit_args}} ) {
                        $sql->{quote}{limit_args} = [];
                        $sql->{quote}{limit_stmt} = " LIMIT";
                        $sql->{print}{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last LIMIT;
                    }
                }
                if ( $choice eq $self->{info}{ok} ) {
                    if ( ! @{$sql->{quote}{limit_args}} ) {
                        $sql->{quote}{limit_stmt} = '';
                        $sql->{print}{limit_stmt} = '';
                    }
                    last LIMIT;
                }
                $sql->{quote}{limit_args} = [];
                $sql->{quote}{limit_stmt} = " LIMIT";
                $sql->{print}{limit_stmt} = " LIMIT";
                # Choose_a_number
                my $limit = choose_a_number( $digits, { name => '"LIMIT"' } );
                next LIMIT if ! defined $limit || $limit eq '--';
                push @{$sql->{quote}{limit_args}}, $limit;
                $self->{opt}{max_rows} = $limit + 1;
                $sql->{quote}{limit_stmt} .= ' ' . '?';
                $sql->{print}{limit_stmt} .= ' ' . insert_sep( $limit, $self->{opt}{thsd_sep} );
                if ( $choice eq $offset_and_limit ) {
                    # Choose_a_number
                    my $offset = choose_a_number( $digits, { name => '"OFFSET"' } );
                    if ( ! defined $offset || $offset eq '--' ) {
                        $sql->{quote}{limit_args} = [];
                        $sql->{quote}{limit_stmt} = " LIMIT";
                        $sql->{print}{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    push @{$sql->{quote}{limit_args}}, $offset;
                    $sql->{quote}{limit_stmt} .= " OFFSET " . '?';
                    $sql->{print}{limit_stmt} .= " OFFSET " . insert_sep( $offset, $self->{opt}{thsd_sep} );
                }
            }
        }
        elsif ( $custom eq $customize{'hidden'} ) {
            if ( $sql_type eq 'Insert' ) {
                my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
                $obj_opt->__config_insert( 0 );
                next CUSTOMIZE;
            }
            my @functions = @{$self->{info}{keys_hidd_func_pr}};
            my $stmt_key = '';
            if ( $sql->{select_type} eq '*' ) {
                @{$sql->{quote}{chosen_cols}} = map { $qt_columns->{$_} } @$pr_columns;
                @{$sql->{print}{chosen_cols}} = @$pr_columns;
                $stmt_key = 'chosen_cols';
            }
            elsif ( $sql->{select_type} eq 'chosen_cols' ) {
                $stmt_key = 'chosen_cols';
            }
            if ( $stmt_key eq 'chosen_cols' ) {
                if ( ! $sql->{pr_backup_in_hidd}{$stmt_key} ) {
                    @{$sql->{pr_backup_in_hidd}{$stmt_key}} = @{$sql->{print}{$stmt_key}};
                }
            }
            else {
                if ( @{$sql->{print}{aggr_cols}} && ! $sql->{pr_backup_in_hidd}{aggr_cols} ) {
                    @{$sql->{pr_backup_in_hidd}{'aggr_cols'}} = @{$sql->{print}{aggr_cols}};
                }
                if ( @{$sql->{print}{group_by_cols}} && ! $sql->{pr_backup_in_hidd}{group_by_cols} ) {
                    @{$sql->{pr_backup_in_hidd}{'group_by_cols'}} = @{$sql->{print}{group_by_cols}};
                }
            }
            my $changed = 0;

            HIDDEN: while ( 1 ) {
                my @cols = $stmt_key eq 'chosen_cols'
                    ? ( @{$sql->{print}{$stmt_key}}                                  )
                    : ( @{$sql->{print}{aggr_cols}}, @{$sql->{print}{group_by_cols}} );
                my @pre = ( undef, $self->{info}{_confirm} );
                my $prompt = 'Choose:';
                my $choose_type = 'Your choice:';
                my $default = 0;
                if ( $sql_type eq 'Select' ) {
                    unshift @pre, $choose_type;
                    $prompt = '';
                    $default = 1;
                }
                my $choices = [ @pre, map( "- $_", @cols ) ];
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $i = $stmt_h->choose(
                    $choices,
                    { %{$self->{info}{lyt_stmt_v}}, index => 1, default => $default, prompt => $prompt }
                );
                if ( ! defined $i ) {
                    $sql = clone( $backup_sql );
                    last HIDDEN;
                }
                my $print_col = $choices->[$i];
                if ( ! defined $print_col ) {
                    $sql = clone( $backup_sql );
                    last HIDDEN;
                }
                if ( $print_col eq $choose_type ) {
                    my $choices = [ undef, map( "- $_", @$sql_types ) ];
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Choose
                    my $st = $stmt_h->choose(
                        $choices,
                        { %{$self->{info}{lyt_stmt_v}}, prompt => '', default => 0 }
                    );
                    if ( defined $st ) {
                        $st =~ s/^-\ //;
                        $sql_type = $st;
                        $old_idx = 1;
                        $util->__reset_sql( $sql );
                    }
                    last HIDDEN;
                }
                if ( $print_col eq $self->{info}{_confirm} ) {
                    if ( ! $changed ) {
                        $sql = clone( $backup_sql );
                        last HIDDEN;
                    }
                    $sql->{select_type} = $stmt_key if $sql->{select_type} eq '*';
                    last HIDDEN;
                }
                $print_col =~ s/^\-\s//;
                $i -= @pre;
                if ( $stmt_key ne 'chosen_cols' ) {
                    if ( $i - @{$sql->{print}{aggr_cols}} >= 0 ) {
                        $i -= @{$sql->{print}{aggr_cols}};
                        $stmt_key = 'group_by_cols';
                    }
                    else {
                        $stmt_key = 'aggr_cols';
                    }
                }
                if ( $sql->{print}{$stmt_key}[$i] ne $sql->{pr_backup_in_hidd}{$stmt_key}[$i] ) {
                    if ( $stmt_key ne 'aggr_cols' ) {
                        my $i = first_index { $sql->{print}{$stmt_key}[$i] eq $_ } @{$sql->{pr_col_with_hidd_func}};
                        splice( @{$sql->{pr_col_with_hidd_func}}, $i, 1 );
                    }
                    $sql->{print}{$stmt_key}[$i] = $sql->{pr_backup_in_hidd}{$stmt_key}[$i];
                    $sql->{quote}{$stmt_key}[$i] = $qt_columns->{$sql->{pr_backup_in_hidd}{$stmt_key}[$i]};
                    $changed++;
                    next HIDDEN;
                }
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $function = $stmt_h->choose(
                    [ undef, map( "  $_", @functions ) ],
                    { %{$self->{info}{lyt_stmt_v}} }
                );
                if ( ! defined $function ) {
                    next HIDDEN;
                }
                $function =~ s/^\s\s//;
                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $util->__print_sql_statement( $sql, $table, $sql_type );
                my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
                my ( $quote_hidd, $print_hidd ) = $obj_db->col_functions( $function, $quote_col, $print_col );
                if ( ! defined $quote_hidd ) {
                    next HIDDEN;
                }
                $print_hidd = $self->__unambiguous_key( $print_hidd, $pr_columns );
                if ( $stmt_key eq 'group_by_cols' ) {
                    $sql->{quote}{$stmt_key}[$i] = $quote_hidd;
                    $sql->{quote}{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{quote}{$stmt_key}} );
                    $sql->{print}{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{print}{$stmt_key}} );
                }
                $sql->{quote}{$stmt_key}[$i] = $quote_hidd . ' AS ' . $dbh->quote_identifier( $print_hidd );
                $sql->{print}{$stmt_key}[$i] = $print_hidd;
                $qt_columns->{$print_hidd} = $quote_hidd;
                if ( $stmt_key ne 'aggr_cols' ) { # WHERE: aggregate functions are not allowed
                    push @{$sql->{pr_col_with_hidd_func}}, $print_hidd;
                }
                $changed++;
                next HIDDEN;
            }
        }
        elsif ( $custom eq $customize{'print_table'} ) {
            my ( $default_cols_sql, $from_stmt ) = $select_from_stmt =~ /^SELECT\s(.*?)(\sFROM\s.*)\z/;
            my $cols_sql;
            if ( $sql->{select_type} eq '*' ) {
                $cols_sql = ' ' . $default_cols_sql;
            }
            elsif ( $sql->{select_type} eq 'chosen_cols' ) {
                $cols_sql = ' ' . join( ', ', @{$sql->{quote}{chosen_cols}} );
            }
            elsif ( @{$sql->{quote}{aggr_cols}} || @{$sql->{quote}{group_by_cols}} ) {
                $cols_sql = ' ' . join( ', ', @{$sql->{quote}{group_by_cols}}, @{$sql->{quote}{aggr_cols}} );
            }
            else { #
                $cols_sql = ' ' . $default_cols_sql;
            }
            my $select .= "SELECT" . $sql->{quote}{distinct_stmt} . $cols_sql . $from_stmt;
            $select .= $sql->{quote}{where_stmt};
            $select .= $sql->{quote}{group_by_stmt};
            $select .= $sql->{quote}{having_stmt};
            $select .= $sql->{quote}{order_by_stmt};
            $select .= $sql->{quote}{limit_stmt};
            my @arguments = ( @{$sql->{quote}{where_args}}, @{$sql->{quote}{having_args}}, @{$sql->{quote}{limit_args}} );
            if ( ! $sql->{quote}{limit_stmt} && $self->{opt}{max_rows} ) {
                $select .= " LIMIT ?";
                push @arguments, $self->{opt}{max_rows};
            }
            local $| = 1;
            print CLEAR_SCREEN;
            say 'Database : ...' if $self->{opt}{progress_bar};
            my $sth = $dbh->prepare( $select );
            $sth->execute( @arguments );
            my $col_names = $sth->{NAME};
            my $all_arrayref = $sth->fetchall_arrayref;
            unshift @$all_arrayref, $col_names;
            print CLEAR_SCREEN;
            return $all_arrayref;
        }
        elsif ( $custom eq $customize{'commit'} ) {
            my ( $qt_table ) = $select_from_stmt =~ /^SELECT\s.*?\sFROM\s(.*)\z/;
            my %map_sql_types = (
                Delete => "DELETE",
                Update => "UPDATE",
                Insert => "INSERT INTO",
            );

            local $| = 1;
            print CLEAR_SCREEN;
            say 'Database : ...' if $self->{opt}{progress_bar};
            my $stmt = $map_sql_types{$sql_type};
            my $to_execute;
            my $transaction;
            eval { $transaction = $dbh->begin_work } or do { $dbh->{AutoCommit} = 1; $transaction = 0 };
            my $dostr = $transaction ? 'COMMIT' : 'EXECUTE';
            my %commit_fmt = (
                Delete => qq(  $dostr %d "Delete"),
                Update => qq(  $dostr %d "Update"),
                Insert => qq(  $dostr %d "Insert"),
            );
            if ( $map_sql_types{$sql_type} eq "INSERT INTO" ) {
                if ( ! @{$sql->{quote}{insert_into_args}} ) {
                    $old_idx = 1;
                    next CUSTOMIZE;
                }
                $stmt .= ' ' . $qt_table;
                $stmt .= " ( " . join( ', ', @{$sql->{quote}{chosen_cols}} ) . " )" if $sql->{quote}{chosen_cols};
                my $nr_insert_cols = @{$sql->{quote}{chosen_cols}};
                $stmt .= " VALUES( " . join( ', ', ( '?' ) x $nr_insert_cols ) . " )";
                $to_execute = $sql->{quote}{insert_into_args};
            }
            else {
                $stmt .= " FROM"                      if $map_sql_types{$sql_type} eq "DELETE";
                $stmt .= ' ' . $qt_table;
                $stmt .= $sql->{quote}{set_stmt}      if $sql->{quote}{set_stmt};
                $stmt .= $sql->{quote}{where_stmt}    if $sql->{quote}{where_stmt};
                #$stmt .= $sql->{quote}{order_by_stmt} if $sql->{quote}{order_by_stmt};
                #$stmt .= $sql->{quote}{limit_stmt}    if $sql->{quote}{limit_stmt};
                my @arguments = ( @{$sql->{quote}{set_args}}, @{$sql->{quote}{where_args}} ); # @{$sql->{quote}{limit_args}}
                $to_execute = [ \@arguments ];
            }
            if ( $transaction ) {
                if ( ! eval {
                    my $sth = $dbh->prepare( $stmt );
                    for my $values ( @$to_execute ) {
                        $sth->execute( @$values );
                    }
                    my $nr_rows   = $sql_type eq 'Insert' ? @$to_execute : $sth->rows;
                    my $commit_ok = sprintf $commit_fmt{$sql_type}, $nr_rows;
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    my $choices = [ undef,  $commit_ok ];
                    # Choose
                    my $choice = $stmt_h->choose(
                        $choices,
                        { %{$self->{info}{lyt_stmt_v}}, undef => '  BACK', prompt => '' }
                    );
                    if ( defined $choice && $choice eq $commit_ok ) {;
                        $dbh->commit;
                    }
                    else {
                        $dbh->rollback;
                    }
                    1;
                    }
                ) {
                    say 'Commit:';
                    $util->__print_error_message( "$@rolling back ...\n" );
                    eval { $dbh->rollback };#
                }
            }
            else {
                my $nr_rows;
                if ( $sql_type eq 'Insert' ) {
                    $nr_rows = @$to_execute;
                }
                else {
                    my $count_stmt = "SELECT COUNT(*) FROM $qt_table" . $sql->{quote}{where_stmt};
                    ( $nr_rows ) = $dbh->selectrow_array( $count_stmt, undef, @{$sql->{quote}{where_args}} );
                }
                my $commit_ok = sprintf $commit_fmt{$sql_type}, $nr_rows;
                $util->__print_sql_statement( $sql, $table, $sql_type );
                my $choices = [ undef,  $commit_ok ];
                # Choose
                my $choice = $stmt_h->choose(
                    $choices,
                    { %{$self->{info}{lyt_stmt_v}}, undef => '  Rollback', prompt => '' }
                );
                if ( defined $choice && $choice eq $commit_ok ) {;
                    my $sth = $dbh->prepare( $stmt );
                    for my $values ( @$to_execute ) {
                        $sth->execute( @$values );
                    }
                }
            }
            $util->__reset_sql( $sql );
            $sql_type = 'Select';
            $old_idx = 1;
            $sql = clone $backup_sql;
            next CUSTOMIZE;
        }
        else {
            die "$custom: no such value in the hash \%customize";
        }
    }
    return;
}



sub __unambiguous_key {
    my ( $self, $new_key, $keys ) = @_;
    while ( any { $new_key eq $_ } @$keys ) {
        $new_key .= '_';
    }
    return $new_key;
}


sub __set_operator_sql {
    my ( $self, $sql, $clause, $table, $cols, $qt_columns, $quote_col, $sql_type ) = @_;
    my $util = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
    my ( $stmt, $args );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    if ( $clause eq 'where' ) {
        $stmt = 'where_stmt';
        $args = 'where_args';
    }
    elsif ( $clause eq 'having' ) {
        $stmt = 'having_stmt';
        $args = 'having_args';
    }
    my $choices = [ @{$self->{opt}{operators}} ];
    unshift @$choices, undef if $self->{opt}{sssc_mode};
    $util->__print_sql_statement( $sql, $table, $sql_type );
    # Choose
    my $operator = $stmt_h->choose(
        $choices
    );
    if ( ! defined $operator ) {
        $sql->{quote}{$args} = [];
        $sql->{quote}{$stmt} = '';
        $sql->{print}{$stmt} = '';
        return;
    }
    $operator =~ s/^\s+|\s+\z//g;
    if ( $operator !~ /\s%?col%?\z/ ) {
        my $trs = Term::ReadLine::Simple->new();
        if ( $operator !~ /REGEXP\z/ ) {
            $sql->{quote}{$stmt} .= ' ' . $operator;
            $sql->{print}{$stmt} .= ' ' . $operator;
        }
        if ( $operator =~ /NULL\z/ ) {
            # do nothing
        }
        elsif ( $operator =~ /^(?:NOT\s)?IN\z/ ) {
            my $col_sep = '';
            $sql->{quote}{$stmt} .= '(';
            $sql->{print}{$stmt} .= '(';

            IN: while ( 1 ) {
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Readline
                my $value = $trs->readline( 'Value: ' );
                if ( ! defined $value ) {
                    $sql->{quote}{$args} = [];
                    $sql->{quote}{$stmt} = '';
                    $sql->{print}{$stmt} = '';
                    return;
                }
                if ( $value eq '' ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{$args} = [];
                        $sql->{quote}{$stmt} = '';
                        $sql->{print}{$stmt} = '';
                        return;
                    }
                    $sql->{quote}{$stmt} .= ')';
                    $sql->{print}{$stmt} .= ')';
                    last IN;
                }
                $sql->{quote}{$stmt} .= $col_sep . '?';
                $sql->{print}{$stmt} .= $col_sep . $value;
                push @{$sql->{quote}{$args}}, $value;
                $col_sep = ',';
            }
        }
        elsif ( $operator =~ /^(?:NOT\s)?BETWEEN\z/ ) {
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Readline
            my $value_1 = $trs->readline( 'Value: ' );
            if ( ! defined $value_1 ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $sql->{quote}{$stmt} .= ' ' . '?' .      ' AND';
            $sql->{print}{$stmt} .= ' ' . $value_1 . ' AND';
            push @{$sql->{quote}{$args}}, $value_1;
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Readline
            my $value_2 = $trs->readline( 'Value: ' );
            if ( ! defined $value_2 ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $sql->{quote}{$stmt} .= ' ' . '?';
            $sql->{print}{$stmt} .= ' ' . $value_2;
            push @{$sql->{quote}{$args}}, $value_2;
        }
        elsif ( $operator =~ /REGEXP\z/ ) {
            $sql->{print}{$stmt} .= ' ' . $operator;
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Readline
            my $value = $trs->readline( 'Pattern: ' );
            if ( ! defined $value ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $value = '^$' if ! length $value;
            if ( $self->{info}{db_driver} eq 'SQLite' ) {
                $value = qr/$value/i if ! $self->{opt}{regexp_case};
                $value = qr/$value/  if   $self->{opt}{regexp_case};
            }
            $sql->{quote}{$stmt} =~ s/.*\K\s\Q$quote_col\E//;
            my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
            $sql->{quote}{$stmt} .= $obj_db->sql_regexp( $quote_col, $operator =~ /^NOT/ ? 1 : 0 );
            $sql->{print}{$stmt} .= ' ' . "'$value'";
            push @{$sql->{quote}{$args}}, $value;
        }
        else {
            $util->__print_sql_statement( $sql, $table, $sql_type );
            my $prompt = $operator =~ /LIKE\z/ ? 'Pattern: ' : 'Value: ';
            # Readline
            my $value = $trs->readline( $prompt );
            if ( ! defined $value ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $sql->{quote}{$stmt} .= ' ' . '?';
            $sql->{print}{$stmt} .= ' ' . "'$value'";
            push @{$sql->{quote}{$args}}, $value;
        }
    }
    elsif ( $operator =~ /\s%?col%?\z/ ) {
        my $arg;
        if ( $operator =~ /^(.+)\s(%?col%?)\z/ ) {
            $operator = $1;
            $arg = $2;
        }
        $operator =~ s/^\s+|\s+\z//g;
        $sql->{quote}{$stmt} .= ' ' . $operator;
        $sql->{print}{$stmt} .= ' ' . $operator;
        my $choices = [ @$cols ];
        unshift @$choices, undef if $self->{opt}{sssc_mode};
        $util->__print_sql_statement( $sql, $table, $sql_type );
        # Choose
        my $print_col = $stmt_h->choose(
            $choices,
            { prompt => "$operator:" }
        );
        if ( ! defined $print_col ) {
            $sql->{quote}{$stmt} = '';
            $sql->{print}{$stmt} = '';
            return;
        }
        ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
        my ( @qt_args, @pr_args );
        if ( $arg =~ /^(%)col/ ) {
            push @qt_args, "'$1'";
            push @pr_args, "'$1'";
        }
        push @qt_args, $quote_col;
        push @pr_args, $print_col;
        if ( $arg =~ /col(%)\z/ ) {
            push @qt_args, "'$1'";
            push @pr_args, "'$1'";
        }
        if ( $operator =~ /LIKE\z/ ) {
            my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
            $sql->{quote}{$stmt} .= ' ' . $obj_db->concatenate( \@qt_args );
            $sql->{print}{$stmt} .= ' ' . join( '+', @pr_args );
        }
        else {
            $sql->{quote}{$stmt} .= ' ' . $quote_col;
            $sql->{print}{$stmt} .= ' ' . $print_col;
        }
    }
    return;
}




1;


__END__

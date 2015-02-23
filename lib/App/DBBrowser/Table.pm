package # hide from PAUSE
App::DBBrowser::Table;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.007';

use Clone                  qw( clone );
use List::MoreUtils        qw( any first_index );
use Term::Choose           qw();
use Term::Choose::Util     qw( choose_a_number choose_multi insert_sep term_size );
use Term::ReadLine::Simple qw();
use Text::LineFold         qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::DBBrowser::DB;
#use App::DBBrowser::Table::Insert;  # "require"-d
use App::DBBrowser::Auxil;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __on_table {
    my ( $self, $sql, $db_driver, $dbh, $table, $stmt_info ) = @_;
    my $select_from_stmt = $stmt_info->{quote}{stmt};
    my $pr_columns       = $stmt_info->{pr_columns};
    my $qt_columns       = $stmt_info->{qt_columns};
    my $auxil  = App::DBBrowser::Auxil->new( $self->{info} );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my $sub_stmts = {
        Select => [ qw( print_table columns aggregate distinct where group_by having order_by limit lock ) ],
        Delete => [ qw( commit     where ) ],
        Update => [ qw( commit set where ) ],
        Insert => [ qw( commit insert    ) ],
    };
    my $lk = [ '  Lk0', '  Lk1' ];
    my %customize = (
        hidden          => 'Customize:',
        print_table     => 'Print TABLE',
        commit          => '  Confirm SQL',
        columns         => '- SELECT',
        set             => '- SET',
        insert          => '  Form SQL',
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
        $auxil->__reset_sql( $sql );
    }
    my $sql_types = {
        single => [ 'Insert', 'Update', 'Delete'  ],
        join   => [],
        union  => [],
    };
    if ( $db_driver eq 'mysql' ) {
        $sql_types->{join} = [ 'Update' ];
    }
    #my $sql_types = [ 'Insert', 'Update', 'Delete' ];
    my $sql_type = 'Select';
    my $backup_sql;
    my $old_idx = 1;

    CUSTOMIZE: while ( 1 ) {
        $backup_sql = clone( $sql ) if $sql_type eq 'Select';
        $auxil->__print_sql_statement( $sql, $table, $sql_type );
        my $choices = [ $customize{hidden}, undef, @customize{@{$sub_stmts->{$sql_type}}} ];
        # Choose
        my $idx = $stmt_h->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => '', index => 1, default => $old_idx,
            undef => $sql_type ne 'Select' ? $self->{info}{_back} : $self->{info}{back} }
        );
        if ( ! defined $idx || ! defined $choices->[$idx] ) {
            if ( $sql_type eq 'Select'  ) {
                last CUSTOMIZE;
            }
            else {
                if ( $sql->{print}{where_stmt} || $sql->{print}{set_stmt} ) {
                    $auxil->__reset_sql( $sql );
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
        my $custom = $choices->[$idx];
        if ( $self->{opt}{G}{menu_sql_memory} ) {
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
                $auxil->__reset_sql( $sql );
            }
            elsif ( $self->{info}{lock} == 0 )   {
                $self->{info}{lock} = 1;
                $customize{lock} = $lk->[1];
            }
        }
        elsif ( $custom eq $customize{'insert'} ) {
            require App::DBBrowser::Table::Insert;
            my $tbl_in = App::DBBrowser::Table::Insert->new( $self->{info}, $self->{opt} );
            $tbl_in->__insert_into( $sql, $table, $qt_columns, $pr_columns );
        }
        elsif ( $custom eq $customize{'columns'} ) {
            if ( ! ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) ) {
                $auxil->__reset_sql( $sql );
            }
            my @cols = ( @$pr_columns );
            $sql->{quote}{chosen_cols} = [];
            $sql->{print}{chosen_cols} = [];
            $sql->{select_type} = 'chosen_cols';

            COLUMNS: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                my $choices = [ @pre, @cols ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my @print_col = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @print_col || ! defined $print_col[0] ) {
                    if ( @{$sql->{quote}{chosen_cols}} ) {
                        $sql->{quote}{chosen_cols} = [];
                        $sql->{print}{chosen_cols} = [];
                        delete $sql->{scalar_func_backup_pr_col}{chosen_cols};
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
                    delete $sql->{scalar_func_backup_pr_col}{chosen_cols};
                    $sql->{pr_col_with_scalar_func} = [];
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
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                $auxil->__reset_sql( $sql );
            }
            my @cols = ( @$pr_columns );
            $sql->{quote}{aggr_cols} = [];
            $sql->{print}{aggr_cols} = [];
            $sql->{select_type} = 'aggr_cols';

            AGGREGATE: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, @{$self->{info}{avail_aggregate}} ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $aggr = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $aggr ) {
                    if ( @{$sql->{quote}{aggr_cols}} ) {
                        $sql->{quote}{aggr_cols} = [];
                        $sql->{print}{aggr_cols} = [];
                        delete $sql->{scalar_func_backup_pr_col}{aggr_cols};
                        next AGGREGATE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last AGGREGATE;
                    }
                }
                if ( $aggr eq $self->{info}{ok} ) {
                    delete $sql->{scalar_func_backup_pr_col}{aggr_cols};
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
                        $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                    $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                # alias to get aggregat function with a column name without quotes in the tableprint (optional):
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
                my $choices = [ @pre, @cols ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $print_col = $stmt_h->choose(
                    $choices,
                );
                if ( ! defined $print_col ) {
                    if ( @{$sql->{quote}{set_args}} ) {
                        $sql->{quote}{set_args} = [];
                        $sql->{quote}{set_stmt} = " SET";
                        $sql->{print}{set_stmt} = " SET";
                        $col_sep = ' ';
                        next SET;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last SET;
                    }
                }
                if ( $print_col eq $self->{info}{ok} ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{set_stmt} = '';
                        $sql->{print}{set_stmt} = '';
                    }
                    last SET;
                }
                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $sql->{quote}{set_stmt} .= $col_sep . $quote_col . ' =';
                $sql->{print}{set_stmt} .= $col_sep . $print_col . ' =';
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Readline
                my $value = $trs->readline( $print_col . ': ' );
                if ( ! defined $value ) {
                    if ( @{$sql->{quote}{set_args}} ) {
                        $sql->{quote}{set_args} = [];
                        $sql->{quote}{set_stmt} = " SET";
                        $sql->{print}{set_stmt} = " SET";
                        $col_sep = ' ';
                        next SET;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last SET;
                    }
                }
                $sql->{quote}{set_stmt} .= ' ' . '?';
                $sql->{print}{set_stmt} .= ' ' . "'$value'";
                push @{$sql->{quote}{set_args}}, $value;
                $col_sep = ', ';
            }
        }
        elsif ( $custom eq $customize{'where'} ) {
            my @cols = ( @$pr_columns, @{$sql->{pr_col_with_scalar_func}} );
            my $AND_OR = ' ';
            $sql->{quote}{where_args} = [];
            $sql->{quote}{where_stmt} = " WHERE";
            $sql->{print}{where_stmt} = " WHERE";
            my $unclosed = 0;
            my $count = 0;

            WHERE: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                my @choices = @cols;
                if ( $self->{opt}{G}{parentheses_w} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                    $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                $self->__set_operator_sql( $sql, 'where', $table, \@cols, $qt_columns, $quote_col, $sql_type );
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
                $auxil->__reset_sql( $sql );
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
                my $choices = [ @pre, @cols ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                        delete $sql->{scalar_func_backup_pr_col}{group_by_cols};
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
                        delete $sql->{scalar_func_backup_pr_col}{group_by_cols};
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
                my @choices = ( @{$self->{info}{avail_aggregate}}, map( '@' . $_, @{$sql->{print}{aggr_cols}} ) );
                if ( $self->{opt}{G}{parentheses_h} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                    $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                    $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                $self->__set_operator_sql( $sql, 'having', $table, \@cols, $qt_columns, $quote_aggr, $sql_type );
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
            my @functions = @{$self->{info}{scalar_func_h}}{@{$self->{info}{scalar_func_keys}}};
            my $f = join '|', map quotemeta, @functions;
            my @not_hidd = map { /^(?:$f)\((.*)\)\z/ ? $1 : () } @{$sql->{print}{aggr_cols}};
            my @cols =
                ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' )
                ? ( @$pr_columns, @{$sql->{pr_col_with_scalar_func}} )
                : ( @{$sql->{print}{group_by_cols}}, @{$sql->{print}{aggr_cols}}, @not_hidd );
            my $col_sep = ' ';
            $sql->{quote}{order_by_stmt} = " ORDER BY";
            $sql->{print}{order_by_stmt} = " ORDER BY";

            ORDER_BY: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, @cols ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $print_col = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $print_col ) {
                    if ( $sql->{quote}{order_by_stmt} ne " ORDER BY" ) {
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
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $direction = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $direction ){
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
            $sql->{quote}{limit_stmt} = " LIMIT";
            $sql->{print}{limit_stmt} = " LIMIT";

            LIMIT: while ( 1 ) {
                my ( $only_limit, $offset_and_limit ) = ( 'LIMIT', 'OFFSET-LIMIT' );
                my $choices = [ $self->{info}{ok}, $only_limit, $offset_and_limit ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $choice = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $choice ) {
                    if ( $sql->{quote}{limit_stmt} ne " LIMIT" ) {
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
                    if ( $sql->{quote}{limit_stmt} eq " LIMIT" ) {
                        $sql->{quote}{limit_stmt} = '';
                        $sql->{print}{limit_stmt} = '';
                    }
                    last LIMIT;
                }
                $sql->{quote}{limit_stmt} = " LIMIT";
                $sql->{print}{limit_stmt} = " LIMIT";
                my $digits = 7;
                # Choose_a_number
                my $limit = choose_a_number( $digits, { name => '"LIMIT"' } );
                next LIMIT if ! defined $limit || $limit eq '--';
                $sql->{quote}{limit_stmt} .= ' ' . sprintf '%d', $limit;
                $sql->{print}{limit_stmt} .= ' ' . insert_sep( $limit, $self->{opt}{G}{thsd_sep} );
                if ( $choice eq $offset_and_limit ) {
                    # Choose_a_number
                    my $offset = choose_a_number( $digits, { name => '"OFFSET"' } );
                    if ( ! defined $offset || $offset eq '--' ) {
                        $sql->{quote}{limit_stmt} = " LIMIT";
                        $sql->{print}{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    $sql->{quote}{limit_stmt} .= " OFFSET " . sprintf '%d', $offset;
                    $sql->{print}{limit_stmt} .= " OFFSET " . insert_sep( $offset, $self->{opt}{G}{thsd_sep} );
                }
            }
        }
        elsif ( $custom eq $customize{'hidden'} ) {
            if ( $sql_type eq 'Insert' ) {
                my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt}, {} );
                $obj_opt->__config_insert( 0 );
                $sql = clone( $backup_sql );
                next CUSTOMIZE;
            }
            my @functions = @{$self->{info}{scalar_func_keys}};
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
                if ( ! $sql->{scalar_func_backup_pr_col}{chosen_cols} ) {
                    @{$sql->{scalar_func_backup_pr_col}{'chosen_cols'}} = @{$sql->{print}{chosen_cols}};
                }
            }
            else {
                if ( @{$sql->{print}{aggr_cols}} && ! $sql->{scalar_func_backup_pr_col}{aggr_cols} ) {
                    @{$sql->{scalar_func_backup_pr_col}{'aggr_cols'}} = @{$sql->{print}{aggr_cols}};
                }
                if ( @{$sql->{print}{group_by_cols}} && ! $sql->{scalar_func_backup_pr_col}{group_by_cols} ) {
                    @{$sql->{scalar_func_backup_pr_col}{'group_by_cols'}} = @{$sql->{print}{group_by_cols}};
                }
            }
            my $changed = 0;

            COL_SCALAR_FUNC: while ( 1 ) {
                my $default = 0;
                my $choose_SQL_type = 'Your choice:';
                my @pre = ( undef, $self->{info}{_confirm} );
                my $prompt = 'Choose:';
                if ( $sql_type eq 'Select' ) {
                    if ( ! defined $pre[0] || $pre[0] ne $choose_SQL_type ) {
                        unshift @pre, $choose_SQL_type;
                    }
                    $prompt = '';
                    $default = 1;
                }
                my @choices_sql_types = @{$sql_types->{$stmt_info->{type}}};
                #if ( ! @choices_sql_types ) {
                #    if ( defined $pre[0] && $pre[0] eq $choose_SQL_type ) {
                #        shift @pre;
                #    }
                #    $prompt = 'Your choice:';
                #    $default = 0;
                #}
                my @cols = $stmt_key eq 'chosen_cols'
                    ? ( @{$sql->{print}{chosen_cols}} )
                    : ( @{$sql->{print}{aggr_cols}}, @{$sql->{print}{group_by_cols}} );
                my $choices = [ @pre, map( "- $_", @cols ) ];
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $idx = $stmt_h->choose(
                    $choices,
                    { %{$self->{info}{lyt_stmt_v}}, index => 1, default => $default, prompt => $prompt }
                );
                if ( ! defined $idx || ! defined $choices->[$idx] ) {
                    $sql = clone( $backup_sql );
                    last COL_SCALAR_FUNC;
                }
                if ( $choices->[$idx] eq $choose_SQL_type ) {
                    if ( ! @choices_sql_types ) {
                        next COL_SCALAR_FUNC;
                    }
                    #my $ch_types = [ undef, map( "- $_", @$sql_types ) ];
                    my $ch_types = [ undef, map( "- $_", @choices_sql_types ) ];
                    # Choose
                    my $type_choice = $stmt_h->choose(
                        $ch_types,
                        { %{$self->{info}{lyt_stmt_v}}, prompt => 'Choose SQL type:', default => 0, clear_screen => 1 }
                    );
                    if ( defined $type_choice ) {
                        ( $sql_type = $type_choice ) =~ s/^-\ //;
                        $old_idx = 1;
                        $auxil->__reset_sql( $sql );
                    }
                    #if ( $stmt_info->{type} eq 'union' ) {
                    #    if ( $sql_type =~ /^(?:Insert|Delete|Update)\z/ ) {
                    #        $auxil->__print_error_message( sprintf "%s: no support for UNION statement\n", uc $sql_type );
                    #        $sql_type = 'Select';
                    #    }
                    #}
                    #if ( $stmt_info->{type} eq 'join' ) {
                    #    if ( $sql_type =~ /^(?:Insert|Delete)\z/ ) {
                    #        $auxil->__print_error_message( sprintf "%s: no support for JOIN statement\n", uc $sql_type );
                    #        $sql_type = 'Select';
                    #    }
                    #    if ( $sql_type eq 'Update' && $db_driver ne 'mysql' ) {
                    #        $auxil->__print_error_message( sprintf "INSERT - JOIN: no support for db driver %s\n", $db_driver );
                    #     $sql_type = 'Select';
                    #    }
                    #}
                    last COL_SCALAR_FUNC;
                }
                if ( $choices->[$idx] eq $self->{info}{_confirm} ) {
                    if ( ! $changed ) {
                        $sql = clone( $backup_sql );
                        last COL_SCALAR_FUNC;
                    }
                    $sql->{select_type} = $stmt_key if $sql->{select_type} eq '*';
                    last COL_SCALAR_FUNC;
                }
                ( my $print_col = $choices->[$idx] ) =~ s/^\-\s//;
                $idx -= @pre;
                if ( $stmt_key ne 'chosen_cols' ) {
                    if ( $idx - @{$sql->{print}{aggr_cols}} >= 0 ) {
                        $idx -= @{$sql->{print}{aggr_cols}};
                        $stmt_key = 'group_by_cols';
                    }
                    else {
                        $stmt_key = 'aggr_cols';
                    }
                }
                if ( $sql->{print}{$stmt_key}[$idx] ne $sql->{scalar_func_backup_pr_col}{$stmt_key}[$idx] ) {
                    if ( $stmt_key ne 'aggr_cols' ) {
                        my $i = first_index { $sql->{print}{$stmt_key}[$idx] eq $_ } @{$sql->{pr_col_with_scalar_func}};
                        splice( @{$sql->{pr_col_with_scalar_func}}, $i, 1 );
                    }
                    $sql->{print}{$stmt_key}[$idx] = $sql->{scalar_func_backup_pr_col}{$stmt_key}[$idx];
                    $sql->{quote}{$stmt_key}[$idx] = $qt_columns->{$sql->{scalar_func_backup_pr_col}{$stmt_key}[$idx]};
                    $changed++;
                    next COL_SCALAR_FUNC;
                }
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my $function = $stmt_h->choose(
                    [ undef, map( "  $_", @functions ) ],
                    { %{$self->{info}{lyt_stmt_v}} }
                );
                if ( ! defined $function ) {
                    next COL_SCALAR_FUNC;
                }
                $function =~ s/^\s\s//;
                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
                my ( $qt_scalar_func, $pr_scalar_func ) = $self->__col_functions( $function, $quote_col, $print_col );
                if ( ! defined $qt_scalar_func ) {
                    next COL_SCALAR_FUNC;
                }
                $pr_scalar_func = $self->__unambiguous_key( $pr_scalar_func, $pr_columns );
                if ( $stmt_key eq 'group_by_cols' ) {
                    $sql->{quote}{$stmt_key}[$idx] = $qt_scalar_func;
                    $sql->{print}{$stmt_key}[$idx] = $pr_scalar_func;
                    $sql->{quote}{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{quote}{$stmt_key}} );
                    $sql->{print}{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{print}{$stmt_key}} );
                }
                $sql->{quote}{$stmt_key}[$idx] = $qt_scalar_func;
                # alias to get a shorter scalar funtion column name in the tableprint (optional):
                $sql->{quote}{$stmt_key}[$idx] .= ' AS ' . $dbh->quote_identifier( $pr_scalar_func );
                $sql->{print}{$stmt_key}[$idx] = $pr_scalar_func;
                $qt_columns->{$pr_scalar_func} = $qt_scalar_func;
                if ( $stmt_key ne 'aggr_cols' ) { # aggregate functions are not allowed in WHERE clauses
                    push @{$sql->{pr_col_with_scalar_func}}, $pr_scalar_func;
                }
                $changed++;
                next COL_SCALAR_FUNC;
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
            my @arguments = ( @{$sql->{quote}{where_args}}, @{$sql->{quote}{having_args}} );
            if ( $self->{opt}{table}{max_rows} ) {
                if ( ! $sql->{quote}{limit_stmt} ) {
                    # don't fetch any more rows than "print_table" would use (to save time/memory)
                    $select .= sprintf " LIMIT %d", $self->{opt}{table}{max_rows};
                }
                else {
                    # LIMIT overwrites "max_rows"
                    $self->{info}{backup_max_rows} = delete $self->{opt}{table}{max_rows};
                }
            }
            local $| = 1;
            print $self->{info}{clear_screen};
            print 'Database : ...' . "\n" if $self->{opt}{table}{progress_bar};
            my $sth = $dbh->prepare( $select );
            $sth->execute( @arguments );
            my $col_names = $sth->{NAME};
            my $all_arrayref = $sth->fetchall_arrayref;
            unshift @$all_arrayref, $col_names;
            print $self->{info}{clear_screen};
            # return $sql explicitly since after a `$sql = clone( $backup )` $sql refers to a different hash.
            return $all_arrayref, $sql;
        }
        elsif ( $custom eq $customize{'commit'} ) {
            my ( $qt_table ) = $select_from_stmt =~ /^SELECT\s.*?\sFROM\s(.*)\z/;
            local $| = 1;
            print $self->{info}{clear_screen};
            print 'Database : ...' . "\n" if $self->{opt}{table}{progress_bar};
            my %map_sql_types = (
                Insert => "INSERT INTO",
                Update => "UPDATE",
                Delete => "DELETE",
            );
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
                my @arguments = ( @{$sql->{quote}{set_args}}, @{$sql->{quote}{where_args}} );
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
                    $auxil->__print_sql_statement( $sql, $table, $sql_type );
                    my $choices = [ undef,  $commit_ok ];
                    # Choose
                    my $choice = $stmt_h->choose(
                        $choices,
                        { %{$self->{info}{lyt_stmt_v}}, undef => '  BACK', prompt => 'Choose:' }
                    );
                    if ( defined $choice && $choice eq $commit_ok ) {;
                        $dbh->commit;
                    }
                    else {
                        $dbh->rollback;
                        $auxil->__reset_sql( $sql );
                        next CUSTOMIZE;
                    }
                    1;
                    }
                ) {
                    $auxil->__print_error_message( "$@rolling back ...\n", 'Commit' );
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
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
                else {
                    $auxil->__reset_sql( $sql );
                    next CUSTOMIZE;
                }
            }
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
    my $auxil = App::DBBrowser::Auxil->new( $self->{info} );
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
    my $choices = [ @{$self->{opt}{G}{operators}} ];
    $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
        if ( $operator !~ /REGEXP(_i)?\z/ ) {
            $sql->{quote}{$stmt} .= ' ' . $operator;
            $sql->{print}{$stmt} .= ' ' . $operator;
        }
        my $trs = Term::ReadLine::Simple->new();
        if ( $operator =~ /NULL\z/ ) {
            # do nothing
        }
        elsif ( $operator =~ /^(?:NOT\s)?IN\z/ ) {
            my $col_sep = '';
            $sql->{quote}{$stmt} .= '(';
            $sql->{print}{$stmt} .= '(';

            IN: while ( 1 ) {
                $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
            $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
            $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
        elsif ( $operator =~ /REGEXP(_i)?\z/ ) {
            $sql->{print}{$stmt} .= ' ' . $operator;
            $auxil->__print_sql_statement( $sql, $table, $sql_type );
            # Readline
            my $value = $trs->readline( 'Pattern: ' );
            if ( ! defined $value ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $value = '^$' if ! length $value;
            $sql->{quote}{$stmt} =~ s/.*\K\s\Q$quote_col\E//;
            my $do_not_match_regexp = $operator =~ /^NOT/       ? 1 : 0;
            my $case_sensitive      = $operator =~ /REGEXP_i\z/ ? 0 : 1;
            if ( ! eval {
                my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
                $sql->{quote}{$stmt} .= $obj_db->sql_regexp( $quote_col, $do_not_match_regexp, $case_sensitive );
                $sql->{print}{$stmt} .= ' ' . "'$value'";
                push @{$sql->{quote}{$args}}, $value;
                1 }
            ) {
                $auxil->__print_error_message( $@, $operator );
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return
            }
        }
        else {
            $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
        $auxil->__print_sql_statement( $sql, $table, $sql_type );
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
        if ( $arg !~ /%/ ) {
            $sql->{quote}{$stmt} .= ' ' . $quote_col;
            $sql->{print}{$stmt} .= ' ' . $print_col;
        }
        else {
            if ( ! eval {
                my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
                my @el = map { "'$_'" } grep { length $_ } $arg =~ /^(%?)(col)(%?)\z/g;
                my $qt_arg = $obj_db->concatenate( \@el );
                my $pr_arg = join ' + ', @el;
                $qt_arg =~ s/'col'/$quote_col/;
                $pr_arg =~ s/'col'/$print_col/;
                $sql->{quote}{$stmt} .= ' ' . $qt_arg;
                $sql->{print}{$stmt} .= ' ' . $pr_arg;
                1 }
            ) {
                $auxil->__print_error_message( $@, $operator . ' ' . $arg );
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
        }
    }
    return;
}


sub __col_functions {
    my ( $self, $func, $quote_col, $print_col ) = @_;
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my $obj_ch = Term::Choose->new();
    my ( $quote_f, $print_f );
    $print_f = $self->{info}{scalar_func_h}{$func} . '(' . $print_col . ')';
    if ( $func =~ /^Epoch_to_Date(?:Time)?\z/ ) {
        my $prompt = "$print_f\nInterval:";
        my ( $microseconds, $milliseconds, $seconds ) = (
            '  ****************   Micro-Second',
            '  *************      Milli-Second',
            '  **********               Second' );
        my $choices = [ undef, $microseconds, $milliseconds, $seconds ];
        # Choose
        my $interval = $obj_ch->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => $prompt }
        );
        return if ! defined $interval;
        my $div = $interval eq $microseconds ? 1000000 :
                  $interval eq $milliseconds ? 1000 : 1;
        if ( $func eq 'Epoch_to_DateTime' ) {
            $quote_f = $obj_db->epoch_to_datetime( $quote_col, $div );
        }
        else {
            $quote_f = $obj_db->epoch_to_date( $quote_col, $div );
        }
    }
    elsif ( $func eq 'Truncate' ) {
        my $prompt = "TRUNC $print_col\nDecimal places:";
        my $choices = [ undef, 0 .. 9 ];
        # Choose
        my $precision = $obj_ch->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_h}}, prompt => $prompt }
        );
        return if ! defined $precision;
        $quote_f = $obj_db->truncate( $quote_col, $precision );
    }
    elsif ( $func eq 'Bit_Length' ) {
        $quote_f = $obj_db->bit_length( $quote_col );
    }
    elsif ( $func eq 'Char_Length' ) {
        $quote_f = $obj_db->char_length( $quote_col );
    }
    return $quote_f, $print_f;
}




1;


__END__

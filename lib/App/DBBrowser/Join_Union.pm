package # hide from PAUSE
App::DBBrowser::Join_Union;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.049_08';

use Clone                  qw( clone );
use List::MoreUtils        qw( any );
use Term::Choose           qw();
use Term::Choose::Util     qw( term_size );
use Text::LineFold         qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::DBBrowser::DB;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __union_tables {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    my $no_lyt = Term::Choose->new();
    my $u = $data->{$db}{$schema};
    if ( ! defined $u->{col_names} || ! defined $u->{col_types} ) {
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        ( $u->{col_names}, $u->{col_types} ) = $obj_db->column_names_and_types( $dbh, $db, $schema, $u->{tables} );
    }
    my $union = {
        unused_tables => [ map { "- $_" } @{$u->{tables}} ],
        used_tables   => [],
        used_cols     => {},
        saved_cols    => [],
    };

    UNION_TABLE: while ( 1 ) {
        my $enough_tables = '  Enough TABLES';
        my $all_tables    = '  All Tables';
        my @pre_tbl  = ( undef, $enough_tables );
        my @post_tbl = ( $all_tables, $self->{info}{_info} );
        my $choices = [ @pre_tbl, map( "+ $_", @{$union->{used_tables}} ), @{$union->{unused_tables}}, @post_tbl ];
        $self->__print_union_statement( $union );
        my $prompt = $self->{union_all} ? 'One UNION table for cols:' : 'Choose UNION table:';
        # Choose
        my $idx_tbl = $no_lyt->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => $prompt, index => 1 }
        );
        return if ! defined $idx_tbl;
        my $union_table = $choices->[$idx_tbl];
        return  if ! defined $union_table;
        if ( $union_table eq $self->{info}{_info} ) {
            if ( ! defined $u->{tables_info} ) {
                $u->{tables_info} = $self->__get_tables_info( $dbh, $db, $schema, $u );
            }
            my $tbls_info = $self->__print_tables_info( $u );
            # Choose
            $no_lyt->choose(
                $tbls_info,
                { %{$self->{info}{lyt_3}}, prompt => '' }
            );
            next UNION_TABLE;
        }
        if ( $union_table eq $enough_tables ) {
            return if ! @{$union->{used_tables}};
            last UNION_TABLE;
        }
        if ( $union_table eq $all_tables ) {
            $union = {
                unused_tables => [ map { "- $_" } @{$u->{tables}} ],
                used_tables   => [],
                used_cols     => {},
                saved_cols    => [],
            };
            $self->{union_all} = 1;
            next UNION_TABLE;
        }
        my $backup_union = clone( $union );
        $union_table =~ s/^[-+]\s//;
        my $check_idx = $idx_tbl - ( @pre_tbl + @{$union->{used_tables}} );
        if ( $check_idx < 0 ) {
            my $idx_used = $idx_tbl - @pre_tbl;
            delete $union->{used_cols}{$union_table};
            $self->{idx_reset_used_tables} = $idx_used;
        }
        else {
            my $idx_unused = $check_idx;
            splice( @{$union->{unused_tables}}, $idx_unused, 1 );
            push @{$union->{used_tables}}, $union_table;
            $self->{idx_reset_used_tables} = -1;
        }

        UNION_COLUMN: while ( 1 ) {
            my ( $all_cols, $privious_cols, $void ) = ( q['*'], q['^'], q[' '] );
            my @short_cuts = ( ( @{$union->{saved_cols}} ? $privious_cols : $void ), $all_cols );
            my @pre_col = ( $self->{info}{ok}, @short_cuts );
            unshift @pre_col, undef if $self->{opt}{sssc_mode};
            my $choices = [ @pre_col, @{$u->{col_names}{$union_table}} ];
            $self->__print_union_statement( $union );
            # Choose
            my @col = $no_lyt->choose(
                $choices,
                { %{$self->{info}{lyt_stmt_h}}, prompt => 'Choose Column:', no_spacebar => [ 0 .. $#pre_col ] }
            );
            if ( ! @col || ! defined $col[0] ) {
                if ( defined $union->{used_cols}{$union_table} ) {
                    delete $union->{used_cols}{$union_table};
                    next UNION_COLUMN;
                }
                else {
                    delete $self->{union_all} if $self->{union_all};
                    $union = clone( $backup_union );
                    last UNION_COLUMN;
                }
            }
            if ( $col[0] eq $self->{info}{ok} ) {
                shift @col;
                if ( @col ) {
                    push @{$union->{used_cols}{$union_table}}, @col;
                }
                elsif ( ! defined $union->{used_cols}{$union_table} ) {
                    my $tbl = splice( @{$union->{used_tables}}, $self->{idx_reset_used_tables}, 1 );
                    push @{$union->{unused_tables}}, "- $tbl";
                    delete $self->{idx_reset_used_tables};
                    delete $self->{union_all} if defined $self->{union_all};
                }
                last UNION_COLUMN;
            }
            if ( $col[0] eq $void ) {
                next UNION_COLUMN;
            }
            if ( $col[0] eq $privious_cols ) {
                $union->{used_cols}{$union_table} = $union->{saved_cols};
                next UNION_COLUMN if $self->{opt}{sssc_mode};
                last UNION_COLUMN;
            }
            if ( $col[0] eq $all_cols ) {
                @{$union->{used_cols}{$union_table}} = @{$u->{col_names}{$union_table}};
                next UNION_COLUMN if $self->{opt}{sssc_mode};
                last UNION_COLUMN;
            }
            else {
                push @{$union->{used_cols}{$union_table}}, @col;
            }
        }
        if ( $self->{union_all} ) {
            my @selected_cols = @{$union->{used_cols}{$union_table}};
            $union = {
                unused_tables => [],
                used_tables   => [ @{$u->{tables}} ],
                used_cols     => {},
                saved_cols    => [],
            };
            for my $union_table ( @{$union->{used_tables}} ) {
                @{$union->{used_cols}{$union_table}} = @selected_cols;
            }
            last UNION_TABLE;
        }
        $union->{saved_cols} = $union->{used_cols}{$union_table} if defined $union->{used_cols}{$union_table};
    }
    # column names in the result-set of a UNION are taken from the first query.
    my $first_table = $union->{used_tables}[0];
    $union->{pr_columns} = $union->{used_cols}{$first_table};
    for my $col ( @{$union->{pr_columns}} ) {
        $union->{qt_columns}{$col} = $dbh->quote_identifier( $col );
    }
    $union->{quote}{stmt} = "SELECT * FROM (";
    my $c;
    for my $table ( @{$union->{used_tables}} ) {
        $c++;
        $union->{quote}{stmt} .= " SELECT ";
        $union->{quote}{stmt} .= join( ', ', map { $dbh->quote_identifier( $_ ) } @{$union->{used_cols}{$table}} );
        $union->{quote}{stmt} .= " FROM " . $dbh->quote_identifier( undef, $schema, $table );
        $union->{quote}{stmt} .= $c < @{$union->{used_tables}} ? " UNION ALL " : " )";
    }
    if ( $self->{union_all} ) {
        $union->{quote}{stmt} .= " AS " . $dbh->quote_identifier( 'UNION_ALL_TABLES' );
    }
    else {
        #$union->{quote}{stmt} .= " AS " . $dbh->quote_identifier( join '_', @{$union->{used_tables}} );
        $union->{quote}{stmt} .= " AS " . $dbh->quote_identifier( 'UNION_SELECTED_TABLES' );
    }
    return $union;
}


sub __print_union_statement {
    my ( $self, $union ) = @_;
    my $str;
    if ( $self->{union_all} ) {
        $str = 'UNION ALL TABLES';
        if ( @{$union->{used_tables}} ) {
            $str .= "\n" . 'Cols: ';
            my $table = $union->{used_tables}[0];
            if ( defined $union->{used_cols}{$table} && @{$union->{used_cols}{$table}} ) { #
                $str .= join( ', ', @{$union->{used_cols}{$table}} );
            }
        }
        $str .= "\n";
    }
    else {
        $str = "SELECT * FROM (\n";
        if ( @{$union->{used_tables}} ) {
            my $c = 0;
            for my $table ( @{$union->{used_tables}} ) {
                ++$c;
                $str .= "  SELECT ";
                if ( defined $union->{used_cols}{$table} && @{$union->{used_cols}{$table}} ) { #
                    $str .= join( ', ', @{$union->{used_cols}{$table}} );
                }
                else {
                    $str .= '?';
                }
                $str .= " FROM $table";
                $str .= $c < @{$union->{used_tables}} ? " UNION ALL\n" : "\n";
            }
            $str .= ") AS ";
            #$str .= join '_', @{$union->{used_tables}};
            $str .= 'Selected_Tables';
            $str .= " \n";
        }
    }
    $str .= "\n";
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}}, ColMax => ( term_size() )[0] - 2 );
    print $self->{info}{clear_screen};
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $str );
}


sub __get_tables_info {
    my ( $self, $dbh, $db, $schema, $u_or_j ) = @_;
    my $tables_info = {};
    my $sth;
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my ( $pk, $fk ) = $obj_db->primary_and_foreign_keys( $dbh, $db, $schema, $u_or_j->{tables} );
    for my $table ( @{$u_or_j->{tables}} ) {
        push @{$tables_info->{$table}}, [ 'Table: ', '== ' . $table . ' ==' ];
        if ( defined $u_or_j->{col_names} ) {
            push @{$tables_info->{$table}}, [
                'Columns: ',
                join( ' | ', map {
                        lc( $u_or_j->{col_types}{$table}[$_] )
                    . ' ' . $u_or_j->{col_names}{$table}[$_] } 0 .. $#{$u_or_j->{col_names}{$table}} )
            ];
        }
        if ( defined $pk && @{$pk->{$table}} ) {
            push @{$tables_info->{$table}}, [ 'PK: ', 'primary key (' . join( ',', @{$pk->{$table}} ) . ')' ];
        }
        if ( defined $fk ) {
            for my $fk_name ( sort keys %{$fk->{$table}} ) {
                if ( $fk->{$table}{$fk_name} ) {
                    push @{$tables_info->{$table}}, [
                        'FK: ',
                        'foreign key (' . join( ',', @{$fk->{$table}{$fk_name}{foreign_key_col}} ) .
                        ') references ' . $fk->{$table}{$fk_name}{reference_table} .
                        '(' . join( ',', @{$fk->{$table}{$fk_name}{reference_key_col}} ) .')'
                    ];
                }
            }
        }
        if ( @{$tables_info->{$table}} == 1 ) {
            push @{$tables_info->{$table}}, [ '   No INFO available.' ];
        }
    }
    return $tables_info;
}


sub __print_tables_info {
    my ( $self, $ref ) = @_;
    my $len_key = 10;
    my $col_max = ( term_size() )[0] - 1;
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}} );
    $line_fold->config( 'ColMax', $col_max > $self->{info}{tbl_info_width} ? $self->{info}{tbl_info_width} : $col_max );
    my $ch_info = [ 'Close with ENTER' ];
    for my $table ( @{$ref->{tables}} ) {
        push @{$ch_info}, " ";
        for my $line ( @{$ref->{tables_info}{$table}} ) {
            my $text = sprintf "%*s%s", $len_key, @$line;
            $text = $line_fold->fold( '' , ' ' x $len_key, $text );
            push @{$ch_info}, split /\R+/, $text;
        }
    }
    return $ch_info;
}


sub __join_tables {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    my $stmt_v = Term::Choose->new( $self->{info}{lyt_stmt_v} );
    my $join = {};
    $join->{quote}{stmt} = "SELECT * FROM";
    $join->{print}{stmt} = "SELECT * FROM";
    my $j = $data->{$db}{$schema};
    if ( ! defined $j->{col_names} || ! defined $j->{col_types} ) {
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        ( $j->{col_names}, $j->{col_types} ) = $obj_db->column_names_and_types( $dbh, $db, $schema, $j->{tables} );
    }
    my @tables = map { "- $_" } @{$j->{tables}};

    MASTER: while ( 1 ) {
        $self->__print_join_statement( $join->{print}{stmt} );
        # Choose
        my @pre = ( undef );
        my $choices = [ @pre, @tables, $self->{info}{_info} ];
        my $idx = $stmt_v->choose(
            $choices,
            { prompt => 'Choose MASTER table:', index => 1 }
        );
        return if ! defined $idx;
        my $master = $choices->[$idx];
        return if ! defined $master;
        if ( $master eq $self->{info}{_info} ) {
            if ( ! defined $j->{tables_info} ) {
                $j->{tables_info} = $self->__get_tables_info( $dbh, $db, $schema, $j );
            }
            my $tbls_info = $self->__print_tables_info( $j );
            # Choose
            $stmt_v->choose(
                $tbls_info,
                { %{$self->{info}{lyt_3}}, prompt => '' }
            );
            next MASTER;
        }
        $idx -= @pre;
        splice( @tables, $idx, 1 );
        $master =~ s/^-\s//;
        $join->{used_tables}  = [ $master ];
        $join->{avail_tables} = [ @tables ];
        $join->{quote}{stmt}  = "SELECT * FROM " . $dbh->quote_identifier( undef, $schema, $master );
        $join->{print}{stmt}  = "SELECT * FROM " .                                         $master  ;
        $join->{primary_keys} = [];
        $join->{foreign_keys} = [];
        my $backup_master = clone( $join );

        JOIN: while ( 1 ) {
            my $enough_slaves = '  Enough TABLES';
            my ( $idx, $slave );
            my $backup_join = clone( $join );

            SLAVE: while ( 1 ) {
                $self->__print_join_statement( $join->{print}{stmt} );
                my @pre = ( undef, $enough_slaves );
                my $choices = [ @pre, @{$join->{avail_tables}}, $self->{info}{_info} ];
                # Choose
                $idx = $stmt_v->choose(
                    $choices,
                    { prompt => 'Add a SLAVE table:', index => 1, undef => $self->{info}{_reset} }
                );
                if ( defined $idx ) {
                    $slave = $choices->[$idx];
                    $idx -= @pre;
                }
                if ( ! defined $slave ) {
                    if ( @{$join->{used_tables}} == 1 ) {
                        @tables = map { "- $_" } @{$j->{tables}};
                        $join->{quote}{stmt} = "SELECT * FROM";
                        $join->{print}{stmt} = "SELECT * FROM";
                        next MASTER;
                    }
                    else {
                        $join = clone( $backup_master );
                        next JOIN;
                    }
                }
                elsif ( $slave eq $enough_slaves ) {
                    last JOIN;
                }
                elsif ( $slave eq $self->{info}{_info} ) {
                    if ( ! defined $j->{tables_info} ) {
                        $j->{tables_info} = $self->__get_tables_info( $dbh, $db, $schema, $j );
                    }
                    my $tbls_info = $self->__print_tables_info( $j );
                    # Choose
                    $stmt_v->choose(
                        $tbls_info,
                        { %{$self->{info}{lyt_3}}, prompt => '' }
                    );
                    next SLAVE;
                }
                else {
                    last SLAVE;
                }
            }
            splice( @{$join->{avail_tables}}, $idx, 1 );
            $slave =~ s/^-\s//;
            $join->{quote}{stmt} .= " LEFT OUTER JOIN " . $dbh->quote_identifier( undef, $schema, $slave ) . " ON";
            $join->{print}{stmt} .= " LEFT OUTER JOIN " .                                         $slave   . " ON";
            my %avail_pk_cols = ();
            for my $used_table ( @{$join->{used_tables}} ) {
                for my $col ( @{$j->{col_names}{$used_table}} ) {
                    $avail_pk_cols{ $used_table . '.' . $col } = $dbh->quote_identifier( undef, $used_table, $col );
                }
            }
            my %avail_fk_cols = ();
            for my $col ( @{$j->{col_names}{$slave}} ) {
                $avail_fk_cols{ $slave . '.' . $col } = $dbh->quote_identifier( undef, $slave, $col );
            }
            my $AND = '';

            ON: while ( 1 ) {
                $self->__print_join_statement( $join->{print}{stmt} );
                my @pre = ( undef );
                push @pre, $self->{info}{_continue} if $AND;
                # Choose
                my $pk_col = $stmt_v->choose(
                    [ @pre, map( "- $_", sort keys %avail_pk_cols ) ],
                    { prompt => 'Choose PRIMARY KEY column:', undef => $self->{info}{_reset} }
                );
                if ( ! defined $pk_col ) {
                    $join = clone( $backup_join );
                    next JOIN;
                }
                if ( $pk_col eq $self->{info}{_continue} ) {
                    if ( @{$join->{primary_keys}} == @{$backup_join->{primary_keys}} ) {
                        $join = clone( $backup_join );
                        next JOIN;
                    }
                    last ON;
                }
                $pk_col =~ s/^-\s//;
                push @{$join->{primary_keys}}, $avail_pk_cols{$pk_col};
                $join->{quote}{stmt} .= $AND;
                $join->{print}{stmt} .= $AND;
                $join->{quote}{stmt} .= ' ' . $avail_pk_cols{$pk_col} . " =";
                $join->{print}{stmt} .= ' ' .                $pk_col  . " =";
                $self->__print_join_statement( $join->{print}{stmt} );
                # Choose
                my $fk_col = $stmt_v->choose(
                    [ undef, map( "- $_", sort keys %avail_fk_cols ) ],
                    { prompt => 'Choose FOREIGN KEY column:', undef => $self->{info}{_reset} }
                );
                if ( ! defined $fk_col ) {
                    $join = clone( $backup_join );
                    next JOIN;
                }
                $fk_col =~ s/^-\s//;
                push @{$join->{foreign_keys}}, $avail_fk_cols{$fk_col};
                $join->{quote}{stmt} .= ' ' . $avail_fk_cols{$fk_col};
                $join->{print}{stmt} .= ' ' .                $fk_col;
                $AND = " AND";
            }
            push @{$join->{used_tables}}, $slave;
        }
        last MASTER;
    }

    #my @not_unique_col;
    #my %seen;
    #for my $table (@{$join->{used_tables}} ) {
    #    for my $col ( @{$j->{col_names}{$table}} ) {
    #        $seen{$col}++;
    #        push @not_unique_col, $col if $seen{$col} == 2;
    #    }
    #}
    my $col_stmt = '';
    for my $table ( @{$join->{used_tables}} ) {
        for my $col ( @{$j->{col_names}{$table}} ) {
            my $col_qt = $dbh->quote_identifier( undef, $table, $col );
            my $col_pr = $col;
            if ( any { $_ eq $col_qt } @{$join->{foreign_keys}} ) {
                next;
            }
            #if ( any { $_ eq $col_pr } @not_unique_col ) {
                $col_pr .= '_' . $table;
                $col_qt .= " AS " . $dbh->quote_identifier( $col_pr );
            #}
            push @{$join->{pr_columns}}, $col_pr;
            $join->{qt_columns}{$col_pr} = $col_qt;
            $col_stmt .= ', ' . $col_qt;
        }
    }
    $col_stmt =~ s/^,\s//;
    $join->{quote}{stmt} =~ s/\s\*\s/ $col_stmt /;
    return $join;
}


sub __print_join_statement {
    my ( $self, $join_stmt_pr ) = @_;
    $join_stmt_pr =~ s/(?=\sLEFT\sOUTER\sJOIN)/\n\ /g;
    $join_stmt_pr .= "\n\n";
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}}, ColMax => ( term_size() )[0] - 2 );
    print $self->{info}{clear_screen};
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $join_stmt_pr );
}





1;

__END__

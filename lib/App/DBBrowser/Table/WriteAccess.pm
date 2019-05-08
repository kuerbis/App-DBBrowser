package # hide from PAUSE
App::DBBrowser::Table::WriteAccess;

use warnings;
use strict;
use 5.010001;

use Term::Choose       qw();
use Term::Choose::Util qw( insert_sep );
use Term::TablePrint   qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;
#use App::DBBrowser::GetContent; # required
use App::DBBrowser::Table::Substatements;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data,
    };
    bless $sf, $class;
}


sub table_write_access {
    my ( $sf, $sql ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $sb = App::DBBrowser::Table::Substatements->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my @stmt_types;
    if ( ! $sf->{i}{special_table} ) {
        push @stmt_types, 'Insert' if $sf->{o}{enable}{insert_into};
        push @stmt_types, 'Update' if $sf->{o}{enable}{update};
        push @stmt_types, 'Delete' if $sf->{o}{enable}{delete};
    }
    elsif ( $sf->{i}{special_table} eq 'join' && $sf->{i}{driver} eq 'mysql' ) {
        push @stmt_types, 'Update' if $sf->{o}{G}{enable}{update};
    }
    if ( ! @stmt_types ) {
        return;
    }

    STMT_TYPE: while ( 1 ) {
        # Choose
        my $stmt_type = $tc->choose(
            [ undef, map( "- $_", @stmt_types ) ],
            { %{$sf->{i}{lyt_v_clear}}, prompt => 'Choose SQL type:' }
        );
        if ( ! defined $stmt_type ) {
            return;
        }
        $stmt_type =~ s/^-\ //;
        $sf->{i}{stmt_types} = [ $stmt_type ];
        $ax->reset_sql( $sql );
        if ( $stmt_type eq 'Insert' ) {
            my $ok = $sf->__build_insert_stmt( $sql );
            if ( $ok ) {
                $ok = $sf->commit_sql( $sql );
            }
            next STMT_TYPE;
        }
        my $sub_stmts = {
            Delete => [ qw( commit     where ) ],
            Update => [ qw( commit set where ) ],
        };
        my %cu = (
            commit => '  CONFIRM Stmt',
            set    => '- SET',
            where  => '- WHERE',
        );
        my $old_idx = 0;

        CUSTOMIZE: while ( 1 ) {
            my $choices = [ undef, @cu{@{$sub_stmts->{$stmt_type}}} ];
            $ax->print_sql( $sql, [ $stmt_type ] );
            # Choose
            my $idx = $tc->choose(
                $choices,
                { %{$sf->{i}{lyt_v}}, prompt => 'Customize:', index => 1, default => $old_idx }
            );
            if ( ! defined $idx || ! defined $choices->[$idx] ) {
                next STMT_TYPE;
            }
            my $custom = $choices->[$idx];
            if ( $sf->{o}{G}{menu_memory} ) {
                if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                    $old_idx = 0;
                    next CUSTOMIZE;
                }
                $old_idx = $idx;
            }
            my $backup_sql = $ax->backup_href( $sql );
            if ( $custom eq $cu{'set'} ) {
                my $ok = $sb->set( $sql );
                if ( ! $ok ) {
                    $sql = $backup_sql;
                }
            }
            elsif ( $custom eq $cu{'where'} ) {
                my $ok = $sb->where( $sql );
                if ( ! $ok ) {
                    $sql = $backup_sql;
                }
            }
            elsif ( $custom eq $cu{'commit'} ) {
                my $ok = $sf->commit_sql( $sql );
                next STMT_TYPE;
            }
            else {
                die "$custom: no such value in the hash \%cu";
            }
        }
    }
}


sub commit_sql {
    my ( $sf, $sql ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $dbh = $sf->{d}{dbh};
    my $waiting = 'DB work ... ';
    $ax->print_sql( $sql, $waiting );
    my $stmt_type = $sf->{i}{stmt_types}[-1];
    my $rows_to_execute = [];
    my $count_affected;
    if ( $stmt_type eq 'Insert' ) {
        return 1 if ! @{$sql->{insert_into_args}};
        $rows_to_execute = $sql->{insert_into_args};
        $count_affected = @$rows_to_execute;
    }
    else {
        $rows_to_execute = [ [ @{$sql->{set_args}}, @{$sql->{where_args}} ] ];
        my $all_arrayref = [];
        if ( ! eval {
            my $sth = $dbh->prepare( "SELECT * FROM " . $sql->{table} . $sql->{where_stmt} );
            $sth->execute( @{$sql->{where_args}} );
            my $col_names = $sth->{NAME};
            $all_arrayref = $sth->fetchall_arrayref;
            $count_affected = @$all_arrayref;
            unshift @$all_arrayref, $col_names;
            1 }
        ) {
            $ax->print_error_message( "$@Fetching info: affected records ...\n", $stmt_type );
        }
        my $prompt = $ax->print_sql( $sql );
        $prompt .= "Affected records:";
        if ( @$all_arrayref > 1 ) {
            my $tp = Term::TablePrint->new( $sf->{o}{table} );
            $tp->print_table(
                $all_arrayref,
                { grid => 2, prompt => $prompt, max_rows => 0, keep_header => 1,
                  table_expand => $sf->{o}{G}{info_expand} }
            );
        }
    }
    $ax->print_sql( $sql, $waiting );
    my $transaction;
    eval {
        $dbh->{AutoCommit} = 1;
        $transaction = $dbh->begin_work;
    } or do {
        $dbh->{AutoCommit} = 1;
        $transaction = 0;
    };
    if ( $transaction ) {
        return $sf->__transaction( $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting );
    }
    else {
        return $sf->__auto_commit( $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting );
    }
}


sub __transaction {
    my ( $sf, $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{default} );
    my $dbh = $sf->{d}{dbh};
    my $rolled_back;
    if ( ! eval {
        my $sth = $dbh->prepare(
            $ax->get_stmt( $sql, $stmt_type, 'prepare' )
        );
        for my $values ( @$rows_to_execute ) {
            $sth->execute( @$values );
        }
        my $commit_ok = sprintf qq(  %s %s "%s"), 'COMMIT', insert_sep( $count_affected, $sf->{o}{G}{thsd_sep} ), $stmt_type;
        $ax->print_sql( $sql );
        # Choose
        my $choice = $tc->choose(
            [ undef,  $commit_ok ],
            { %{$sf->{i}{lyt_v}} }
        );
        $ax->print_sql( $sql, $waiting );
        if ( ! defined $choice || $choice ne $commit_ok ) {
            $dbh->rollback;
            $rolled_back = 1;
        }
        else {;
            $dbh->commit;
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
    return 1;
}


sub __auto_commit {
    my ( $sf, $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{default} );
    my $dbh = $sf->{d}{dbh};
    my $commit_ok = sprintf qq(  %s %s "%s"), 'EXECUTE', insert_sep( $count_affected, $sf->{o}{G}{thsd_sep} ), $stmt_type;
    $ax->print_sql( $sql ); #
    # Choose
    my $choice = $tc->choose(
        [ undef,  $commit_ok ],
        { %{$sf->{i}{lyt_v}}, prompt => '' }
    );
    $ax->print_sql( $sql, $waiting );
    if ( ! defined $choice || $choice ne $commit_ok ) {
        return;
    }
    if ( ! eval {
        my $sth = $dbh->prepare(
            $ax->get_stmt( $sql, $stmt_type, 'prepare' )
        );
        for my $values ( @$rows_to_execute ) {
            $sth->execute( @$values );
        }
        1 }
    ) {
        $ax->print_error_message( $@, 'Auto Commit' );
        return;
    }
    return 1;
}


sub __build_insert_stmt {
    my ( $sf, $sql ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $tc = Term::Choose->new( $sf->{i}{default} );
    $ax->reset_sql( $sql );
    my @cu_keys = ( qw/insert_col insert_copy insert_file/ );
    my %cu = (
        insert_col  => '- Plain',
        insert_file => '- From File',
        insert_copy => '- Copy & Paste',
    );
    my $old_idx = 0;

    MENU: while ( 1 ) {
        my $choices = [ undef, @cu{@cu_keys} ];
        # Choose
        my $idx = $tc->choose(
            $choices,
            { %{$sf->{i}{lyt_v_clear}}, index => 1, default => $old_idx, undef => '  <=' }
        );
        if ( ! defined $idx || ! defined $choices->[$idx] ) {
            return;
        }
        my $custom = $choices->[$idx];
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx = 0;
                next MENU;
            }
            $old_idx = $idx;
        }
        my $cols_ok = $sf->__insert_into_stmt_columns( $sql );
        if ( ! $cols_ok ) {
            next MENU;
        }
        my $insert_ok;
        require App::DBBrowser::GetContent;
        my $gc = App::DBBrowser::GetContent->new( $sf->{i}, $sf->{o}, $sf->{d} );
        if ( $custom eq $cu{insert_col} ) {
            $insert_ok = $gc->from_col_by_col( $sql );
        }
        elsif ( $custom eq $cu{insert_copy} ) {
            $insert_ok = $gc->from_copy_and_paste( $sql );
        }
        elsif ( $custom eq $cu{insert_file} ) {
            $insert_ok = $gc->from_file( $sql );
        }
        if ( ! $insert_ok ) {
            next MENU;
        }
        return 1
    }
}


sub __insert_into_stmt_columns {
    my ( $sf, $sql ) = @_;
    my $ax  = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $plui = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $tc = Term::Choose->new( $sf->{i}{default} );
    $sql->{insert_into_cols} = [];
    my @cols = ( @{$sql->{cols}} );
    if ( $plui->first_column_is_autoincrement( $sf->{d}{dbh}, $sf->{d}{schema}, $sf->{d}{table} ) ) {
        shift @cols;
    }
    my $bu_cols = [ @cols ];

    COL_NAMES: while ( 1 ) {
        $ax->print_sql( $sql );
        my @pre = ( undef, $sf->{i}{ok} );
        my $choices = [ @pre, @cols ];
        # Choose
        my @idx = $tc->choose(
            $choices,
            { %{$sf->{i}{lyt_h}}, prompt => 'Columns:', meta_items => [ 0 .. $#pre ], include_highlighted => 2,
              index => 1 }
        );
        if ( ! $idx[0] ) {
            if ( ! @{$sql->{insert_into_cols}} ) {
                return;
            }
            $sql->{insert_into_cols} = [];
            @cols = @$bu_cols;
            next COL_NAMES;
        }
        if ( $idx[0] == 1 ) {
            shift @idx;
            push @{$sql->{insert_into_cols}}, @{$choices}[@idx];
            if ( ! @{$sql->{insert_into_cols}} ) {
                $sql->{insert_into_cols} = $bu_cols;
            }
            return 1;
        }
        push @{$sql->{insert_into_cols}}, @{$choices}[@idx];
        my $c = 0;
        for my $i ( @idx ) {
            last if ! @cols;
            my $ni = $i - ( @pre + $c );
            splice( @cols, $ni, 1 );
            ++$c;
        }
    }
}





1;


__END__

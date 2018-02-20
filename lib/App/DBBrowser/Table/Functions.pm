package # hide from PAUSE
App::DBBrowser::Table::Functions;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_02';

use Clone           qw( clone );
use List::MoreUtils qw( first_index );
use Term::Choose    qw( choose );

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;


sub new {
    my ( $class, $info, $opt ) = @_;
    bless { i => $info, o => $opt }, $class;
}


sub col_function {
    my ( $sf, $dbh, $sql, $backup_sql, $sql_type ) = @_;
    my $ax  = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my @functions = ( qw( Epoch_to_Date Bit_Length Truncate Char_Length Epoch_to_DateTime ) );
    my $stmt_key = '';
    if ( $sql->{select_type} eq '*' ) {
        @{$sql->{chosen_cols}} = @{$sql->{cols}};
        $stmt_key = 'chosen_cols';
    }
    elsif ( $sql->{select_type} eq 'chosen_cols' ) {
        $stmt_key = 'chosen_cols';
    }
    # if not $sql->{orig_cols}{stmt_type}, then no modified cols in $sql->{stmt_key}
    if ( $stmt_key eq 'chosen_cols' ) {
        if ( ! $sql->{orig_cols}{chosen_cols} ) {
            @{$sql->{orig_cols}{'chosen_cols'}} = @{$sql->{chosen_cols}};
        }
    }
    else {
        if ( @{$sql->{aggr_cols}} && ! $sql->{orig_cols}{aggr_cols} ) {
            @{$sql->{orig_cols}{'aggr_cols'}} = @{$sql->{aggr_cols}};
        }
        if ( @{$sql->{group_by_cols}} && ! $sql->{orig_cols}{group_by_cols} ) {
            @{$sql->{orig_cols}{'group_by_cols'}} = @{$sql->{group_by_cols}};
        }
    }
    my $changed = 0;

    COL_SCALAR_FUNC: while ( 1 ) {
        my $default = 0;
        my @pre = ( undef, $sf->{i}{_confirm} );
        my @cols;
        if ( $stmt_key eq 'chosen_cols' ) {
            @cols = @{$sql->{chosen_cols}};
        }
        else {
            @cols = ( @{$sql->{aggr_cols}}, @{$sql->{group_by_cols}} );
        }
        my $choices = [ @pre, map( "- $_", @cols ) ];
        $ax->print_sql( $sql, [ $sql_type ] );
        # Choose
        my $idx = choose(
            $choices,
            { %{$sf->{i}{lyt_stmt_v}}, index => 1, default => $default }
        );
        if ( ! defined $idx || ! defined $choices->[$idx] ) {
            $sql = clone( $backup_sql );
            return;
        }
        if ( $choices->[$idx] eq $sf->{i}{_confirm} ) {
            if ( ! $changed ) {
                $sql = clone( $backup_sql );
                return;
            }
            $sql->{select_type} = 'chosen_cols' if $sql->{select_type} eq '*'; # makes the changes visible
            return;
        }
        ( my $qt_col = $choices->[$idx] ) =~ s/^\-\s//;
        $idx -= @pre;
        if ( $stmt_key ne 'chosen_cols' ) {
            if ( $idx - @{$sql->{aggr_cols}} >= 0 ) { # chosen a "group by" col
                $idx -= @{$sql->{aggr_cols}};
                $stmt_key = 'group_by_cols';
            }
            else {
                $stmt_key = 'aggr_cols';
            }
        }
        # reset col to original, if __col_function is called on a already modified col:
        if ( $sql->{$stmt_key}[$idx] ne $sql->{orig_cols}{$stmt_key}[$idx] ) {
            if ( $stmt_key eq 'chosen_cols' || $stmt_key eq 'group_by_cols' ) {
                my $i = first_index { $sql->{$stmt_key}[$idx] eq $_ } @{$sql->{modified_cols}};
                splice( @{$sql->{modified_cols}}, $i, 1 );
            }
            $sql->{$stmt_key}[$idx] = $sql->{orig_cols}{$stmt_key}[$idx];
            $changed++;
            next COL_SCALAR_FUNC;
        }
        $ax->print_sql( $sql, [ $sql_type ] );
        # Choose
        my $function = choose(
            [ undef, map( "  $_", @functions ) ],
            { %{$sf->{i}{lyt_stmt_v}} }
        );
        if ( ! defined $function ) {
            next COL_SCALAR_FUNC;
        }
        $function =~ s/^\s\s//;
        $ax->print_sql( $sql, [ $sql_type ] );
        my $qt_scalar_func = $sf->__prepare_col_func( $function, $qt_col );
        if ( ! defined $qt_scalar_func ) {
            next COL_SCALAR_FUNC;
        }
        $sql->{$stmt_key}[$idx] = $qt_scalar_func;
        if ( $stmt_key eq 'group_by_cols' ) {
            $sql->{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{$stmt_key}} );
        }
        # modified_cols: used in WHERE and GROUB BY
        # skip aggregate functions because aggregate are not allowed in WHERE clauses
        # no problem for GROUB BY because it doesn't use modified_cols in aggregate mode
        if ( $stmt_key ne 'aggr_cols' ) {
            push @{$sql->{modified_cols}}, $qt_scalar_func;
        }
        $changed++;
        next COL_SCALAR_FUNC;
    }
}


sub __prepare_col_func {
    my ( $sf, $func, $qt_col ) = @_;
    my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $quote_f;
    if ( $func =~ /^Epoch_to_Date(?:Time)?\z/ ) {
        my $prompt = $func eq 'Epoch_to_Date' ? 'DATE' : 'DATETIME';
        $prompt .= "($qt_col)\nInterval:";
        my ( $microseconds, $milliseconds, $seconds ) = (
            '  ****************   Micro-Second',
            '  *************      Milli-Second',
            '  **********               Second' );
        my $choices = [ undef, $microseconds, $milliseconds, $seconds ];
        # Choose
        my $interval = choose(
            $choices,
            { %{$sf->{i}{lyt_stmt_v}}, prompt => $prompt }
        );
        return if ! defined $interval;
        my $div = $interval eq $microseconds ? 1000000 :
                  $interval eq $milliseconds ? 1000 : 1;
        if ( $func eq 'Epoch_to_DateTime' ) {
            $quote_f = $obj_db->epoch_to_datetime( $qt_col, $div );
        }
        else {
            $quote_f = $obj_db->epoch_to_date( $qt_col, $div );
        }
    }
    elsif ( $func eq 'Truncate' ) {
        my $prompt = "TRUNC $qt_col\nDecimal places:";
        my $choices = [ undef, 0 .. 9 ];
        # Choose
        my $precision = choose( # choose_a_number
            $choices,
            { %{$sf->{i}{lyt_stmt_h}}, prompt => $prompt }
        );
        return if ! defined $precision;
        $quote_f = $obj_db->truncate( $qt_col, $precision );
    }
    elsif ( $func eq 'Bit_Length' ) {
        $quote_f = $obj_db->bit_length( $qt_col );
    }
    elsif ( $func eq 'Char_Length' ) {
        $quote_f = $obj_db->char_length( $qt_col );
    }
    return $quote_f;
}





1;


__END__

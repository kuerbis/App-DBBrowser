package # hide from PAUSE
App::DBBrowser::Table::Extensions;

use warnings;
use strict;
use 5.014;

use Term::Choose qw();

use App::DBBrowser::Auxil;
#use App::DBBrowser::Subqueries;              # required
#use App::DBBrowser::Table::ScalarFunctions;  # required
#use App::DBBrowser::Table::WindowFunctions;  # required

sub new {
    my ( $class, $info, $options, $d ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $d
    }, $class;
}


sub complex_unit {
    my ( $sf, $sql, $clause, $info, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my ( $subquery, $function, $window_function, $cs, $set_to_null ) = ( 'SQ', 'f()', 'w()', '(c)', '=N' );
    my @types;
    if ( $clause eq 'set' ) {
        @types = ( $subquery, $function, $cs, $set_to_null );
    }
    elsif ( $clause =~ /^(?:select|order_by)\z/i ) {
        # Window functions are permitted only in SELECT and ORDER BY
        @types = ( $subquery, $function, $window_function, $cs );
    }
    elsif ( $clause =~ /^(?:where|having)\z/ && $sql->{$clause . '_stmt'} =~ /\s(?:ALL|ANY|IN)\z/ ) {
            @types = ( $subquery );
    }
    else {
        @types = ( $subquery, $function, $cs );
    }
    if ( $clause =~ /^when\z/ ) {
        @types = grep { ! /^\Q$cs\E\z/ } @types;
    }
    my $old_idx = 0;

    EXTENSIONS: while ( 1 ) {
        my @pre = ( undef );
        $info ||= $ax->get_sql_info( $sql ); ##
        # Choose
        my $idx = $tc->choose(
            [ @pre, @types ],
            { %{$sf->{i}{lyt_h}}, info => $info, index => 1, default => $old_idx }
        );
        $ax->print_sql_info( $info );
        if ( ! $idx ) {
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx = 0;
                next EXTENSIONS;
            }
            $old_idx = $idx;
        }
        my $type = $types[$idx-@pre];
        my $complex_units = [];
        if ( $type eq $set_to_null ) {
            return "NULL";
        }
        elsif ( $type eq $subquery ) {
            require App::DBBrowser::Subqueries;
            my $new_sq = App::DBBrowser::Subqueries->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $subq = $new_sq->choose_subquery( $sql );
            if ( ! defined $subq ) {
                next EXTENSIONS;
            }
            return $subq;
        }
        elsif ( $type eq $function ) {
            require App::DBBrowser::Table::ScalarFunctions;
            my $new_func = App::DBBrowser::Table::ScalarFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $scalar_func_stmt = $new_func->col_function( $sql, $clause, $r_data );
            if ( ! defined $scalar_func_stmt ) {
                next EXTENSIONS;
            }
            return $scalar_func_stmt;
        }
        elsif ( $type eq $window_function ) {
            require App::DBBrowser::Table::WindowFunctions;
            my $wf = App::DBBrowser::Table::WindowFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $win_func_stmt = $wf->window_function( $sql, $clause );
            if ( ! defined $win_func_stmt ) {
                next EXTENSIONS;
            }
            return $win_func_stmt;
        }
        elsif ( $type eq $cs ) {
            require App::DBBrowser::Table::Case;
            my $new_cs = App::DBBrowser::Table::Case->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $case_stmt = $new_cs->case( $sql, $clause, $r_data );
            if ( ! defined $case_stmt ) {
                next EXTENSIONS;
            }
            return $case_stmt;
        }
    }
}




1;


__END__

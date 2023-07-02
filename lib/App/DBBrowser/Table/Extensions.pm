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
    my ( $sf, $sql, $clause, $func_recurs_arg ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my ( $function, $subquery, $set_to_null, $window_function ) = ( 'f()', 'SQ', '=N', 'w()' );
    my @types;
    if ( $clause eq 'set' ) {
        @types = ( $function, $subquery, $set_to_null );
    }
    elsif ( $clause =~ /^(?:select|order_by)\z/i ) {
        @types = ( $function, $subquery, $window_function );
    }
    elsif ( $clause =~ /^(?:where|having)\z/ && $sql->{$clause . '_stmt'} =~ /\s(?:ALL|ANY|IN)\z/ ) {
            @types = ( $subquery );
    }
    else {
        @types = ( $function, $subquery );
    }
    my $info = $ax->get_sql_info( $sql );
    # Choose
    my $type = $tc->choose(
        [ undef, @types ],
        { %{$sf->{i}{lyt_h}}, info => $info }
    );
    $ax->print_sql_info( $info );
    if ( ! defined $type ) {
        return;
    }
    my $complex_units = [];
    if ( $type eq $set_to_null ) {
        return "NULL";
    }
    elsif ( $type eq $subquery ) {
        require App::DBBrowser::Subqueries;
        my $new_sq = App::DBBrowser::Subqueries->new( $sf->{i}, $sf->{o}, $sf->{d} );
        my $subq = $new_sq->choose_subquery( $sql );
        if ( ! defined $subq ) {
            return;
        }
        return $subq;
    }
    elsif ( $type eq $function ) {
        require App::DBBrowser::Table::ScalarFunctions;
        my $new_func = App::DBBrowser::Table::ScalarFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
        my $scalar_func_stmt = $new_func->col_function( $sql, $clause, $func_recurs_arg );
        if ( ! defined $scalar_func_stmt ) {
            return;
        }
        return $scalar_func_stmt;
    }
    elsif ( $type eq $window_function ) {
        require App::DBBrowser::Table::WindowFunctions;
        my $wf = App::DBBrowser::Table::WindowFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
        my $win_func_stmt = $wf->window_function( $sql, $clause );
        if ( ! defined $win_func_stmt ) {
            return;
        }
        return $win_func_stmt;
    }
}




1;


__END__

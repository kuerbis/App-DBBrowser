package # hide from PAUSE
App::DBBrowser::Table::Extensions::Case;

use warnings;
use strict;
use 5.014;

use Term::Choose         qw();
use Term::Form::ReadLine qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Subqueries;
use App::DBBrowser::Table::Extensions::ScalarFunctions;

sub new {
    my ( $class, $info, $options, $d ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $d
    }, $class;
}


sub case {
    my ( $sf, $sql, $clause, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $sb = App::DBBrowser::Table::Substatements->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    $r_data //= {};
    $r_data->{case} //= []; # name ##
    my $tmp_sql = $ax->backup_href( $sql );
    $tmp_sql->{case_stmt} = $r_data->{case}[-1] // '';
    my $qt_cols = [ @{$sql->{cols}} ];
    my $in = ' ' x $sf->{o}{G}{base_indent};
    my $count = @{$r_data->{case}};
    #my $pad1 = $in x ( $count * 4 );
    #my $pad2 = $in x ( ($count + 1 ) * 4 );
    my $pad1;
    my $pad2;
    if ( ! $count ) {
        $pad1 = '';
        $pad2 = $in x 2;
    }
    else {
        my $d = $count * 4;
        $pad1 = $in x $d;
        $pad2 = $in x ( $d + 2);
    }
    $pad1 .= $in;
    $pad2 .= $in;
    my $preceding_stmt = $tmp_sql->{case_stmt};
    if ( $preceding_stmt ) {
        $tmp_sql->{case_stmt} .= "\n${pad1}CASE";
    }
    else {
        $tmp_sql->{case_stmt} .= "${pad1}CASE";
    }
    my @bu;
    my $else_on = 0;

    ROWS: while ( 1 ) { # name
        my ( $when, $else, $end ) = ( '  WHEN', '  ELSE', '  END' );
        my @pre = ( undef );
        my $menu;
        if ( $else_on ) {
             $menu = [ @pre, $end ];
        }
        else {
            $menu = [ @pre, $when, $else, $end ];
        }
        my $info = $ax->get_sql_info( $tmp_sql );
        # Choose
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_v}}, info => $info, prompt => 'Your choice:', index => 1, undef => '  <=' }
        );
        $ax->print_sql_info( $info );
        if ( ! $idx ) {
            if ( @bu ) {
                $tmp_sql->{case_stmt} = pop @bu;
                $else_on = 0;
                next ROWS;
            }
            delete $tmp_sql->{case_stmt};
            return;
        }
        push @bu, $tmp_sql->{case_stmt};
        if ( $menu->[$idx] eq $end ) {
            $tmp_sql->{case_stmt} .= "\n${pad1}END";
            my $case_stmt = delete $tmp_sql->{case_stmt};
            if ( $preceding_stmt ) {
                $case_stmt =~ s/^\Q$preceding_stmt\E//;
            }
            else {
                $case_stmt = "\n" . $case_stmt;
            }
            return $case_stmt;
        }
        elsif ( $menu->[$idx] eq $when ) {
            $tmp_sql->{when_stmt} = "${pad2}WHEN";
            $tmp_sql->{when_args} = [];
            my $ret = $sb->__add_condition( $tmp_sql, 'when', $qt_cols );
            delete $tmp_sql->{when_args};
            if ( ! defined $ret ) {
                delete $tmp_sql->{when_stmt};
                $tmp_sql->{case_stmt} = pop @bu;
                next ROWS;
            }
            $tmp_sql->{case_stmt} .= "\n" . delete $tmp_sql->{when_stmt};
            $tmp_sql->{case_stmt} .= " THEN";
            my $value = $sf->__value( $tmp_sql, $qt_cols, $r_data );
            if ( ! defined $value ) {
                $tmp_sql->{case_stmt} = pop @bu;
                next ROWS;
            }
            $tmp_sql->{case_stmt} .= ' ' . $value;
        }
        elsif ( $menu->[$idx] eq $else ) {
            $tmp_sql->{case_stmt} .= "\n${pad2}ELSE";
            my $value = $sf->__value( $tmp_sql, $qt_cols, $r_data );
            if ( ! defined $value ) {
                $tmp_sql->{case_stmt} = pop @bu;
                next ROWS;
            }
            $tmp_sql->{case_stmt} .= ' ' . $value;
            $else_on = 1;

        }
    }
}


sub __value {
    my ( $sf, $tmp_sql, $qt_cols, $r_data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my ( $const, $sq, $func, $cs, $col ) = ( 'Value', 'SQ', 'f()', 'case', 'col' );
    my $clause = 'case';

    TYPE: while ( 1 ) {
        my $info = $ax->get_sql_info( $tmp_sql );
        # Choose
        my $type = $tc->choose(
            [ undef, $const, $sq, $func, $cs, $col ],
            { %{$sf->{i}{lyt_h}}, info => $info, prompt => 'Result:', undef => '<<' }
        );
        $ax->print_sql_info( $info );
        if ( ! defined $type ) {
            return;
        }
        if ( $type eq $const ) {
            # Readline
            my $value = $tr->readline(
                'Value: ',
                { info => $info }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $value ) {
                next TYPE;
            }
            return $ax->quote_constant( $value );
        }
        elsif ( $type eq $sq ) {
            my $new_sq = App::DBBrowser::Subqueries->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $subq = $new_sq->choose_subquery( $tmp_sql );
            if ( ! defined $subq ) {
                next TYPE;
            }
            return $subq;
        }
        elsif ( $type eq $col ) {
            # Choose
            my $col = $tc->choose(
                [ undef, map { '- ' . $_ } @$qt_cols ],
                { %{$sf->{i}{lyt_v}}, info => $info, prompt => '', undef => '<=' }
            );
            $ax->print_sql_info( $info );
            if ( ! defined $col ) {
                next TYPE;
            }
            return $col =~ s/^- //r;
        }
        elsif ( $type eq $func ) {
            my $new_func = App::DBBrowser::Table::Extensions::ScalarFunctions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $scalar_func_stmt = $new_func->col_function( $tmp_sql, $clause, $r_data );
            if ( ! defined $scalar_func_stmt ) {
                next TYPE;
            }
            return $scalar_func_stmt;
        }
        elsif ( $type eq $cs ) {
            push @{$r_data->{case}}, $tmp_sql->{case_stmt};
            my $case_stmt = $sf->case( $tmp_sql, $clause, $r_data );
            pop @{$r_data->{case}};
            if ( ! defined $case_stmt ) {
                next TYPE;
            }
            return $case_stmt;
        }
    }
}






1
__END__

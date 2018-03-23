package # hide from PAUSE
App::DBBrowser::Subqueries;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '2.007';

use File::Basename        qw( basename );
use File::Spec::Functions qw( catfile );

use List::MoreUtils qw( any );

use Term::Choose           qw( choose );
use Term::Choose::LineFold qw( print_columns );
use Term::Choose::Util     qw( choose_a_subset term_width );
use Term::Form             qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI'; #

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data
    };
    bless $sf, $class;
}


sub choose_subquery {
    my ( $sf, $sql, $tmp, $stmt_type ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my @pre = ( undef );
    my $h_ref = $ax->read_json( $sf->{i}{sq_file} );
    my $saved_subqueries = $h_ref->{$sf->{d}{db}} || []; # reverse
    my $tmp_subqueries = $sf->{i}{stmt_history};
    my $pr_saved_subqueries = $sf->__pr_subqueries( $saved_subqueries );
    my $pr_tmp_subqueries = $sf->__pr_subqueries( $tmp_subqueries );

    while ( 1 ) {
        my $pr_subqueries = $sf->__pr_subqueries( $saved_subqueries, $tmp_subqueries );
        my $choices = [ @pre, map( '  ' . $_, @$pr_saved_subqueries ), map( 't ' . $_, @$pr_tmp_subqueries ) ];
        my $idx = $sf->__choose_see_long( $choices, $sql, $tmp, $stmt_type  );
        if ( ! $idx ) {
            return;
        }
        else {
            $idx -= @pre;
            if ( $idx <= $#$saved_subqueries ) {
                return $saved_subqueries->[$idx];
            }
            else {
                $idx -= @$saved_subqueries;
                return $tmp_subqueries->[$idx];
            }
        }
    }
}


sub __pr_subqueries {
    my ( $sf, $subqueries ) = @_;
    my $pr_subqueries = [];
    for my $e ( @$subqueries ) {
        push @$pr_subqueries, $e->[0] . '  [' . join( ',', @{$e->[1]} ) . ']';
    }
    return $pr_subqueries;
}


sub __choose_see_long {
    my ( $sf, $choices, $sql, $tmp, $stmt_type  ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );

    HIST: while ( 1 ) {
        $ax->print_sql( $sql, [ $stmt_type ], $tmp );
        my $idx = choose( $choices, { %{$sf->{i}{lyt_stmt_v}}, index => 1 } );
        if ( ! $idx ) {
            return;
        }
        if ( print_columns( $choices->[$idx] ) > term_width() ) {
            my $stmt = $choices->[$idx];
            $stmt =~ s/^[\ t]\ //;
            $ax->print_sql( $sql, [ $stmt_type ], $tmp );
            my $ok = choose(
                [ undef, $sf->{i}{ok} ],
                { %{$sf->{i}{lyt_stmt_h}}, prompt => $stmt, undef => '<<' }
            );
            if ( ! $ok ) {
                next HIST;
            }
        }
        return $idx;
    }
}


sub edit_sq_file {
    my ( $sf ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my ( $add, $remove ) = ( '  Add', '  Remove' );
    my @pre = ( undef );

    while ( 1 ) {
        my $h_ref = $ax->read_json( $sf->{i}{sq_file} );
        my $subqueries = $h_ref->{$sf->{d}{db}} || [];
        my $pr_subqueries = $sf->__pr_subqueries( $subqueries );
        my @tmp = ( $sf->{d}{db_string}, 'Saved stmts:', map( '  ' . $_, @$pr_subqueries ), ' ' );
        my $info = join "\n", @tmp;
        my $choice = choose(
            [ @pre, $add, $remove ],
            { %{$sf->{i}{lyt_3}}, undef => $sf->{i}{back_config}, prompt => 'Choose:', info => $info }
        );
        if ( ! defined $choice ) {
            return;
        }
        elsif ( $choice eq $add ) {
            $sf->__add_subqueries();
        }
        elsif ( $choice eq $remove ) {
            $sf->__remove_subqueries();
        }
    }
}


sub __add_subqueries {
    my ( $sf ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $h_ref = $ax->read_json( $sf->{i}{sq_file} );
    my $subqueries = $h_ref->{$sf->{d}{db}} || [];
    my $available = [ @{$sf->{i}{stmt_history}} ];
    my $readline = '  readline';
    my @pre = ( undef, $sf->{i}{_confirm}, $readline );
    my $info = $sf->{d}{db_string} . "\n" . 'Saved stmts:';
    my $bu = [];

    while ( 1 ) {
        my $pr_subqueries = $sf->__pr_subqueries( $subqueries );
        my @tmp = ( $sf->{d}{db_string}, 'Saved stmts:', map( '  ' . $_, @$pr_subqueries ), ' ' );
        my $info = join "\n", @tmp;
        my $pr_history = $sf->__pr_subqueries( $available );
        my $choices = [ @pre, map { '  ' . $_ } @$pr_history ];
        my $idx = choose(
            $choices,
            { %{$sf->{i}{lyt_3}}, prompt => 'Add:', info => $info, index => 1, undef => $sf->{i}{_back} }
        );
        if ( ! $idx ) {
            if ( @$bu ) {
                ( $subqueries, $available ) = @{pop @$bu};
                next; #
            }
            return 0;
        }
        elsif ( $choices->[$idx] eq $sf->{i}{_confirm} ) {
            if ( $subqueries ) {
                $h_ref->{$sf->{d}{db}} = $subqueries;
            }
            else {
                delete $h_ref->{$sf->{d}{db}};
            }
            $ax->write_json( $sf->{i}{sq_file}, $h_ref );
            return 1;
        }
        elsif ( $choices->[$idx] eq $readline ) {
            my $tf = Term::Form->new();
            my $stmt = $tf->readline( 'Statement: ', { info => $info, clear_screen => 1  } );
            if ( ! defined $stmt || ! length $stmt ) {
                if ( @$bu ) {
                    ( $subqueries, $available ) = @{pop @$bu};
                    next; #
                }
                return 0;
            }
            my $args = [];
            ARGS: while ( 1 ) {
                my $new = '  ' . $stmt . '  [' . join( ',', @$args );
                my @tmp = ( $sf->{d}{db_string}, 'Saved stmts:', map( '  ' . $_, @$pr_subqueries ), $new, ' ' );
                my $info = join "\n", @tmp;
                # Readline
                my $value = $tf->readline( 'Argument: ', { info => $info, clear_screen => 1 } );
                if ( ! defined $value ) {
                    if ( @$args ) {
                        pop @$args;
                        next ARGS;
                    }
                    return 0;
                }
                elsif ( $value eq '' ) {
                    last ARGS;
                }
                else {
                    push @$args, $value;
                }
            }
            push @$bu, [ [ @$subqueries ], [ @$available ] ];
            push @$subqueries, [ $stmt, $args ];
        }
        else {
            push @$bu, [ [ @$subqueries ], [ @$available ] ];
            push @$subqueries, splice( @$available, $idx-@pre, 1 );
        }
    }
}


sub __remove_subqueries {
    my ( $sf ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $h_ref = $ax->read_json( $sf->{i}{sq_file} );
    my $subqueries = $h_ref->{$sf->{d}{db}} || [];
    if ( ! @$subqueries ) {
        return 0;
    }
    my @tmp = ( $sf->{d}{db_string}, 'Remove:' );
    my $info = join "\n", @tmp;
    my $prompt = "\n" . 'Choose stmt to remove:';
    my $pr_subqueries = $sf->__pr_subqueries( $subqueries );
    my $idx = choose_a_subset(
        $pr_subqueries,
        { mouse => $sf->{o}{table}{mouse}, index => 1, show_fmt => 1,
          keep_chosen => 0, prompt => $prompt, info => $info }
    );
    if ( ! defined $idx || ! @$idx ) {
        return 0;
    }
    for my $i ( sort { $b <=> $a } @$idx ) {
        my $ref = splice( @$subqueries, $i, 1 );
    }
    if ( $subqueries ) {
        $h_ref->{$sf->{d}{db}} = $subqueries;
    }
    else {
        delete $h_ref->{$sf->{d}{db}};
    }
    $ax->write_json( $sf->{i}{sq_file}, $h_ref );
}





1;


__END__

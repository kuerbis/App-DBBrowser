package # hide from PAUSE
App::DBBrowser::Subqueries;

use warnings;
use strict;
use 5.008003;

use File::Spec::Functions qw( catfile );

use List::MoreUtils qw( any );

use Term::Choose           qw( choose );
use Term::Choose::LineFold qw( print_columns line_fold );
use Term::Choose::Util     qw( choose_a_subset term_width );
use Term::Form             qw();

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data,
        subquery_file => catfile( $info->{app_dir}, 'subqueries.json' ),
    };
    bless $sf, $class;
}


sub __stmt_history {
    my ( $sf ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $history_filled = [];
    my $tmp_history_stmt = [];
    for my $stmt ( @{$sf->{i}{stmt_history}} ) {
        my $filled_stmt = $ax->stmt_placeholder_to_value( @$stmt, 1 );
        if ( $filled_stmt =~ /^[^\(]+FROM\s*\(\s*(\S.+\S)\s*\)[^\)]*\z/ ) { # Union, Join
            $filled_stmt = $1;
        }
        if ( any { $_ eq $filled_stmt } @$history_filled ) {
            next;
        }
        if ( @$tmp_history_stmt == 7 ) {
            $sf->{i}{stmt_history} = $tmp_history_stmt;
            last;
        }
        push @$tmp_history_stmt, $stmt;
        push @$history_filled, $filled_stmt;
    }
    return $history_filled;
}


sub choose_subquery {
    my ( $sf, $sql, $tmp, $stmt_type, $from_clause ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my @pre = ( undef );
    my $h_ref = $ax->read_json( $sf->{subquery_file} );
    my $driver = $sf->{d}{driver};
    my $db = $sf->{d}{db};
    my $subqueries = $h_ref->{$driver}{$db} || []; # reverse
    my $history = [];
    $history = $sf->__stmt_history() if ! $from_clause;
    my $choices = [ @pre, map( '- ' . $_->[-1], @$subqueries ), map( '  ' . $_, @$history ) ];
    if ( @$choices == @pre ) {
        return; # no subqueries
    }
    my $idx = $sf->__choose_see_long( $choices, $sql, $tmp, $stmt_type, $from_clause );
    if ( ! $idx ) {
        return;
    }
    else {
        $idx -= @pre;
        if ( $idx <= $#$subqueries ) {
            return $subqueries->[$idx][0];
        }
        else {
            $idx -= @$subqueries;
            return $history->[$idx];
        }
    }
}


sub __choose_see_long {
    my ( $sf, $choices, $sql, $tmp, $stmt_type, $from_clause  ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $info;
    if ( $from_clause ) {
        $info = $sf->{d}{db_string};
    }

    HIST: while ( 1 ) {
        $ax->print_sql( $sql, [ $stmt_type ], $tmp ) if ! $from_clause;
        my $idx = choose( $choices, { %{$sf->{i}{lyt_stmt_v}}, index => 1, info => $info, prompt => "\nChoose SQ:" } );
        if ( ! $idx ) {
            return;
        }
        if ( print_columns( $choices->[$idx] ) > term_width() ) {
            my $stmt = $choices->[$idx];
            $stmt =~ s/^[\ t]\ //;
            $ax->print_sql( $sql, [ $stmt_type ], $tmp ) if ! $from_clause;
            my $ok = choose(
                [ undef, $sf->{i}{ok} ],
                { %{$sf->{i}{lyt_stmt_h}}, prompt => $stmt, undef => '<<', info => $info }
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
    my $driver = $sf->{d}{driver};
    my $db = $sf->{d}{db};
    my @pre = ( undef );
    my ( $add, $edit, $remove ) = ( '- Add', '- Edit', '- Remove' );

    while ( 1 ) {
        my $h_ref = $ax->read_json( $sf->{subquery_file} );
        my $subqueries = $h_ref->{$driver}{$db} || [];
        my @tmp_info = (
            $sf->{d}{db_string},
            'Saved SQs:',
            map( '  ' . $_->[-1], @$subqueries ),
            ' '
        );
        my $info = join "\n", @tmp_info;
        # Choose
        my $choice = choose(
            [ @pre, $add, $edit, $remove ],
            { %{$sf->{i}{lyt_stmt_v}}, undef => $sf->{i}{back_config}, info => $info }
        );
        my $changed = 0;
        if ( ! defined $choice ) {
            return;
        }
        elsif ( $choice eq $add ) {
            $changed = $sf->__add_subqueries( $subqueries );
        }
        elsif ( $choice eq $edit ) {
            $changed = $sf->__edit_subqueries( $subqueries );
        }
        elsif ( $choice eq $remove ) {
            $changed = $sf->__remove_subqueries( $subqueries );
        }
        if ( $changed ) {
            if ( @$subqueries ) {
                $h_ref->{$driver}{$db} = $subqueries;
            }
            else {
                delete $h_ref->{$driver}{$db};
            }
            $ax->write_json( $sf->{subquery_file}, $h_ref );
        }
    }
}


sub __add_subqueries {
    my ( $sf, $subqueries ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $history = $sf->__stmt_history();
    my $used = [];
    my $readline = '  ReadLine';
    my @pre = ( undef, $sf->{i}{_confirm}, $readline );
    my $bu = [];

    while ( 1 ) {
        my @tmp_info = (
            $sf->{d}{db_string},
            'Saved SQs:',,
            map( '  ' . $_->[-1], @$subqueries ),
            ' '
        );
        my $info = join "\n", @tmp_info;
        my $choices = [ @pre, map { '- ' . $_ } @$history ];
        # Choose
        my $idx = choose(
            $choices,
            { %{$sf->{i}{lyt_3}}, prompt => 'Add:', info => $info, index => 1, undef => $sf->{i}{_back} }
        );
        if ( ! $idx ) {
            if ( @$bu ) {
                ( $subqueries, $history, $used ) = @{pop @$bu};
                next;
            }
            return;
        }
        elsif ( $choices->[$idx] eq $sf->{i}{_confirm} ) {
            return 1;
        }
        elsif ( $choices->[$idx] eq $readline ) {
            my $tf = Term::Form->new();
            my $stmt = $tf->readline( 'Stmt: ', { info => $info, clear_screen => 1  } );
            if ( defined $stmt && length $stmt ) {
                push @$bu, [ [ @$subqueries ], [ @$history ], [ @$used ] ];
                my $folded_stmt = "\n" . line_fold( 'Stmt: ' . $stmt, term_width() - 1, '', ' ' x length( 'Stmt: ' ) ); # -1: rautf
                my $name = $tf->readline( 'Name: ', { info => $info . $folded_stmt } );
                push @$subqueries, [ $stmt, length $name ? $name : () ]; #
            }
        }
        else {
            push @$bu, [ [ @$subqueries ], [ @$history ], [ @$used ] ]; #
            push @$used, splice @$history, $idx-@pre, 1;
            my $stmt = $used->[-1];
            my $folded_stmt = "\n" . line_fold( 'Stmt: ' . $stmt, term_width() - 1, '', ' ' x length( 'Stmt: ' ) ); # -1: rautf
            my $tf = Term::Form->new();
            my $name = $tf->readline( 'Name: ', { info => $info . $folded_stmt } );
            push @$subqueries, [ $stmt, length $name ? $name : () ];
        }
    }
}


sub __edit_subqueries {
    my ( $sf, $subqueries ) = @_;
    if ( ! @$subqueries ) {
        return;
    }
    my $indexes = [];
    my @pre = ( undef, $sf->{i}{_confirm} );
    my $bu = [];
    my $old_idx = 0;
    my @unchanged_subqueries = @$subqueries;

    STMT: while ( 1 ) {
        my @tmp_info = (
            $sf->{d}{db_string},
            'Saved SQs:',
            map( '  ' . $_->[-1], @unchanged_subqueries ),
            ' '
        );
        #my $info = join "\n", @tmp_info;
        my $info = $sf->{d}{db_string};
        my @available;
        for my $i ( 0 .. $#$subqueries ) {
            my $pre = ( any { $i == $_ } @$indexes ) ? '| ' : '- ';
            push @available, $pre . $subqueries->[$i][-1];
        }
        my $choices = [ @pre, @available ];
        $ENV{TC_RESET_AUTO_UP} = 0;
        # Choose
        my $idx = choose(
            $choices,
            { %{$sf->{i}{lyt_3}}, prompt => 'Edit SQs:', info => $info, index => 1, default => $old_idx }
        );
        if ( ! $idx ) {
            if ( @$bu ) {
                ( $subqueries, $indexes ) = @{pop @$bu};
                next STMT;
            }
            return;
        }
        if ( $sf->{o}{G}{menu_memory} ) {
            if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                $old_idx = 0;
                next STMT;
            }
            else {
                $old_idx = $idx;
            }
        }
        delete $ENV{TC_RESET_AUTO_UP};
        if ( $choices->[$idx] eq $sf->{i}{_confirm} ) {
            return 1;
        }
        else {
            $idx -= @pre;
            my @tmp_info = ( $sf->{d}{db_string}, 'Edit SQs:', '  BACK', '  CONFIRM' );
            for my $i ( 0 .. $#$subqueries ) {
                my $pre = '  ';
                if ( $i == $idx ) {
                    $pre = '> ';
                }
                elsif ( any { $i == $_ } @$indexes ) {
                    $pre = '| ';
                }
                push @tmp_info, $pre . $subqueries->[$i][-1];
            }
            push @tmp_info, ' ';
            my $info = join "\n", @tmp_info;
            my $tf = Term::Form->new();
            my $stmt = $tf->readline( 'Stmt: ', { info => $info, clear_screen => 1, default => $subqueries->[$idx][0] } );
            if ( ! defined $stmt || ! length $stmt ) {
                if ( @$bu ) {
                    ( $subqueries, $indexes ) = @{pop @$bu};
                    next STMT; #
                }
                return;
            }
            my $name = $tf->readline( 'Name: ', { info => $info . "\nStmt: $stmt", default => $subqueries->[$idx][1] } );
            {
                no warnings 'uninitialized';
                if ( $stmt ne $subqueries->[$idx][0] || $name ne $subqueries->[$idx][1] ) {
                    push @$bu, [ [ @$subqueries ], [ @$indexes ] ];
                    $subqueries->[$idx] = [ $stmt, length $name ? $name : () ];;
                    push @$indexes, $idx;
                }
            }
        }
    }
}


sub __remove_subqueries {
    my ( $sf, $subqueries ) = @_;
    if ( ! @$subqueries ) {
        return;
    }
    my @tmp_info = ( $sf->{d}{db_string}, 'Remove SQs:' );
    my $info = join "\n", @tmp_info;
    my $prompt = "\n" . 'Choose:';
    my $idx = choose_a_subset(
        [ map { $_->[-1] } @$subqueries ],
        { mouse => $sf->{o}{table}{mouse}, index => 1, fmt_chosen => 1, remove_chosen => 1, prompt => $prompt,
          info => $info, back => '  BACK', confirm => '  CONFRIM', prefix => '- ' }
    );
    if ( ! defined $idx || ! @$idx ) {
        return;
    }
    for my $i ( sort { $b <=> $a } @$idx ) {
        my $ref = splice( @$subqueries, $i, 1 );
    }
    return 1;
}





1;


__END__

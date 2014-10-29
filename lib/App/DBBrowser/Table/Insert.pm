package # hide from PAUSE
App::DBBrowser::Table::Insert;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.045';

use File::Temp qw( tempfile );

use Clone                  qw( clone );
use File::Slurp            qw( read_file );
use List::Util             qw( all );
use Term::Choose           qw();
use Term::Choose::Util     qw( choose_multi );
use Term::ReadLine::Simple qw();
use Text::CSV              qw();

use App::DBBrowser::Util;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __insert_into {
    my ( $self, $sql, $table, $qt_columns, $pr_columns, $backup_sql ) = @_;
    my $util   = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my @cols = ( @$pr_columns );
    $sql->{quote}{insert_into_args} = [];
    $sql->{quote}{chosen_cols}      = [];
    $sql->{print}{chosen_cols}      = [];
    my $sql_type = 'Insert';

    COL_NAMES: while ( 1 ) {
        my @pre = ( $self->{info}{ok} );
        unshift @pre, undef if $self->{opt}{sssc_mode};
        my $choices = [ @pre, @cols ];
        $util->__print_sql_statement( $sql, $table, $sql_type );
        # Choose
        my @idx = $stmt_h->choose(
            $choices,
            { prompt => 'Columns:', index => 1, no_spacebar => [ 0 .. $#pre ] }
        );
        my $c = 0;
        for my $i ( @idx ) {
            last if ! @cols;
            my $ni = $i - ( @pre + $c );
            splice( @cols, $ni, 1 );
            ++$c;
        }
        my @print_col = map { $choices->[$_] } @idx;
        if ( ! defined $print_col[0] ) {
            if ( @{$sql->{quote}{chosen_cols}} ) {
                $sql->{quote}{chosen_cols} = [];
                $sql->{print}{chosen_cols} = [];
                @cols = ( @$pr_columns );
                next COL_NAMES;
            }
            else {
                $sql = clone( $backup_sql );
                return;
            }
        }
        if ( $print_col[0] eq $self->{info}{ok} ) {
            shift @print_col;
            for my $print_col ( @print_col ) {
                push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
                push @{$sql->{print}{chosen_cols}}, $print_col;
            }
            if ( ! @{$sql->{quote}{chosen_cols}} ) {
                @{$sql->{quote}{chosen_cols}} = @{$qt_columns}{@$pr_columns};
                @{$sql->{print}{chosen_cols}} = @$pr_columns;
            }
            last COL_NAMES;
        }
        for my $print_col ( @print_col ) {
            push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
            push @{$sql->{print}{chosen_cols}}, $print_col;
        }
    }
    my $trs = Term::ReadLine::Simple->new();
    my $insert_mode;

    VALUES: while ( 1 ) {
        if ( ! $self->{opt}{insert_mode} ) {
            $util->__print_sql_statement( $sql, $table, $sql_type );
            my $choices = [ undef, 'Cols', 'Rows', 'Multirow', 'File' ];
            # Choose
            $insert_mode = $stmt_h->choose(
                $choices,
                { prompt => 'Input mode: ', index => 1 }
            );
            if ( ! $insert_mode ) {
                $sql = clone( $backup_sql );
                return;
            }
        }
        else {
            $insert_mode = $self->{opt}{insert_mode};
        }
        if ( $insert_mode <= 2 ) {
            my ( $last, $add, $del ) = ( '-OK-', 'Add', 'Del' );
            ROWS: while ( 1 ) {
                if ( $insert_mode == 1 ) {
                    my $row_idx = @{$sql->{quote}{insert_into_args}};
                    COLS: for my $col_name ( @{$sql->{print}{chosen_cols}} ) {
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Readline
                        my $col = $trs->readline( $col_name . ': ' );
                        push @{$sql->{quote}{insert_into_args}->[$row_idx]}, $col; # show $col immediatly in "print_sql_statement"
                    }
                }
                elsif ( $insert_mode == 2 ) {
                    my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Readline
                    my $row = $trs->readline( 'Row: ' );
                    if ( ! defined $row ) {
                        if ( ! @{$sql->{quote}{insert_into_args}} ) {
                            $sql->{quote}{chosen_cols} = [];
                            $sql->{print}{chosen_cols} = [];
                            return;
                        }
                        $#{$sql->{quote}{insert_into_args}}--;
                        next ROWS;
                    }
                    my $status = $csv->parse( $row );
                    push @{$sql->{quote}{insert_into_args}}, [ $csv->fields() ];
                }
                my $choices = [ $last, $add, $del ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                my $default = ( all { ! length } @{$sql->{quote}{insert_into_args}[-1]} ) ? 2 : 1;

                ASK: while ( 1 ) {
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Choose
                    my $add_row = $stmt_h->choose(
                        $choices,
                        { prompt => '', default => $default }
                    );
                    if ( ! defined $add_row ) {
                        $sql->{quote}{insert_into_args} = [];
                        $sql->{quote}{chosen_cols}      = [];
                        $sql->{print}{chosen_cols}      = [];
                        return;
                    }
                    elsif ( $add_row eq $last ) {
                        if ( ! @{$sql->{quote}{insert_into_args}} ) {
                            $sql->{quote}{chosen_cols} = [];
                            $sql->{print}{chosen_cols} = [];
                        }
                        return;
                    }
                    elsif ( $add_row eq $del ) {
                        if ( ! @{$sql->{quote}{insert_into_args}} ) {
                            $sql->{quote}{chosen_cols} = [];
                            $sql->{print}{chosen_cols} = [];
                            return;
                        }
                        $default = 0;
                        $#{$sql->{quote}{insert_into_args}}--; ###
                        next ASK;
                    }
                    last ASK;
                }
            }
        }
        else {
            my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
            my $fh;
            $util->__print_sql_statement( $sql, $table, $sql_type );
            if ( $insert_mode == 3 ) {
                say 'Multirow: ';
                # STDIN
                my $input = read_file( \*STDIN );
                ( $fh ) = tempfile( DIR => $self->{info}{app_dir}, UNLINK => 1 );
                binmode $fh, ':encoding(' . $self->{opt}{encoding_csv_file} . ')';
                print $fh $input;
                seek $fh, 0, 0;
                #$sql->{quote}{insert_into_args} = $csv->getline_all( \*STDIN );
            }
            elsif ( $insert_mode == 4 ) {
                # Readline
                my $file = $trs->readline( 'Path to file: ' );
                return if ! defined $file;
                open $fh, '<:encoding(' . $self->{opt}{encoding_csv_file} . ')', $file or die $!;
                #open my $fh, '<:encoding(' . $self->{opt}{encoding_csv_file} . ')', $file or die $!;
                #$sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
                #close $fh;
            }
            $sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
            if ( ! @{$sql->{quote}{insert_into_args}} ) {
                $sql->{quote}{chosen_cols} = [];
                $sql->{print}{chosen_cols} = [];
                return;
            }
            if ( $self->{opt}{row_col_filter} ) {
                $self->__filter_input( $sql, $table, $sql_type, $fh );
            }
            close $fh;
            return;
        }
    }
}


sub __filter_input {
    my ( $self, $sql, $table, $sql_type, $fh ) = @_;
    my $util = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
    #my $backup = clone $sql->{quote}{insert_into_args};

    FILTER: while ( 1 ) {
        my @pre = ( $self->{info}{ok} );
        unshift @pre, undef if $self->{opt}{sssc_mode};
        my ( $input_cols, $input_rows_range, $input_rows_choose, $reset ) = ( 'Columns', 'Rows-range', 'Rows-choose', 'Reset' );
        my $choices = [ @pre, $input_cols, $input_rows_range, $input_rows_choose, $reset ];
        $util->__print_sql_statement( $sql, $table, $sql_type );
        # Choose
        my $choice = $stmt_h->choose(
            $choices,
            { prompt => 'Filter:' }
        );
        if ( ! defined $choice ) {
            $sql->{quote}{insert_into_args} = [];
            $sql->{quote}{chosen_cols}      = [];
            $sql->{print}{chosen_cols}      = [];
            return;
        }
        elsif ( $choice eq $reset ) {
            seek $fh, 0, 0;
            $sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
            #$sql->{quote}{insert_into_args} = clone $backup;
        }
        elsif ( $choice eq $self->{info}{ok} ) {
            return;
        }
        elsif ( $choice eq $input_cols  ) {
            my @col_idx = ();

            COLS: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, map { "col_$_" } 0 .. $#{$sql->{quote}{insert_into_args}[0]} ];
                my $prompt = 'Cols: ';
                $prompt .= join ',', @col_idx if @col_idx;
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                my @col_nr = $stmt_h->choose(
                    $choices,
                    { prompt => $prompt, no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! defined $col_nr[0] ) {
                    if ( @col_idx ) {
                        @col_idx = ();
                        next COLS;
                    }
                    else {
                        next FILTER;
                    }
                }
                if ( $col_nr[0] eq $self->{info}{ok} ) {
                    shift @col_nr;
                    for my $col ( @col_nr ) {
                        $col =~ s/^col_//;
                        push @col_idx, $col;
                    }
                    if ( @col_idx ) {
                        my $tmp = [];
                        for my $row ( @{$sql->{quote}{insert_into_args}} ) {
                            push @$tmp, [ @{$row}[@col_idx] ];
                        }
                        $sql->{quote}{insert_into_args} = $tmp;
                    }
                    next FILTER;
                }
                for my $col ( @col_nr ) {
                    $col =~ s/^col_//;
                    push @col_idx, $col;
                }
            }
        }
        elsif ( $choice eq $input_rows_range ) {
            my @pre = ();
            unshift @pre, undef if $self->{opt}{sssc_mode};
            my $choices = [ @pre, map { "@$_" } @{$sql->{quote}{insert_into_args}} ];
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Choose
            my $first_row = $stmt_h->choose(
                $choices,
                { prompt => "First row:\n\n", layout => 3, index => 1 }
            );
            next FILTER if ! defined $first_row;
            $first_row -= @pre;
            next FILTER if $first_row < 0;
            $choices->[$first_row + @pre] = '* ' . $choices->[$first_row + @pre];
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Choose
            my $last_row = $stmt_h->choose(
                $choices,
                { prompt => "Last row:\n\n", default => $first_row, layout => 3, index => 1 }
            );
            next FILTER if ! defined $last_row;
            $last_row -= @pre;
            next FILTER if $last_row < 0;
            if ( $last_row < $first_row ) {
                $util->__print_sql_statement( $sql, $table, $sql_type );
                # Choose
                $stmt_h->choose(
                    [ "Last row ($last_row) is less than First row ($first_row)" ],
                    { %{$self->{info}{lyt_stop}}, prompt => '' }
                );
                next FILTER;
            }
            $sql->{quote}{insert_into_args} = [ @{$sql->{quote}{insert_into_args}}[$first_row .. $last_row] ];
            next FILTER;
        }
        elsif ( $choice eq $input_rows_choose ) {
            my @pre = ();
            unshift @pre, undef if $self->{opt}{sssc_mode};
            #my $choices = [ @pre, map { "@$_" } @{$sql->{quote}{insert_into_args}} ];
            my $choices = [ @pre, map { join ',', @$_ } @{$sql->{quote}{insert_into_args}} ];
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Choose
            my @row_idx = $stmt_h->choose(
                $choices,
                { prompt => 'Choose rows:', layout => 3, justify => 0, index => 1, no_spacebar => [ 0 .. $#pre ] }
            );
            next FILTER if ! defined $row_idx[0];
            $sql->{quote}{insert_into_args} = [ @{$sql->{quote}{insert_into_args}}[@row_idx] ];
            next FILTER;
        }
    }
}




1;


__END__

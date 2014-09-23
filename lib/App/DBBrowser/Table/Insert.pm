package # hide from PAUSE
App::DBBrowser::Table::Insert;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.040_04';

use File::Temp qw( tempfile );

use Clone                  qw( clone );
use File::Slurp            qw( read_file );
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

    COLUMNS: while ( 1 ) {
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
                next COLUMNS;
            }
            else {
                $sql = clone( $backup_sql );
                return $sql;
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
            last COLUMNS;
        }
        for my $print_col ( @print_col ) {
            push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
            push @{$sql->{print}{chosen_cols}}, $print_col;
        }
    }
    my $trs = Term::ReadLine::Simple->new();
    my $insert_mode;

    INSERT: while ( 1 ) {
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
                return $sql;
            }
        }
        else {
            $insert_mode = $self->{opt}{insert_mode};
        }
        if ( $insert_mode <= 2 ) {
            my ( $last, $add ) = ( 'Last', 'Add' );
            ROWS: while ( 1 ) {
                my $row_idx = @{$sql->{quote}{insert_into_args}};
                if ( $insert_mode == 1 ) {
                    COLS: for my $col ( @{$sql->{print}{chosen_cols}} ) {
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Readline
                        my $value = $trs->readline( $col . ': ' );
                        if ( ! defined $value ) {
                            if ( $row_idx > 0 ) {
                                $#{$sql->{quote}{insert_into_args}}--;
                            }
                            else {
                                next INSERT if ! defined $sql->{quote}{insert_into_args}[0][0];
                                $sql->{quote}{insert_into_args} = [];
                            }
                            last COLS;
                        }
                        push @{$sql->{quote}{insert_into_args}->[$row_idx]}, $value;
                    }
                }
                elsif ( $insert_mode == 2 ) {
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
                    # Readline
                    my $row = $trs->readline( 'Row: ' );
                    if ( ! defined $row ) {
                            if ( $row_idx > 0 ) {
                                $#{$sql->{quote}{insert_into_args}}--;
                            }
                            else {
                                $sql->{quote}{insert_into_args} = [];
                            }
                            next ROWS;
                    }
                    my $status = $csv->parse( $row );
                    push @{$sql->{quote}{insert_into_args}}, [ $csv->fields() ];
                }
                $util->__print_sql_statement( $sql, $table, $sql_type );
                my $choices = [ $last, $add ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                # Choose
                my $add_row = $stmt_h->choose(
                    $choices,
                    { prompt => '' }
                );
                if ( ! defined $add_row ) {
                    $sql->{quote}{insert_into_args} = [];
                    next INSERT;
                }
                elsif ( $add_row eq $last ) {
                    last INSERT;
                }
            }
        }
        else {
            my $row_idx = @{$sql->{quote}{insert_into_args}};
            my $fh;
            $util->__print_sql_statement( $sql, $table, $sql_type );
            my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
            if ( $insert_mode == 3 ) {
                say 'Multirow: ';
                # STDIN
                my $input = read_file( \*STDIN );
                ( $fh ) = tempfile( DIR => $self->{info}{app_dir}, UNLINK => 1 );
                binmode $fh, ':encoding(' . $self->{opt}{encoding_csv_file} . ')';
                print $fh $input;
                seek $fh, 0 , 0;
                #$sql->{quote}{insert_into_args} = $csv->getline_all( \*STDIN );
            }
            elsif ( $insert_mode == 4 ) {
                # Readline
                my $file = $trs->readline( 'Path to file: ' );
                open $fh, '<:encoding(' . $self->{opt}{encoding_csv_file} . ')', $file or die $!;
                #open my $fh, '<:encoding(' . $self->{opt}{encoding_csv_file} . ')', $file or die $!;
                #$sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
                #close $fh;
            }
            $sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
            if ( $self->{opt}{row_col_filter} ) {
                $self->__filter_input( $sql, $table, $sql_type, $fh );
            }
            close $fh;
            last INSERT;
        }
    }
    return $sql;
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
        my ( $input_cols, $input_rows, $reset ) = ( 'Columns', 'Rows', 'Reset' );
        my $choices = [ @pre, $input_cols, $input_rows, $reset ];
        $util->__print_sql_statement( $sql, $table, $sql_type );
        # Choose
        my $choice = $stmt_h->choose(
            $choices,
            { prompt => 'Filter:' }
        );
        if ( ! defined $choice ) {
            seek $fh, 0 , 0;
            $sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
            #$sql->{quote}{insert_into_args} = clone $backup;
            return;
        }
        elsif ( $choice eq $reset ) {
            seek $fh, 0 , 0;
            $sql->{quote}{insert_into_args} = $csv->getline_all( $fh );
            #$sql->{quote}{insert_into_args} = clone $backup;
        }
        elsif ( $choice eq $self->{info}{ok} ) {
            return;
        }
        elsif ( $choice eq $input_cols  ) {
            my $aoa = $sql->{quote}{insert_into_args};
            my $cols = [ 0 .. $#{$aoa->[0]} ];
            my @col_idx = ();

            COLS: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, map { "col_$_" } @$cols ];
                $util->__print_sql_statement( $sql, $table, $sql_type );
                my $prompt = 'Cols: ';
                $prompt .= join ',', @col_idx if @col_idx;
                # Choose
                my @choices = $stmt_h->choose(
                    $choices,
                    { prompt => $prompt, no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! defined $choices[0] ) {
                    if ( @col_idx ) {
                        @col_idx = ();
                        next COLS;
                    }
                    else {
                        next FILTER;
                    }
                }
                if ( $choices[0] eq $self->{info}{ok} ) {
                    shift @choices;
                    if ( @$choices ) {
                        for my $col ( @choices ) {
                            $col =~ s/^col_//;
                            push @col_idx, $col;
                        }
                        my $tmp = [];
                        for my $row ( @$aoa ) {
                            push @$tmp, [ @{$row}[@col_idx] ];
                        }
                        $sql->{quote}{insert_into_args} = $tmp;
                    }
                    next FILTER;
                }
                for my $col ( @choices ) {
                    $col =~ s/^col_//;
                    push @col_idx, $col;
                }
            }
        }
        elsif ( $choice eq $input_rows ) {
            my $aoa = $sql->{quote}{insert_into_args};
            my $rows = [ 0 .. $#{$aoa} ];
            my @pre = ();
            unshift @pre, undef if $self->{opt}{sssc_mode};
            my $choices = [ @pre, map { "@$_" } @{$aoa}[@$rows] ];
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
                $stmt_h->choose(
                    [ "Last row ($last_row) is less than First row ($first_row)" ],
                    { %{$self->{info}{lyt_stop}}, prompt => '' }
                );
                next FILTER;
            }
            $util->__print_sql_statement( $sql, $table, $sql_type );
            my $prompt = sprintf "First row: %*d\n", length $last_row, $first_row;
            $prompt .= sprintf "Last  row: %*d\n\n", length $last_row, $last_row;
            ## Choose
            #my $confirm = $stmt_h->choose(
            #    [ undef, $self->{info}{confirm} ],
            #    { prompt => $prompt, undef => $self->{info}{back} }
            #);
            #next FILTER if ! defined $confirm;
            $sql->{quote}{insert_into_args} = [ @{$aoa}[$first_row .. $last_row] ];
            next FILTER;
        }
    }
}




1;


__END__

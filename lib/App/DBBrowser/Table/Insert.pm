package # hide from PAUSE
App::DBBrowser::Table::Insert;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.049_05';

use Cwd        qw( realpath );
use Encode     qw( encode decode );
use File::Temp qw( tempfile );
use List::Util qw( all );

#use Clone                  qw( clone );
use File::Slurp            qw( read_file );
use List::MoreUtils        qw( first_index );
use Encode::Locale         qw();
#use Spreadsheet::Read      qw( ReadData rows ); # "require"d
use Term::Choose           qw();
use Term::Choose::Util     qw( choose_multi );
use Term::ReadLine::Simple qw();
use Text::CSV              qw();
use Text::ParseWords       qw( parse_line );

use App::DBBrowser::Util;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __insert_into {
    my ( $self, $sql, $table, $qt_columns, $pr_columns ) = @_;
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
            if ( ! @{$sql->{quote}{chosen_cols}} ) {
                return;
            }
            $sql->{quote}{chosen_cols} = [];
            $sql->{print}{chosen_cols} = [];
            @cols = ( @$pr_columns );
            next COL_NAMES;
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

    VALUES: while ( 1 ) {
        my $input_mode;
        if ( @{$self->{opt}{input_modes}} == 1 ) {
            $input_mode = $self->{opt}{input_modes}[0];
        }
        else {
            $util->__print_sql_statement( $sql, $table, $sql_type );
            # Choose
            $input_mode = $stmt_h->choose(
                [ undef, @{$self->{opt}{input_modes}} ],
                { prompt => 'Input mode: ' }
            );
            if ( ! defined $input_mode ) {
                $sql->{quote}{chosen_cols} = [];
                $sql->{print}{chosen_cols} = [];
                return;
            }
        }
        if ( $input_mode =~ /^(?:Cols|Rows)\z/ ) {
            my ( $last, $add, $del ) = ( '-OK-', 'Add', 'Del' );
            ROWS: while ( 1 ) {
                if ( $input_mode eq 'Cols' ) {
                    my $input_row_idx = @{$sql->{quote}{insert_into_args}};
                    COLS: for my $col_name ( @{$sql->{print}{chosen_cols}} ) {
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Readline
                        my $col = $trs->readline( $col_name . ': ' );
                        push @{$sql->{quote}{insert_into_args}->[$input_row_idx]}, $col; # show $col immediately in "print_sql_statement"
                    }
                }
                elsif ( $input_mode eq 'Rows' ) {
                    my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
                    $util->__print_sql_statement( $sql, $table, $sql_type );
                    # Readline
                    my $row = $trs->readline( 'Row: ' );
                    if ( ! defined $row ) {
                        next VALUES if ! @{$sql->{quote}{insert_into_args}};
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
                        next VALUES;
                    }
                    elsif ( $add_row eq $last ) {
                        if ( ! @{$sql->{quote}{insert_into_args}} ) {
                            $sql->{quote}{chosen_cols} = [];
                            $sql->{print}{chosen_cols} = [];
                        }
                        return;
                    }
                    elsif ( $add_row eq $del ) {
                        next VALUES if ! @{$sql->{quote}{insert_into_args}};
                        $default = 0;
                        $#{$sql->{quote}{insert_into_args}}--;
                        next ASK;
                    }
                    last ASK;
                }
            }
        }
        else {
            my ( $file, $sheet_idx );
            if ( $input_mode eq 'Multirow' ) {
                $util->__print_sql_statement( $sql, $table, $sql_type );
                print 'Multirow: ' . "\n";
                # STDIN
                my $input = read_file( \*STDIN );
                ( my $fh, $file ) = tempfile( DIR => $self->{info}{app_dir}, UNLINK => 1 , SUFFIX => '.csv' );
                binmode $fh, ':encoding(' . $self->{opt}{encoding_csv_file} . ')';
                print $fh $input;
                seek $fh, 0, 0;
                if ( $self->{opt}{csv_read} < 2 ) {
                    $file = $fh;
                }
                ( $sql->{quote}{insert_into_args}, $sheet_idx ) = $self->__parse_file( $file );
                if ( ! @{$sql->{quote}{insert_into_args}} ) {
                    my $cm = Term::Choose->new( { prompt => 'Press ENTER' } );
                    $cm->choose( [ 'empty sheet!' ] );
                    if ( @{$self->{opt}{input_modes}} == 1 ) {
                        $sql->{quote}{chosen_cols} = [];
                        $sql->{print}{chosen_cols} = [];
                        return;
                    }
                    next VALUES;
                }
                if ( $self->{opt}{row_col_filter} ) {
                    $self->__filter_input( $sql, $table, $sql_type, $file, $sheet_idx );
                    if ( ! @{$sql->{quote}{insert_into_args}} ) {
                        if ( @{$self->{opt}{input_modes}} == 1 ) {
                            $sql->{quote}{chosen_cols} = [];
                            $sql->{print}{chosen_cols} = [];
                            return;
                        }
                        next VALUES;
                    }
                }
            }
            elsif ( $input_mode eq 'File' ) {
                FILE: while ( 1 ) {
                    my @files = ();
                    if ( $self->{opt}{max_files} && -e $self->{info}{input_files} ) {
                        open my $fh_in, '<', $self->{info}{input_files} or die $!;
                        while ( my $f = <$fh_in> ) {
                            chomp $f;
                            next if ! -e $f;
                            push @files, $f;
                        }
                        close $fh_in;
                    }
                    ###
                    my @files_sorted = sort map { decode 'locale_fs', $_ } @files;
                    if ( length $file ) {
                        my $i = first_index { decode( 'locale_fs', $file ) eq $_ } @files_sorted;
                        if ( $i > -1  ) {
                            splice @files_sorted, $i, 1;
                        }
                        unshift @files_sorted, decode 'locale_fs', $file;
                    }
                    ###
                    my $add_file = 'New file';
                    if ( @files_sorted ) {
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Choose
                        $file = $stmt_h->choose(
                            [ undef, '  ' . $add_file, map( "- $_", @files_sorted ) ],
                            { %{$self->{info}{lyt_stmt_v}} }
                        );
                        if ( ! defined $file ) {
                            if ( @{$self->{opt}{input_modes}} == 1 ) {
                                $sql->{quote}{chosen_cols} = [];
                                $sql->{print}{chosen_cols} = [];
                                return;
                            }
                            next VALUES;
                        }
                        $file =~ s/^.\s//;
                    }
                    if ( ! defined $file || $file eq $add_file ) {
                        $util->__print_sql_statement( $sql, $table, $sql_type );
                        # Readline
                        $file = $trs->readline( 'Path to file: ' );
                        if ( ! defined $file || ! length $file ) {
                            if ( @{$self->{opt}{input_modes}} == 1 ) {
                                $sql->{quote}{chosen_cols} = [];
                                $sql->{print}{chosen_cols} = [];
                                return;
                            }
                            next VALUES;
                        }
                        $file = realpath encode 'locale_fs', $file;
                        if ( $self->{opt}{max_files} ) {
                            my $i = first_index { $file eq $_ } @files;
                            if ( $i > -1  ) {
                                splice @files, $i, 1;
                            }
                            push @files, $file;
                            while ( @files > $self->{opt}{max_files} ) {
                                shift @files;
                            }
                            open my $fh_out, '>', $self->{info}{input_files} or die $!;
                            for my $f ( @files ) {
                                print $fh_out $f . "\n";
                            }
                            close $fh_out;
                        }
                    }
                    else {
                        $file = realpath encode 'locale_fs', $file;
                    }
                    if ( $self->{opt}{csv_read} < 2 && -T $file ) {
                        open my $fh, '<:encoding(' . $self->{opt}{encoding_csv_file} . ')', $file or die $!;
                        $file = $fh;
                    }
                    ( $sql->{quote}{insert_into_args}, $sheet_idx ) = $self->__parse_file( $file );
                    if ( ! defined $sql->{quote}{insert_into_args} ) {
                        $sql->{quote}{insert_into_args} = [];
                        next FILE;
                    }
                    if ( ! @{$sql->{quote}{insert_into_args}} ) {
                        my $cm = Term::Choose->new( { %{$self->{info}{lyt_stop}}, prompt => 'Press ENTER' } );
                        $cm->choose( [ 'empty file!' ] );
                        next FILE;
                    }
                    if ( $self->{opt}{row_col_filter} ) {
                        $self->__filter_input( $sql, $table, $sql_type, $file, $sheet_idx );
                        if ( ! @{$sql->{quote}{insert_into_args}} ) {
                            next FILE;
                        }
                    }
                    last FILE;
                }
            }
            close $file if ref $file eq 'GLOB';
            return;
        }
    }
}


sub __parse_file {
    my ( $self, $file, $sheet_idx ) = @_;
    if ( ref $file eq 'GLOB' ) {
        seek $file, 0, 0;
        my $tmp = [];
        if ( $self->{opt}{csv_read} == 0 ) {
            my $csv = Text::CSV->new( { map { $_ => $self->{opt}{$_} } @{$self->{info}{csv_opt}} } );
            while ( my $row = $csv->getline( $file ) ) {
                push @$tmp, $row;
            }
        }
        else {
            while ( my $row = <$file> ) {
                chomp $row;
                push @$tmp, [ parse_line( $self->{opt}{delim}, $self->{opt}{keep}, $row ) ];
                #push @$tmp, [ split $self->{opt}{delim}, $row ];
            }
        }
        return $tmp;
    }
    else {
        my $cm = Term::Choose->new( { %{$self->{info}{lyt_stop}}, prompt => 'Press ENTER' } );
        my $file_dc = decode( 'locale_fs', $file );
        if ( ! -e $file ) {
            $cm->choose( [ $file_dc . ' : file not found!' ] );
            return;
        }
        if ( ! -s $file ) {
            $cm->choose( [ $file_dc . ' : file is empty!' ] );
            return;
        }
        if ( ! -r $file ) {
            $cm->choose( [ $file_dc . ' : file is not readable!' ] );
            return;
        }
        require Spreadsheet::Read;
        my $book = Spreadsheet::Read::ReadData( $file, cells => 0, attr => 0, rc => 1, strip => 0 );
        if ( ! defined $book ) {
            $cm->choose( [ $file_dc . ' : no book!' ] );
            return;
        }
        if ( $sheet_idx ) {
            return [ Spreadsheet::Read::rows( $book->[$sheet_idx] ) ], $sheet_idx;
        }
        if ( @$book < 2 ) {
            $cm->choose( [ $file_dc . ' : no sheets!' ] );
            return;
        }
        elsif ( @$book == 2 ) { # first sheet in $book contains meta info
            $sheet_idx = 1;
        }
        else {
            my @sheets = map { '- ' . ( length $book->[$_]{label} ? $book->[$_]{label} : 'sheet_' . $_ ) } 1 .. $#$book;
            my $c_sheet = Term::Choose->new();
            # Choose
            $sheet_idx = $c_sheet->choose(
                [ undef, @sheets ],
                { %{$self->{info}{lyt_stmt_v}}, index => 1, prompt => 'Choose a sheet' }
            );
            return if ! defined $sheet_idx;
            return if $sheet_idx == 0;

        }
        if ( $book->[$sheet_idx]{maxrow} == 0 ) {
            my $cm = Term::Choose->new( { %{$self->{info}{lyt_stop}}, prompt => 'Press ENTER' } );
            my $sheet = length $book->[$sheet_idx]{label} ? $book->[$sheet_idx]{label} : 'sheet_' . $_;
            $cm->choose( [ $sheet . ': empty sheet!' ] );
            return;
        }
        return [ Spreadsheet::Read::rows( $book->[$sheet_idx] ) ], $sheet_idx;
    }
}


sub __filter_input {
    my ( $self, $sql, $table, $sql_type, $file, $sheet_idx ) = @_;
    my $util = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    #my $backup = clone $sql->{quote}{insert_into_args};

    FILTER: while ( 1 ) {
        my @pre = ( undef, $self->{info}{ok} );
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
            return;
        }
        elsif ( $choice eq $reset ) {
            ( $sql->{quote}{insert_into_args} ) = $self->__parse_file( $file, $sheet_idx );
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
                my $choices = [ @pre, map { "col_$_" } 1 .. @{$sql->{quote}{insert_into_args}[0]} ];
                my $prompt = 'Cols: ';
                $prompt .= join ',', map { $_ + 1 } @col_idx if @col_idx;
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
                        push @col_idx, $col - 1;
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
                    push @col_idx, $col - 1;
                }
            }
        }
        elsif ( $choice eq $input_rows_range ) {
            my @pre = ();
            unshift @pre, undef if $self->{opt}{sssc_mode};
            #my $choices = [ @pre, map { "@$_" } @{$sql->{quote}{insert_into_args}} ];
            my $choices = [ @pre, map { join ',', @$_ } @{$sql->{quote}{insert_into_args}} ];
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
                    [ "Last row [$last_row] is less than First row [$first_row]!" ],
                    { %{$self->{info}{lyt_stop}}, prompt => 'Press ENTER' }
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

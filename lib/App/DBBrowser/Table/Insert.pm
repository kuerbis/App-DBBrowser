package # hide from PAUSE
App::DBBrowser::Table::Insert;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_05';

use Cwd        qw( realpath );
use Encode     qw( encode decode );
use File::Temp qw( tempfile );
use List::Util qw( all );

use List::MoreUtils   qw( first_index any );
use Encode::Locale    qw();
#use Spreadsheet::Read qw( ReadData rows ); # "require"d
use Text::CSV         qw();

use Term::Choose       qw( choose );
use Term::Choose::Util qw( choose_a_file choose_a_subset );#
use Term::Form         qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Opt;
use App::DBBrowser::Table;


sub new {
    my ( $class, $info, $opt ) = @_;
    bless { i => $info, o => $opt }, $class;
}


sub __insert_into_cols {
    my ( $sf, $sql, $stmt_typeS ) = @_;
    my $ax  = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    $sql->{insert_into_cols} = [];
    my @cols = ( @{$sql->{cols}} );

    COL_NAMES: while ( 1 ) {
        my @pre = ( undef, $sf->{i}{ok} );
        my $choices = [ @pre, @cols ];
        $ax->print_sql( $sql, $stmt_typeS );
        # Choose
        my @idx = choose(
            $choices,
            { %{$sf->{i}{lyt_stmt_h}}, prompt => 'Columns:', index => 1, no_spacebar => [ 0 .. $#pre ] }
        );
        if ( ! defined $idx[0] || ! defined $choices->[$idx[0]] ) {
            return if ! @{$sql->{insert_into_cols}};
            $sql->{insert_into_cols} = [];
            @cols = ( @{$sql->{cols}} );
            next COL_NAMES;
        }
        my $c = 0;
        for my $i ( @idx ) {
            last if ! @cols;
            my $ni = $i - ( @pre + $c );
            splice( @cols, $ni, 1 );
            ++$c;
        }
        my @chosen = map { $choices->[$_] } @idx;
        if ( $chosen[0] eq $sf->{i}{ok} ) {
            shift @chosen;
            for my $col ( @chosen ) {
                push @{$sql->{insert_into_cols}}, $col;
            }
            if ( ! @{$sql->{insert_into_cols}} ) {
                @{$sql->{insert_into_cols}} = @{$sql->{cols}};
            }
            last COL_NAMES;
        }
        for my $col ( @chosen ) {
            push @{$sql->{insert_into_cols}}, $col;
        }
    }
    return 1;
}


sub build_insert_stmt {
    my ( $sf, $sql, $stmt_typeS, $dbh ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    $ax->reset_sql( $sql );
    my @cu_keys = ( qw/insert_col insert_copy insert_file settings/ );
    my %cu = (
        insert_col  => '- plain',
        insert_copy => '- copy',
        insert_file => '- file',
        settings    => '  Settings'
    );
    my $old_idx = 0;

    MENU: while ( 1 ) {
        my $choices = [ undef, @cu{@cu_keys} ];
        # Choose
        $ENV{TC_RESET_AUTO_UP} = 0;
        my $idx = choose(
            $choices,
            { %{$sf->{i}{lyt_3}}, index => 1, default => $old_idx, prompt => 'Choose:' }
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
            else {
                $old_idx = $idx;
            }
        }
        delete $ENV{TC_RESET_AUTO_UP};
        if ( $custom eq $cu{settings} ) {
            my $obj_opt = App::DBBrowser::Opt->new( $sf->{i}, $sf->{o} );
            $obj_opt->config_insert;
            next MENU;
        }
        my $cols_ok = $sf->__insert_into_cols( $sql, $stmt_typeS );
        if ( ! $cols_ok ) {
            next MENU;
        }
        my $insert_ok;
        if ( $custom eq $cu{insert_col} ) {
            $insert_ok = $sf->__from_col_by_col( $sql, $stmt_typeS );
        }
        elsif ( $custom eq $cu{insert_copy} ) {
            $insert_ok = $sf->from_copy_and_paste( $sql, $stmt_typeS );
        }
        elsif ( $custom eq $cu{insert_file} ) {
            $insert_ok = $sf->from_file( $sql, $stmt_typeS );
        }
        if ( ! $insert_ok ) {
            next MENU;
        }
        return 1
    }
}


sub __from_col_by_col {
    my ( $sf, $sql, $stmt_typeS ) = @_;
    my $ax  = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    $sql->{insert_into_args} = [];
    my $trs = Term::Form->new();

    ROWS: while ( 1 ) {
        my $row_idx = @{$sql->{insert_into_args}};

        COLS: for my $col_name ( @{$sql->{insert_into_cols}} ) {
            $ax->print_sql( $sql, $stmt_typeS );
            # Readline
            my $col = $trs->readline( $col_name . ': ' );
            # push $col to show $col immediately in "print_sql"
            push @{$sql->{insert_into_args}->[$row_idx]}, $col;
        }
        my $default = ( all { ! length } @{$sql->{insert_into_args}[-1]} ) ? 3 : 2;

        ASK: while ( 1 ) {
            my ( $add, $del ) = ( 'Add', 'Del' );
            my @pre = ( undef, $sf->{i}{ok} );
            my $choices = [ @pre, $add, $del ];
            $ax->print_sql( $sql, $stmt_typeS );
            # Choose
            my $add_row = choose(
                $choices,
                { %{$sf->{i}{lyt_stmt_h}}, prompt => '', default => $default }
            );
            if ( ! defined $add_row ) {
                if ( @{$sql->{insert_into_args}} ) {
                    $sql->{insert_into_args} = [];
                    next ASK;
                }
                $sql->{insert_into_cols} = [];
                $sql->{insert_into_args} = [];
                return;
            }
            elsif ( $add_row eq $sf->{i}{ok} ) {
                if ( ! @{$sql->{insert_into_args}} ) {
                    $sql->{insert_into_cols} = [];
                    return;
                }
                return 1;
            }
            elsif ( $add_row eq $del ) {
                return if ! @{$sql->{insert_into_args}};
                $default = 0;
                $#{$sql->{insert_into_args}}--;
                next ASK;
            }
            last ASK;
        }
    }
    return 1;
}


sub __parse_setting {
    my ( $sf ) = @_;
    my $i = $sf->{o}{insert}{copy_parse_mode};
    my $parse_mode = ( 'Text::CSV', 'split', 'Spreadsheet::Read' )[$i]; #
    my $sep;
    if ( $i == 0 ) {
        $sep = $sf->{o}{csv}{sep_char};
    }
    elsif ( $i == 1 ) {
        $sep =  $sf->{o}{split}{i_f_s};
    }
    return $parse_mode, $sep;
}


sub from_copy_and_paste {
    my ( $sf, $sql, $stmt_typeS ) = @_;
    $sql->{insert_into_args} = [];
    my ( $fh, $file ) = tempfile( DIR => $sf->{i}{app_dir}, UNLINK => 1 , SUFFIX => '.csv' );
    binmode $fh, ':encoding(' . $sf->{o}{insert}{file_encoding} . ')' or die $!;
    print $sf->{i}{clear_screen};
    # STDIN
    my $prompt = sprintf "Mulit row  (%s sep %s):\n", $sf->__parse_setting;
    print $prompt;
    while ( my $row = <STDIN> ) {
        print $fh $row;
    }
    seek $fh, 0, 0;
    $sf->{i}{input_mode} = 'copy';
    $sf->__input_filter( $sql, $stmt_typeS, $fh, 'copy' );
    if ( ! @{$sql->{insert_into_args}} ) {
        $sql->{insert_into_cols} = [];
        return; ###
    }
    return 1;
}


sub from_file {
    my ( $sf, $sql, $stmt_typeS ) = @_;
    $sql->{insert_into_args} = []; # data
    my ( $file );

    FILE: while ( 1 ) {
        $file = $sf->__file_name( $sql, $file );
        return if ! defined $file;
        if ( $sf->{o}{insert}{parse_mode} < 2 && -T $file ) {
            open my $fh, '<:encoding(' . $sf->{o}{insert}{file_encoding} . ')', $file or die $!;
            if ( -z $file ) {
                choose( [ 'empty file!' ], { %{$sf->{i}{lyt_m}}, prompt => 'Press ENTER' } );
                close $fh;
                next FILE;
            }
            $sf->__input_filter( $sql, $stmt_typeS, $fh, 'file' );
            close $fh;
        }
        else {
            $sf->__input_filter( $sql, $stmt_typeS, $file, 'file' );
        }
        next FILE if ! @{$sql->{insert_into_args}}; #
        return 1;
    }
}


sub __file_name { # h?
    my ( $sf, $sql, $file ) = @_;
    my @files;
    if ( $sf->{o}{insert}{max_files} && -e $sf->{i}{input_files} ) {
        open my $fh_in, '<:encoding(locale_fs)', $sf->{i}{input_files} or die $!; #
        while ( my $fl = <$fh_in> ) {
            chomp $fl;
            next if ! -e $fl;
            push @files, $fl;
        }
        close $fh_in;
    }
# while ( 1 ) {
    my @files_sorted = sort map { decode 'locale_fs', $_ } @files;
    if ( length $file ) {
        my $i = first_index { decode( 'locale_fs', $file ) eq $_ } @files_sorted;
        splice @files_sorted, $i, 1 if $i > -1;
        unshift @files_sorted, decode 'locale_fs', $file;
    }
    my $add_file = 'New file';
    if ( @files_sorted ) {
        my $prompt = sprintf "Choose a file (%s, %s):", $sf->__parse_setting;
        # Choose
        $file = choose(
            [ undef, $add_file, @files_sorted ],
            { %{$sf->{i}{lyt_stmt_v}}, clear_screen => 1, prompt => $prompt, undef => $sf->{i}{back} }
        );
        if ( ! defined $file ) {
            if ( @{$sf->{o}{insert}{input_modes}} == 1 ) {
                $sql->{insert_into_cols} = [];
            }
            return;
        }
    }
    if ( ! defined $file || $file eq $add_file ) {
            my $prompt = sprintf "%s, %s", $sf->__parse_setting;
        # Choose_a_file
        $file = choose_a_file( { dir => $sf->{o}{insert}{files_dir}, mouse => $sf->{o}{table}{mouse} } );
        if ( ! defined $file || ! length $file ) {
            if ( @{$sf->{o}{insert}{input_modes}} == 1 ) {
                $sql->{insert_into_cols} = [];
            }
            return;
        }
        $file = realpath encode 'locale_fs', $file;
        if ( $sf->{o}{insert}{max_files} ) {
            my $i = first_index { $file eq $_ } @files;
            splice @files, $i, 1 if $i > -1;
            push @files, $file;
            while ( @files > $sf->{o}{insert}{max_files} ) {
                shift @files;
            }
            open my $fh_out, '>:encoding(locale_fs)', $sf->{i}{input_files} or die $!; # '>:encoding(locale_fs)'
            for my $fl ( @files ) {
                print $fh_out $fl . "\n";
            }
            close $fh_out;
        }
    }
# }
    else {
        $file = realpath encode 'locale_fs', $file;
    }
    return $file;
}


sub __input_filter {
    my ( $sf, $sql, $stmt_typeS, $file_or_fh, $input_type ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );

    SHEET: while ( 1 ) {
        my ( $sheet_count, $sheet_idx ) = $sf->__parse_file( $sql, $stmt_typeS, $file_or_fh, $input_type );
        last SHEET if ! @{$sql->{insert_into_args}};
        my $stmt_h = Term::Choose->new( $sf->{i}{lyt_stmt_h} );
        my $r2c = 0;

        FILTER: while ( 1 ) {
            my @pre = ( undef, $sf->{i}{ok} );
            my $input_cols       = 'Choose Columns';
            my $input_rows       = 'Choose Rows';
            my $input_rows_range = 'Choose Row-range';
            my $cols_to_rows     = $r2c ? 'Cols_to_Rows' : 'Rows_to_Cols';
            my $reset            = 'Reset';
            my $choices = [ @pre, $input_cols, $input_rows, $input_rows_range, $cols_to_rows, $reset ];
            $ax->print_sql( $sql, $stmt_typeS );
            # Choose
            my $filter = $stmt_h->choose(
                $choices,
                { prompt => 'Filter:' }
            );
            if ( ! defined $filter ) {
                $sql->{insert_into_args} = [];
                last SHEET if ! $sheet_count || $sheet_count < 2;
                next SHEET;
            }
            elsif ( $filter eq $reset ) {
                $sf->__parse_file( $sql, $stmt_typeS, $file_or_fh, $input_type, $sheet_idx );
                $r2c = 0;
                next FILTER
            }
            elsif ( $filter eq $sf->{i}{ok} ) {
                last SHEET;
            }
            elsif ( $filter eq $input_cols  ) {
                my $aoa = $sql->{insert_into_args};
                my @empty = ( 0 ) x @{$aoa->[0]};
                COL: for my $c ( 0 .. $#{$aoa->[0]} ) {
                    for my $r ( 0 .. $#$aoa ) {
                        next COL if length $aoa->[$r][$c];
                        $empty[$c]++;
                    }
                }
                my $mark = [ grep { $empty[$_] < @$aoa } 0 .. $#empty ];
                $mark = undef if scalar( @$mark ) == scalar( @{$aoa->[0]} );
                $ax->print_sql( $sql, $stmt_typeS );
                my $col_idx = choose_a_subset(
                    \@{$aoa->[0]},
                    { back => '<<', confirm => $sf->{i}{ok}, index => 1, mark => $mark, layout => 0,
                      name => 'Cols: ', clear_screen => 0, mouse => $sf->{o}{table}{mouse}, prompt => ' ' }
                );
                if ( defined $col_idx && @$col_idx ) {
                    $sql->{insert_into_args} = [ map { [ @{$_}[@$col_idx] ] } @$aoa ];
                }
                next FILTER;
            }
            elsif ( $filter eq $input_rows_range ) {
                my $aoa = $sql->{insert_into_args};
                my $stmt_v = Term::Choose->new( $sf->{i}{lyt_stmt_v} );
                my @pre = ( undef );
                my $choices;
                {
                    no warnings 'uninitialized';
                    $choices = [ @pre, map { join ',', @$_ } @$aoa ];
                }
                $ax->print_sql( $sql, $stmt_typeS );
                # Choose
                my $first_idx = $stmt_v->choose(
                    $choices,
                    { prompt => "Choose FIRST ROW:", index => 1, undef => '<<' }
                );
                next FILTER if ! defined $first_idx || ! defined $choices->[$first_idx];
                my $first_row = $first_idx - @pre;
                next FILTER if $first_row < 0;
                $choices->[$first_row + @pre] = '* ' . $choices->[$first_row + @pre];
                $ax->print_sql( $sql, $stmt_typeS );
                # Choose
                my $last_idx = $stmt_v->choose(
                    $choices,
                    { prompt => "Choose LAST ROW:", default => $first_row, index => 1, undef => '<<' }
                );
                next FILTER if ! defined $last_idx || ! defined $choices->[$last_idx];
                my $last_row = $last_idx - @pre;
                next FILTER if $last_row < 0;
                if ( $last_row < $first_row ) {
                    $ax->print_sql( $sql, $stmt_typeS );
                    # Choose
                    choose(
                        [ "Last row [$last_row] is less than First row [$first_row]!" ],
                        { %{$sf->{i}{lyt_m}}, prompt => 'Press ENTER' }
                    );
                    next FILTER;
                }
                $sql->{insert_into_args} = [ @{$aoa}[$first_row .. $last_row] ];
                next FILTER;
            }
            elsif ( $filter eq $input_rows ) {
                my $aoa = $sql->{insert_into_args};
                my %hash;
                for my $i ( 0 .. $#$aoa ) {
                    push @{$hash{ scalar @{$aoa->[$i]} }}, $i;
                }
                my @keys = sort { scalar( @{$hash{$b}} ) <=> scalar( @{$hash{$a}} ) } keys %hash;
                my $stmt_v = Term::Choose->new( $sf->{i}{lyt_stmt_v} );
                my @pre = ( undef, $sf->{i}{ok} );
                my $mark = ( @keys > 1 ) ? [ map { $_ + @pre } @{$hash{$keys[0]}} ] : undef; # copy only ?
                my $choices;
                {
                    no warnings 'uninitialized';
                    $choices = [ @pre, map { join ',', @$_ } @$aoa ];
                }
                $ax->print_sql( $sql, $stmt_typeS );
                # Choose
                my @idx = $stmt_v->choose(
                    $choices,
                    { prompt => 'Choose rows:', index => 1, no_spacebar => [ 0 .. $#pre ], undef => '<<', mark => $mark }
                );
                if ( ! defined $idx[0] || ! defined $choices->[$idx[0]] ) {
                    next FILTER;
                }
                elsif ( $choices->[$idx[0]] eq $sf->{i}{ok} ) {
                    shift @idx;
                }
                my $tmp_aoa = [];
                for my $i ( @idx ) {
                    $i -= @pre;
                    push @$tmp_aoa, [ map { s/^\s+|\s+\z//g; $_ } @{$aoa->[$i]} ];
                }
                $sql->{insert_into_args} = $tmp_aoa;
                next FILTER;
            }
            elsif ( $filter eq $cols_to_rows ) {
                my $aoa = $sql->{insert_into_args};
                my $tmp_aoa = []; # name
                for my $i ( 0 .. $#$aoa ) {
                    for my $j ( 0 .. $#{$aoa->[$i]} ) {
                        $tmp_aoa->[$j][$i] = $aoa->[$i][$j];
                    }
                }
                 $sql->{insert_into_args} = $tmp_aoa;
                 $r2c = ! $r2c;
                next FILTER;
            }
        }
    }
}


sub __parse_file {
    my ( $sf, $sql, $stmt_typeS, $file_or_fh, $input_type, $sheet_idx ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    $ax->print_sql( $sql, $stmt_typeS );
    if ( ref $file_or_fh eq 'GLOB' ) {
        my $fh = $file_or_fh;
        seek $fh, 0, 0;
        my $tmp = [];
        if ( $sf->{o}{insert}{$input_type . '_parse_mode'} == 0 ) {
            my $csv = Text::CSV->new( { auto_diag => 2, map { $_ => $sf->{o}{csv}{$_} } sort keys %{$sf->{o}{csv}} } ) or die Text::CSV->error_diag();
            $csv->callbacks( error => sub { die "$_[0] $_[1] - pos:$_[2] rec:$_[3] fld:$_[4]" } );
            while ( my $row = $csv->getline( $fh ) ) {
                push @$tmp, $row;
            }
        }
        else {
            local $/;
            push @$tmp, map { [ split /$sf->{o}{split}{i_f_s}/ ] } split /$sf->{o}{split}{i_r_s}/, <$fh>;
        }
        $sql->{insert_into_args} = $tmp;
        return;
    }
    else {
        my $file = $file_or_fh;
        my $cm = Term::Choose->new( { %{$sf->{i}{lyt_m}}, prompt => 'Press ENTER' } );
        my $file_dc = decode( 'locale_fs', $file );
        if ( ! -e $file ) {
            $cm->choose( [ $file_dc . ' : file not found!' ] );
            return;
        }
        if ( ! -s $file ) {
            $cm->choose( [ $file_dc . ' : empty file!' ] );
            return;
        }
        if ( ! -r $file ) {
            $cm->choose( [ $file_dc . ' : file not readable!' ] );
            return;
        }
        require Spreadsheet::Read;
        my $book = Spreadsheet::Read::ReadData( $file, cells => 0, attr => 0, rc => 1, strip => 0 );
        if ( ! defined $book ) {
            $cm->choose( [ $file_dc . ' : no book!' ] );
            return;
        }
        my $sheet_count = @$book - 1; # first sheet in $book contains meta info
        if ( $sheet_count == 0 ) {
            $cm->choose( [ $file_dc . ' : no sheets!' ] );
            return;
        }
        if ( $sheet_idx ) {
            $sheet_idx = $sheet_idx;
        }
        elsif ( @$book == 2 ) {
            $sheet_idx = 1;
        }
        else {
            my @sheets = map { '- ' . ( length $book->[$_]{label} ? $book->[$_]{label} : 'sheet_' . $_ ) } 1 .. $#$book;
            my @pre = ( undef );
            my $choices = [ @pre, @sheets ];
            # Choose
            $sheet_idx = choose(
                $choices,
                { %{$sf->{i}{lyt_stmt_v}}, index => 1, prompt => 'Choose a sheet' }
            );
            if ( ! defined $sheet_idx || ! defined $choices->[$sheet_idx] ) {
                return;
            }
        }
        if ( $book->[$sheet_idx]{maxrow} == 0 ) {
            my $sheet = length $book->[$sheet_idx]{label} ? $book->[$sheet_idx]{label} : 'sheet_' . $_;
            choose( [ $sheet . ': empty sheet!' ], { %{$sf->{i}{lyt_m}}, prompt => 'Press ENTER' } );
            return;
        }
        $sql->{insert_into_args} = [ Spreadsheet::Read::rows( $book->[$sheet_idx] ) ];
        return $sheet_count, $sheet_idx;
    }
}



1;


__END__

package # hide from PAUSE
App::DBBrowser::Opt;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.042';

use Encode                qw( encode );
use File::Basename        qw( basename );
use File::Spec::Functions qw( catfile );
use FindBin               qw( $RealBin $RealScript );
#use Pod::Usage            qw( pod2usage );  # "require"-d

use Clone                  qw( clone );
use Encode::Locale         qw();
use JSON                   qw( decode_json );
use Term::Choose           qw( choose );
use Term::Choose::Util     qw( insert_sep print_hash choose_a_number choose_a_subset choose_multi choose_dirs );
use Term::ReadLine::Simple qw();



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub defaults {
    my ( $self, @keys ) = @_;
    my $defaults = {
        db_drivers           => [ 'SQLite', 'mysql', 'Pg' ],
        ask_host_port_per_db => 1,
        ask_user_pass_per_db => 1,
        use_env_dbi_user     => 0,
        use_env_dbi_pass     => 0,
        use_env_dbi_host     => 0,
        use_env_dbi_port     => 0,
        menus_config_memory  => 0,
        menu_sql_memory      => 0,
        menus_db_memory      => 0,
        table_expand         => 1,
        sssc_mode            => 0,
        lock_stmt            => 0,
        mouse                => 0,
        thsd_sep             => ',',
        metadata             => 0,
        max_rows             => 50_000,
        operators            => [ "REGEXP", " = ", " != ", " < ", " > ", "IS NULL", "IS NOT NULL" ],
        parentheses_w        => 0,
        parentheses_h        => 0,
        regexp_case          => 0,
        keep_header          => 0,
        progress_bar         => 40_000,
        min_col_width        => 30,
        tab_width            => 2,
        undef                => '',
        binary_string        => 'BNRY',
        insert_mode          => 1,
        row_col_filter       => 0,
        encoding_csv_file    => 'UTF-8',
        sep_char             => ',',
        quote_char           => '"',
        escape_char          => '"',
        eol                  => $/,
        allow_loose_escapes  => 0,
        allow_loose_quotes   => 0,
        allow_whitespace     => 0,
        auto_diag            => 1,
        blank_is_undef       => 1,
        binary               => 1,
        empty_is_undef       => 0,
        SQLite => {
            sqlite_unicode             => 1,
            sqlite_see_if_its_a_number => 1,
            binary_filter              => 0,
            dirs_sqlite_search         => undef,
        },
        mysql => {
            user              => undef,
            host              => undef,
            port              => undef,
            mysql_enable_utf8 => 1,
            binary_filter     => 0,
        },
        Pg => {
            user           => undef,
            host           => undef,
            port           => undef,
            pg_enable_utf8 => -1,
            binary_filter  => 0,
        },
    };
    die "To many keys: @keys"              if @keys >  2;
    return $defaults->{$keys[0]}           if @keys == 1;
    return $defaults->{$keys[0]}{$keys[1]} if @keys == 2;
    return $defaults;
}


sub __multi_choose {
    my ( $self, $key ) = @_;
    my $multi_choose = {
       _enchant      => [
            [ 'menus_config_memory', "- Menus config", [ 'Simple', 'Memory' ] ],
            [ 'menu_sql_memory',     "- Menu  sql",    [ 'Simple', 'Memory' ] ],
            [ 'menus_db_memory',     "- Menus db",     [ 'Simple', 'Memory' ] ],
            [ 'table_expand',        "- Print  Table", [ 'Simple', 'Expand' ] ],
            [ 'keep_header',         "- Table Header", [ 'Simple', 'Each page' ] ],
        ],
        _parentheses => [
            [ 'parentheses_w', "- Parentheses in WHERE",     [ 'NO', '(YES', 'YES(' ] ],
            [ 'parentheses_h', "- Parentheses in HAVING TO", [ 'NO', '(YES', 'YES(' ] ],
        ],
        _env_dbi     => [
            [ 'use_env_dbi_user', "- Use DBI_USER", [ 'NO', 'YES' ] ],
            [ 'use_env_dbi_pass', "- Use DBI_PASS", [ 'NO', 'YES' ] ],
            [ 'use_env_dbi_host', "- Use DBI_HOST", [ 'NO', 'YES' ] ],
            [ 'use_env_dbi_port', "- Use DBI_PORT", [ 'NO', 'YES' ] ],
        ],
        _db_connect  => [
            [ 'ask_host_port_per_db', "- Ask host/port per DB", [ 'NO', 'YES' ] ],
            [ 'ask_user_pass_per_db', "- Ask user/pass per DB", [ 'NO', 'YES' ] ],
        ],
        _options_csv => [
            [ 'allow_loose_escapes', "- allow_loose_escapes", [ 'NO', 'YES' ] ],
            [ 'allow_loose_quotes',  "- allow_loose_quotes",  [ 'NO', 'YES' ] ],
            [ 'allow_whitespace',    "- allow_whitespace",    [ 'NO', 'YES' ] ],
            [ 'blank_is_undef',      "- blank_is_undef",      [ 'NO', 'YES' ] ],
            [ 'empty_is_undef',      "- empty_is_undef",      [ 'NO', 'YES' ] ],
        ],
    };
    return $multi_choose->{$key};
}


sub __menus {
    my ( $self, $group ) = @_;
    my $menus = {
        main => [
            [ 'help',            "  HELP" ],
            [ 'path',            "  Path" ],
            [ 'config_output',   "- Output" ],
            [ 'config_menu',     "- Menu" ],
            [ 'config_sql',      "- SQL" ],
            [ 'config_database', "- Database" ],
            [ 'config_insert',   "- Insert" ],
        ],
        config_output => [
            [ 'min_col_width', "- Colwidth" ],
            [ 'progress_bar',  "- ProgressBar" ],
            [ 'tab_width',     "- Tabwidth" ],
            [ 'undef',         "- Undef" ],
        ],
        config_menu => [
            [ '_enchant',  "- Enchant" ],
            [ 'lock_stmt', "- Lock" ],
            [ 'mouse',     "- Mouse Mode" ],
            [ 'sssc_mode', "- Sssc Mode" ],
        ],
        config_sql => [
            [ 'max_rows',     "- Max Rows" ],
            [ 'metadata',     "- Metadata" ],
            [ 'operators',    "- Operators" ],
            [ '_parentheses', "- Parentheses" ],
            [ 'regexp_case',  "- Regexp Case" ],

        ],
        config_database => [
            [ '_db_defaults', "- DB Defaults" ],
            [ 'db_drivers',   "- DB Drivers" ],
            [ '_db_connect',  "- DB Login" ],
            [ '_env_dbi',     "- ENV DBI" ],
        ],
        config_insert => [
            [ 'insert_mode',       "- Insert mode" ],
            [ 'row_col_filter',    "- Col-Row input filter" ],
            [ 'encoding_csv_file', "- Encoding csv file" ],
            [ 'sep_char',          "- csv sep_char" ],
            [ 'quote_char',        "- csv quote_char" ],
            [ 'escape_char',       "- csv escape_char" ],
            [ '_options_csv',      "- Options csv" ],
        ],
    };
    return $menus->{$group};
}


sub __config_insert {
    my ( $self, $write_to_file ) = @_;
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my $no_yes = [ 'NO', 'YES' ];
    my $group = 'config_insert';
    my @pre = ( undef, $self->{info}{_confirm} );
    my $menu = $self->__menus( $group );
    my @real = map( $_->[1], @$menu );
    my $old_idx = 0;

    OPTION_INSERT: while ( 1 ) {
        # Choose
        my $idx = choose(
            [ @pre, @real ],
            { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx }
        );
        exit if ! defined $idx;
        my $key = $idx <= $#pre ? $pre[$idx] : $menu->[$idx - @pre][0];
        if ( ! defined $key ) {
            return;
        }
        if ( $self->{opt}{menus_config_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 0;
                next OPTION_INSERT;
            }
            $old_idx = $idx;
        }
        else {
            if ( $old_idx != 0 ) {
                $old_idx = 0;
                next OPTION_INSERT;
            }
        }
        if ( $key eq $self->{info}{_confirm} ) {
            if ( $self->{info}{write_config} ) {
                $self->__write_config_files() if $write_to_file;
                delete $self->{info}{write_config};
            }
            return;
        }
        elsif ( $key eq 'insert_mode' ) {
            my $list = [ '--', 'Cols', 'Rows', 'Multirow', 'File' ];
            my $prompt = 'Insert mode';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq 'row_col_filter' ) {
            my $list = $no_yes;
            my $prompt = 'Enable col-row input filter';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq 'encoding_csv_file' ) {
            my $prompt = 'Encoding csv file';
            $self->__opt_readline( $key, $prompt );
        }
        elsif ( $key eq 'sep_char' ) {
            my $prompt = 'csv sep_char';
            $self->__opt_readline( $key, $prompt );
        }
        elsif ( $key eq 'quote_char' ) {
            my $prompt = 'csv quote_char';
            $self->__opt_readline( $key, $prompt );
        }
        elsif ( $key eq 'escape_char' ) {
            my $prompt = 'csv escape_char';
            $self->__opt_readline( $key, $prompt );
        }
        #elsif ( $key eq 'eol' ) {
        #    my $prompt = 'csv eol';
        #    $self->__opt_readline( $key, $prompt );
        #}
        elsif ( $key eq '_options_csv' ) {
            my $sub_menu = $self->__multi_choose( $key );
            $self->__opt_choose_multi( $sub_menu );
        }
        else { die "Unknown option: $key" }
    }
}


sub set_options {
    my ( $self ) = @_;
    my $no_yes = [ 'NO', 'YES' ];
    my $group = 'main';
    my $backup_old_idx;
    my $old_idx = 0;

    GROUP: while ( 1 ) {
        my @pre = ( undef, $self->{info}{$group eq 'main' ? '_continue' : '_confirm'} );
        my $menu = $self->__menus( $group );
        my @real = map( $_->[1], @$menu );

        OPTION: while ( 1 ) {
            my $back = $self->{info}{$group eq 'main' ? '_exit' : '_back'};
            # Choose
            my $idx = choose(
                [ @pre, @real ],
                { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx, undef => $back }
            );
            exit if ! defined $idx;
            my $key = $idx <= $#pre ? $pre[$idx] : $menu->[$idx - @pre][0];
            if ( ! defined $key ) {
                if ( $group =~ /^config_/ ) {
                    $old_idx = $backup_old_idx;
                    $group = 'main';
                    redo GROUP;
                }
                exit();
            }
            if ( $self->{opt}{menus_config_memory} ) {
                if ( $old_idx == $idx ) {
                    $old_idx = 0;
                    next OPTION;
                }
                $old_idx = $idx;
            }
            else {
                if ( $old_idx != 0 ) {
                    $old_idx = 0;
                    next OPTION;
                }
            }
            if ( $key eq 'config_insert' ) {
                $self->__config_insert( 1 );
                $old_idx = $backup_old_idx;
                $group = 'main';
                redo GROUP;
            }
            if ( $key =~ /^config_/ ) {
                $backup_old_idx = $old_idx;
                $old_idx = 0;
                $group = $key;
                redo GROUP;
            }
            if ( $key eq $self->{info}{_continue} ) {
                return $self->{opt}; #
            }
            elsif ( $key eq $self->{info}{_confirm} ) {
                if ( $self->{info}{write_config} ) {
                    $self->__write_config_files();
                    delete $self->{info}{write_config};
                }
                $old_idx = $backup_old_idx;
                $group = 'main';
                redo GROUP;
            }
            elsif ( $key eq 'help' ) {
                require Pod::Usage;
                Pod::Usage::pod2usage( {
                    -exitval => 'NOEXIT',
                    -verbose => 2 } );
            }
            elsif ( $key eq 'path' ) {
                my $version = 'version';
                my $bin     = '  bin  ';
                my $app_dir = 'app-dir';
                my $path = {
                    $version => $main::VERSION,
                    $bin     => catfile( $RealBin, $RealScript ),
                    $app_dir => $self->{info}{app_dir},
                };
                my $keys = [ $version, $bin, $app_dir ];
                print_hash( $path, { keys => $keys, preface => ' Close with ENTER' } );
            }
            elsif ( $key eq 'tab_width' ) {
                my $digits = 3;
                my $prompt = 'Tab width';
                $self->__opt_number_range( $key, $prompt, $digits );
            }
            elsif ( $key eq 'min_col_width' ) {
                my $digits = 3;
                my $prompt = 'Minimum Column width';
                $self->__opt_number_range( $key, $prompt, $digits );
            }
            elsif ( $key eq 'undef' ) {
                my $prompt = 'Print replacement for undefined table vales';
                $self->__opt_readline( $key, $prompt );
            }
            elsif ( $key eq 'progress_bar' ) {
                my $digits = 7;
                my $prompt = '"Threshold ProgressBar"';
                $self->__opt_number_range( $key, $prompt, $digits );
            }
            elsif ( $key eq 'max_rows' ) {
                my $digits = 7;
                my $prompt = '"Max rows"';
                $self->__opt_number_range( $key, $prompt, $digits );
            }
            elsif ( $key eq 'lock_stmt' ) {
                my $list = [ 'Lk0', 'Lk1' ];
                my $prompt = 'Keep statement';
                $self->__opt_choose_index( $key, $prompt, $list );
            }
            elsif ( $key eq 'metadata' ) {
                my $list = $no_yes;
                my $prompt = 'Enable Metadata';
                $self->__opt_choose_index( $key, $prompt, $list );
            }
            elsif ( $key eq 'regexp_case' ) {
                my $list = $no_yes;
                my $prompt = 'REGEXP case sensitiv';
                $self->__opt_choose_index( $key, $prompt, $list );
            }
            elsif ( $key eq '_parentheses' ) {
                my $sub_menu = $self->__multi_choose( $key );
                $self->__opt_choose_multi( $sub_menu );
            }
            elsif ( $key eq '_db_connect' ) {
                my $sub_menu = $self->__multi_choose( $key );
                $self->__opt_choose_multi( $sub_menu );
            }
            elsif ( $key eq '_env_dbi' ) {
                my $sub_menu = $self->__multi_choose( $key );
                $self->__opt_choose_multi( $sub_menu );
            }
            elsif ( $key eq '_db_defaults' ) {
                $self->database_setting();
            }
            elsif ( $key eq 'sssc_mode' ) {
                my $list = [ 'simple', 'compat' ];
                my $prompt = 'Sssc mode';
                $self->__opt_choose_index( $key, $prompt, $list );
            }
            elsif ( $key eq 'operators' ) {
                my $available = $self->{info}{avail_operators};
                $self->__opt_choose_a_list( $key, $available );
            }
            elsif ( $key eq 'db_drivers' ) {
                my $available = $self->{info}{avail_db_drivers};
                $self->__opt_choose_a_list( $key, $available );
            }
            elsif ( $key eq 'mouse' ) {
                my $max = 4;
                my $prompt = 'Mouse mode';
                $self->__opt_number( $key, $prompt, $max );
            }
            elsif ( $key eq '_enchant' ) {
                my $sub_menu = $self->__multi_choose( $key );
                $self->__opt_choose_multi( $sub_menu );
            }
            else { die "Unknown option: $key" }
        }
    }
}

sub __opt_choose_multi {
    my ( $self, $sub_menu ) = @_;
    my $changed = choose_multi( $sub_menu, $self->{opt} );
    return if ! $changed;
    $self->{info}{write_config}++;
}

sub __opt_choose_index {
    my ( $self, $key, $prompt, $list ) = @_;
    my $yn = 0;
    my $current = $list->[$self->{opt}{$key}];
    # Choose
    my $idx = choose(
        [ undef, @$list ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', index => 1 }
    );
    return if ! defined $idx;
    return if $idx == 0;
    $idx--;
    $self->{opt}{$key} = $idx;
    $self->{info}{write_config}++;
    return;
}

sub __opt_choose_a_list {
    my ( $self, $key, $available ) = @_;
    my $current = $self->{opt}{$key};
    # Choose_list
    my $list = choose_a_subset( $available, { current => $current } );
    return if ! defined $list;
    return if ! @$list;
    $self->{opt}{$key} = $list;
    $self->{info}{write_config}++;
    return;
}

sub __opt_number {
    my ( $self, $key, $prompt, $max ) = @_;
    my $current = $self->{opt}{$key};
    # Choose
    my $choice = choose(
        [ undef, 0 .. $max ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', justify => 1 }
    );
    return if ! defined $choice;
    $self->{opt}{$key} = $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_number_range {
    my ( $self, $key, $prompt, $digits ) = @_;
    my $current = $self->{opt}{$key};
    $current = insert_sep( $current, $self->{opt}{thsd_sep} );
    # Choose_a_number
    my $choice = choose_a_number( $digits, { name => $prompt, current => $current } );
    return if ! defined $choice;
    $self->{opt}{$key} = $choice eq '--' ? undef : $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_readline {
    my ( $self, $key, $prompt ) = @_;
    my $current = $self->{opt}{$key};
    my $trs = Term::ReadLine::Simple->new();
    # Readline
    my $choice = $trs->readline( $prompt . ': ', { default => $current } );
    return if ! defined $choice;
    $self->{opt}{$key} = $choice;
    $self->{info}{write_config}++;
    return;
}


sub database_setting {
    my ( $self, $db ) = @_;
    my ( $db_driver, $section );
    if ( ! defined $db ) {
        if ( @{$self->{opt}{db_drivers}} == 1 ) {
            $db_driver = $self->{opt}{db_drivers}[0];
        }
        else {
            # Choose
            $db_driver = choose(
                [ undef, @{$self->{opt}{db_drivers}} ],
                { %{$self->{info}{lyt_1}} }
            );
            return if ! defined $db_driver;
        }
        $section = $db_driver;
    }
    else {
        $db_driver = $self->{info}{db_driver};
        $section   = $db_driver . '_' . $db;
        for my $key ( keys %{$self->{opt}{$db_driver}} ) {
            next if $key =~ /^(?:host|port|user)\z/; #
            next if $key eq 'dirs_sqlite_search';
            $self->{opt}{$section}{$key} //= $self->{opt}{$db_driver}{$key};
        }
    }

    my $orig = clone( $self->{opt} );
    my $menus = {
        SQLite => [
            [ 'sqlite_unicode',             "- Unicode" ],
            [ 'sqlite_see_if_its_a_number', "- See if its a number" ],
        ],
        mysql => [
            [ 'mysql_enable_utf8', "- Enable utf8" ],
        ],
        Pg => [
            [ 'pg_enable_utf8', "- Enable utf8" ],
        ],
    };
    if ( $db_driver =~ /^(?:mysql|Pg)\z/ ) {
        unshift @{$menus->{$db_driver}}, [ 'host', "- Host" ], [ 'port', "- Port" ] if $self->{opt}{ask_host_port_per_db};
        unshift @{$menus->{$db_driver}}, [ 'user', "- User" ];
    }
    if ( ! $db && $db_driver eq 'SQLite' ) {
        push @{$menus->{$db_driver}}, [ 'dirs_sqlite_search', "- Default DB dirs" ];
    }
    push @{$menus->{$db_driver}}, [ 'binary_filter', "- Binary Filter" ], [ '_reset', "  RESET" ];
    my $prompt;
    if ( defined $db ) {
        $prompt = 'DB: "' . ( $db_driver eq 'SQLite' ? basename( $db ) : $db ) . '"';
    }
    else {
        $prompt = 'Driver: ' . $db_driver;
    }
    my @pre = ( undef, $self->{info}{_confirm} );
    my @real = map { $_->[1] } @{$menus->{$db_driver}};
    my $old_idx = 0;

    DB_OPTION: while ( 1 ) {
        # Choose
        my $idx = choose(
            [ @pre, @real ],
            { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx, prompt => $prompt }
        );
        exit if ! defined $idx;
        my $key = $idx <= $#pre ? $pre[$idx] : $menus->{$db_driver}[$idx - @pre][0];
        if ( ! defined $key ) {
            $self->{opt} = clone( $orig ) if $self->{info}{write_config};
            return;
        }
        if ( $self->{opt}{menus_config_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 0;
                next DB_OPTION;
            }
            else {
                $old_idx = $idx;
            }
        }

        if ( $key eq '_reset' ) {
            if ( $db ) {
                delete $self->{opt}{$section};
            }
            else {
                my @dbs = ();
                for my $section ( keys %{$self->{opt}} ) {
                    push @dbs, $1 if $section =~ /^\Q$db_driver\E_(.+)\z/;
                }
                my $dlt = choose_a_subset( [ '*' . $db_driver, sort @dbs ], { p_new => 'Reset: ' } );
                next DB_OPTION if ! defined $dlt;
                next DB_OPTION if ! defined $dlt->[0];
                for my $db ( @$dlt ) {
                    if ( $db eq '*' . $db_driver ) {
                        $self->{opt}{$db_driver} = $self->defaults( $db_driver );
                    }
                    else {
                        my $section = $db_driver . '_' . $db;
                        delete $self->{opt}{$section};
                    }
                }
            }
            $self->{info}{write_config}++;
            next DB_OPTION;
        }
        if ( $key eq $self->{info}{_confirm} ) {
            if ( $self->{info}{write_config} ) {
                $self->__write_config_files();
                delete $self->{info}{write_config};
                return 1;
            }
            return;
        }
        my $no_yes = [ 'NO', 'YES' ];

        if ( $db_driver eq "SQLite" ) {
            if ( $key eq 'sqlite_unicode' ) {
                my $prompt = 'Unicode';
                $self->__db_opt_choose_index( $section, $key, $prompt, $no_yes );
            }
            elsif ( $key eq 'sqlite_see_if_its_a_number' ) {
                my $prompt = 'See if its a number';
                $self->__db_opt_choose_index( $section, $key, $prompt, $no_yes );
            }
            elsif ( $key eq 'binary_filter' ) {
                my $prompt = 'Enable Binary Filter';
                $self->__db_opt_choose_index( $section, $key, $prompt, $no_yes );
            }
            elsif ( $key eq 'dirs_sqlite_search' ) {
                $self->__db_opt_choose_dirs( $section, $key, $prompt );
            }
            else { die "Unknown key: $key" }
        }
        elsif ( $db_driver eq "mysql" ) {
            if ( $key eq 'mysql_enable_utf8' ) {
                my $prompt = 'Enable utf8';
                $self->__db_opt_choose_index( $section, $key, $prompt, $no_yes );
            }
            elsif ( $key eq 'user' ) {
                my $prompt = 'User';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'host' ) {
                my $prompt = 'Host';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'port' ) {
                my $prompt = 'Port';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'binary_filter' ) {
                my $prompt = 'Enable Binary Filter';
                $self->__db_opt_choose_index( $section, $key, $prompt, $no_yes );
            }
            else { die "Unknown key: $key" }
        }
        elsif ( $db_driver eq "Pg" ) {
            if ( $key eq 'pg_enable_utf8' ) {
                my $prompt = 'Enable utf8';
                my $list = [ @{$no_yes}, 'AUTO' ];
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
                $self->{opt}{$section}{$key} = -1 if $self->{opt}{$section}{$key} == 2;
            }
            elsif ( $key eq 'user' ) {
                my $prompt = 'User';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'host' ) {
                my $prompt = 'Host';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'port' ) {
                my $prompt = 'Port';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'binary_filter' ) {
                my $prompt = 'Enable Binary Filter';
                $self->__db_opt_choose_index( $section, $key, $prompt, $no_yes );
            }
            else { die "Unknown key: $key" }
        }
    }
}

sub __db_opt_choose_index {
    my ( $self, $section, $key, $prompt, $list ) = @_;
    my $current = $list->[$self->{opt}{$section}{$key}];
    # Choose
    my $idx = choose(
        [ undef, @$list ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', index => 1 }
    );
    return if ! defined $idx;
    return if $idx == 0;
    $idx--;
    $self->{opt}{$section}{$key} = $idx;
    $self->{info}{write_config}++;
    return;
}

sub __db_opt_choose_dirs {
    my ( $self, $section, $key ) = @_;
    my $current = $self->{opt}{$section}{$key};
    # Choose_dirs
    my $dirs = choose_dirs( { mouse => $self->{opt}{mouse}, current => $current } );
    return if ! defined $dirs;
    return if ! @$dirs;
    $self->{opt}{$section}{$key} = $dirs;
    $self->{info}{write_config}++;
    return;
}

sub __db_opt_readline {
    my ( $self, $section, $key, $prompt ) = @_;
    my $current = $self->{opt}{$section}{$key};
    my $trs = Term::ReadLine::Simple->new();
    # Readline
    my $choice = $trs->readline( $prompt . ': ', { default => $current } );
    return if ! defined $choice;
    $self->{opt}{$section}{$key} = $choice;
    $self->{info}{write_config}++;
    return;
}


sub __write_config_files {
    my ( $self ) = @_;
    my $regexp_db_drivers = join '|', map quotemeta, @{$self->defaults( qw( db_drivers ) )};
    my $fmt = $self->{info}{conf_file_fmt};
    my $tmp = {};
    for my $section ( sort keys %{$self->{opt}} ) {
        if ( $section =~ /^($regexp_db_drivers)(?:_(.+))?\z/ ) {
            die $section if ref( $self->{opt}{$section} ) ne 'HASH';
            my ( $db_driver, $conf_sect ) = ( $1, $2 );
            $conf_sect //= '*' . $db_driver;
            for my $key ( keys %{$self->{opt}{$section}} ) {
                next if $key =~ /^_/;
                $tmp->{$db_driver}{$conf_sect}{$key} = $self->{opt}{$section}{$key};
            }
        }
        else {
            die $section if ref( $self->{opt}{$section} ) eq 'HASH';
            my $generic = $self->{info}{sect_generic};
            my $key = $section;
            next if $key =~ /^_/;
            $tmp->{$generic}{$key} = $self->{opt}{$key};
        }
    }
    for my $name ( keys %$tmp ) {
        $self->write_json( sprintf( $fmt, $name ), $tmp->{$name}  );
    }

}


sub read_config_files {
    my ( $self ) = @_;
    $self->{opt} = $self->defaults();
    my $fmt = $self->{info}{conf_file_fmt};
    for my $db_driver ( @{$self->defaults( qw( db_drivers ) )} ) {
        my $file = sprintf( $fmt, $db_driver );
        if ( -f $file && -s $file ) {
            my $tmp = $self->read_json( $file );
            for my $conf_sect ( keys %$tmp ) {
                my $section = $db_driver . ( $conf_sect =~ /^\*(?:$db_driver)\z/ ? '' : '_' . $conf_sect );
                for my $key ( keys %{$tmp->{$conf_sect}} ) {
                    $self->{opt}{$section}{$key} = $tmp->{$conf_sect}{$key} if exists $self->{opt}{$db_driver}{$key};
                }
            }
        }
    }
    my $file =  sprintf( $fmt, $self->{info}{sect_generic} );
    if ( -f $file && -s $file ) {
        my $tmp = $self->read_json( $file );
        for my $key ( keys %$tmp ) {
            $self->{opt}{$key} = $tmp->{$key} if exists $self->{opt}{$key};
        }
    }
    return $self->{opt};
}


sub write_json {
    my ( $self, $file, $h_ref ) = @_;
    my $json = JSON::XS->new->utf8( 1 )->pretty->canonical->encode( $h_ref );
    open my $fh, '>', encode( 'locale_fs', $file ) or die $!;
    print $fh $json;
    close $fh;
}


sub read_json {
    my ( $self, $file ) = @_;
    return {} if ! -f encode( 'locale_fs', $file );
    open my $fh, '<', encode( 'locale_fs', $file ) or die $!;
    my $json = do { local $/; <$fh> };
    close $fh;
    my $h_ref = {};
    if ( ! eval {
        $h_ref = decode_json( $json ) if $json;
        1 }
    ) {
        die "In '$file':\n$@";
    }
    return $h_ref;
}


1;


__END__

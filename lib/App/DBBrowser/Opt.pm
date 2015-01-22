package # hide from PAUSE
App::DBBrowser::Opt;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.994';

use File::Basename        qw( basename fileparse );
use File::Spec::Functions qw( catfile );
use FindBin               qw( $RealBin $RealScript );
#use Pod::Usage            qw( pod2usage );  # "require"-d

use Term::Choose           qw( choose );
use Term::Choose::Util     qw( insert_sep print_hash choose_a_number choose_a_subset choose_multi choose_dirs );
use Term::ReadLine::Simple qw();

use App::DBBrowser::DB;
use App::DBBrowser::Auxil;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub defaults {
    my ( $self, $section, $key ) = @_;
    my $defaults = {
        G => {
            db_plugins           => [ 'SQLite', 'mysql', 'Pg' ],
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
            operators            => [ "REGEXP", "REGEXP_i", " = ", " != ", " < ", " > ", "IS NULL", "IS NOT NULL" ],
            parentheses_w        => 0,
            parentheses_h        => 0,
            keep_header          => 0,
            progress_bar         => 40_000,
            min_col_width        => 30,
            tab_width            => 2,
            undef                => '',
            binary_string        => 'BNRY',
        },
        insert => {
            input_modes          => [ 'Cols', 'Multirow', 'File' ],
            csv_read             => 0,
            encoding_csv_file    => 'UTF-8',
            max_files            => 15,
        # Text::CSV:
            sep_char             => ',',
            quote_char           => '"',
            escape_char          => '"',
            allow_loose_escapes  => 0,
            allow_loose_quotes   => 0,
            allow_whitespace     => 0,
            auto_diag            => 1,
            blank_is_undef       => 1,
            binary               => 1,
            empty_is_undef       => 0,
        # Text::ParseWords:
            delim                => ',',
            keep                 => 0,
        }
    };
    return $defaults                   if ! $section;
    return $defaults->{$section}       if ! $key;
    return $defaults->{$section}{$key};
}


sub __sub_menus_insert {
    my ( $self, $group ) = @_;
    my $sub_menus_insert = {
        main_insert => [
            [ 'input_modes',             "- Input modes" ],
            [ 'csv_read',                "- Parse module" ],
            [ 'encoding_csv_file',       "- File encoding" ],
            [ '_module_text_csv',        "- Text::CSV" ],
            [ '_module_text_parsewords', "- Text::ParseWords" ],
            [ 'max_files',               "- File history" ],
        ],
        _module_text_csv => [
            [ '_csv_char',               "- *_char attributes" ],
            [ '_options_csv',            "-  Other attributes" ],
        ],
        _module_text_parsewords => [
            [ 'delim',                   "- \$delim" ],
            [ 'keep',                    "- \$keep" ],
        ],
    };
    return $sub_menus_insert->{$group};
}


sub __config_insert {
    my ( $self, $write_to_file ) = @_;
    my $old_idx = 0;
    my $backup_old_idx = 0;
    my $group  = 'main_insert';

    GROUP_INSERT: while ( 1 ) {
        my $sub_menu_insert = $self->__sub_menus_insert( $group );

        OPTION_INSERT: while ( 1 ) {
            my @pre    = ( undef );
            my @real   = map( $_->[1], @$sub_menu_insert );
            # Choose
            my $idx = choose(
                [ @pre, @real ],
                { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx, undef => $self->{info}{conf_back} }
            );
            if ( ! $idx ) {
                if ( $group =~ /^_module_/ ) {
                    $old_idx = $backup_old_idx;
                    $group = 'main_insert';
                    redo GROUP_INSERT;
                }
                else {
                    if ( $self->{info}{write_config} ) {
                        $self->__write_config_files();
                        delete $self->{info}{write_config} if $write_to_file;
                    }
                    return
                }
            }
            if ( $self->{opt}{G}{menus_config_memory} ) {
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
            my $section = 'insert';
            my $name = $idx <= $#pre ? $pre[$idx] : $sub_menu_insert->[$idx - @pre][0];
            if ( $name =~ /^_module_/ ) {
                $backup_old_idx = $old_idx;
                $old_idx = 0;
                $group = $name;
                redo GROUP_INSERT;
            }
            my $no_yes = [ 'NO', 'YES' ];
            if ( $name eq 'input_modes' ) {
                    my $available = [ 'Cols', 'Rows', 'Multirow', 'File' ];
                    $self->__opt_choose_a_list( $section, $name, $available );
            }
            elsif ( $name eq 'csv_read' ) {
                my $prompt = 'Parsing CSV files: ';
                my $list = [ 'Text::CSV', 'Text::ParseWords', 'Spreadsheet::Read' ];
                my $sub_menu = [ [ $name, "  Use", $list ] ];
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq 'encoding_csv_file' ) {
                my $prompt = 'Encoding CSV files';
                $self->__opt_readline( 'insert', $name, $prompt );
            }
            elsif ( $name eq '_csv_char' ) {
                my $items = [
                    { name => 'sep_char',    prompt => "sep_char   " },
                    { name => 'quote_char',  prompt => "quote_char " },
                    { name => 'escape_char', prompt => "escape_char" },
                ];
                my $prompt = 'Text::CSV:';
                $self->__group_readline( $section, $items, $prompt );
            }
            elsif ( $name eq '_options_csv' ) {
                my $prompt = 'Text::CSV:';
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq 'delim' ) {
                my $prompt = 'Text::ParseWords delimiter (regexp)';
                $self->__opt_readline( $section, $name, $prompt );
            }
            elsif ( $name eq 'keep' ) {
                my $prompt = 'Text::ParseWords: ';
                my $list = $no_yes;
                my $sub_menu = [ [ $name, "  Enable option '\$keep'", $list ] ];
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq 'max_files' ) {
                my $digits = 3;
                my $prompt = 'Save the last x input file names';
                $self->__opt_number_range( $section, $name, $prompt, $digits );
            }
            else { die "Unknown option: $name" }
        }
    }
}


sub __multi_choose {
    my ( $self, $key ) = @_;
    my $multi_choose = {
       _menu_memory  => [
            [ 'menus_config_memory', "- Config Menus", [ 'Simple', 'Memory' ] ],
            [ 'menu_sql_memory',     "- SQL    Menu",  [ 'Simple', 'Memory' ] ],
            [ 'menus_db_memory',     "- DB     Menus", [ 'Simple', 'Memory' ] ],
        ],
       _table_expand => [
            [ 'table_expand', "- Table Rows",   [ 'Simple', 'Expand'    ] ],
            [ 'keep_header',  "- Table Header", [ 'Simple', 'Each page' ] ],
        ],
        _parentheses => [
            [ 'parentheses_w', "- Parens in WHERE",     [ 'NO', '(YES', 'YES(' ] ],
            [ 'parentheses_h', "- Parens in HAVING TO", [ 'NO', '(YES', 'YES(' ] ],
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
            [ 'config_database', "- DB" ],
            [ 'config_menu',     "- Menu" ],
            [ 'config_sql',      "- SQL" ],
            [ 'config_output',   "- Output" ],
            [ 'config_insert',   "- Insert" ],
        ],
        config_database => [
            [ '_db_defaults', "- DB Settings" ],
            [ 'db_plugins',   "- DB Plugins" ],
        ],
        config_menu => [
            [ '_menu_memory',  "- Menu Memory" ],
            [ '_table_expand', "- Table" ],
            [ 'mouse',         "- Mouse Mode" ],
            [ 'sssc_mode',     "- Sssc Mode" ],
        ],
        config_sql => [
            [ 'max_rows',     "- Max Rows" ],
            [ 'metadata',     "- Metadata" ],
            [ 'operators',    "- Operators" ],
            [ 'lock_stmt',    "- Lock Mode" ],
            [ '_parentheses', "- Parentheses" ],

        ],
        config_output => [
            [ 'min_col_width', "- Colwidth" ],
            [ 'progress_bar',  "- ProgressBar" ],
            [ 'tab_width',     "- Tabwidth" ],
            [ 'undef',         "- Undef" ],
        ],
    };
    return $menus->{$group};
}


sub set_options {
    my ( $self ) = @_;
    my $group = 'main';
    my $backup_old_idx = 0;
    my $old_idx = 0;

    GROUP: while ( 1 ) {
        my $menu = $self->__menus( $group );

        OPTION: while ( 1 ) {
            my $back =          $group eq 'main' ? $self->{info}{_quit}     : $self->{info}{conf_back};
            my @pre  = ( undef, $group eq 'main' ? $self->{info}{_continue} : () );
            my @real = map( $_->[1], @$menu );
            # Choose
            my $idx = choose(
                [ @pre, @real ],
                { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx, undef => $back }
            );
            exit if ! defined $idx;
            my $name = $idx <= $#pre ? $pre[$idx] : $menu->[$idx - @pre][0];
            if ( ! defined $name ) {
                if ( $group =~ /^config_/ ) {
                    $old_idx = $backup_old_idx;
                    $group = 'main';
                    redo GROUP;
                }
                else {
                    if ( $self->{info}{write_config} ) {
                        $self->__write_config_files();
                        delete $self->{info}{write_config};
                    }
                    exit();
                }
            }
            if ( $self->{opt}{G}{menus_config_memory} ) {
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
            if ( $name eq 'config_insert' ) {
                $self->__config_insert( 1 );
                $old_idx = $backup_old_idx;
                $group = 'main';
                redo GROUP;
            }
            if ( $name =~ /^config_/ ) {
                $backup_old_idx = $old_idx;
                $old_idx = 0;
                $group = $name;
                redo GROUP;
            }
            my $section = 'G';
            my $no_yes = [ 'NO', 'YES' ];
            if ( $name eq $self->{info}{_continue} ) {
                if ( $self->{info}{write_config} ) {
                    $self->__write_config_files();
                    delete $self->{info}{write_config};
                }
                return $self->{opt};
            }
            elsif ( $name eq 'help' ) {
                require Pod::Usage;
                Pod::Usage::pod2usage( {
                    -exitval => 'NOEXIT',
                    -verbose => 2 } );
            }
            elsif ( $name eq 'path' ) {
                my $version = 'version';
                my $bin     = '  bin  ';
                my $app_dir = 'app-dir';
                my $path = {
                    $version => $main::VERSION,
                    $bin     => catfile( $RealBin, $RealScript ),
                    $app_dir => $self->{info}{app_dir},
                };
                my $names = [ $version, $bin, $app_dir ];
                print_hash( $path, { keys => $names, preface => ' Close with ENTER' } );
            }
            elsif ( $name eq 'tab_width' ) {
                my $digits = 3;
                my $prompt = 'Tab width';
                $self->__opt_number_range( $section, $name, $prompt, $digits );
            }
            elsif ( $name eq 'min_col_width' ) {
                my $digits = 3;
                my $prompt = 'Minimum Column width';
                $self->__opt_number_range( $section, $name, $prompt, $digits );
            }
            elsif ( $name eq 'undef' ) {
                my $prompt = 'Print replacement for undefined table vales';
                $self->__opt_readline( $section, $name, $prompt );
            }
            elsif ( $name eq 'progress_bar' ) {
                my $digits = 7;
                my $prompt = '"Threshold ProgressBar"';
                $self->__opt_number_range( $section, $name, $prompt, $digits );
            }
            elsif ( $name eq 'max_rows' ) {
                my $digits = 7;
                my $prompt = '"Max rows"';
                $self->__opt_number_range( $section, $name, $prompt, $digits );
            }
            elsif ( $name eq 'lock_stmt' ) {
                my $prompt = 'SQL statement: ';
                my $list = [ 'Lk0', 'Lk1' ];
                my $sub_menu = [ [ $name, "  Lock Mode", $list ] ];
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq 'metadata' ) {
                my $prompt = 'DB/schemas/tables: ';
                my $list = $no_yes;
                my $sub_menu = [ [ $name, "  Add metadata", $list ] ];
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq '_parentheses' ) {
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $section, $sub_menu );
            }
            elsif ( $name eq '_db_defaults' ) {
                $self->database_setting();
            }
            elsif ( $name eq 'sssc_mode' ) {
                my $prompt = 'Sssc mode: ';
                my $list = [ 'simple', 'compat' ];
                my $sub_menu = [ [ $name, "  Sssc Mode", $list ] ];
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq 'operators' ) {
                my $available = $self->{info}{avail_operators};
                $self->__opt_choose_a_list( $section, $name, $available );
            }
            elsif ( $name eq 'db_plugins' ) {
                my %installed_db_driver;
                for my $dir ( @INC ) {
                    my $glob_pattern = catfile $dir, 'App', 'DBBrowser', 'DB', '*.pm';
                    map { $installed_db_driver{( fileparse $_, '.pm' )[0]}++ } glob $glob_pattern;
                }
                $self->__opt_choose_a_list( $section, $name, [ sort keys %installed_db_driver ] );
            }
            elsif ( $name eq 'mouse' ) {
                my $prompt = 'Mouse mode: ';
                my $list = [ 0, 1, 2, 3, 4 ];
                my $sub_menu = [ [ $name, "  Mouse mode", $list ] ];
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
            }
            elsif ( $name eq '_menu_memory' ) {
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $section, $sub_menu );
            }
            elsif ( $name eq '_table_expand' ) {
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $section, $sub_menu );
            }
            else { die "Unknown option: $name" }
        }
    }
}


sub __opt_choose_multi {
    my ( $self, $section, $sub_menu, $prompt ) = @_;
    my $val = $self->{opt}{$section};
    my $changed = choose_multi( $sub_menu, $val, {  prompt => $prompt } );#, simple => 1, back => '<='
    return if ! $changed;
    $self->{info}{write_config}++;
}


sub __opt_choose_a_list {
    my ( $self, $section, $name, $available, $index ) = @_;
    my $current = $self->{opt}{$section}{$name};
    # Choose_list
    my $list = choose_a_subset( $available, { current => $current, index => $index } );
    return if ! defined $list;
    return if ! @$list;
    $self->{opt}{$section}{$name} = $list;
    $self->{info}{write_config}++;
    return;
}


sub __opt_number_range {
    my ( $self, $section, $name, $prompt, $digits ) = @_;
    my $current = $self->{opt}{$section}{$name};
    $current = insert_sep( $current, $self->{opt}{G}{thsd_sep} );
    # Choose_a_number
    my $choice = choose_a_number( $digits, { name => $prompt, current => $current } );
    return if ! defined $choice;
    $self->{opt}{$section}{$name} = $choice eq '--' ? undef : $choice;
    $self->{info}{write_config}++;
    return;
}


sub __group_readline {
    my ( $self, $section, $items, $prompt ) = @_;
    my $old_idx = 0;

    OPTION: while ( 1 ) {
        my @pre = ( undef );
        my @real = map {
                '- '
            . $_->{prompt}
            . ( $self->{opt}{$section}{$_->{name}} ? ": $self->{opt}{$section}{$_->{name}}" : ":" )
        } @{$items};
        my $choices = [ @pre, @real ];
        # Choose
        my $idx = choose(
            $choices,
            { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx,
              prompt => $prompt, undef => $self->{info}{conf_back} }
        );
        if ( ! $idx ) {
            return;
        }
        if ( $self->{opt}{G}{menus_config_memory} ) {
            if ( $old_idx == $idx ) {
                $old_idx = 0;
                next OPTION;;
            }
            else {
                $old_idx = $idx;
            }
        }
        $idx -= @pre;
        my $name = $items->[$idx]{name};
        my $readline_prompt = $items->[$idx]{prompt};
        $readline_prompt =~ s/\s+\z//;
        $self->__opt_readline( $section, $name, $readline_prompt );
    }
}


sub __opt_readline {
    my ( $self, $section, $name, $prompt ) = @_;
    my $current = $self->{opt}{$section}{$name};
    my $trs = Term::ReadLine::Simple->new();
    # Readline
    my $choice = $trs->readline( $prompt . ': ', { default => $current } );
    return if ! defined $choice;
    $self->{opt}{$section}{$name} = $choice;
    $self->{info}{write_config}++;
    return;
}


sub __opt_choose_dirs {
    my ( $self, $section, $name ) = @_;
    my $current = $self->{opt}{$section}{$name};
    # Choose_dirs
    my $dirs = choose_dirs( { mouse => $self->{opt}{G}{mouse}, current => $current } );
    return if ! defined $dirs;
    return if ! @$dirs;
    $self->{opt}{$section}{$name} = $dirs;
    $self->{info}{write_config}++;
    return;
}


sub database_setting {
    my ( $self, $db ) = @_;
    my $changed = 0;
    SECTION: while ( 1 ) {
        my ( $db_driver, $db_plugin, $section );
        if ( defined $db ) {
            $db_plugin = $self->{info}{db_plugin};
            $db_driver = $self->{info}{db_driver};
            $section   = $db_plugin . '_' . $db;
            for my $name ( keys %{$self->{opt}{$db_plugin}} ) {
                next if $name eq 'directories_sqlite';
                if ( ! defined $self->{opt}{$section}{$name} ) {
                    $self->{opt}{$section}{$name} = $self->{opt}{$db_plugin}{$name};
                }
            }
        }
        else {
            if ( @{$self->{opt}{G}{db_plugins}} == 1 ) {
                $db_plugin = $self->{opt}{G}{db_plugins}[0];
            }
            else {
                # Choose
                $db_plugin = choose(
                    [ undef, map( "- $_", @{$self->{opt}{G}{db_plugins}} ) ],
                    { %{$self->{info}{lyt_3}}, undef => $self->{info}{conf_back} }
                );
                return if ! defined $db_plugin;
            }
            $db_plugin =~ s/^-\ //;
            $self->{info}{db_plugin} = $db_plugin;
            $section = $db_plugin;
        }
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        $db_driver = $obj_db->db_driver() if ! $db_driver;
        my $login_data = $obj_db->login_data();
        my $connect_attr = $obj_db->connect_attributes();
        my $items = {
            login_mode   => [ map { { name         => 'login_mode_' . $_->{name},
                                      prompt       => $_->{prompt},
                                      avail_values => [ 'Ask', 'Use DBI_HOST', 'Don\'t set' ] } } @$login_data ],
            login_data   => [ grep { ! $_->{keep_secret} } @$login_data ],
            connect_attr => $connect_attr,
        };
        push @{$items->{connect_attr}}, {
            name          => 'binary_filter',
            avail_values  => [ 0, 1 ],
            default_index => 0,
        };
        my @groups;
        push @groups, [ 'login_mode',   "- Login Mode"         ] if @{$items->{login_mode}};
        push @groups, [ 'login_data',   "- Login Data"         ] if @{$items->{login_data}};
        push @groups, [ 'connect_attr', "- DB Options"         ];
        push @groups, [ 'sqlite_dir',   "- Sqlite directories" ] if $db_driver eq 'SQLite';
        my $prompt = defined $db ? 'DB: "' . ( $db_driver eq 'SQLite' ? basename $db : $db )
                                 : 'Plugin: ' . $db_plugin;
        my $old_idx_group = 0;

        GROUP: while ( 1 ) {
            my $reset = '  Reset DB';
            my @pre = ( undef );
            my $choices = [ @pre, map( $_->[1], @groups ) ];
            push @$choices, $reset if ! defined $db;
            # Choose
            my $idx_group = choose(
                $choices,
                { %{$self->{info}{lyt_3}}, prompt => $prompt, index => 1,
                  default => $old_idx_group, undef => $self->{info}{conf_back} }
            );
            if ( ! $idx_group ) {
                if ( $self->{info}{write_config} ) {
                    $self->__write_db_config_files();
                    delete $self->{info}{write_config};
                    $changed++;
                }
                next SECTION if ! $db && @{$self->{opt}{G}{db_plugins}} > 1;
                return $changed;
            }
            if ( $self->{opt}{G}{menus_config_memory} ) {
                if ( $old_idx_group == $idx_group ) {
                    $old_idx_group = 0;
                    next GROUP;
                }
                else {
                    $old_idx_group = $idx_group;
                }
            }
            if ( $choices->[$idx_group] eq $reset ) {
                my @databases;
                for my $section ( keys %{$self->{opt}} ) {
                    push @databases, $1 if $section =~ /^\Q$db_plugin\E_(.+)\z/;
                }
                if ( ! @databases ) {
                    choose(
                        [ 'No databases with customized settings.' ],
                        { %{$self->{info}{lyt_stop}}, prompt => 'Press ENTER' }
                    );
                    next GROUP;
                }
                my $choices = choose_a_subset(
                    [ sort @databases ],
                    { p_new => 'Reset DB: ' }
                );
                if ( ! $choices->[0] ) {
                    next GROUP;
                }
                for my $db ( @$choices ) {
                    my $section = $db_plugin . '_' . $db;
                    delete $self->{opt}{$section};
                }
                $self->{info}{write_config}++;
                next GROUP;;
            }
            my $group  = $groups[$idx_group-@pre][0];
            if ( $group eq 'login_mode' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $login_mode_key = $item->{name};
                    push @$sub_menu, [ $login_mode_key, '- ' . $item->{prompt}, $item->{avail_values} ];
                    if ( ! defined $self->{opt}{$section}{$login_mode_key} ) {
                        $self->{opt}{$section}{$login_mode_key} = 0;
                    }
                }
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'login_data' ) {
                $self->__group_readline( $section, $items->{$group}, $prompt );
            }
            elsif ( $group eq 'connect_attr' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    push @$sub_menu, [ $item->{name}, '- ' . $item->{name}, $item->{avail_values} ];
                    if ( ! defined $self->{opt}{$section}{$item->{name}} ) {
                        $self->{opt}{$section}{$item->{name}} = $item->{avail_values}[$item->{default_index}];
                    }
                }
                $self->__opt_choose_multi( $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'sqlite_dir' ) {
                my $name = 'directories_sqlite';
                $self->__opt_choose_dirs( $section, $name );
                next GROUP;
            }
        }
    }
}


sub __write_config_files {
    my ( $self ) = @_;
    my $fmt = $self->{info}{conf_file_fmt};
    my $tmp = {};
    for my $section ( 'G', 'insert' ) {
        for my $name ( keys %{$self->{opt}{$section}} ) {
            #next if $name =~ /^_/;
            $tmp->{$section}{$name} = $self->{opt}{$section}{$name};
        }
    }
    my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    my $file_name = $self->{info}{config_generic};
    $auxil->write_json( sprintf( $fmt, $file_name ), $tmp  );
}


sub __write_db_config_files {
    my ( $self ) = @_;
    my $regexp_db_plugins = join '|', map quotemeta, @{$self->{opt}{G}{db_plugins}};
    my $fmt = $self->{info}{conf_file_fmt};
    my $tmp = {};
    for my $section ( sort keys %{$self->{opt}} ) {
        if ( $section =~ /^($regexp_db_plugins)(?:_(.+))?\z/ ) { #
            my ( $db_plugin, $conf_sect ) = ( $1, $2 );
            $conf_sect = '*' . $db_plugin if ! defined $conf_sect;
            for my $name ( keys %{$self->{opt}{$section}} ) {
                #next if $name =~ /^_/;
                $tmp->{$db_plugin}{$conf_sect}{$name} = $self->{opt}{$section}{$name};
            }
        }
    }
    my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    for my $section ( keys %$tmp ) {
        my $file_name =  $section;
        $auxil->write_json( sprintf( $fmt, $file_name ), $tmp->{$section}  );
    }
}


sub read_config_files {
    my ( $self ) = @_;
    $self->{opt} = $self->defaults();
    my $fmt = $self->{info}{conf_file_fmt};
    my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    my $file =  sprintf( $fmt, $self->{info}{config_generic} );
    if ( -f $file && -s $file ) {
        my $tmp = $auxil->read_json( $file );
        for my $section ( keys %$tmp ) {
            for my $name ( keys %{$tmp->{$section}} ) {
                $self->{opt}{$section}{$name} = $tmp->{$section}{$name} if exists $self->{opt}{$section}{$name};
            }
        }
    }
    for my $db_plugin ( @{$self->{opt}{G}{db_plugins}} ) {
        my $file = sprintf( $fmt, $db_plugin );
        if ( -f $file && -s $file ) {
            my $tmp = $auxil->read_json( $file );
            for my $conf_sect ( keys %$tmp ) {
                my $section = $db_plugin . ( $conf_sect =~ /^\*\Q$db_plugin\E\z/ ? '' : '_' . $conf_sect );
                for my $name ( keys %{$tmp->{$conf_sect}} ) {
                    $self->{opt}{$section}{$name} = $tmp->{$conf_sect}{$name};
                }
            }
        }
    }
    return $self->{opt};
}




1;


__END__

package # hide from PAUSE
App::DBBrowser::Opt;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.993';

use File::Basename        qw( basename fileparse );
use File::Spec::Functions qw( catfile );
use FindBin               qw( $RealBin $RealScript );
#use Pod::Usage            qw( pod2usage );  # "require"-d

use Clone                  qw( clone );
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
    my ( $self, @keys ) = @_;
    my $defaults = {
        db_plugins           => [ 'SQLite', 'mysql', 'Pg' ],
        ################################### 1.0 ################################
        login_host           => 1,
        login_port           => 1,
        login_user           => 1,
        login_pass           => 1,
        ########################################################################
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
        ################################### 1.0 ################################
        SQLite => {
            sqlite_unicode             => 1,
            sqlite_see_if_its_a_number => 1,
            binary_filter              => 0,
            directories_sqlite         => [ $self->{info}{home_dir} ],
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
        ########################################################################
    };
    die "To many keys: @keys"              if @keys >  2;
    return $defaults->{$keys[0]}           if @keys == 1;
    return $defaults->{$keys[0]}{$keys[1]} if @keys == 2;
    return $defaults;
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
            [ 'table_expand', "- Print  Table", [ 'Simple', 'Expand'    ] ],
            [ 'keep_header',  "- Table Header", [ 'Simple', 'Each page' ] ],
        ],
        _parentheses => [
            [ 'parentheses_w', "- Parentheses in WHERE",     [ 'NO', '(YES', 'YES(' ] ],
            [ 'parentheses_h', "- Parentheses in HAVING TO", [ 'NO', '(YES', 'YES(' ] ],
        ],
        ######################################## 1.0 #############################################
        #_db_connect  => [
        #    [ 'login_host', "- Host",     [ 'Ask', 'Use DBI_HOST', 'Don\'t set' ] ],
        #    [ 'login_port', "- Port",     [ 'Ask', 'Use DBI_PORT', 'Don\'t set' ] ],
        #    [ 'login_user', "- User",     [ 'Ask', 'Use DBI_USER', 'Don\'t set' ] ],
        #    [ 'login_pass', "- Password", [ 'Ask', 'Use DBI_PASS', 'Don\'t set' ] ],
        #],
        ##########################################################################################
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
            [ 'config_database', "- DB" ],
            [ 'config_insert',   "- Insert" ],
        ],
        config_output => [
            [ 'min_col_width', "- Colwidth" ],
            [ 'progress_bar',  "- ProgressBar" ],
            [ 'tab_width',     "- Tabwidth" ],
            [ 'undef',         "- Undef" ],
        ],
        config_menu => [
            [ '_menu_memory',  "- Menu Memory" ],
            [ '_table_expand', "- Table Expand" ],
            [ 'lock_stmt',     "- Lock" ],
            [ 'mouse',         "- Mouse Mode" ],
            [ 'sssc_mode',     "- Sssc Mode" ],
        ],
        config_sql => [
            [ 'max_rows',     "- Max Rows" ],
            [ 'metadata',     "- Metadata" ],
            [ 'operators',    "- Operators" ],
            [ '_parentheses', "- Parentheses" ],

        ],
        config_database => [
            [ '_db_defaults',  "- DB Settings" ],
            [ 'db_plugins',    "- DB Plugins" ],
        ],
        config_insert => [
            [ 'input_modes',       "- Input modes" ],
            [ 'csv_read',          "- CSV parse module" ],
            [ 'encoding_csv_file', "- CSV file encoding" ],
            [ 'sep_char',          "- csv sep_char" ],
            [ 'quote_char',        "- csv quote_char" ],
            [ 'escape_char',       "- csv escape_char" ],
            [ '_options_csv',      "- csv various" ],
            [ 'delim',             "- T::PW: \$delim" ],
            [ 'keep',              "- T::PW: \$keep" ],
            [ 'max_files',         "- File history" ],
        ],
    };
    ################################ 1.0 ##################################################
    #if ( $self->{info}{plguin_api_version} && $self->{info}{plguin_api_version} == 1.0 ) {
    #    push @{$menus->{config_database}}, [ '_db_connect',   "- DB Login Mode" ];
    #}
    #######################################################################################
    return $menus->{$group};
}


sub __config_insert {
    my ( $self, $write_to_file ) = @_;
    my $old_idx = 0;

    OPTION_INSERT: while ( 1 ) {
        my $group  = 'config_insert';
        my @pre    = ( undef, $self->{info}{_confirm} );
        my $menu   = $self->__menus( $group );
        my @real   = map( $_->[1], @$menu );
        # Choose
        my $idx = choose(
            [ @pre, @real ],
            { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx }
        );
        exit if ! defined $idx;
        my $name = $idx <= $#pre ? $pre[$idx] : $menu->[$idx - @pre][0];
        if ( ! defined $name ) {
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
        my $no_yes = [ 'NO', 'YES' ];
        if ( $name eq $self->{info}{_confirm} ) {
            if ( $self->{info}{write_config} ) {
                $self->__write_config_files() if $write_to_file;
                delete $self->{info}{write_config};
            }
            return;
        }
        elsif ( $name eq 'input_modes' ) {
                my $available = [ 'Cols', 'Rows', 'Multirow', 'File' ];
                $self->__opt_choose_a_list( $name, $available );
        }
        elsif ( $name eq 'csv_read' ) {
            my $list = [ 'Text::CSV', 'Text::ParseWords', 'Spreadsheet::Read' ];
            my $prompt = 'Module for parsing CSV files';
            $self->__opt_choose_index( $name, $prompt, $list );
        }
        elsif ( $name eq 'encoding_csv_file' ) {
            my $prompt = 'Encoding csv file';
            $self->__opt_readline( $name, $prompt );
        }
        elsif ( $name eq 'sep_char' ) {
            my $prompt = 'csv sep_char';
            $self->__opt_readline( $name, $prompt );
        }
        elsif ( $name eq 'quote_char' ) {
            my $prompt = 'csv quote_char';
            $self->__opt_readline( $name, $prompt );
        }
        elsif ( $name eq 'escape_char' ) {
            my $prompt = 'csv escape_char';
            $self->__opt_readline( $name, $prompt );
        }
        elsif ( $name eq '_options_csv' ) {
            my $sub_menu = $self->__multi_choose( $name );
            $self->__opt_choose_multi( $sub_menu );
        }
        elsif ( $name eq 'delim' ) {
            my $prompt = 'Text::ParseWords delimiter (regexp)';
            $self->__opt_readline( $name, $prompt );
        }
        elsif ( $name eq 'keep' ) {
            my $list = $no_yes;
            my $prompt = 'Text::ParseWords option $keep';
            $self->__opt_choose_index( $name, $prompt, $list );
        }
        elsif ( $name eq 'max_files' ) {
            my $digits = 3;
            my $prompt = 'Save the last x input file names';
            $self->__opt_number_range( $name, $prompt, $digits );
        }
        else { die "Unknown option: $name" }
    }
}


sub set_options {
    my ( $self ) = @_;
    my $group = 'main';
    my $backup_old_idx;
    my $old_idx = 0;

    GROUP: while ( 1 ) {
        my $menu = $self->__menus( $group );

        OPTION: while ( 1 ) {
            my $back =          $group eq 'main' ? $self->{info}{_quit}     : $self->{info}{_back};
            my @pre  = ( undef, $group eq 'main' ? $self->{info}{_continue} : $self->{info}{_confirm} );
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
            my $no_yes = [ 'NO', 'YES' ];
            if ( $name eq $self->{info}{_continue} ) {
                return $self->{opt};
            }
            elsif ( $name eq $self->{info}{_confirm} ) {
                if ( $self->{info}{write_config} ) {
                    $self->__write_config_files();
                    delete $self->{info}{write_config};
                }
                $old_idx = $backup_old_idx;
                $group = 'main';
                redo GROUP;
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
                $self->__opt_number_range( $name, $prompt, $digits );
            }
            elsif ( $name eq 'min_col_width' ) {
                my $digits = 3;
                my $prompt = 'Minimum Column width';
                $self->__opt_number_range( $name, $prompt, $digits );
            }
            elsif ( $name eq 'undef' ) {
                my $prompt = 'Print replacement for undefined table vales';
                $self->__opt_readline( $name, $prompt );
            }
            elsif ( $name eq 'progress_bar' ) {
                my $digits = 7;
                my $prompt = '"Threshold ProgressBar"';
                $self->__opt_number_range( $name, $prompt, $digits );
            }
            elsif ( $name eq 'max_rows' ) {
                my $digits = 7;
                my $prompt = '"Max rows"';
                $self->__opt_number_range( $name, $prompt, $digits );
            }
            elsif ( $name eq 'lock_stmt' ) {
                my $list = [ 'Lk0', 'Lk1' ];
                my $prompt = 'Keep statement';
                $self->__opt_choose_index( $name, $prompt, $list );
            }
            elsif ( $name eq 'metadata' ) {
                my $list = $no_yes;
                my $prompt = 'Enable Metadata';
                $self->__opt_choose_index( $name, $prompt, $list );
            }
            elsif ( $name eq '_parentheses' ) {
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $sub_menu );
            }
            ######################################### 1.0 ##########################
            #elsif ( $name eq '_db_connect' ) {
            #    my $sub_menu = $self->__multi_choose( $name );
            #    $self->__opt_choose_multi( $sub_menu );
            #}
            ########################################################################
            elsif ( $name eq '_db_defaults' ) {
                $self->database_setting();
            }
            elsif ( $name eq 'sssc_mode' ) {
                my $list = [ 'simple', 'compat' ];
                my $prompt = 'Sssc mode';
                $self->__opt_choose_index( $name, $prompt, $list );
            }
            elsif ( $name eq 'operators' ) {
                my $available = $self->{info}{avail_operators};
                $self->__opt_choose_a_list( $name, $available );
            }
            elsif ( $name eq 'db_plugins' ) {
                my %installed_db_driver;
                for my $dir ( @INC ) {
                    my $glob_pattern = catfile $dir, 'App', 'DBBrowser', 'DB', '*.pm';
                    map { $installed_db_driver{( fileparse $_, '.pm' )[0]}++ } glob $glob_pattern;
                }
                $self->__opt_choose_a_list( $name, [ sort keys %installed_db_driver ] );
            }
            elsif ( $name eq 'mouse' ) {
                my $max = 4;
                my $prompt = 'Mouse mode';
                $self->__opt_number( $name, $prompt, $max );
            }
            elsif ( $name eq '_menu_memory' ) {
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $sub_menu );
            }
            elsif ( $name eq '_table_expand' ) {
                my $sub_menu = $self->__multi_choose( $name );
                $self->__opt_choose_multi( $sub_menu );
            }
            else { die "Unknown option: $name" }
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
    my ( $self, $name, $prompt, $list ) = @_;
    my $yn = 0;
    my $current = $list->[$self->{opt}{$name}];
    # Choose
    my $idx = choose(
        [ undef, @$list ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', index => 1 }
    );
    return if ! defined $idx;
    return if $idx == 0;
    $idx--;
    $self->{opt}{$name} = $idx;
    $self->{info}{write_config}++;
    return;
}

sub __opt_choose_a_list {
    my ( $self, $name, $available, $index ) = @_;
    my $current = $self->{opt}{$name};
    # Choose_list
    my $list = choose_a_subset( $available, { current => $current, index => $index } );
    return if ! defined $list;
    return if ! @$list;
    $self->{opt}{$name} = $list;
    $self->{info}{write_config}++;
    return;
}

sub __opt_number {
    my ( $self, $name, $prompt, $max ) = @_;
    my $current = $self->{opt}{$name};
    # Choose
    my $choice = choose(
        [ undef, 0 .. $max ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', justify => 1 }
    );
    return if ! defined $choice;
    $self->{opt}{$name} = $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_number_range {
    my ( $self, $name, $prompt, $digits ) = @_;
    my $current = $self->{opt}{$name};
    $current = insert_sep( $current, $self->{opt}{thsd_sep} );
    # Choose_a_number
    my $choice = choose_a_number( $digits, { name => $prompt, current => $current } );
    return if ! defined $choice;
    $self->{opt}{$name} = $choice eq '--' ? undef : $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_readline {
    my ( $self, $name, $prompt ) = @_;
    my $current = $self->{opt}{$name};
    my $trs = Term::ReadLine::Simple->new();
    # Readline
    my $choice = $trs->readline( $prompt . ': ', { default => $current } );
    return if ! defined $choice;
    $self->{opt}{$name} = $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_choose_dirs {
    my ( $self, $name ) = @_;
    my $current = $self->{opt}{$name};
    # Choose_dirs
    my $dirs = choose_dirs( { mouse => $self->{opt}{mouse}, current => $current } );
    return if ! defined $dirs;
    return if ! @$dirs;
    $self->{opt}{$name} = $dirs;
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
            for my $name ( keys %{$self->{opt}{$db_driver}} ) {
                next if $name eq 'directories_sqlite';
                if ( ! defined $self->{opt}{$section}{$name} ) {
                    $self->{opt}{$section}{$name} = $self->{opt}{$db_plugin}{$name};
                }
            }
        }
        else {
            if ( @{$self->{opt}{db_plugins}} == 1 ) {
                $db_plugin = $self->{opt}{db_plugins}[0];
            }
            else {
                # Choose
                $db_plugin = choose(
                    [ undef, map( "- $_", @{$self->{opt}{db_plugins}} ) ],
                    { %{$self->{info}{lyt_3}} }
                );
                return if ! defined $db_plugin;
            }
            $db_plugin =~ s/^-\ //;
            $self->{info}{db_plugin} = $db_plugin;
            $section = $db_plugin;
        }
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );

############################################### 1.0 #######################################################
my $plugin_api_version = $obj_db->plugin_api_version();
if ( $plugin_api_version && $plugin_api_version == 1.0 ) {
    $self->database_setting_api_1_0( $db );
    return;
}
###########################################################################################################

        $db_driver = $obj_db->db_driver() if ! $db_driver;
        my @pre = ( undef, $self->{info}{_confirm} );
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
        my $orig = clone( $self->{opt} );
        my $old_idx_group = 0;

        GROUP: while ( 1 ) {
            my $choices = [ @pre, map( $_->[1], @groups ) ];
            # Choose
            my $idx_group = choose(
                $choices,
                { %{$self->{info}{lyt_3}}, prompt => "Your choice ($db_plugin):", index => 1, default => $old_idx_group }
            );
            if ( ! $idx_group ) {
                $self->{opt} = clone( $orig ) if $changed;
                next SECTION if ! $db && @{$self->{opt}{db_plugins}} > 1;
                last SECTION;
                #return;
            }
            if ( $self->{opt}{menus_config_memory} ) {
                if ( $old_idx_group == $idx_group ) {
                    $old_idx_group = 0;
                    next GROUP;
                }
                else {
                    $old_idx_group = $idx_group;
                }
            }
            if ( $idx_group == 1 ) {
                next SECTION if ! $db && @{$self->{opt}{db_plugins}} > 1;
                last SECTION;
                #return;
            }
            my $group = $groups[$idx_group-@pre][0];
            if ( $group eq 'login_mode' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $login_mode_key = $item->{name};
                    push @$sub_menu, [ $login_mode_key, '- ' . $item->{prompt}, $item->{avail_values} ];
                    if ( ! defined $self->{opt}{$section}{$login_mode_key} ) {
                        $self->{opt}{$section}{$login_mode_key} = 0;
                    }
                }
                $self->__db_opt_choose_multi( $section, $sub_menu );
                next GROUP;
            }
            elsif ( $group eq 'connect_attr' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    push @$sub_menu, [ $item->{name}, '- ' . $item->{name}, $item->{avail_values} ];
                    if ( ! defined $self->{opt}{$section}{$item->{name}} ) {
                        $self->{opt}{$section}{$item->{name}} = $item->{default_index};
                    }
                }
                $self->__db_opt_choose_multi( $section, $sub_menu );
                next GROUP;
            }
            elsif ( $group eq 'sqlite_dir' ) {
                my $name = 'directories_sqlite';
                my $prompt = 'Where to search for SQLite databases';
                $self->__db_opt_choose_dirs( $section, $name );
                next GROUP;
            }
            elsif ( $group eq 'login_data' ) {
                my $orig_db_option = clone( $self->{opt} ); #
                my $old_idx = 0;

                DB_OPTION: while ( 1 ) {
                    my $prompt;
                    if ( defined $db ) {
                        $prompt = 'DB: "' . ( $db_driver eq 'SQLite' ? basename( $db ) : $db ) . '"';
                    }
                    else {
                        $prompt = 'Plugin: ' . $db_plugin;
                        $prompt .= ' (' . $db_driver . ')' if $db_driver ne $db_plugin;
                    }
                    my $reset = '  RESET';
                    my @pre = ( undef, $self->{info}{_confirm} );
                    my @post = ( $reset );
                    my @real = map {
                            '- '
                        . $_->{prompt}
                        . ( $self->{opt}{$section}{$_->{name}} ? ": $self->{opt}{$section}{$_->{name}}" : "" )
                    } @{$items->{$group}};
                    my $choices = [ @pre, @real, @post ];
                    # Choose
                    my $idx = choose(
                        $choices,
                        { %{$self->{info}{lyt_3}}, index => 1, default => $old_idx, prompt => $prompt }
                    );
                    if ( ! defined $idx ) {
                        $self->{opt} = clone( $orig_db_option ) if $self->{info}{write_config};
                        next GROUP;
                    }
                    my $chosen = $choices->[$idx];
                    if ( ! defined $chosen ) {
                        $self->{opt} = clone( $orig_db_option ) if $self->{info}{write_config};
                        next GROUP;
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
                    if ( $chosen eq $reset ) {
                        my @names = map { $_->{name} } @{$items->{$group}};
                        if ( $db ) {
                            delete @{$self->{opt}{$section}}{@names};
                        }
                        else {
                            my @databases;
                            for my $section ( keys %{$self->{opt}} ) {
                                push @databases, $1 if $section =~ /^\Q$db_plugin\E_(.+)\z/;
                            }
                            my $choices = choose_a_subset( [ '*' . $db_plugin, sort @databases ], { p_new => 'Reset: ' } );
                            next DB_OPTION if ! $choices->[0];
                            for my $choice ( @$choices ) {
                                if ( $choice eq '*' . $db_plugin ) {
                                    for my $item ( @{$items->{$group}} ) {
                                        $self->{opt}{$db_plugin}{$item->{name}} = $item->{default_index};
                                    }
                                }
                                else {
                                    my $db = $choice;
                                    my $section = $db_plugin . '_' . $db;
                                    delete @{$self->{opt}{$section}}{@names};
                                }
                            }
                        }
                        $self->{info}{write_config}++;
                        next DB_OPTION;
                    }
                    if ( $chosen eq $self->{info}{_confirm} ) {
                        if ( $self->{info}{write_config} ) {
                            $self->__write_config_files();
                            delete $self->{info}{write_config};
                            $changed++;
                        }
                        next GROUP;
                    }
                    $idx -= @pre;
                    $self->__db_opt_readline( $section, $items->{$group}, $idx, scalar @pre );
                }
            }
        }
    }
    return $changed;
}


sub __db_opt_choose_dirs {
    my ( $self, $section, $name ) = @_;
    my $current = $self->{opt}{$section}{$name};
    # Choose_dirs
    my $dirs = choose_dirs( { mouse => $self->{opt}{mouse}, current => $current } );
    return if ! defined $dirs;
    return if ! @$dirs;
    $self->{opt}{$section}{$name} = $dirs;
    $self->{info}{write_config}++;
    return;
}



sub __db_opt_choose_multi {
    my ( $self, $section, $sub_menu ) = @_;
    my $changed = choose_multi( $sub_menu, $self->{opt}{$section} );
    return if ! $changed;
    $self->{info}{write_config}++;
}


sub __db_opt_readline {
    my ( $self, $section, $items, $idx, $nr_pre ) = @_;
    my $name    = $items->[$idx]{name};
    my $prompt  = "Plugin: $self->{info}{db_plugin}\n" . ( "\n" x ( $idx + $nr_pre ) ) . '- ' . $items->[$idx]{prompt};
    my $current = $self->{opt}{$section}{$name};
    my $trs = Term::ReadLine::Simple->new();
    # Readline
    my $choice = $trs->readline( $prompt . ': ', { default => $current } );
    return if ! defined $choice;
    $self->{opt}{$section}{$name} = $choice;
    $self->{info}{write_config}++;
    return;
}


sub __write_config_files {
    my ( $self ) = @_;
    my $regexp_db_plugins = join '|', map quotemeta, @{$self->defaults( qw( db_plugins ) )};
    my $fmt = $self->{info}{conf_file_fmt};
    my $tmp = {};
    for my $section ( sort keys %{$self->{opt}} ) {
        if ( $section =~ /^($regexp_db_plugins)(?:_(.+))?\z/ ) {
            die $section if ref( $self->{opt}{$section} ) ne 'HASH';
            my ( $db_plugin, $conf_sect ) = ( $1, $2 );
            $conf_sect = '*' . $db_plugin if ! defined $conf_sect;
            for my $name ( keys %{$self->{opt}{$section}} ) {
                next if $name =~ /^_/;
                $tmp->{$db_plugin}{$conf_sect}{$name} = $self->{opt}{$section}{$name};
            }
        }
        else {
            die $section if ref( $self->{opt}{$section} ) eq 'HASH';
            my $generic = $self->{info}{sect_generic};
            my $name = $section;
            next if $name =~ /^_/;
            $tmp->{$generic}{$name} = $self->{opt}{$name};
        }
    }
    my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    for my $name ( keys %$tmp ) {
        $auxil->write_json( sprintf( $fmt, $name ), $tmp->{$name}  );
    }
}


sub read_config_files {
    my ( $self ) = @_;
    $self->{opt} = $self->defaults();
    my $fmt = $self->{info}{conf_file_fmt};
    my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    for my $db_plugin ( @{$self->defaults( qw( db_plugins ) )} ) {
        my $file = sprintf( $fmt, $db_plugin );
        if ( -f $file && -s $file ) {
            my $tmp = $auxil->read_json( $file );
            for my $conf_sect ( keys %$tmp ) {
                my $section = $db_plugin . ( $conf_sect =~ /^\*(?:$db_plugin)\z/ ? '' : '_' . $conf_sect );
                for my $name ( keys %{$tmp->{$conf_sect}} ) {
                    $self->{opt}{$section}{$name} = $tmp->{$conf_sect}{$name}; # if exists $self->{opt}{$db_plugin}{$name};
                }
            }
        }
    }
    my $file =  sprintf( $fmt, $self->{info}{sect_generic} );
    if ( -f $file && -s $file ) {
        my $tmp = $auxil->read_json( $file );
        for my $name ( keys %$tmp ) {
            $self->{opt}{$name} = $tmp->{$name} if exists $self->{opt}{$name};
        }
    }
    return $self->{opt};
}

###################################################################### 1.0 ###############################################################################



sub database_setting_api_1_0 {
    my ( $self, $db ) = @_;
    my ( $db_driver, $db_plugin, $section );
    if ( defined $db ) {
        $db_plugin = $self->{info}{db_plugin};
        $db_driver = $self->{info}{db_driver};
        $section   = $db_plugin . '_' . $db;
        for my $key ( keys %{$self->{opt}{$db_driver}} ) {
            next if $key eq 'directories_sqlite';
            if ( ! defined $self->{opt}{$section}{$key} ) {
                $self->{opt}{$section}{$key} = $self->{opt}{$db_plugin}{$key};
            }
        }
    }
    else {
        if ( @{$self->{opt}{db_plugins}} == 1 ) {
            $db_plugin = $self->{opt}{db_plugins}[0];
        }
        else {
            # Choose
            $db_plugin = choose(
                [ undef, @{$self->{opt}{db_plugins}} ],
                { %{$self->{info}{lyt_1}} }
            );
            return if ! defined $db_plugin;
        }
        $self->{info}{db_plugin} = $db_plugin;
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        $db_driver = $obj_db->db_driver();
        $section = $db_plugin;
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
    if ( $db_driver ne 'SQLite' ) {
        unshift @{$menus->{$db_driver}}, ( [ 'host', "- Host" ], [ 'port', "- Port" ], [ 'user', "- User" ] );
    }
    push @{$menus->{$db_driver}}, [ 'binary_filter',      "- Binary Filter" ];
    push @{$menus->{$db_driver}}, [ 'directories_sqlite', "  Search directories" ] if ! $db && $db_driver eq 'SQLite';
    push @{$menus->{$db_driver}}, [ '_reset',             "  RESET" ];
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
                my @databases;
                for my $section ( keys %{$self->{opt}} ) {
                    push @databases, $1 if $section =~ /^\Q$db_driver\E_(.+)\z/;
                }
                my $choices = choose_a_subset( [ '*' . $db_driver, sort @databases ], { p_new => 'Reset: ' } );
                next DB_OPTION if ! $choices->[0];
                for my $item ( @$choices ) {
                    if ( $item eq '*' . $db_driver ) {
                        $self->{opt}{$db_driver} = $self->defaults( $db_driver );
                    }
                    else {
                        my $db = $item;
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
            elsif ( $key eq 'directories_sqlite' ) {
                $self->__old_db_opt_choose_dirs( $section, $key, $prompt );
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
                $self->__old_db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'host' ) {
                my $prompt = 'Host';
                $self->__old_db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'port' ) {
                my $prompt = 'Port';
                $self->__old_db_opt_readline( $section, $key, $prompt );
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
                $self->__old_db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'host' ) {
                my $prompt = 'Host';
                $self->__old_db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'port' ) {
                my $prompt = 'Port';
                $self->__old_db_opt_readline( $section, $key, $prompt );
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

sub __old_db_opt_choose_dirs {
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

sub __old_db_opt_readline {
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




1;


__END__

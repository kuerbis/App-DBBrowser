package # hide from PAUSE
App::DBBrowser::Opt;

use warnings;
use strict;
use 5.008003;

use File::Basename        qw( fileparse );
use File::Spec::Functions qw( catfile );
use FindBin               qw( $RealBin $RealScript );
#use Pod::Usage            qw( pod2usage ); # required

use Term::Choose       qw( choose );
use Term::Choose::Util qw( insert_sep print_hash choose_a_number choose_a_subset settings_menu choose_a_dir );
use Term::Form         qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::OptDB;


sub new {
    my ( $class, $info, $options ) = @_;
    bless {
        i => $info,
        o => $options,
        avail_operators => [
            "REGEXP", "REGEXP_i", "NOT REGEXP", "NOT REGEXP_i", "LIKE", "NOT LIKE", "IS NULL", "IS NOT NULL",
            "IN", "NOT IN", "BETWEEN", "NOT BETWEEN", " = ", " != ", " <> ", " < ", " > ", " >= ", " <= ",
            " = col", " != col", " <> col", " < col", " > col", " >= col", " <= col",
            "LIKE %col%", "NOT LIKE %col%",  "LIKE col%", "NOT LIKE col%", "LIKE %col", "NOT LIKE %col" ],
            # "LIKE col", "NOT LIKE col"
        }, $class;
}


sub defaults {
    my ( $sf, $section, $key ) = @_;
    my $defaults = {
        G => {
            enable_create_table  => 0,
            enable_delete        => 0,
            enable_drop_table    => 0,
            enable_insert_into   => 0,
            enable_update        => 0,
            file_find_warnings   => 0,
            info_expand          => 0,
            max_rows             => 200_000,
            menu_memory          => 0,
            meta                 => 0,
            operators            => [ "REGEXP", "REGEXP_i", " = ", " != ", " < ", " > ", "IS NULL", "IS NOT NULL" ],
            parentheses          => 0,
            plugins              => [ 'SQLite', 'mysql', 'Pg' ],
            qualified_table_name => 0,
            quote_identifiers    => 1,
            thsd_sep             => ',',
        },
        alias => {
            aggregate  => 0,
            functions  => 0,
            join       => 0,
            union      => 0,
            subqueries => 0,
        },
        extend => {
            select   => 0,
            group_by => 0,
            having   => 0,
            order_by => 0,
            join     => 0,
            set      => 0,
            table    => 0,
            union    => 0,
            where    => 0,
        },
        table => {
            binary_filter     => 0,
            binary_string     => 'BNRY',
            codepage_mapping  => 0, # not an option, always 0
            color             => 0,
            decimal_separator => '.',
            grid              => 1,
            keep_header       => 1,
            min_col_width     => 30,
            mouse             => 0,
            progress_bar      => 40_000,
            squash_spaces     => 0,
            tab_width         => 2,
            table_expand      => 1,
            undef             => '',
        },
        insert => {
            copy_parse_mode => 1,
            file_encoding   => 'UTF-8',
            file_parse_mode => 0,
            max_files       => 4,
        },
        create => {
            autoincrement_col_name => 'Id',
            data_type_guessing     => 1,
        },
        split => {
            record_sep    => '\n',
            record_l_trim => '',
            record_r_trim => '',
            field_sep     => ',',
            field_l_trim  => '\s+',
            field_r_trim  => '\s+',
        },
        csv => {
            allow_loose_escapes => 0,
            allow_loose_quotes  => 0,
            allow_whitespace    => 0,
            auto_diag           => 1,
            blank_is_undef      => 1,
            binary              => 1,
            empty_is_undef      => 0,
            eol                 => '',
            escape_char         => '"',
            quote_char          => '"',
            sep_char            => ',',
        }
    };
    return $defaults                   if ! $section;
    return $defaults->{$section}       if ! $key;
    return $defaults->{$section}{$key};
}


sub _groups {
    my $groups = [
        { name => 'group_help',     text => "  HELP"   },
        { name => 'group_path',     text => "  Path"   },
        { name => 'group_database', text => "- DB"     },
        { name => 'group_menu',     text => "- Menu"   },
        { name => 'group_sql',      text => "- SQL",   },
        { name => 'group_output',   text => "- Output" },
        { name => 'group_insert',   text => "- Get Data" }, #
    ];
    return $groups;
}


sub _options {
    my ( $group ) = @_;
    my $groups = {
        group_help => [
            { name => 'help', text => '', section => '' }
        ],
        group_path => [
            { name => 'path', text => '', section => '' }
        ],
        group_database => [
            { name => 'plugins',      text => "- DB Plugins",  section => 'G' },
            { name => '_db_defaults', text => "- DB Settings", section => '' },
        ],
        group_menu => [
            { name => '_menu_memory',  text => "- Menu Memory", section => 'G'     },
            { name => '_table_expand', text => "- Table",       section => 'table' },
            { name => '_info_expand',  text => "- Info",        section => 'G'     }, #
            { name => '_mouse',        text => "- Mouse Mode",  section => 'table' },
        ],
        group_sql => [
            { name => 'max_rows',                text => "- Max Rows",       section => 'G' },
            { name => '_meta',                    text => "- Metadata",       section => 'G' },
            { name => 'operators',               text => "- Operators",      section => 'G' },
            { name => '_alias',                  text => "- Alias",          section => 'alias' },
            { name => '_extended_cols',          text => "- Extentions",     section => 'extend' },
            { name => '_sql_identifiers',        text => "- Identifiers",    section => 'G' },
            { name => '_parentheses',            text => "- Parentheses",    section => 'G' },
            { name => '_write_access',           text => "- Write access",   section => 'G' },       #
            { name => '_autoincrement_col_name', text => "- Auto increment", section => 'create' },  #
            { name => '_data_type_guessing',     text => "- Data types",     section => 'create' },  #
        ],
        group_output => [
            { name => 'min_col_width',       text => "- Colwidth",      section => 'table' },
            { name => 'progress_bar',        text => "- ProgressBar",   section => 'table' },
            { name => 'tab_width',           text => "- Tabwidth",      section => 'table' },
            { name => '_grid',               text => "- Grid",          section => 'table' },
            { name => '_color',              text => "- Color",         section => 'table' },
            { name => '_keep_header',        text => "- Keep Header",   section => 'table' },
            { name => '_undef',              text => "- Undef",         section => 'table' },
            { name => '_binary_filter',      text => "- Binary filter", section => 'table' },
            { name => '_squash_spaces',      text => "- Squash spaces", section => 'table' },
            { name => '_decimal_separator',  text => "- Decimal sep",   section => 'table' },
            { name => '_file_find_warnings', text => "- Warnings",      section => 'G' },
        ],
        group_insert => [
            { name => '_split_config',  text => "- Config 'split'   ", section => 'split'  },
            { name => '_csv_char',      text => "- Config Text-CSV a", section => 'csv'    },
            { name => '_csv_options',   text => "- Config Text-CSV b", section => 'csv'    },
            { name => '_parse_file',    text => "- Parse File",        section => 'insert' },
            { name => '_parse_copy',    text => "- Parse C & P",       section => 'insert' },
            { name => '_file_encoding', text => "- File Encoding",     section => 'insert' },
            { name => 'max_files',      text => "- File History",      section => 'insert' },
        ],
    };
    return $groups->{$group};
}


sub set_options {
    my ( $sf, $arg_groups, $arg_options ) = @_;
    if ( ! $sf->{o} || ! %{$sf->{o}} ) {
        $sf->{o} = $sf->read_config_files();
    }
    my $groups;
    if ( $arg_groups ) {
        $groups = [ @$arg_groups ];
    }
    else {
        $groups = _groups();
    }
    my $grp_old_idx = 0;

    GROUP: while( 1 ) {
        my $group;
        if ( @$groups == 1 ) {
            $group = $groups->[0]{name};
        }
        else {
            my @pre  = ( undef, $sf->{i}{_continue} );
            my $choices = [ @pre, map( $_->{text}, @$groups ) ];
            # Choose
            $ENV{TC_RESET_AUTO_UP} = 0;
            my $grp_idx = choose(
                $choices,
                { %{$sf->{i}{lyt_v_clear}}, index => 1, default => $grp_old_idx, undef => $sf->{i}{_quit} }
            );
            if ( ! $grp_idx ) {
                if ( $sf->{write_config} ) {
                    $sf->__write_config_files();
                    delete $sf->{write_config};
                }
                exit();
            }
            if ( $sf->{o}{G}{menu_memory} ) {
                if ( $grp_old_idx == $grp_idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                    $grp_old_idx = 0;
                    next GROUP;
                }
                $grp_old_idx = $grp_idx;
            }
            else {
                if ( $grp_old_idx != 0 ) {
                    $grp_old_idx = 0;
                    next GROUP;
                }
            }
            delete $ENV{TC_RESET_AUTO_UP};
            if ( $choices->[$grp_idx] eq $sf->{i}{_continue} ) {
                if ( $sf->{write_config} ) {
                    $sf->__write_config_files();
                    delete $sf->{write_config};
                }
                return $sf->{o};
            }
            $group = $groups->[$grp_idx-@pre]{name};
        };
        my $options;
        if ( $arg_options ) {
            $options = [ @$arg_options ];
        }
        else {
            $options = _options( $group );
        }
        my $opt_old_idx = 0;

        OPTION: while ( 1 ) {
            my ( $section, $opt );
            if ( @$options == 1 ) {
                $section = $options->[0]{section};
                $opt     = $options->[0]{name};
            }
            else {
                my @pre  = ( undef );
                my $choices = [ @pre, map( $_->{text}, @$options ) ];
                # Choose
                $ENV{TC_RESET_AUTO_UP} = 0;
                my $opt_idx = choose(
                    $choices,
                    { %{$sf->{i}{lyt_v_clear}}, index => 1, default => $opt_old_idx, undef => '  <=' }
                );
                if ( ! $opt_idx ) {
                    if ( @$groups == 1 ) {
                        if ( $sf->{write_config} ) {
                            $sf->__write_config_files();
                            delete $sf->{write_config};
                        }
                        return $sf->{o};
                    }
                    next GROUP;
                }
                if ( $sf->{o}{G}{menu_memory} ) {
                    if ( $opt_old_idx == $opt_idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                        $opt_old_idx = 0;
                        next OPTION;
                    }
                    $opt_old_idx = $opt_idx;
                }
                else {
                    if ( $opt_old_idx != 0 ) {
                        $opt_old_idx = 0;
                        next OPTION;
                    }
                }
                delete $ENV{TC_RESET_AUTO_UP};
                $section = $options->[$opt_idx-@pre]{section};
                $opt     = $options->[$opt_idx-@pre]{name};
            }
            my $no_yes  = [ 'NO', 'YES' ];
            if ( $opt eq 'help' ) {
                require Pod::Usage;  # ctrl-c
                Pod::Usage::pod2usage( { -exitval => 'NOEXIT', -verbose => 2 } );
            }
            elsif ( $opt eq 'path' ) {
                my $version = 'version';
                my $bin     = '  bin  ';
                my $app_dir = 'app-dir';
                my $path = {
                    $version => $main::VERSION,
                    $bin     => catfile( $RealBin, $RealScript ),
                    $app_dir => $sf->{i}{app_dir},
                };
                my $opts = [ $version, $bin, $app_dir ];
                print_hash( $path, { keys => $opts, preface => ' Close with ENTER', clear_screen => 1 } );
            }
            elsif ( $opt eq '_db_defaults' ) {
                my $odb = App::DBBrowser::OptDB->new( $sf->{i}, $sf->{o} );
                $odb->database_setting();
            }
            elsif ( $opt eq 'plugins' ) {
                my %installed_driver;
                for my $dir ( @INC ) {
                    my $glob_pattern = catfile $dir, 'App', 'DBBrowser', 'DB', '*.pm';
                    map { $installed_driver{( fileparse $_, '.pm' )[0]}++ } glob $glob_pattern;
                }
                my $prompt = 'Choose DB plugins';
                $sf->__choose_a_subset_wrap( $section, $opt, [ sort keys %installed_driver ], $prompt );
            }
            elsif ( $opt eq 'operators' ) {
                my $prompt = 'Choose operators';
                $sf->__choose_a_subset_wrap( $section, $opt, $sf->{avail_operators}, $prompt );
            }

            elsif ( $opt eq '_file_encoding' ) {
                my $items = [
                    { name => 'file_encoding', prompt => "file_encoding" },
                ];
                my $prompt = 'Encoding CSV files';
                $sf->__group_readline( $section, $items, $prompt );
            }
            elsif ( $opt eq '_csv_char' ) {
                my $items = [
                    { name => 'sep_char',    prompt => "sep_char   " },
                    { name => 'quote_char',  prompt => "quote_char " },
                    { name => 'escape_char', prompt => "escape_char" },
                    { name => 'eol',         prompt => "eol        " },
                ];
                my $prompt = 'Text::CSV a';
                $sf->__group_readline( $section, $items, $prompt );
            }
            elsif ( $opt eq '_split_config' ) {
                my $items = [
                    { name => 'field_sep',     prompt => "Field separator  " },
                    { name => 'field_l_trim',  prompt => "Trim field left  " },
                    { name => 'field_r_trim',  prompt => "Trim field right " },
                    { name => 'record_sep',    prompt => "Record separator " },
                    { name => 'record_l_trim', prompt => "Trim record left " },
                    { name => 'record_r_trim', prompt => "Trim record right" },

                ];
                my $prompt = 'Config \'split\' mode';
                $sf->__group_readline( $section, $items, $prompt );
            }
            elsif ( $opt eq '_undef' ) {
                my $items = [
                    { name => 'undef', prompt => "undef" },
                ];
                my $prompt = 'Print replacement for undefined table values.';
                $sf->__group_readline( $section, $items, $prompt );
            }
            elsif ( $opt eq '_decimal_separator' ) {
                my $items = [
                    { name => 'decimal_separator', prompt => "Decimal separator" },
                ];
                my $prompt = 'Set the decimal separator.';
                $sf->__group_readline( $section, $items, $prompt );
            }
            elsif ( $opt eq '_autoincrement_col_name' ) {
                my $items = [
                    { name => 'autoincrement_col_name', prompt => "AI column name" },
                ];
                my $prompt = 'Default auto increment column name';
                $sf->__group_readline( $section, $items, $prompt );
            }
            elsif ( $opt eq 'max_files' ) {
                my $digits = 2;
                my $prompt = 'Max file history ';
                $sf->__choose_a_number_wrap( $section, $opt, $prompt, $digits, 1 );
            }
            elsif ( $opt eq 'tab_width' ) {
                my $digits = 3;
                my $prompt = 'Set the tab width ';
                $sf->__choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }
            elsif ( $opt eq 'min_col_width' ) {
                my $digits = 3;
                my $prompt = 'Set the minimum column width ';
                $sf->__choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }
            elsif ( $opt eq 'progress_bar' ) {
                my $digits = 7;
                my $prompt = 'Set the threshold for the progress bar ';
                $sf->__choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }

            elsif ( $opt eq 'max_rows' ) {
                my $digits = 7;
                my $prompt = 'Set the SQL auto LIMIT ';
                $sf->__choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }
            elsif ( $opt eq '_parse_file' ) {
                my $prompt = 'Parsing "File"';
                my $sub_menu = [
                    [ 'file_parse_mode', "- Use:", [ 'Text::CSV', 'split', 'Spreadsheet::Read' ] ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_parse_copy' ) {
                my $prompt = 'Parsing "Copy & Paste"';
                my $sub_menu = [
                    [ 'copy_parse_mode', "- Use:", [ 'Text::CSV', 'split', 'Spreadsheet::Read' ] ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_csv_options' ) {
                my $prompt = 'Text::CSV b';
                my $sub_menu = [
                    [ 'allow_loose_escapes', "- allow_loose_escapes", $no_yes ],
                    [ 'allow_loose_quotes',  "- allow_loose_quotes",  $no_yes ],
                    [ 'allow_whitespace',    "- allow_whitespace",    $no_yes ],
                    [ 'blank_is_undef',      "- blank_is_undef",      $no_yes ],
                    [ 'binary',              "- binary",              $no_yes ],
                    [ 'empty_is_undef',      "- empty_is_undef",      $no_yes ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_grid' ) {
                my $prompt = '"Grid"';
                my $sub_menu = [
                    [ 'grid', "- Grid", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_keep_header' ) {
                my $prompt = '"Header each Page"';
                my $sub_menu = [
                    [ 'keep_header', "- Keep header", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_color' ) {
                my $prompt = '"ANSI color escapes"';
                my $sub_menu = [
                    [ 'color', "- ANSI color escapes", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_binary_filter' ) {
                my $prompt = 'Print "BNRY" instead of binary data';
                my $sub_menu = [
                    [ 'binary_filter', "- Binary filter", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_squash_spaces' ) {
                my $prompt = '"Remove leading and trailing spaces and squash consecutive spaces"';
                my $sub_menu = [
                    [ 'squash_spaces', "- Squash spaces", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_file_find_warnings' ) {
                my $prompt = '"SQLite database search"';
                my $sub_menu = [
                    [ 'file_find_warnings', "- Enable \"File::Find\" warnings", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_meta' ) {
                my $prompt = 'DB/schemas/tables ';
                my $list = $no_yes;
                my $sub_menu = [
                    [ 'meta', "- Add metadata", $list ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_alias' ) {
                my $prompt = 'Alias for:';
                my $sub_menu = [
                    [ 'aggregate',  "- Aggregate",  $no_yes ], # s - p
                    [ 'functions',  "- Functions",  $no_yes ],
                    [ 'join',       "- Join",       $no_yes ],
                    [ 'subqueries', "- Subqueries", $no_yes ],
                    [ 'union',      "- Union",      $no_yes ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_extended_cols' ) {
                my $sub_menu = [
                    [ 'select',   "- Extend SELECT",   [ 'None', 'Func', 'SQ',       'Func/SQ'    ] ],
                    [ 'where',    "- Extend WHERE",    [ 'None', 'Func', 'SQ',       'Func/SQ'    ] ],
                    [ 'group_by', "- Extend GROUB BY", [ 'None', 'Func', 'SQ',       'Func/SQ'    ] ],
                    [ 'having',   "- Extend HAVING",   [ 'None', 'Func', 'SQ',       'Func/SQ'    ] ],
                    [ 'order_by', "- Extend ORDER BY", [ 'None', 'Func', 'SQ',       'Func/SQ'    ] ],
                    [ 'set',      "- Extend SET",      [ 'None', 'Func', 'SQ', '=N', 'Func/SQ/=N' ] ], #
                    [ 'table',    "- Extend Table",    [ 'None',         'SQ'                     ] ],
                    [ 'join',     "- Extend Join",     [ 'None',         'SQ'                     ] ],
                    [ 'union',    "- Extend Union",    [ 'None',         'SQ'                     ] ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu );
            }
            elsif ( $opt eq '_parentheses' ) {
                my $prompt = 'Parentheses in WHERE/HAVING';
                my $sub_menu = [
                    [ 'parentheses', "- Enable parentheses", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_alias' ) {
                my $prompt = 'For complex columns:';
                my $sub_menu = [
                    [ 'alias', "- Add alias", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_sql_identifiers' ) {
                my $prompt = 'Choose: ';
                my $sub_menu = [
                    [ 'qualified_table_name', "- Qualified table names", $no_yes ],
                    [ 'quote_identifiers',    "- Quote identifiers",     $no_yes ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_write_access' ) {
                my $prompt = 'Write access: ';
                my $sub_menu = [
                    [ 'enable_insert_into',  "- Insert records", $no_yes ],
                    [ 'enable_update',       "- Update records", $no_yes ],
                    [ 'enable_delete',       "- Delete records", $no_yes ],
                    [ 'enable_create_table', "- Create table",   $no_yes ],
                    [ 'enable_drop_table',   "- Drop   table",   $no_yes ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_mouse' ) {
                my $prompt = 'Choose: ';
                my $list = [ 0, 1, 2, 3, 4 ];
                my $sub_menu = [
                    [ 'mouse', "- Mouse mode", $list ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_menu_memory' ) {
                my $prompt = 'Choose: ';
                my $sub_menu = [
                    [ 'menu_memory', "- Menu memory", $no_yes ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_table_expand' ) {
                my $prompt = 'Choose: ';
                my $sub_menu = [
                    [ 'table_expand', "- Expand table rows",   [ 'NO', 'YES - fast back', 'YES' ] ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_info_expand' ) {
                my $prompt = 'Choose: ';
                my $sub_menu = [
                    [ 'info_expand', "- Expand info-table rows",   [ 'NO', 'YES - fast back', 'YES' ] ],
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            elsif ( $opt eq '_data_type_guessing' ) {
                my $prompt = 'Data type guessing';
                my $sub_menu = [
                    [ 'data_type_guessing', "- Enable data type guessing", $no_yes ]
                ];
                $sf->__settings_menu_wrap( $section, $sub_menu, $prompt );
            }
            else {
                die "Unknown option: $opt";
            }
            if ( @$options == 1 ) {
                if ( @$groups == 1 ) {
                    if ( $sf->{write_config} ) {
                        $sf->__write_config_files();
                        delete $sf->{write_config};
                    }
                    return $sf->{o};
                }
                else {
                    next GROUP;
                }
            }
        }
    }
}


sub __settings_menu_wrap {
    my ( $sf, $section, $sub_menu, $prompt ) = @_;
    my $changed = settings_menu( $sub_menu, $sf->{o}{$section}, { prompt => $prompt, mouse => $sf->{o}{table}{mouse} } );
    return if ! $changed;
    $sf->{write_config}++;
}


sub __choose_a_subset_wrap {
    my ( $sf, $section, $opt, $available, $prompt ) = @_;
    my $current = $sf->{o}{$section}{$opt};
    # Choose_list
    my $info = 'Cur: ' . join( ', ', @$current );
    my $name = 'New: ';
    my $list = choose_a_subset(
        $available,
        { info => $info, name => $name, prompt => $prompt, prefix => '- ', index => 0, remove_chosen => 1,
          clear_screen => 1, mouse => $sf->{o}{table}{mouse}, back => '  BACK', confirm => '  CONFIRM' }
    );
    return if ! defined $list;
    return if ! @$list;
    $sf->{o}{$section}{$opt} = $list;
    $sf->{write_config}++;
    return;
}


sub __choose_a_number_wrap {
    my ( $sf, $section, $opt, $prompt, $digits, $small_first ) = @_;
    my $current = $sf->{o}{$section}{$opt};
    my $w = $digits + int( ( $digits - 1 ) / 3 ) * length $sf->{o}{G}{thsd_sep};
    my $info = 'Cur: ' . sprintf( "%*s", $w, insert_sep( $current, $sf->{o}{G}{thsd_sep} ) );
    my $name = 'New: ';
    #$info = $prompt . "\n" . $info;
    # Choose_a_number
    my $choice = choose_a_number(
        $digits, { prompt => $prompt, name => $name, info => $info, mouse => $sf->{o}{table}{mouse},
                   clear_screen => 1, small_on_top => $small_first }
    );
    return if ! defined $choice;
    $sf->{o}{$section}{$opt} = $choice;
    $sf->{write_config}++;
    return;
}


sub __group_readline {
    my ( $sf, $section, $items, $prompt ) = @_;
    my $list = [ map {
        [
            exists $_->{prompt} ? $_->{prompt} : $_->{name},
            $sf->{o}{$section}{$_->{name}}
        ]
    } @{$items} ];
    my $trs = Term::Form->new();
    my $new_list = $trs->fill_form(
        $list,
        { prompt => $prompt, auto_up => 2, confirm => $sf->{i}{confirm}, back => $sf->{i}{back} }
    );
    if ( $new_list ) {
        for my $i ( 0 .. $#$items ) {
            $sf->{o}{$section}{$items->[$i]{name}} = $new_list->[$i][1];
        }
        $sf->{write_config}++;
    }
}


sub __choose_a_dir_wrap {
    my ( $sf, $section, $opt ) = @_;
    my $info;
    if ( defined $sf->{o}{$section}{$opt} ) {
        $info = '<< ' . $sf->{o}{$section}{$opt};
    }
    # Choose_a_dir
    my $dir = choose_a_dir( { mouse => $sf->{o}{table}{mouse}, info => $info, name => 'OK ' } );
    return if ! length $dir;
    $sf->{o}{$section}{$opt} = $dir;
    $sf->{write_config}++;
    return;
}


sub __write_config_files {
    my ( $sf ) = @_;
    my $tmp = {};
    for my $section ( keys %{$sf->{o}} ) {
        for my $opt ( keys %{$sf->{o}{$section}} ) {
            $tmp->{$section}{$opt} = $sf->{o}{$section}{$opt};
        }
    }
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, {} );
    my $file_name = $sf->{i}{file_settings};
    $ax->write_json( $file_name, $tmp  );
}


sub read_config_files {
    my ( $sf ) = @_;
    my $o = $sf->defaults();
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, {} );
    my $file_name = $sf->{i}{file_settings};
    if ( -f $file_name && -s $file_name ) {
        my $tmp = $ax->read_json( $file_name );
        for my $section ( keys %$tmp ) {
            for my $opt ( keys %{$tmp->{$section}} ) {
                $o->{$section}{$opt} = $tmp->{$section}{$opt} if exists $o->{$section}{$opt};
            }
        }
    }
    return $o;
}




1;


__END__

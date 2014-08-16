package # hide from PAUSE
App::DBBrowser::Browser;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.039';

use Encode                qw( decode );
use File::Basename        qw( basename );
use File::Spec::Functions qw( catfile catdir );
use Getopt::Long          qw( GetOptions );

use Clone                qw( clone );
use Encode::Locale       qw( decode_argv );
use File::HomeDir        qw();
use List::MoreUtils      qw( any first_index );
use Term::Choose         qw();
use Term::Choose::Util   qw( choose_a_number insert_sep term_size );
use Term::ReadLine::Tiny qw();
use Term::TablePrint     qw( print_table );
use Text::LineFold       qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::DBBrowser::Opt;
use App::DBBrowser::DB;

BEGIN {
    decode_argv(); # not at the end of the BEGIN block if less than perl 5.16
    1;
}


sub CLEAR_SCREEN () { "\e[1;1H\e[0J" }


sub new {
    my ( $class ) = @_;

    my $info = {
        lyt_1      => {                      layout => 1, order => 0, justify => 2, clear_screen => 1, mouse => 0, undef => '<<'     },
        lyt_stmt_h => { prompt => 'Choose:', layout => 1, order => 0, justify => 2, clear_screen => 0, mouse => 0, undef => '<<'     },
        lyt_3      => {                      layout => 3,             justify => 0, clear_screen => 1, mouse => 0, undef => '  BACK' },
        lyt_stmt_v => { prompt => 'Choose:', layout => 3,             justify => 0, clear_screen => 0, mouse => 0, undef => '  BACK' },
        lyt_stop   => {                                                             clear_screen => 0, mouse => 0                    },
        back      => 'BACK',
        confirm   => 'CONFIRM',
        ok        => '- OK -',
        _exit     => '  EXIT',
        _help     => '  HELP',
        _back     => '  BACK',
        _confirm  => '  CONFIRM',
        _continue => '  CONTINUE',
        _info     => '  INFO',
        _reset    => '  RESET',
        line_fold         => { Charset=> 'utf8', OutputCharset => '_UNICODE_', Urgent => 'FORCE' },
        sect_generic      => 'Generic',
        stmt_init_tab     => 4,
        tbl_info_width    => 140,
        avail_aggregate   => [ "AVG(X)", "COUNT(X)", "COUNT(*)", "MAX(X)", "MIN(X)", "SUM(X)" ],
        cached            => '',
        avail_operators   => [ "REGEXP", "NOT REGEXP", "LIKE", "NOT LIKE", "IS NULL", "IS NOT NULL", "IN", "NOT IN",
                            "BETWEEN", "NOT BETWEEN", " = ", " != ", " <> ", " < ", " > ", " >= ", " <= ", "LIKE col",
                            "NOT LIKE col", "LIKE %col%", "NOT LIKE %col%", " = col", " != col", " <> col", " < col",
                            " > col", " >= col", " <= col" ], # "LIKE col%", "NOT LIKE col%", "LIKE %col", "NOT LIKE %col"
        avail_db_drivers  => [ 'SQLite', 'mysql', 'Pg' ],
        hidd_func_pr      => { Epoch_to_Date => 'DATE', Truncate => 'TRUNC', Epoch_to_DateTime => 'DATETIME',
                               Bit_Length => 'BIT_LENGTH', Char_Length => 'CHAR_LENGTH' },
        keys_hidd_func_pr => [ qw( Epoch_to_Date Bit_Length Truncate Char_Length Epoch_to_DateTime ) ],
        connect_opt_pre   => {  SQLite => 'sqlite_', mysql => 'mysql_', Pg => 'pg_' },
    };

    return bless { info => $info }, $class;
}


sub __init {
    my ( $self ) = @_;
    my $home = decode( 'locale', File::HomeDir->my_home() );
    if ( ! $home ) {
        say "'File::HomeDir->my_home()' could not find the home directory!";
        say "A home directory is needed to be able to use 'db-browser'";
        exit;
    }
    my $my_data = decode( 'locale', File::HomeDir->my_data() );
    my $app_dir = $my_data ? catdir( $my_data, 'db_browser_conf' ) : catdir( $home, '.db_browser_conf' );
    mkdir $app_dir or die $! if ! -d $app_dir;
    $self->{info}{app_dir}       = $app_dir;
    $self->{info}{conf_file_fmt} = catfile $app_dir, 'config_%s.json';
    $self->{info}{db_cache_file} = catfile $app_dir, 'cache_db_search.json';

    if ( ! eval {
        my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
        $self->{opt} = $obj_opt->read_config_files();
        my $help;
        GetOptions (
            'h|?|help' => \$help,
            's|search' => \$self->{info}{sqlite_search},
        );
        if ( $help ) {
            if ( $self->{opt}{mouse} ) {
                for my $key ( keys %{$self->{info}} ) {
                    next if $key !~ /^lyt_/;
                    $self->{info}{$key}{mouse} = $self->{opt}{mouse};
                }
            }
            $self->{opt} = $obj_opt->set_options();
            if ( defined $self->{opt}{mouse} ) {
                for my $key ( keys %{$self->{info}} ) {
                    next if $key !~ /^lyt_/;
                    $self->{info}{$key}{mouse} = $self->{opt}{mouse};
                }
            }
        }
        1 }
    ) {
        say 'Configfile/Options:';
        $self->__print_error_message( $@ );
        my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
        $self->{opt} = $obj_opt->defaults();
        while ( $ARGV[0] =~ /^-/ ) {
            my $arg = shift @ARGV;
            last if $arg eq '--';
        }
    }
    if ( $self->{opt}{mouse} ) {
        for my $key ( keys %{$self->{info}} ) {
            next if $key !~ /^lyt_/;
            $self->{info}{$key}{mouse} = $self->{opt}{mouse};
        }
    }
    $self->{info}{ok} = '<OK>' if $self->{opt}{sssc_mode};
    $self->{info}{argv} = @ARGV ? 1 : 0;
    $self->{info}{sqlite_dirs} = @ARGV ? \@ARGV : $self->{opt}{SQLite}{dirs_sqlite_search} // [ $home ];
}


sub run {
    my ( $self ) = @_;
    $self->__init();
    my $lyt_3 = Term::Choose->new( $self->{info}{lyt_3} );
    my $db_driver;

    DB_DRIVER: while ( 1 ) {

        if ( $self->{info}{sqlite_search} || $self->{info}{argv} ) {
            $db_driver = 'SQLite';
            $self->{info}{argv} = 0;
        }
        else {
            if ( @{$self->{opt}{db_drivers}} == 1 ) {
                $self->{info}{one_db_driver} = 1;
                $db_driver = $self->{opt}{db_drivers}[0];
            }
            else {
                $self->{info}{one_db_driver} = 0;
                # Choose
                $db_driver = $lyt_3->choose(
                    [ undef, @{$self->{opt}{db_drivers}} ],
                    { %{$self->{info}{lyt_1}}, prompt => 'Database Driver: ', undef => 'Quit' }
                );
                last DB_DRIVER if ! defined $db_driver;
            }
        }
        $self->{info}{db_driver} = $db_driver;

        $self->{info}{cached} = '';
        my $databases = [];
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        if ( ! eval {
            my $db = $obj_db->info_database();
            my $dbh = $obj_db->get_db_handle( $db );
            if ( $db_driver eq 'SQLite' ) {
                $databases = $self->__available_databases_cached( $dbh );
            }
            else {
                $databases = $obj_db->available_databases( $dbh );
            }
            1 }
        ) {
            say 'Available databases:';
            delete $self->{info}{login}{$db_driver};
            $self->__print_error_message( $@ );
            next DB_DRIVER;
        }
        if ( ! @$databases ) {
            $self->__print_error_message( "no $db_driver-databases found\n" );
            exit if @{$self->{opt}{db_drivers}} == 1;
            next DB_DRIVER;
        }
        my $regexp_system;
        $regexp_system = $obj_db->regexp_system( 'database' ) if $self->{opt}{metadata};
        if ( defined $regexp_system ) {
            my $regexp = join( '|', @$regexp_system );
            my ( @data, @system );
            for my $database ( @{$databases} ) {
                if ( $database =~ /(?:$regexp)/ ) {
                    push @system, $database;
                }
                else {
                    push @data, $database;
                }
            }
            if ( $db_driver eq 'SQLite' ) {
                $databases = [ @data, @system ];
            }
            else {
                $databases = [ map( "- $_", @data ), map( "  $_", @system ) ];
            }
        }
        else {
            if ( $db_driver ne 'SQLite' ) {
                $databases = [ map{ "- $_" } @$databases ];
            }
        }

        my $data = {};
        my $old_idx_db = 0;
        my $new_db_settings = 0;
        my $db;

        DATABASE: while ( 1 ) {

            if ( $new_db_settings ) {
                $new_db_settings = 0;
                $data = {};
            }
            else {
                my $back = ( $db_driver eq 'SQLite' ? '' : ' ' x 2 ) . ( $self->{info}{one_db_driver} ? 'Quit' : 'BACK' );
                my $prompt = 'Choose Database' . $self->{info}{cached};
                my $choices = [ undef, @$databases ];
                # Choose
                my $idx_db = $lyt_3->choose(
                    $choices,
                    { prompt => $prompt, index => 1, default => $old_idx_db, undef => $back }
                );
                $db = undef;
                $db = $choices->[$idx_db] if defined $idx_db;
                if ( ! defined $db ) {
                    last DB_DRIVER if   $self->{info}{one_db_driver};
                    next DB_DRIVER if ! $self->{info}{one_db_driver};
                }
                if ( $self->{opt}{menus_memory} ) {
                    if ( $old_idx_db == $idx_db ) {
                        $old_idx_db = 0;
                        next DATABASE;
                    }
                    else {
                        $old_idx_db = $idx_db;
                    }
                }
                $db =~ s/^[-\ ]\s// if $db_driver ne 'SQLite';
                die "'$db': $!. Maybe the cached data is not up to date." if $db_driver eq 'SQLite' && ! -f $db;
            }

            my $dbh;
            if ( ! eval {
                $dbh = $obj_db->get_db_handle( $db );
                $data->{$db}{schemas} = $obj_db->get_schema_names( $dbh, $db ) if ! defined $data->{$db}{schemas};
                1 }
            ) {
                say 'Get database handle and schema names:';
                delete $self->{info}{login}{$db_driver . '_' . $db};
                $self->__print_error_message( $@ );
                # remove database from @databases
                next DATABASE;
            }
            my $old_idx_sch = 0;

            SCHEMA: while ( 1 ) {

                my $schema;
                if ( @{$data->{$db}{schemas}} == 1 ) {
                    $schema = $data->{$db}{schemas}[0];
                }
                elsif ( @{$data->{$db}{schemas}} > 1 ) {
                    my $choices;
                    my $idx_sch;
                    my $regexp_system;
                    $regexp_system = $obj_db->regexp_system( 'schema' ) if $self->{opt}{metadata};
                    if ( defined $regexp_system ) {
                        my $regexp = join( '|', @$regexp_system );
                        my ( @data, @system );
                        for my $schema ( @{$data->{$db}{schemas}} ) {
                            if ( $schema =~ /(?:$regexp)/ ) {
                                push @system, $schema;
                            }
                            else {
                                push @data, $schema;
                            }
                        }
                        $choices = [ undef, map( "- $_", @data ), map( "  $_", @system ) ];
                    }
                    else {
                        $choices = [ undef, map( "- $_", @{$data->{$db}{schemas}} ) ];
                    }
                    my $prompt = 'DB "'. basename( $db ) . '" - choose Schema:';
                    # Choose
                    $idx_sch = $lyt_3->choose(
                        $choices,
                        { prompt => $prompt, index => 1, default => $old_idx_sch }
                    );
                    $schema = $choices->[$idx_sch] if defined $idx_sch;
                    next DATABASE if ! defined $schema;
                    if ( $self->{opt}{menus_memory} ) {
                        if ( $old_idx_sch == $idx_sch ) {
                            $old_idx_sch = 0;
                            next SCHEMA;
                        }
                        else {
                            $old_idx_sch = $idx_sch;
                        }
                    }
                    $schema =~ s/^[-\ ]\s//;
                }

                if ( ! eval {
                    if ( ! defined $data->{$db}{$schema}{tables} ) {
                        $data->{$db}{$schema}{tables} = $obj_db->get_table_names( $dbh, $schema );
                    }
                    1 }
                ) {
                    say 'Get table names:';
                    $self->__print_error_message( $@ );
                    next DATABASE;
                }

                my $join       = '  Join';
                my $union      = '  Union';
                my $db_setting = '  Database settings';
                my @tables = ();
                my $regexp_system;
                $regexp_system = $obj_db->regexp_system( 'table' ) if $self->{opt}{metadata};
                if ( defined $regexp_system ) {
                    my $regexp = join( '|', @$regexp_system );
                    my ( @data, @system );
                    for my $table ( @{$data->{$db}{$schema}{tables}} ) {
                        if ( $table =~ /(?:$regexp)/ ) {
                            push @system, $table;
                        }
                        else {
                            push @data, $table;
                        }
                    }
                    @tables = ( map( "- $_", @data ), map( "  $_", @system ) );
                }
                else {
                    @tables = map { "- $_" } @{$data->{$db}{$schema}{tables}};
                }
                my $old_idx_tbl = 0;

                TABLE: while ( 1 ) {

                    my $prompt = 'DB: "'. basename( $db );
                    $prompt .= '.' . $schema if defined $data->{$db}{schemas} && @{$data->{$db}{schemas}} > 1;
                    $prompt .= '"';
                    my $choices = [ undef, @tables, $join, $union, $db_setting ];
                    # Choose
                    my $idx_tbl = $lyt_3->choose(
                        $choices,
                        { prompt => $prompt, index => 1, default => $old_idx_tbl }
                    );
                    my $table;
                    $table = $choices->[$idx_tbl] if defined $idx_tbl;
                    if ( ! defined $table ) {
                        next SCHEMA if defined $data->{$db}{schemas} && @{$data->{$db}{schemas}} > 1;
                        next DATABASE;
                    }
                    if ( $self->{opt}{menus_memory} ) {
                        if ( $old_idx_tbl == $idx_tbl ) {
                            $old_idx_tbl = 0;
                            next TABLE;
                        }
                        else {
                            $old_idx_tbl = $idx_tbl;
                        }
                    }
                    my $multi_table;
                    if ( $table eq $db_setting ) {
                        if ( ! eval {
                            my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
                            $new_db_settings = $obj_opt->database_setting( $db );
                            1 }
                        ) {
                            say 'Database settings:';
                            $self->__print_error_message( $@ );
                        }
                        next DATABASE if $new_db_settings;
                        next TABLE;
                    }
                    elsif ( $table eq $join ) {
                        if ( ! eval {
                            $multi_table = $self->__join_tables( $dbh, $db, $schema, $data );
                            $table = 'joined_tables';
                            1 }
                        ) {
                            say 'Join tables:';
                            $self->__print_error_message( $@ );
                        }
                        next TABLE if ! defined $multi_table;
                    }
                    elsif ( $table eq $union ) {
                        if ( ! eval {
                            $multi_table = $self->__union_tables( $dbh, $db, $schema, $data );
                            if ( $self->{union_all} ) {
                                $table = 'union_all_tables';
                                delete $self->{union_all};
                            }
                            else {
                                $table = 'union_tables';
                            }
                            1 }
                        ) {
                            say 'Union tables:';
                            $self->__print_error_message( $@ );
                        }
                        next TABLE if ! defined $multi_table;
                    }
                    else {
                        $table =~ s/^[-\ ]\s//;
                    }
                    if ( ! eval {
                        my $qt_columns = {};
                        my $pr_columns = [];
                        my $sql;
                        $sql->{strg_keys} = [ qw( distinct_stmt where_stmt group_by_stmt having_stmt order_by_stmt limit_stmt ) ];
                        $sql->{list_keys} = [ qw( chosen_cols aggr_cols where_args group_by_cols having_args limit_args ) ];
                        $self->__reset_sql( $sql, $qt_columns );

                        $self->{info}{lock} = $self->{opt}{lock_stmt};

                        my $select_from_stmt = '';
                        if ( $multi_table ) {
                            $select_from_stmt = $multi_table->{quote}{stmt};
                            for my $col ( @{$multi_table->{pr_columns}} ) {
                                $qt_columns->{$col} = $multi_table->{qt_columns}{$col};
                                push @$pr_columns, $col;
                            }
                        }
                        else {
                            $select_from_stmt = "SELECT * FROM " . $dbh->quote_identifier( undef, $schema, $table );
                            my $sth = $dbh->prepare( $select_from_stmt . " LIMIT 0" );
                            $sth->execute();
                            for my $col ( @{$sth->{NAME}} ) {
                                $qt_columns->{$col} = $dbh->quote_identifier( $col );
                                push @$pr_columns, $col;
                            }
                        }

                        $self->{opt}{_db_browser_mode} = 1;
                        $self->{opt}{binary_filter}    =    $self->{opt}{$db_driver . '_' . $db}{binary_filter}
                                                         || $self->{opt}{$db_driver}{binary_filter};

                        PRINT_TABLE: while ( 1 ) {
                            my $all_arrayref = $self->__read_table( $sql, $dbh, $table, $select_from_stmt, $qt_columns, $pr_columns );
                            last PRINT_TABLE if ! defined $all_arrayref;
                            delete @{$self->{info}}{qw(width_head width_cols not_a_number)};
                            print_table( $all_arrayref, $self->{opt} );
                        }

                        1 }
                    ) {
                        say 'Print table:';
                        $self->__print_error_message( $@ );
                    }
                }
            }
            $dbh->disconnect();
        }
    }
}


sub __print_error_message {
    my ( $self, $message ) = @_;
    utf8::decode( $message );
    print $message;
    my $ch = Term::Choose->new();
    $ch->choose(
        [ 'Press ENTER to continue' ],
        { %{$self->{info}{lyt_stop}}, prompt => '' }
    );
}


sub __available_databases_cached {
    my ( $self, $dbh ) = @_;
    my $db_driver = $self->{info}{db_driver};
    my $cache_key = $db_driver . '_' . join ' ', @{$self->{info}{sqlite_dirs}};
    my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
    $self->{info}{cache} = $obj_opt->read_json( $self->{info}{db_cache_file} );
    if ( $self->{info}{sqlite_search} ) {
        delete $self->{info}{cache}{$cache_key};
        $self->{info}{sqlite_search} = 0;
    }
    if ( $self->{info}{cache}{$cache_key} ) {
        $self->{info}{cached} = ' (cached)';
        return $self->{info}{cache}{$cache_key};
    }
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my $databases = $obj_db->available_databases( $dbh );
    $self->{info}{cache}{$cache_key} = $databases;
    $obj_opt->write_json( $self->{info}{db_cache_file}, $self->{info}{cache} );
    return $databases;
}


sub __union_tables {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    my $no_lyt = Term::Choose->new();
    my $u = $data->{$db}{$schema};
    if ( ! defined $u->{col_names} || ! defined $u->{col_types} ) {
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        $data = $obj_db->column_names_and_types( $dbh, $db, $schema, $data );
    }
    my $union = {
        unused_tables => [ map { "- $_" } @{$u->{tables}} ],
        used_tables   => [],
        used_cols     => {},
        saved_cols    => [],
    };

    UNION_TABLE: while ( 1 ) {
        my $enough_tables = '  Enough TABLES';
        my $all_tables    = '  All Tables';
        my @pre_tbl  = ( undef, $enough_tables );
        my @post_tbl = ( $all_tables, $self->{info}{_info} );
        my $choices = [ @pre_tbl, map( "+ $_", @{$union->{used_tables}} ), @{$union->{unused_tables}}, @post_tbl ];
        $self->__print_union_statement( $union );
        # Choose
        my $idx_tbl = $no_lyt->choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => 'Choose UNION table:', index => 1 }
        );
        return if ! defined $idx_tbl;
        my $union_table = $choices->[$idx_tbl];
        return  if ! defined $union_table;
        if ( $union_table eq $self->{info}{_info} ) {
            if ( ! defined $u->{tables_info} ) {
                $u->{tables_info} = $self->__get_tables_info( $dbh, $db, $schema, $data );
            }
            my $tbls_info = $self->__print_tables_info( $u );
            # Choose
            $no_lyt->choose(
                $tbls_info,
                { %{$self->{info}{lyt_3}}, prompt => '' }
            );
            next UNION_TABLE;
        }
        if ( $union_table eq $enough_tables ) {
            return if ! @{$union->{used_tables}};
            last UNION_TABLE;
        }
        if ( $union_table eq $all_tables ) {
            $union = {
                unused_tables => [ map { "- $_" } @{$u->{tables}} ],
                used_tables   => [],
                used_cols     => {},
                saved_cols    => [],
            };
            $self->{union_all} = 1;
            next UNION_TABLE;
        }
        my $backup_union = clone( $union );
        $union_table =~ s/^[-+]\s//;
        my $check_idx = $idx_tbl - ( @pre_tbl + @{$union->{used_tables}} );
        if ( $check_idx < 0 ) {
            my $idx_used = $idx_tbl - @pre_tbl;
            delete $union->{used_cols}{$union_table};
            $self->{idx_reset_used_tables} = $idx_used;
        }
        else {
            my $idx_unused = $check_idx;
            splice( @{$union->{unused_tables}}, $idx_unused, 1 );
            push @{$union->{used_tables}}, $union_table;
            $self->{idx_reset_used_tables} = -1;
        }

        UNION_COLUMN: while ( 1 ) {
            my ( $all_cols, $privious_cols, $void ) = ( q['*'], q['^'], q[' '] );
            my @short_cuts = ( ( @{$union->{saved_cols}} ? $privious_cols : $void ), $all_cols );
            my @pre_col = ( $self->{info}{ok}, @short_cuts );
            unshift @pre_col, undef if $self->{opt}{sssc_mode};
            my $choices = [ @pre_col, @{$u->{col_names}{$union_table}} ];
            $self->__print_union_statement( $union );
            # Choose
            my @col = $no_lyt->choose(
                $choices,
                { %{$self->{info}{lyt_stmt_h}}, prompt => 'Choose Column:', no_spacebar => [ 0 .. $#pre_col ] }
            );
            if ( ! @col || ! defined $col[0] ) {
                if ( defined $union->{used_cols}{$union_table} ) {
                    delete $union->{used_cols}{$union_table};
                    next UNION_COLUMN;
                }
                else {
                    delete $self->{union_all} if $self->{union_all};
                    $union = clone( $backup_union );
                    last UNION_COLUMN;
                }
            }
            if ( $col[0] eq $self->{info}{ok} ) {
                shift @col;
                if ( @col ) {
                    push @{$union->{used_cols}{$union_table}}, @col;
                }
                elsif ( ! defined $union->{used_cols}{$union_table} ) {
                    my $tbl = splice( @{$union->{used_tables}}, $self->{idx_reset_used_tables}, 1 );
                    push @{$union->{unused_tables}}, "- $tbl";
                    delete $self->{idx_reset_used_tables};
                    delete $self->{union_all} if defined $self->{union_all};
                }
                last UNION_COLUMN;
            }
            if ( $col[0] eq $void ) {
                next UNION_COLUMN;
            }
            if ( $col[0] eq $privious_cols ) {
                $union->{used_cols}{$union_table} = $union->{saved_cols};
                next UNION_COLUMN if $self->{opt}{sssc_mode};
                last UNION_COLUMN;
            }
            if ( $col[0] eq $all_cols ) {
                @{$union->{used_cols}{$union_table}} = @{$u->{col_names}{$union_table}};
                next UNION_COLUMN if $self->{opt}{sssc_mode};
                last UNION_COLUMN;
            }
            else {
                push @{$union->{used_cols}{$union_table}}, @col;
            }
        }
        if ( $self->{union_all} ) {
            my @selected_cols = @{$union->{used_cols}{$union_table}};
            $union = {
                unused_tables => [],
                used_tables   => [ @{$u->{tables}} ],
                used_cols     => {},
                saved_cols    => [],
            };
            for my $union_table ( @{$union->{used_tables}} ) {
                @{$union->{used_cols}{$union_table}} = @selected_cols;
            }
            last UNION_TABLE;
        }
        $union->{saved_cols} = $union->{used_cols}{$union_table} if defined $union->{used_cols}{$union_table};
    }
    # column names in the result-set of a UNION are taken from the first query.
    my $first_table = $union->{used_tables}[0];
    $union->{pr_columns} = $union->{used_cols}{$first_table};
    for my $col ( @{$union->{pr_columns}} ) {
        $union->{qt_columns}{$col} = $dbh->quote_identifier( $col );
    }
    $union->{quote}{stmt} = "SELECT * FROM (";
    my $c;
    for my $table ( @{$union->{used_tables}} ) {
        $c++;
        $union->{quote}{stmt} .= " SELECT ";
        $union->{quote}{stmt} .= join( ', ', map { $dbh->quote_identifier( $_ ) } @{$union->{used_cols}{$table}} );
        $union->{quote}{stmt} .= " FROM " . $dbh->quote_identifier( undef, $schema, $table );
        $union->{quote}{stmt} .= $c < @{$union->{used_tables}} ? " UNION ALL " : " )";
    }
    if ( $self->{union_all} ) {
        $union->{quote}{stmt} .= " AS " . $dbh->quote_identifier( 'UNION_ALL_TABLES' );
    }
    else {
        $union->{quote}{stmt} .= " AS " . $dbh->quote_identifier( join '_', @{$union->{used_tables}} );
    }
    return $union;
}


sub __print_union_statement {
    my ( $self, $union ) = @_;
    my $str;
    if ( $self->{union_all} ) {
        $str = 'UNION ALL TABLES' . "\n" . 'Col: ';
        if ( @{$union->{used_tables}} ) {
            my $table = $union->{used_tables}[0];
            $str .= join( ', ', @{$union->{used_cols}{$table}} ) if @{$union->{used_cols}{$table}//[]};
        }
        $str .= "\n";
    }
    else {
        $str = "SELECT * FROM (\n";
        my $c = 0;
        for my $table ( @{$union->{used_tables}} ) {
            ++$c;
            $str .= "  SELECT ";
            $str .= @{$union->{used_cols}{$table}//[]} ? join( ', ', @{$union->{used_cols}{$table}} ) : '?';
            $str .= " FROM $table";
            $str .= $c < @{$union->{used_tables}} ? " UNION ALL\n" : "\n";
        }
        if ( @{$union->{used_tables}} ) {
            $str .= ") AS ";
            $str .= $self->{union_all} ? 'UNION_ALL_TABLES' : join '_', @{$union->{used_tables}};
            $str .= " \n";
        }
    }
    $str .= "\n";
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}}, ColMax => ( term_size() )[0] - 2 );
    print CLEAR_SCREEN;
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $str );
}


sub __get_tables_info {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    my $tables_info = {};
    my $sth;
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my ( $pk, $fk ) = $obj_db->primary_and_foreign_keys( $dbh, $db, $schema, $data );
    for my $table ( @{$data->{$db}{$schema}{tables}} ) {
        push @{$tables_info->{$table}}, [ 'Table: ', '== ' . $table . ' ==' ];
        push @{$tables_info->{$table}}, [
            'Columns: ',
            join( ' | ', map {
                    lc( $data->{$db}{$schema}{col_types}{$table}[$_] )
                . ' ' . $data->{$db}{$schema}{col_names}{$table}[$_] } 0 .. $#{$data->{$db}{$schema}{col_names}{$table}} )
        ];
        if ( @{$pk->{$table}} ) {
            push @{$tables_info->{$table}}, [ 'PK: ', 'primary key (' . join( ',', @{$pk->{$table}} ) . ')' ];
        }
        for my $fk_name ( sort keys %{$fk->{$table}} ) {
            if ( $fk->{$table}{$fk_name} ) {
                push @{$tables_info->{$table}}, [
                    'FK: ',
                    'foreign key (' . join( ',', @{$fk->{$table}{$fk_name}{foreign_key_col}} ) .
                    ') references ' . $fk->{$table}{$fk_name}{reference_table} .
                    '(' . join( ',', @{$fk->{$table}{$fk_name}{reference_key_col}} ) .')'
                ];
            }
        }
    }
    return $tables_info;
}


sub __print_tables_info {
    my ( $self, $ref ) = @_;
    my $len_key = 10;
    my $col_max = ( term_size() )[0] - 1;
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}} );
    $line_fold->config( 'ColMax', $col_max > $self->{info}{tbl_info_width} ? $self->{info}{tbl_info_width} : $col_max );
    my $ch_info = [ 'Close with ENTER' ];
    for my $table ( @{$ref->{tables}} ) {
        push @{$ch_info}, " ";
        for my $line ( @{$ref->{tables_info}{$table}} ) {
            my $text = sprintf "%*s%s", $len_key, @$line;
            $text = $line_fold->fold( '' , ' ' x $len_key, $text );
            push @{$ch_info}, split /\R+/, $text;
        }
    }
    return $ch_info;
}


sub __join_tables {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    my $stmt_v = Term::Choose->new( $self->{info}{lyt_stmt_v} );
    my $join = {};
    $join->{quote}{stmt} = "SELECT * FROM";
    $join->{print}{stmt} = "SELECT * FROM";
    my $j = $data->{$db}{$schema};
    if ( ! defined $j->{col_names} || ! defined $j->{col_types} ) {
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        $data = $obj_db->column_names_and_types( $dbh, $db, $schema, $data );
    }
    my @tables = map { "- $_" } @{$j->{tables}};

    MASTER: while ( 1 ) {
        $self->__print_join_statement( $join->{print}{stmt} );
        # Choose
        my @pre = ( undef );
        my $choices = [ @pre, @tables, $self->{info}{_info} ];
        my $idx = $stmt_v->choose(
            $choices,
            { prompt => 'Choose MASTER table:', index => 1 }
        );
        return if ! defined $idx;
        my $master = $choices->[$idx];
        return if ! defined $master;
        if ( $master eq $self->{info}{_info} ) {
            if ( ! defined $j->{tables_info} ) {
                $j->{tables_info} = $self->__get_tables_info( $dbh, $db, $schema, $data );
            }
            my $tbls_info = $self->__print_tables_info( $j );
            # Choose
            $stmt_v->choose(
                $tbls_info,
                { %{$self->{info}{lyt_3}}, prompt => '' }
            );
            next MASTER;
        }
        $idx -= @pre;
        splice( @tables, $idx, 1 );
        $master =~ s/^-\s//;
        $join->{used_tables}  = [ $master ];
        $join->{avail_tables} = [ @tables ];
        $join->{quote}{stmt}  = "SELECT * FROM " . $dbh->quote_identifier( undef, $schema, $master );
        $join->{print}{stmt}  = "SELECT * FROM " .                                         $master  ;
        $join->{primary_keys} = [];
        $join->{foreign_keys} = [];
        my $backup_master = clone( $join );

        JOIN: while ( 1 ) {
            my $enough_slaves = '  Enough TABLES';
            my ( $idx, $slave );
            my $backup_join = clone( $join );

            SLAVE: while ( 1 ) {
                $self->__print_join_statement( $join->{print}{stmt} );
                my @pre = ( undef, $enough_slaves );
                my $choices = [ @pre, @{$join->{avail_tables}}, $self->{info}{_info} ];
                # Choose
                $idx = $stmt_v->choose(
                    $choices,
                    { prompt => 'Add a SLAVE table:', index => 1, undef => $self->{info}{_reset} }
                );
                if ( defined $idx ) {
                    $slave = $choices->[$idx];
                    $idx -= @pre;
                }
                if ( ! defined $slave ) {
                    if ( @{$join->{used_tables}} == 1 ) {
                        @tables = map { "- $_" } @{$j->{tables}};
                        $join->{quote}{stmt} = "SELECT * FROM";
                        $join->{print}{stmt} = "SELECT * FROM";
                        next MASTER;
                    }
                    else {
                        $join = clone( $backup_master );
                        next JOIN;
                    }
                }
                elsif ( $slave eq $enough_slaves ) {
                    last JOIN;
                }
                elsif ( $slave eq $self->{info}{_info} ) {
                    if ( ! defined $j->{tables_info} ) {
                        $j->{tables_info} = $self->__get_tables_info( $dbh, $db, $schema, $data );
                    }
                    my $tbls_info = $self->__print_tables_info( $j );
                    # Choose
                    $stmt_v->choose(
                        $tbls_info,
                        { %{$self->{info}{lyt_3}}, prompt => '' }
                    );
                    next SLAVE;
                }
                else {
                    last SLAVE;
                }
            }
            splice( @{$join->{avail_tables}}, $idx, 1 );
            $slave =~ s/^-\s//;
            $join->{quote}{stmt} .= " LEFT OUTER JOIN " . $dbh->quote_identifier( undef, $schema, $slave ) . " ON";
            $join->{print}{stmt} .= " LEFT OUTER JOIN " .                                         $slave   . " ON";
            my %avail_pk_cols = ();
            for my $used_table ( @{$join->{used_tables}} ) {
                for my $col ( @{$j->{col_names}{$used_table}} ) {
                    $avail_pk_cols{ $used_table . '.' . $col } = $dbh->quote_identifier( undef, $used_table, $col );
                }
            }
            my %avail_fk_cols = ();
            for my $col ( @{$j->{col_names}{$slave}} ) {
                $avail_fk_cols{ $slave . '.' . $col } = $dbh->quote_identifier( undef, $slave, $col );
            }
            my $AND = '';

            ON: while ( 1 ) {
                $self->__print_join_statement( $join->{print}{stmt} );
                my @pre = ( undef );
                push @pre, $self->{info}{_continue} if $AND;
                # Choose
                my $pk_col = $stmt_v->choose(
                    [ @pre, map( "- $_", sort keys %avail_pk_cols ) ],
                    { prompt => 'Choose PRIMARY KEY column:', undef => $self->{info}{_reset} }
                );
                if ( ! defined $pk_col ) {
                    $join = clone( $backup_join );
                    next JOIN;
                }
                if ( $pk_col eq $self->{info}{_continue} ) {
                    if ( @{$join->{primary_keys}} == @{$backup_join->{primary_keys}} ) {
                        $join = clone( $backup_join );
                        next JOIN;
                    }
                    last ON;
                }
                $pk_col =~ s/^-\s//;
                push @{$join->{primary_keys}}, $avail_pk_cols{$pk_col};
                $join->{quote}{stmt} .= $AND;
                $join->{print}{stmt} .= $AND;
                $join->{quote}{stmt} .= ' ' . $avail_pk_cols{$pk_col} . " =";
                $join->{print}{stmt} .= ' ' .                $pk_col  . " =";
                $self->__print_join_statement( $join->{print}{stmt} );
                # Choose
                my $fk_col = $stmt_v->choose(
                    [ undef, map( "- $_", sort keys %avail_fk_cols ) ],
                    { prompt => 'Choose FOREIGN KEY column:', undef => $self->{info}{_reset} }
                );
                if ( ! defined $fk_col ) {
                    $join = clone( $backup_join );
                    next JOIN;
                }
                $fk_col =~ s/^-\s//;
                push @{$join->{foreign_keys}}, $avail_fk_cols{$fk_col};
                $join->{quote}{stmt} .= ' ' . $avail_fk_cols{$fk_col};
                $join->{print}{stmt} .= ' ' .                $fk_col;
                $AND = " AND";
            }
            push @{$join->{used_tables}}, $slave;
        }
        last MASTER;
    }

    #my @not_unique_col;
    #my %seen;
    #for my $table (@{$join->{used_tables}} ) {
    #    for my $col ( @{$j->{col_names}{$table}} ) {
    #        $seen{$col}++;
    #        push @not_unique_col, $col if $seen{$col} == 2;
    #    }
    #}
    my $col_stmt = '';
    for my $table ( @{$join->{used_tables}} ) {
        for my $col ( @{$j->{col_names}{$table}} ) {
            my $col_qt = $dbh->quote_identifier( undef, $table, $col );
            my $col_pr = $col;
            if ( any { $_ eq $col_qt } @{$join->{foreign_keys}} ) {
                next;
            }
            #if ( any { $_ eq $col_pr } @not_unique_col ) {
                $col_pr .= '_' . $table;
                $col_qt .= " AS " . $dbh->quote_identifier( $col_pr );
            #}
            push @{$join->{pr_columns}}, $col_pr;
            $join->{qt_columns}{$col_pr} = $col_qt;
            $col_stmt .= ', ' . $col_qt;
        }
    }
    $col_stmt =~ s/^,\s//;
    $join->{quote}{stmt} =~ s/\s\*\s/ $col_stmt /;
    return $join;
}


sub __print_join_statement {
    my ( $self, $join_stmt_pr ) = @_;
    $join_stmt_pr =~ s/(?=\sLEFT\sOUTER\sJOIN)/\n\ /g;
    $join_stmt_pr .= "\n\n";
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}}, ColMax => ( term_size() )[0] - 2 );
    print CLEAR_SCREEN;
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $join_stmt_pr );
}


sub __print_select_statement {
    my ( $self, $sql, $table, $status ) = @_;
    my $cols_sql;
    if ( $sql->{select_type} eq '*' ) {
        $cols_sql = ' *';
    }
    elsif ( $sql->{select_type} eq 'chosen_cols' ) {
        $cols_sql = ' ' . join( ', ', @{$sql->{print}{chosen_cols}} );
    }
    elsif ( @{$sql->{print}{aggr_cols}} || @{$sql->{print}{group_by_cols}} ) {
        $cols_sql = ' ' . join( ', ', @{$sql->{print}{group_by_cols}}, @{$sql->{print}{aggr_cols}} );
    }
    else {
        $cols_sql = ' *';
    }
    my $str = "SELECT";
    $str .= $sql->{print}{distinct_stmt} if $sql->{print}{distinct_stmt};
    $str .= $cols_sql . "\n";
    $str .= "  FROM $table" . "\n";
    $str .= ' ' . $sql->{print}{where_stmt}    . "\n" if $sql->{print}{where_stmt};
    $str .= ' ' . $sql->{print}{group_by_stmt} . "\n" if $sql->{print}{group_by_stmt};
    $str .= ' ' . $sql->{print}{having_stmt}   . "\n" if $sql->{print}{having_stmt};
    $str .= ' ' . $sql->{print}{order_by_stmt} . "\n" if $sql->{print}{order_by_stmt};
    $str .= ' ' . $sql->{print}{limit_stmt}    . "\n" if $sql->{print}{limit_stmt};
    $str .= "\n";
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}}, ColMax => ( term_size() )[0] - 2 );
    return $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $str ) if $status;
    print CLEAR_SCREEN;
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $str );
}


sub __reset_sql {
    my ( $self, $sql, $qt_columns ) = @_;
    $sql->{select_type} = '*';
    @{$sql->{print}}{ @{$sql->{strg_keys}} } = ( '' ) x  @{$sql->{strg_keys}};
    @{$sql->{quote}}{ @{$sql->{strg_keys}} } = ( '' ) x  @{$sql->{strg_keys}};
    @{$sql->{print}}{ @{$sql->{list_keys}} } = map{ [] } @{$sql->{list_keys}};
    @{$sql->{quote}}{ @{$sql->{list_keys}} } = map{ [] } @{$sql->{list_keys}};
    $sql->{pr_col_with_hidd_func} = [];
    delete $sql->{pr_backup_in_hidd};
}


sub __read_table {
    my ( $self, $sql, $dbh, $table, $select_from_stmt, $qt_columns, $pr_columns ) = @_;
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    my @keys = ( qw( print_table columns aggregate distinct where group_by having order_by limit lock ) );
    my $lk = [ '  Lk0', '  Lk1' ];
    my %customize = (
        hidden          => 'Customize:',
        print_table     => 'Print TABLE',
        columns         => '- SELECT',
        aggregate       => '- AGGREGATE',
        distinct        => '- DISTINCT',
        where           => '- WHERE',
        group_by        => '- GROUP BY',
        having          => '- HAVING',
        order_by        => '- ORDER BY',
        limit           => '- LIMIT',
        lock            => $lk->[$self->{info}{lock}],
    );
    my ( $DISTINCT, $ALL, $ASC, $DESC, $AND, $OR ) = ( "DISTINCT", "ALL", "ASC", "DESC", "AND", "OR" );
    if ( $self->{info}{lock} == 0 ) {
        $self->__reset_sql( $sql, $qt_columns );
    }

    CUSTOMIZE: while ( 1 ) {
        my $backup_sql = clone( $sql );
        $self->__print_select_statement( $sql, $table );
        # Choose
        my $custom = $stmt_h->choose(
            [ $customize{hidden}, undef, @customize{@keys} ],
            { %{$self->{info}{lyt_stmt_v}}, prompt => '', default => 1, undef => $self->{info}{back} }
        );
        if ( ! defined $custom ) {
            last CUSTOMIZE;
        }
        elsif ( $custom eq $customize{'lock'} ) {
            if ( $self->{info}{lock} == 1 ) {
                $self->{info}{lock} = 0;
                $customize{lock} = $lk->[0];
                $self->__reset_sql( $sql, $qt_columns );
            }
            elsif ( $self->{info}{lock} == 0 )   {
                $self->{info}{lock} = 1;
                $customize{lock} = $lk->[1];
            }
        }
        elsif( $custom eq $customize{'columns'} ) {
            if ( ! ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) ) {
                $self->__reset_sql( $sql, $qt_columns );
            }
            my @cols = ( @$pr_columns );
            $sql->{quote}{chosen_cols} = [];
            $sql->{print}{chosen_cols} = [];
            $sql->{select_type} = 'chosen_cols';

            COLUMNS: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, @cols ];
                $self->__print_select_statement( $sql, $table );
                # Choose
                my @print_col = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @print_col || ! defined $print_col[0] ) {
                    if ( @{$sql->{quote}{chosen_cols}} ) {
                        $sql->{quote}{chosen_cols} = [];
                        $sql->{print}{chosen_cols} = [];
                        delete $sql->{pr_backup_in_hidd}{chosen_cols};
                        next COLUMNS;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last COLUMNS;
                    }
                }
                if ( $print_col[0] eq $self->{info}{ok} ) {
                    shift @print_col;
                    for my $print_col ( @print_col ) {
                        push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
                        push @{$sql->{print}{chosen_cols}}, $print_col;
                    }
                    if ( ! @{$sql->{quote}{chosen_cols}} ) {
                        $sql->{select_type} = '*';
                    }
                    delete $sql->{pr_backup_in_hidd}{chosen_cols};
                    $sql->{pr_col_with_hidd_func} = [];
                    last COLUMNS;
                }
                for my $print_col ( @print_col ) {
                    push @{$sql->{quote}{chosen_cols}}, $qt_columns->{$print_col};
                    push @{$sql->{print}{chosen_cols}}, $print_col;
                }
            }
        }
        elsif( $custom eq $customize{'distinct'} ) {
            $sql->{quote}{distinct_stmt} = '';
            $sql->{print}{distinct_stmt} = '';

            DISTINCT: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, $DISTINCT, $ALL ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $select_distinct = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $select_distinct ) {
                    if ( $sql->{quote}{distinct_stmt} ) {
                        $sql->{quote}{distinct_stmt} = '';
                        $sql->{print}{distinct_stmt} = '';
                        next DISTINCT;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last DISTINCT;
                    }
                }
                if ( $select_distinct eq $self->{info}{ok} ) {
                    last DISTINCT;
                }
                $sql->{quote}{distinct_stmt} = ' ' . $select_distinct;
                $sql->{print}{distinct_stmt} = ' ' . $select_distinct;
            }
        }
        elsif( $custom eq $customize{'aggregate'} ) {
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                $self->__reset_sql( $sql, $qt_columns );
            }
            my @cols = ( @$pr_columns );
            $sql->{quote}{aggr_cols} = [];
            $sql->{print}{aggr_cols} = [];
            $sql->{select_type} = 'aggr_cols';

            AGGREGATE: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, @{$self->{info}{avail_aggregate}} ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $aggr = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $aggr ) {
                    if ( @{$sql->{quote}{aggr_cols}} ) {
                        $sql->{quote}{aggr_cols} = [];
                        $sql->{print}{aggr_cols} = [];
                        delete $sql->{pr_backup_in_hidd}{aggr_cols};
                        next AGGREGATE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last AGGREGATE;
                    }
                }
                if ( $aggr eq $self->{info}{ok} ) {
                    delete $sql->{pr_backup_in_hidd}{aggr_cols};
                    if ( ! @{$sql->{quote}{aggr_cols}} && ! @{$sql->{quote}{group_by_cols}} ) {
                        $sql->{select_type} = '*';
                    }
                    last AGGREGATE;
                }
                my $i = @{$sql->{quote}{aggr_cols}};
                if ( $aggr eq 'COUNT(*)' ) {
                    $sql->{print}{aggr_cols}[$i] = $aggr;
                    $sql->{quote}{aggr_cols}[$i] = $aggr;
                }
                else {
                    $aggr =~ s/\(\S\)\z//;
                    $sql->{quote}{aggr_cols}[$i] = $aggr . "(";
                    $sql->{print}{aggr_cols}[$i] = $aggr . "(";
                    if ( $aggr eq 'COUNT' ) {
                        my $choices = [ $ALL, $DISTINCT ];
                        unshift @$choices, undef if $self->{opt}{sssc_mode};
                        $self->__print_select_statement( $sql, $table );
                        # Choose
                        my $all_or_distinct = $stmt_h->choose(
                            $choices
                        );
                        if ( ! defined $all_or_distinct ) {
                            $sql->{quote}{aggr_cols} = [];
                            $sql->{print}{aggr_cols} = [];
                            next AGGREGATE;
                        }
                        if ( $all_or_distinct eq $DISTINCT ) {
                            $sql->{quote}{aggr_cols}[$i] .= $DISTINCT . ' ';
                            $sql->{print}{aggr_cols}[$i] .= $DISTINCT . ' ';
                        }
                    }
                    my $choices = [ @cols ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $self->__print_select_statement( $sql, $table );
                    # Choose
                    my $print_col = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $print_col ) {
                        $sql->{quote}{aggr_cols} = [];
                        $sql->{print}{aggr_cols} = [];
                        next AGGREGATE;
                    }
                    ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    $sql->{print}{aggr_cols}[$i] .= $print_col . ")";
                    $sql->{quote}{aggr_cols}[$i] .= $quote_col . ")";
                }
                $sql->{print}{aggr_cols}[$i] = $self->__unambiguous_key( $sql->{print}{aggr_cols}[$i], $pr_columns );
                $sql->{quote}{aggr_cols}[$i] .= " AS " . $dbh->quote_identifier( $sql->{print}{aggr_cols}[$i] );
                my $print_aggr = $sql->{print}{aggr_cols}[$i];
                my $quote_aggr = $sql->{quote}{aggr_cols}[$i];
                ( $qt_columns->{$print_aggr} = $quote_aggr ) =~ s/\sAS\s\S+//;
            }
        }
        elsif ( $custom eq $customize{'where'} ) {
            my @cols = ( @$pr_columns, @{$sql->{pr_col_with_hidd_func}} );
            my $AND_OR = ' ';
            $sql->{quote}{where_args} = [];
            $sql->{quote}{where_stmt} = " WHERE";
            $sql->{print}{where_stmt} = " WHERE";
            my $unclosed = 0;
            my $count = 0;

            WHERE: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my @choices = @cols;
                if ( $self->{opt}{parentheses_w} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                elsif ( $self->{opt}{parentheses_w} == 2 ) {
                    push @choices, $unclosed ? ')' : '(';
                }
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $print_col = $stmt_h->choose(
                    [ @pre, @choices ]
                );
                if ( ! defined $print_col ) {
                    if ( $sql->{quote}{where_stmt} ne " WHERE" ) {
                        $sql->{quote}{where_args} = [];
                        $sql->{quote}{where_stmt} = " WHERE";
                        $sql->{print}{where_stmt} = " WHERE";
                        $count = 0;
                        $AND_OR = ' ';
                        next WHERE;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last WHERE;
                    }
                }
                if ( $print_col eq $self->{info}{ok} ) {
                    if ( $count == 0 ) {
                        $sql->{quote}{where_stmt} = '';
                        $sql->{print}{where_stmt} = '';
                    }
                    last WHERE;
                }
                if ( $print_col eq ')' ) {
                    $sql->{quote}{where_stmt} .= ")";
                    $sql->{print}{where_stmt} .= ")";
                    $unclosed--;
                    next WHERE;
                }
                if ( $count > 0 && $sql->{quote}{where_stmt} !~ /\(\z/ ) {
                    my $choices = [ $AND, $OR ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $self->__print_select_statement( $sql, $table );
                    # Choose
                    $AND_OR = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $AND_OR ) {
                        $sql->{quote}{where_args} = [];
                        $sql->{quote}{where_stmt} = " WHERE";
                        $sql->{print}{where_stmt} = " WHERE";
                        $count = 0;
                        $AND_OR = ' ';
                        next WHERE;
                    }
                    $AND_OR = ' ' . $AND_OR . ' ';
                }
                if ( $print_col eq '(' ) {
                    $sql->{quote}{where_stmt} .= $AND_OR . "(";
                    $sql->{print}{where_stmt} .= $AND_OR . "(";
                    $AND_OR = '';
                    $unclosed++;
                    next WHERE;
                }

                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $sql->{quote}{where_stmt} .= $AND_OR . $quote_col;
                $sql->{print}{where_stmt} .= $AND_OR . $print_col;
                $self->__set_operator_sql( $sql, 'where', $table, \@cols, $qt_columns, $quote_col );
                if ( ! $sql->{quote}{where_stmt} ) {
                    $sql->{quote}{where_args} = [];
                    $sql->{quote}{where_stmt} = " WHERE";
                    $sql->{print}{where_stmt} = " WHERE";
                    $count = 0;
                    $AND_OR = ' ';
                    next WHERE;
                }
                $count++;
            }
        }
        elsif( $custom eq $customize{'group_by'} ) {
            if ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' ) {
                $self->__reset_sql( $sql, $qt_columns );
            }
            my @cols = ( @$pr_columns );
            my $col_sep = ' ';
            $sql->{quote}{group_by_stmt} = " GROUP BY";
            $sql->{print}{group_by_stmt} = " GROUP BY";
            $sql->{quote}{group_by_cols} = [];
            $sql->{print}{group_by_cols} = [];
            $sql->{select_type} = 'group_by_cols';

            GROUP_BY: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my $choices = [ @pre, @cols ];
                $self->__print_select_statement( $sql, $table );
                # Choose
                my @print_col = $stmt_h->choose(
                    $choices,
                    { no_spacebar => [ 0 .. $#pre ] }
                );
                if ( ! @print_col || ! defined $print_col[0] ) {
                    if ( @{$sql->{quote}{group_by_cols}} ) {
                        $sql->{quote}{group_by_stmt} = " GROUP BY";
                        $sql->{print}{group_by_stmt} = " GROUP BY";
                        $sql->{quote}{group_by_cols} = [];
                        $sql->{print}{group_by_cols} = [];
                        $col_sep = ' ';
                        delete $sql->{pr_backup_in_hidd}{group_by_cols};
                        next GROUP_BY;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last GROUP_BY;
                    }
                }
                if ( $print_col[0] eq $self->{info}{ok} ) {
                    shift @print_col;
                    for my $print_col ( @print_col ) {
                        ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                        push @{$sql->{quote}{group_by_cols}}, $quote_col;
                        push @{$sql->{print}{group_by_cols}}, $print_col;
                        $sql->{quote}{group_by_stmt} .= $col_sep . $quote_col;
                        $sql->{print}{group_by_stmt} .= $col_sep . $print_col;
                        $col_sep = ', ';
                    }
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{group_by_stmt} = '';
                        $sql->{print}{group_by_stmt} = '';
                        if ( ! @{$sql->{quote}{aggr_cols}} ) {
                            $sql->{select_type} = '*';
                        }
                        delete $sql->{pr_backup_in_hidd}{group_by_cols};
                    }
                    last GROUP_BY;
                }
                for my $print_col ( @print_col ) {
                    ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    push @{$sql->{quote}{group_by_cols}}, $quote_col;
                    push @{$sql->{print}{group_by_cols}}, $print_col;
                    $sql->{quote}{group_by_stmt} .= $col_sep . $quote_col;
                    $sql->{print}{group_by_stmt} .= $col_sep . $print_col;
                    $col_sep = ', ';
                }
            }
        }
        elsif( $custom eq $customize{'having'} ) {
            my @cols = ( @$pr_columns );
            my $AND_OR = ' ';
            $sql->{quote}{having_args} = [];
            $sql->{quote}{having_stmt} = " HAVING";
            $sql->{print}{having_stmt} = " HAVING";
            my $unclosed = 0;
            my $count = 0;

            HAVING: while ( 1 ) {
                my @pre = ( $self->{info}{ok} );
                unshift @pre, undef if $self->{opt}{sssc_mode};
                my @choices = ( @{$self->{info}{avail_aggregate}}, map( '@' . $_, @{$sql->{print}{aggr_cols}} ) );
                if ( $self->{opt}{parentheses_h} == 1 ) {
                    unshift @choices, $unclosed ? ')' : '(';
                }
                elsif ( $self->{opt}{parentheses_h} == 2 ) {
                    push @choices, $unclosed ? ')' : '(';
                }
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $aggr = $stmt_h->choose(
                    [ @pre, @choices ]
                );
                if ( ! defined $aggr ) {
                    if ( $sql->{quote}{having_stmt} ne " HAVING" ) {
                        $sql->{quote}{having_args} = [];
                        $sql->{quote}{having_stmt} = " HAVING";
                        $sql->{print}{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last HAVING;
                    }
                }
                if ( $aggr eq $self->{info}{ok} ) {
                    if ( $count == 0 ) {
                        $sql->{quote}{having_stmt} = '';
                        $sql->{print}{having_stmt} = '';
                    }
                    last HAVING;
                }
                if ( $aggr eq ')' ) {
                    $sql->{quote}{having_stmt} .= ")";
                    $sql->{print}{having_stmt} .= ")";
                    $unclosed--;
                    next HAVING;
                }
                if ( $count > 0 && $sql->{quote}{having_stmt} !~ /\(\z/ ) {
                    my $choices = [ $AND, $OR ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $self->__print_select_statement( $sql, $table );
                    # Choose
                    $AND_OR = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $AND_OR ) {
                        $sql->{quote}{having_args} = [];
                        $sql->{quote}{having_stmt} = " HAVING";
                        $sql->{print}{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    $AND_OR = ' ' . $AND_OR . ' ';
                }
                if ( $aggr eq '(' ) {
                    $sql->{quote}{having_stmt} .= $AND_OR . "(";
                    $sql->{print}{having_stmt} .= $AND_OR . "(";
                    $AND_OR = '';
                    $unclosed++;
                    next HAVING;
                }
                my ( $print_col,  $quote_col );
                my ( $print_aggr, $quote_aggr);
                if ( ( any { '@' . $_ eq $aggr } @{$sql->{print}{aggr_cols}} ) ) {
                    ( $print_aggr = $aggr ) =~ s/^\@//;
                    $quote_aggr = $qt_columns->{$print_aggr};
                    $sql->{quote}{having_stmt} .= $AND_OR . $quote_aggr;
                    $sql->{print}{having_stmt} .= $AND_OR . $print_aggr;
                    $quote_col = $qt_columns->{$print_aggr};
                }
                elsif ( $aggr eq 'COUNT(*)' ) {
                    $print_col = '*';
                    $quote_col = '*';
                    $print_aggr = $aggr;
                    $quote_aggr = $aggr;
                    $sql->{quote}{having_stmt} .= $AND_OR . $quote_aggr;
                    $sql->{print}{having_stmt} .= $AND_OR . $print_aggr;
                }
                else {
                    $aggr =~ s/\(\S\)\z//;
                    $sql->{quote}{having_stmt} .= $AND_OR . $aggr . "(";
                    $sql->{print}{having_stmt} .= $AND_OR . $aggr . "(";
                    $quote_aggr                 =           $aggr . "(";
                    $print_aggr                 =           $aggr . "(";
                    my $choices = [ @cols ];
                    unshift @$choices, undef if $self->{opt}{sssc_mode};
                    $self->__print_select_statement( $sql, $table );
                    # Choose
                    $print_col = $stmt_h->choose(
                        $choices
                    );
                    if ( ! defined $print_col ) {
                        $sql->{quote}{having_args} = [];
                        $sql->{quote}{having_stmt} = " HAVING";
                        $sql->{print}{having_stmt} = " HAVING";
                        $count = 0;
                        $AND_OR = ' ';
                        next HAVING;
                    }
                    ( $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                    $sql->{quote}{having_stmt} .= $quote_col . ")";
                    $sql->{print}{having_stmt} .= $print_col . ")";
                    $quote_aggr                .= $quote_col . ")";
                    $print_aggr                .= $print_col . ")";
                }
                $self->__set_operator_sql( $sql, 'having', $table, \@cols, $qt_columns, $quote_aggr );
                if ( ! $sql->{quote}{having_stmt} ) {
                    $sql->{quote}{having_args} = [];
                    $sql->{quote}{having_stmt} = " HAVING";
                    $sql->{print}{having_stmt} = " HAVING";
                    $count = 0;
                    $AND_OR = ' ';
                    next HAVING;
                }
                $count++;
            }
        }
        elsif( $custom eq $customize{'order_by'} ) {
            my @functions = @{$self->{info}{hidd_func_pr}}{@{$self->{info}{keys_hidd_func_pr}}};
            my $f = join '|', map quotemeta, @functions;
            my @not_hidd = map { /^(?:$f)\((.*)\)\z/ ? $1 : () } @{$sql->{print}{aggr_cols}};
            my @cols =
                ( $sql->{select_type} eq '*' || $sql->{select_type} eq 'chosen_cols' )
                ? ( @$pr_columns, @{$sql->{pr_col_with_hidd_func}} )
                : ( @{$sql->{print}{group_by_cols}}, @{$sql->{print}{aggr_cols}}, @not_hidd );
            my $col_sep = ' ';
            $sql->{quote}{order_by_stmt} = " ORDER BY";
            $sql->{print}{order_by_stmt} = " ORDER BY";

            ORDER_BY: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, @cols ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $print_col = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $print_col ) {
                    if ( $sql->{quote}{order_by_stmt} ne " ORDER BY" ) {
                        $sql->{quote}{order_by_args} = [];
                        $sql->{quote}{order_by_stmt} = " ORDER BY";
                        $sql->{print}{order_by_stmt} = " ORDER BY";
                        $col_sep = ' ';
                        next ORDER_BY;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last ORDER_BY;
                    }
                }
                if ( $print_col eq $self->{info}{ok} ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{order_by_stmt} = '';
                        $sql->{print}{order_by_stmt} = '';
                    }
                    last ORDER_BY;
                }
                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $sql->{quote}{order_by_stmt} .= $col_sep . $quote_col;
                $sql->{print}{order_by_stmt} .= $col_sep . $print_col;
                $choices = [ $ASC, $DESC ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $direction = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $direction ){
                    $sql->{quote}{order_by_args} = [];
                    $sql->{quote}{order_by_stmt} = " ORDER BY";
                    $sql->{print}{order_by_stmt} = " ORDER BY";
                    $col_sep = ' ';
                    next ORDER_BY;
                }
                $sql->{quote}{order_by_stmt} .= ' ' . $direction;
                $sql->{print}{order_by_stmt} .= ' ' . $direction;
                $col_sep = ', ';
            }
        }
        elsif( $custom eq $customize{'limit'} ) {
            $sql->{quote}{limit_args} = [];
            $sql->{quote}{limit_stmt} = " LIMIT";
            $sql->{print}{limit_stmt} = " LIMIT";
            my $digits = 7;
            my ( $only_limit, $offset_and_limit ) = ( 'LIMIT', 'OFFSET-LIMIT' );

            LIMIT: while ( 1 ) {
                my $choices = [ $self->{info}{ok}, $only_limit, $offset_and_limit ];
                unshift @$choices, undef if $self->{opt}{sssc_mode};
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $choice = $stmt_h->choose(
                    $choices
                );
                if ( ! defined $choice ) {
                    if ( @{$sql->{quote}{limit_args}} ) {
                        $sql->{quote}{limit_args} = [];
                        $sql->{quote}{limit_stmt} = " LIMIT";
                        $sql->{print}{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    else {
                        $sql = clone( $backup_sql );
                        last LIMIT;
                    }
                }
                if ( $choice eq $self->{info}{ok} ) {
                    if ( ! @{$sql->{quote}{limit_args}} ) {
                        $sql->{quote}{limit_stmt} = '';
                        $sql->{print}{limit_stmt} = '';
                    }
                    last LIMIT;
                }
                $sql->{quote}{limit_args} = [];
                $sql->{quote}{limit_stmt} = " LIMIT";
                $sql->{print}{limit_stmt} = " LIMIT";
                # Choose_a_number
                my $limit = choose_a_number( $digits, { name => '"LIMIT"' } );
                next LIMIT if ! defined $limit || $limit eq '--';
                push @{$sql->{quote}{limit_args}}, $limit;
                $self->{opt}{max_rows} = $limit + 1;
                $sql->{quote}{limit_stmt} .= ' ' . '?';
                $sql->{print}{limit_stmt} .= ' ' . insert_sep( $limit, $self->{opt}{thsd_sep} );
                if ( $choice eq $offset_and_limit ) {
                    # Choose_a_number
                    my $offset = choose_a_number( $digits, { name => '"OFFSET"' } );
                    if ( ! defined $offset || $offset eq '--' ) {
                        $sql->{quote}{limit_args} = [];
                        $sql->{quote}{limit_stmt} = " LIMIT";
                        $sql->{print}{limit_stmt} = " LIMIT";
                        next LIMIT;
                    }
                    push @{$sql->{quote}{limit_args}}, $offset;
                    $sql->{quote}{limit_stmt} .= " OFFSET " . '?';
                    $sql->{print}{limit_stmt} .= " OFFSET " . insert_sep( $offset, $self->{opt}{thsd_sep} );
                }
            }
        }
        elsif ( $custom eq $customize{'hidden'} ) {
            my @functions = @{$self->{info}{keys_hidd_func_pr}};
            my $stmt_key = '';
            if ( $sql->{select_type} eq '*' ) {
                @{$sql->{quote}{chosen_cols}} = map { $qt_columns->{$_} } @$pr_columns;
                @{$sql->{print}{chosen_cols}} = @$pr_columns;
                $stmt_key = 'chosen_cols';
            }
            elsif ( $sql->{select_type} eq 'chosen_cols' ) {
                $stmt_key = 'chosen_cols';
            }
            if ( $stmt_key eq 'chosen_cols' ) {
                if ( ! $sql->{pr_backup_in_hidd}{$stmt_key} ) {
                    @{$sql->{pr_backup_in_hidd}{$stmt_key}} = @{$sql->{print}{$stmt_key}};
                }
            }
            else {
                if ( @{$sql->{print}{aggr_cols}} && ! $sql->{pr_backup_in_hidd}{aggr_cols} ) {
                    @{$sql->{pr_backup_in_hidd}{'aggr_cols'}} = @{$sql->{print}{aggr_cols}};
                }
                if ( @{$sql->{print}{group_by_cols}} && ! $sql->{pr_backup_in_hidd}{group_by_cols} ) {
                    @{$sql->{pr_backup_in_hidd}{'group_by_cols'}} = @{$sql->{print}{group_by_cols}};
                }
            }
            my $changed = 0;

            HIDDEN: while ( 1 ) {
                my @cols = $stmt_key eq 'chosen_cols'
                    ? ( @{$sql->{print}{$stmt_key}}                                  )
                    : ( @{$sql->{print}{aggr_cols}}, @{$sql->{print}{group_by_cols}} );
                my @pre = ( undef, $self->{info}{_confirm} );
                my $choices = [ @pre, map( "- $_", @cols ) ];
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $i = $stmt_h->choose(
                    $choices,
                    { %{$self->{info}{lyt_stmt_v}}, index => 1 }
                );
                if ( ! defined $i ) {
                    $sql = clone( $backup_sql );
                    last HIDDEN;
                }
                my $print_col = $choices->[$i];
                if ( ! defined $print_col ) {
                    $sql = clone( $backup_sql );
                    last HIDDEN;
                }
                if ( $print_col eq $self->{info}{_confirm} ) {
                    if ( ! $changed ) {
                        $sql = clone( $backup_sql );
                        last HIDDEN;
                    }
                    $sql->{select_type} = $stmt_key if $sql->{select_type} eq '*';
                    last HIDDEN;
                }
                $print_col =~ s/^\-\s//;
                $i -= @pre;
                if ( $stmt_key ne 'chosen_cols' ) {
                    if ( $i - @{$sql->{print}{aggr_cols}} >= 0 ) {
                        $i -= @{$sql->{print}{aggr_cols}};
                        $stmt_key = 'group_by_cols';
                    }
                    else {
                        $stmt_key = 'aggr_cols';
                    }
                }
                if ( $sql->{print}{$stmt_key}[$i] ne $sql->{pr_backup_in_hidd}{$stmt_key}[$i] ) {
                    if ( $stmt_key ne 'aggr_cols' ) {
                        my $i = first_index { $sql->{print}{$stmt_key}[$i] eq $_ } @{$sql->{pr_col_with_hidd_func}};
                        splice( @{$sql->{pr_col_with_hidd_func}}, $i, 1 );
                    }
                    $sql->{print}{$stmt_key}[$i] = $sql->{pr_backup_in_hidd}{$stmt_key}[$i];
                    $sql->{quote}{$stmt_key}[$i] = $qt_columns->{$sql->{pr_backup_in_hidd}{$stmt_key}[$i]};
                    $changed++;
                    next HIDDEN;
                }
                $self->__print_select_statement( $sql, $table );
                # Choose
                my $function = $stmt_h->choose(
                    [ undef, map( "  $_", @functions ) ],
                    { %{$self->{info}{lyt_stmt_v}} }
                );
                if ( ! defined $function ) {
                    next HIDDEN;
                }
                $function =~ s/^\s\s//;
                ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
                $self->__print_select_statement( $sql, $table );
                my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
                my ( $quote_hidd, $print_hidd ) = $obj_db->col_functions( $function, $quote_col, $print_col );
                if ( ! defined $quote_hidd ) {
                    next HIDDEN;
                }
                $print_hidd = $self->__unambiguous_key( $print_hidd, $pr_columns );
                if ( $stmt_key eq 'group_by_cols' ) {
                    $sql->{quote}{$stmt_key}[$i] = $quote_hidd;
                    $sql->{quote}{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{quote}{$stmt_key}} );
                    $sql->{print}{group_by_stmt} = " GROUP BY " . join( ', ', @{$sql->{print}{$stmt_key}} );
                }
                $sql->{quote}{$stmt_key}[$i] = $quote_hidd . ' AS ' . $dbh->quote_identifier( $print_hidd );
                $sql->{print}{$stmt_key}[$i] = $print_hidd;
                $qt_columns->{$print_hidd} = $quote_hidd;
                if ( $stmt_key ne 'aggr_cols' ) { # WHERE: aggregate functions are not allowed
                    push @{$sql->{pr_col_with_hidd_func}}, $print_hidd;
                }
                $changed++;
                next HIDDEN;
            }
        }
        elsif( $custom eq $customize{'print_table'} ) {
            my ( $default_cols_sql, $from_stmt ) = $select_from_stmt =~ /^SELECT\s(.*?)(\sFROM\s.*)\z/;
            my $cols_sql;
            if ( $sql->{select_type} eq '*' ) {
                $cols_sql = ' ' . $default_cols_sql;
            }
            elsif ( $sql->{select_type} eq 'chosen_cols' ) {
                $cols_sql = ' ' . join( ', ', @{$sql->{quote}{chosen_cols}} );
            }
            elsif ( @{$sql->{quote}{aggr_cols}} || @{$sql->{quote}{group_by_cols}} ) {
                $cols_sql = ' ' . join( ', ', @{$sql->{quote}{group_by_cols}}, @{$sql->{quote}{aggr_cols}} );
            }
            else { #
                $cols_sql = ' ' . $default_cols_sql;
            }
            my $select .= "SELECT" . $sql->{quote}{distinct_stmt} . $cols_sql . $from_stmt;
            $select .= $sql->{quote}{where_stmt};
            $select .= $sql->{quote}{group_by_stmt};
            $select .= $sql->{quote}{having_stmt};
            $select .= $sql->{quote}{order_by_stmt};
            $select .= $sql->{quote}{limit_stmt};
            my @arguments = ( @{$sql->{quote}{where_args}}, @{$sql->{quote}{having_args}}, @{$sql->{quote}{limit_args}} );
            if ( ! $sql->{quote}{limit_stmt} && $self->{opt}{max_rows} ) {
                $select .= " LIMIT ?";
                push @arguments, $self->{opt}{max_rows};
            }
            local $| = 1;
            print CLEAR_SCREEN;
            say 'Database : ...' if $self->{opt}{progress_bar};
            my $sth = $dbh->prepare( $select );
            $sth->execute( @arguments );
            my $col_names = $sth->{NAME};
            my $all_arrayref = $sth->fetchall_arrayref;
            unshift @$all_arrayref, $col_names;
            print CLEAR_SCREEN;
            return $all_arrayref;
        }
        else {
            die "$custom: no such value in the hash \%customize";
        }
    }
    return;
}

sub __unambiguous_key {
    my ( $self, $new_key, $keys ) = @_;
    while ( any { $new_key eq $_ } @$keys ) {
        $new_key .= '_';
    }
    return $new_key;
}

sub __set_operator_sql {
    my ( $self, $sql, $clause, $table, $cols, $qt_columns, $quote_col ) = @_;
    my ( $stmt, $args );
    my $stmt_h = Term::Choose->new( $self->{info}{lyt_stmt_h} );
    if ( $clause eq 'where' ) {
        $stmt = 'where_stmt';
        $args = 'where_args';
    }
    elsif ( $clause eq 'having' ) {
        $stmt = 'having_stmt';
        $args = 'having_args';
    }
    my $choices = [ @{$self->{opt}{operators}} ];
    unshift @$choices, undef if $self->{opt}{sssc_mode};
    $self->__print_select_statement( $sql, $table );
    # Choose
    my $operator = $stmt_h->choose(
        $choices
    );
    if ( ! defined $operator ) {
        $sql->{quote}{$args} = [];
        $sql->{quote}{$stmt} = '';
        $sql->{print}{$stmt} = '';
        return;
    }
    $operator =~ s/^\s+|\s+\z//g;
    if ( $operator !~ /\s%?col%?\z/ ) {
        my $tiny = Term::ReadLine::Tiny->new();
        if ( $operator !~ /REGEXP\z/ ) {
            $sql->{quote}{$stmt} .= ' ' . $operator;
            $sql->{print}{$stmt} .= ' ' . $operator;
        }
        if ( $operator =~ /NULL\z/ ) {
            # do nothing
        }
        elsif ( $operator =~ /^(?:NOT\s)?IN\z/ ) {
            my $col_sep = '';
            $sql->{quote}{$stmt} .= '(';
            $sql->{print}{$stmt} .= '(';

            IN: while ( 1 ) {
                $self->__print_select_statement( $sql, $table );
                # Readline
                my $value = $tiny->readline( 'Value: ' );
                if ( ! defined $value ) {
                    $sql->{quote}{$args} = [];
                    $sql->{quote}{$stmt} = '';
                    $sql->{print}{$stmt} = '';
                    return;
                }
                if ( $value eq '' ) {
                    if ( $col_sep eq ' ' ) {
                        $sql->{quote}{$args} = [];
                        $sql->{quote}{$stmt} = '';
                        $sql->{print}{$stmt} = '';
                        return;
                    }
                    $sql->{quote}{$stmt} .= ')';
                    $sql->{print}{$stmt} .= ')';
                    last IN;
                }
                $sql->{quote}{$stmt} .= $col_sep . '?';
                $sql->{print}{$stmt} .= $col_sep . $value;
                push @{$sql->{quote}{$args}}, $value;
                $col_sep = ',';
            }
        }
        elsif ( $operator =~ /^(?:NOT\s)?BETWEEN\z/ ) {
            $self->__print_select_statement( $sql, $table );
            # Readline
            my $value_1 = $tiny->readline( 'Value: ' );
            if ( ! defined $value_1 ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $sql->{quote}{$stmt} .= ' ' . '?' .      ' AND';
            $sql->{print}{$stmt} .= ' ' . $value_1 . ' AND';
            push @{$sql->{quote}{$args}}, $value_1;
            $self->__print_select_statement( $sql, $table );
            # Readline
            my $value_2 = $tiny->readline( 'Value: ' );
            if ( ! defined $value_2 ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $sql->{quote}{$stmt} .= ' ' . '?';
            $sql->{print}{$stmt} .= ' ' . $value_2;
            push @{$sql->{quote}{$args}}, $value_2;
        }
        elsif ( $operator =~ /REGEXP\z/ ) {
            $sql->{print}{$stmt} .= ' ' . $operator;
            $self->__print_select_statement( $sql, $table );
            # Readline
            my $value = $tiny->readline( 'Pattern: ' );
            if ( ! defined $value ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $value = '^$' if ! length $value;
            if ( $self->{info}{db_driver} eq 'SQLite' ) {
                $value = qr/$value/i if ! $self->{opt}{regexp_case};
                $value = qr/$value/  if   $self->{opt}{regexp_case};
            }
            $sql->{quote}{$stmt} =~ s/.*\K\s\Q$quote_col\E//;
            my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
            $sql->{quote}{$stmt} .= $obj_db->sql_regexp( $quote_col, $operator =~ /^NOT/ ? 1 : 0 );
            $sql->{print}{$stmt} .= ' ' . "'$value'";
            push @{$sql->{quote}{$args}}, $value;
        }
        else {
            $self->__print_select_statement( $sql, $table );
            my $prompt = $operator =~ /LIKE\z/ ? 'Pattern: ' : 'Value: ';
            # Readline
            my $value = $tiny->readline( $prompt );
            if ( ! defined $value ) {
                $sql->{quote}{$args} = [];
                $sql->{quote}{$stmt} = '';
                $sql->{print}{$stmt} = '';
                return;
            }
            $sql->{quote}{$stmt} .= ' ' . '?';
            $sql->{print}{$stmt} .= ' ' . "'$value'";
            push @{$sql->{quote}{$args}}, $value;
        }
    }
    elsif ( $operator =~ /\s%?col%?\z/ ) {
        my $arg;
        if ( $operator =~ /^(.+)\s(%?col%?)\z/ ) {
            $operator = $1;
            $arg = $2;
        }
        $operator =~ s/^\s+|\s+\z//g;
        $sql->{quote}{$stmt} .= ' ' . $operator;
        $sql->{print}{$stmt} .= ' ' . $operator;
        my $choices = [ @$cols ];
        unshift @$choices, undef if $self->{opt}{sssc_mode};
        $self->__print_select_statement( $sql, $table );
        # Choose
        my $print_col = $stmt_h->choose(
            $choices,
            { prompt => "$operator:" }
        );
        if ( ! defined $print_col ) {
            $sql->{quote}{$stmt} = '';
            $sql->{print}{$stmt} = '';
            return;
        }
        ( my $quote_col = $qt_columns->{$print_col} ) =~ s/\sAS\s\S+\z//;
        my ( @qt_args, @pr_args );
        if ( $arg =~ /^(%)col/ ) {
            push @qt_args, "'$1'";
            push @pr_args, "'$1'";
        }
        push @qt_args, $quote_col;
        push @pr_args, $print_col;
        if ( $arg =~ /col(%)\z/ ) {
            push @qt_args, "'$1'";
            push @pr_args, "'$1'";
        }
        if ( $operator =~ /LIKE\z/ ) {
            my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
            $sql->{quote}{$stmt} .= ' ' . $obj_db->concatenate( \@qt_args );
            $sql->{print}{$stmt} .= ' ' . join( '+', @pr_args );
        }
        else {
            $sql->{quote}{$stmt} .= ' ' . $quote_col;
            $sql->{print}{$stmt} .= ' ' . $print_col;
        }
    }
    return;
}


1;


__END__

package App::DBBrowser;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.997';

use Encode                qw( decode );
use File::Basename        qw( basename );
use File::Spec::Functions qw( catfile catdir );
use Getopt::Long          qw( GetOptions );

use Encode::Locale   qw( decode_argv );
use File::HomeDir    qw();
use Term::Choose     qw();
use Term::TablePrint qw( print_table );

use App::DBBrowser::Opt;
use App::DBBrowser::DB;
#use App::DBBrowser::Join_Union;  # "require"-d
use App::DBBrowser::Table;
use App::DBBrowser::Auxil;

BEGIN {
    decode_argv(); # not at the end of the BEGIN block if less than perl 5.16
    1;
}


sub new {
    my ( $class ) = @_;
    my $info = {
        lyt_1      => {                      layout => 1, order => 0, justify => 2, clear_screen => 1, mouse => 0, undef => '<<'     },
        lyt_stmt_h => { prompt => 'Choose:', layout => 1, order => 0, justify => 2, clear_screen => 0, mouse => 0, undef => '<<'     },
        lyt_3      => {                      layout => 3,             justify => 0, clear_screen => 1, mouse => 0, undef => '  BACK' },
        lyt_stmt_v => { prompt => 'Choose:', layout => 3,             justify => 0, clear_screen => 0, mouse => 0, undef => '  BACK' },
        lyt_stop   => {                                                             clear_screen => 0, mouse => 0                    },
        quit      => 'QUIT',
        back      => 'BACK',
        _quit     => '  QUIT',
        _back     => '  BACK',
        _continue => '  CONTINUE',
        _confirm  => '  CONFIRM',
        _reset    => '  RESET',
        ok        => '- OK -',
        conf_back => '  <=',
        clear_screen      => "\e[H\e[J",
        line_fold         => { Charset=> 'utf8', OutputCharset => '_UNICODE_', Urgent => 'FORCE' },
        config_generic    => 'Generic',
        stmt_init_tab     => 4,
        avail_aggregate   => [ "AVG(X)", "COUNT(X)", "COUNT(*)", "MAX(X)", "MIN(X)", "SUM(X)" ],
        avail_operators   => [ "REGEXP", "REGEXP_i", "NOT REGEXP", "NOT REGEXP_i", "LIKE", "NOT LIKE", "IS NULL", "IS NOT NULL",
                               "IN", "NOT IN", "BETWEEN", "NOT BETWEEN", " = ", " != ", " <> ", " < ", " > ", " >= ", " <= ",
                               "LIKE col", "NOT LIKE col", "LIKE %col%", "NOT LIKE %col%", " = col", " != col", " <> col",
                               " < col", " > col", " >= col", " <= col" ], # "LIKE col%", "NOT LIKE col%", "LIKE %col", "NOT LIKE %col"
        hidd_func_pr      => { Epoch_to_Date => 'DATE', Truncate => 'TRUNC', Epoch_to_DateTime => 'DATETIME',
                               Bit_Length => 'BIT_LENGTH', Char_Length => 'CHAR_LENGTH' },
        keys_hidd_func_pr => [ qw( Epoch_to_Date Bit_Length Truncate Char_Length Epoch_to_DateTime ) ],
        csv_opt           => [ qw( allow_loose_escapes allow_loose_quotes allow_whitespace auto_diag
                                   blank_is_undef binary empty_is_undef eol escape_char quote_char sep_char ) ],
    };
    return bless { info => $info }, $class;
}


sub __init {
    my ( $self ) = @_;
    my $home = decode( 'locale', File::HomeDir->my_home() );
    if ( ! $home ) {
        print "'File::HomeDir->my_home()' could not find the home directory!\n";
        print "'db-browser' requires a home directory\n";
        exit;
    }
    my $my_data = decode( 'locale', File::HomeDir->my_data() );
    my $app_dir = $my_data ? catdir( $my_data, 'db_browser_conf' ) : catdir( $home, '.db_browser_conf' );
    mkdir $app_dir or die $! if ! -d $app_dir;
    $self->{info}{home_dir}      = $home;
    $self->{info}{app_dir}       = $app_dir;
    $self->{info}{conf_file_fmt} = catfile $app_dir, 'config_%s.json';
    $self->{info}{db_cache_file} = catfile $app_dir, 'cache_db_search.json';
    $self->{info}{input_files}   = catfile $app_dir, 'file_history.txt';

    if ( ! eval {
        my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, {}, {} );
        $self->{opt}    = $obj_opt->read_config_files();
        $self->{db_opt} = $obj_opt->read_db_config_files();
        my $help;
        GetOptions (
            'h|?|help' => \$help,
            's|search' => \$self->{info}{sqlite_search},
        );
        if ( $help ) {
            if ( $self->{opt}{table}{mouse} ) {
                for my $key ( keys %{$self->{info}} ) {
                    next if $key !~ /^lyt_/;
                    $self->{info}{$key}{mouse} = $self->{opt}{table}{mouse};
                }
            }
            ( $self->{opt}, $self->{db_opt} ) = $obj_opt->set_options();
            if ( defined $self->{opt}{table}{mouse} ) {
                for my $key ( keys %{$self->{info}} ) {
                    next if $key !~ /^lyt_/;
                    $self->{info}{$key}{mouse} = $self->{opt}{table}{mouse};
                }
            }
        }
        1 }
    ) {
        my $auxil = App::DBBrowser::Auxil->new( $self->{info} );
        $auxil->__print_error_message( $@, 'Configfile/Options' );
        my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, {}, {} );
        $self->{opt} = $obj_opt->defaults();
        while ( $ARGV[0] && $ARGV[0] =~ /^-/ ) {
            my $arg = shift @ARGV;
            last if $arg eq '--';
        }
    }
    if ( $self->{opt}{table}{mouse} ) {
        for my $key ( keys %{$self->{info}} ) {
            next if $key !~ /^lyt_/;
            $self->{info}{$key}{mouse} = $self->{opt}{table}{mouse};
        }
    }
}


sub __prepare_connect_parameter {
    my ( $self, $db ) = @_;
    my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
    my $connect_attr = $obj_db->connect_attributes();
    my $login_data = $obj_db->login_data();
    my $connect_parameter = {
        attributes => {},
        login_data => {},
        login_mode => {},
        dir_sqlite => [],
    };
    my $db_plugin = $self->{info}{db_plugin};
    my $section = $db ? $db_plugin . '_' . $db : $db_plugin;
    for my $option ( keys %{$self->{db_opt}{$db_plugin}} ) {
        if ( defined $db && ! defined $self->{db_opt}{$section}{$option} ) {
            $section = $db_plugin;
        }
        if ( defined $self->{info}{driver_prefix} && $option =~ /^\Q$self->{info}{driver_prefix}\E/ ) {
            $connect_parameter->{attributes}{$option} = $self->{db_opt}{$section}{$option};
        }
    }
    for my $attr ( @$connect_attr ) {
        my $name = $attr->{name};
        if ( defined $db && ! defined $self->{db_opt}{$section}{$name} ) {
            $section = $db_plugin;
        }
        if ( ! defined $self->{db_opt}{$section}{$name} ) {
            $self->{db_opt}{$section}{$name} = $attr->{avail_values}[$attr->{default_index}];
        }
        $connect_parameter->{attributes}{$name} = $self->{db_opt}{$section}{$name};
    }
    for my $item ( @$login_data ) {
        my $name = $item->{name};
        my $login_mode_key = 'login_mode_' . $name;
        $connect_parameter->{keep_secret}{$name} = $item->{keep_secret};
        if ( defined $db && ! defined $self->{db_opt}{$section}{$login_mode_key} ) {
            $section = $db_plugin;
        }
        if ( ! defined $self->{db_opt}{$section}{$login_mode_key} ) {
            $self->{db_opt}{$section}{$login_mode_key} = 0;
        }
        $connect_parameter->{login_mode}{$name} = $self->{db_opt}{$section}{$login_mode_key};
        if ( ! $self->{info}{error} ) {
            if ( defined $db && ! defined $self->{db_opt}{$section}{$name} ) {
                $section = $db_plugin;
            }
            $connect_parameter->{login_data}{$name} = $self->{db_opt}{$section}{$name};
        }
    }
    if ( ! defined $self->{db_opt}{$db_plugin}{directories_sqlite} ) {
        $self->{db_opt}{$db_plugin}{directories_sqlite} = [ $self->{info}{home_dir} ];
    }
    $connect_parameter->{dir_sqlite} = $self->{db_opt}{$db_plugin}{directories_sqlite};
    delete $self->{info}{error} if exists $self->{info}{error};
    return $connect_parameter;
}


sub run {
    my ( $self ) = @_;
    $self->__init();
    my $lyt_3 = Term::Choose->new( $self->{info}{lyt_3} );
    my $auxil = App::DBBrowser::Auxil->new( $self->{info} );
    my $auto_one = 0;

    DB_PLUGIN: while ( 1 ) {

        my $db_plugin;
        if ( @{$self->{opt}{G}{db_plugins}} == 1 ) {
            $auto_one++;
            $db_plugin = $self->{opt}{G}{db_plugins}[0];
        }
        else {
            # Choose
            $db_plugin = $lyt_3->choose(
                [ undef, @{$self->{opt}{G}{db_plugins}} ],
                { %{$self->{info}{lyt_1}}, prompt => 'DB Plugin: ', undef => $self->{info}{quit} }
            );
            last DB_PLUGIN if ! defined $db_plugin;
        }
        $self->{info}{db_plugin} = $db_plugin;
        my $obj_db;
        if ( ! eval {
            $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
            $self->{info}{db_driver} = $obj_db->db_driver();
            die "No database driver!" if ! $self->{info}{db_driver};
            $self->{info}{driver_prefix} = $obj_db->driver_prefix(); #
            1 }
        ) {
            $auxil->__print_error_message( $@, 'DB plugin - driver - prefix' );
            next DB_PLUGIN;
        }
        my $db_driver = $self->{info}{db_driver};
        ###
        $self->{opt}{G}{sqlite_directories} = $self->{db_opt}{$db_plugin}{directories_sqlite};                              ### 1.1
        $self->{opt}{G}{sqlite_directories} = [ $self->{info}{home_dir} ] if ! defined $self->{opt}{G}{sqlite_directories}; ### 1.1

        # DATABASES

        my $databases = [];
        if ( ! eval {
            my $connect_parameter = $self->__prepare_connect_parameter();
            my ( $user_db, $system_db ) = $obj_db->available_databases( $connect_parameter );
            $system_db = [] if ! defined $system_db;
            if ( $db_driver eq 'SQLite' ) {
                $databases = [ @$user_db, @$system_db ];
            }
            else {
                $databases = [ map( "- $_", @$user_db ), map( "  $_", @$system_db ) ];
            }
            $self->{info}{sqlite_search} = 0 if $self->{info}{sqlite_search};
            1 }
        ) {
            $auxil->__print_error_message( $@, 'Available databases' );
            $self->{info}{error} = 1;
            next DB_PLUGIN;
        }
        if ( ! @$databases ) {
            $auxil->__print_error_message( "no $db_driver-databases found\n" );
            exit if @{$self->{opt}{G}{db_plugins}} == 1;
            next DB_PLUGIN;
        }

        my $db;
        my $old_idx_db = 0;

        DATABASE: while ( 1 ) {

            if ( @$databases == 1 ) {
                $db = $databases->[0];
                $auto_one++ if $auto_one == 1;
            }
            else {
                my $back;
                if ( $db_driver eq 'SQLite' ) {
                    $back = $auto_one ? $self->{info}{quit} : $self->{info}{back};
                }
                else {
                    $back = $auto_one ? $self->{info}{_quit} : $self->{info}{_back};
                }
                my $prompt = 'Choose Database:';
                my $choices_db = [ undef, @$databases ];
                # Choose
                my $idx_db = $lyt_3->choose(
                    $choices_db,
                    { prompt => $prompt, index => 1, default => $old_idx_db, undef => $back }
                );
                $db = undef;
                $db = $choices_db->[$idx_db] if defined $idx_db;
                if ( ! defined $db ) {
                    last DB_PLUGIN if @{$self->{opt}{G}{db_plugins}} == 1;
                    next DB_PLUGIN;
                }
                if ( $self->{opt}{G}{menus_db_memory} ) {
                    if ( $old_idx_db == $idx_db ) {
                        $old_idx_db = 0;
                        next DATABASE;
                    }
                    else {
                        $old_idx_db = $idx_db;
                    }
                }
            }
            $db =~ s/^[-\ ]\s// if $db_driver ne 'SQLite';

            # DB-HANDLE

            my $dbh;
            if ( ! eval {
                print $self->{info}{clear_screen};
                print 'DB: "'. basename( $db ) . '"' . "\n";
                my $connect_parameter = $self->__prepare_connect_parameter( $db );
                $dbh = $obj_db->get_db_handle( $db, $connect_parameter );
                1 }
            ) {
                $auxil->__print_error_message( $@, 'Get database handle' );
                # remove database from @databases
                $self->{info}{error} = 1;
                next DATABASE;
            }

            # SCHEMAS

            my @schemas;
            if ( ! eval {
                my ( $user_schemas, $system_schemas ) = $obj_db->get_schema_names( $dbh, $db );
                $system_schemas = [] if ! defined $system_schemas;
                if ( ( @$user_schemas + @$system_schemas ) > 1 ) {
                    @schemas = ( map( "- $_", @$user_schemas ), map( "  $_", @$system_schemas ) );
                }
                else {
                    @schemas = ( @$user_schemas , @$system_schemas );
                }
                1 }
            ) {
                $auxil->__print_error_message( $@, 'Get schema names' );
                next DATABASE;
            }
            my $old_idx_sch = 0;

            SCHEMA: while ( 1 ) {

                my $schema;
                if ( @schemas == 1 ) {
                    $schema = $schemas[0];
                    $auto_one++ if $auto_one == 2
                }
                else {
                    my $back   = $auto_one == 2 ? $self->{info}{_quit} : $self->{info}{_back};
                    my $prompt = 'DB "'. basename( $db ) . '" - choose Schema:';
                    my $choices_schema = [ undef, @schemas ];
                    # Choose
                    my $idx_sch = $lyt_3->choose(
                        $choices_schema,
                        { prompt => $prompt, index => 1, default => $old_idx_sch, undef => $back }
                    );
                    $schema = $choices_schema->[$idx_sch] if defined $idx_sch;
                    if ( ! defined $schema ) {
                        next DATABASE  if @$databases                    > 1;
                        next DB_PLUGIN if @{$self->{opt}{G}{db_plugins}} > 1;
                        last DB_PLUGIN;
                    }
                    if ( $self->{opt}{G}{menus_db_memory} ) {
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

                # TABLES

                my $data = {};
                my @tables;
                if ( ! eval {
                    my ( $user_tbl, $system_tbl ) = $obj_db->get_table_names( $dbh, $schema );
                    $system_tbl = [] if ! defined $system_tbl;
                    $data->{tables} = [ @$user_tbl, @$system_tbl ];
                    @tables = ( map( "- $_", @$user_tbl ), map( "  $_", @$system_tbl ) );
                    1 }
                ) {
                    $auxil->__print_error_message( $@, 'Get table names' );
                    next DATABASE;
                }
                my $old_idx_tbl = 0;

                TABLE: while ( 1 ) {

                    my ( $join, $union, $db_setting ) = ( '  Join', '  Union', '  Database settings' );
                    my $choices_table = [ undef, @tables, $join, $union, $db_setting ];
                    my $back   = $auto_one == 3 ? $self->{info}{_quit} : $self->{info}{_back};
                    my $prompt = 'DB: "'. basename( $db ) . ( @schemas > 1 ? '.' . $schema : '' ) . '"';
                    # Choose
                    my $idx_tbl = $lyt_3->choose(
                        $choices_table,
                        { prompt => $prompt, index => 1, default => $old_idx_tbl, undef => $back }
                    );
                    my $table = $choices_table->[$idx_tbl] if defined $idx_tbl;
                    if ( ! defined $table ) {
                        next SCHEMA    if @schemas                       > 1;
                        next DATABASE  if @$databases                    > 1;
                        next DB_PLUGIN if @{$self->{opt}{G}{db_plugins}} > 1;
                        last DB_PLUGIN;
                    }
                    if ( $self->{opt}{G}{menus_db_memory} ) {
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
                        my $new_db_settings;
                        if ( ! eval {
                            my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt}, $self->{db_opt} );
                            $new_db_settings = $obj_opt->database_setting( $db );
                            1 }
                        ) {
                            $auxil->__print_error_message( $@, 'Database settings' );
                            next TABLE;
                        }
                        next SCHEMA if $new_db_settings;
                        next TABLE;
                    }
                    elsif ( $table eq $join ) {
                        if ( ! eval {
                            require App::DBBrowser::Join_Union;
                            my $obj_ju = App::DBBrowser::Join_Union->new( $self->{info}, $self->{opt} );
                            $multi_table = $obj_ju->__join_tables( $dbh, $db, $schema, $data );
                            $table = 'joined_tables';
                            1 }
                        ) {
                            $auxil->__print_error_message( $@, 'Join tables' );
                            next TABLE;
                        }
                        next TABLE if ! defined $multi_table;
                    }
                    elsif ( $table eq $union ) {
                        if ( ! eval {
                            require App::DBBrowser::Join_Union;
                            my $obj_ju = App::DBBrowser::Join_Union->new( $self->{info}, $self->{opt} );
                            $multi_table = $obj_ju->__union_tables( $dbh, $db, $schema, $data );
                            if ( $obj_ju->{union_all} ) {
                                $table = 'union_all_tables';
                            }
                            else {
                                $table = 'union_selected_tables';
                            }
                            1 }
                        ) {
                            $auxil->__print_error_message( $@, 'Union tables' );
                            next TABLE;
                        }
                        next TABLE if ! defined $multi_table;
                    }
                    else {
                        $table =~ s/^[-\ ]\s//;
                    }
                    #if ( ! eval {
                         $self->__browse_the_table( $dbh, $db, $schema, $table, $multi_table );
                    #    1 }
                    #) {
                    #    $auxil->__print_error_message( $@, 'Browse table' );
                    #    next TABLE;
                    #}
                }
            }
            $dbh->disconnect();
        }
    }
}


sub __browse_the_table {
    my ( $self, $dbh, $db, $schema, $table, $multi_table ) = @_;
    my $auxil     = App::DBBrowser::Auxil->new( $self->{info} );
    my $db_plugin = $self->{info}{db_plugin};
    my $qt_columns = {};
    my $pr_columns = [];
    my $sql        = {};
    $sql->{strg_keys} = [ qw( distinct_stmt set_stmt where_stmt group_by_stmt having_stmt order_by_stmt limit_stmt ) ];
    $sql->{list_keys} = [ qw( chosen_cols set_args aggr_cols where_args group_by_cols having_args insert_into_args ) ];
    $auxil->__reset_sql( $sql );
    $self->{info}{lock} = $self->{opt}{G}{lock_stmt};
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
    my $obj_table = App::DBBrowser::Table->new( $self->{info}, $self->{opt} );
    $self->{opt}{table}{binary_filter} = $self->{db_opt}{$db_plugin . '_' . $db}{binary_filter};
    if ( ! defined $self->{opt}{table}{binary_filter} ) {
        $self->{opt}{table}{binary_filter} = $self->{db_opt}{$db_plugin}{binary_filter};
    }

    PRINT_TABLE: while ( 1 ) {
        my $all_arrayref;
        if ( ! eval {
            ( $all_arrayref, $sql ) = $obj_table->__on_table( $sql, $dbh, $table, $select_from_stmt, $qt_columns, $pr_columns );
            1 }
        ) {
            $auxil->__print_error_message( $@, 'Print table' );
            next PRINT_TABLE;
        }
        last PRINT_TABLE if ! defined $all_arrayref;
        delete @{$self->{info}}{qw(width_head width_cols not_a_number)};
        print_table( $all_arrayref, $self->{opt}{table} );
        if ( defined $self->{info}{backup_max_rows} ) {
            $self->{opt}{table}{max_rows} = delete $self->{info}{backup_max_rows};
        }
    }
}




1;


__END__

=pod

=encoding UTF-8

=head1 NAME

App::DBBrowser - Browse SQLite/MySQL/PostgreSQL databases and their tables interactively.

=head1 VERSION

Version 0.997

=head1 DESCRIPTION

See L<db-browser> for further information.

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012-2015 Matthäus Kiem.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut

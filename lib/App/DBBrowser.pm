package App::DBBrowser;

use warnings FATAL => 'all';
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.049_03';

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
use App::DBBrowser::Util;

BEGIN {
    decode_argv(); # not at the end of the BEGIN block if less than perl 5.16
    1;
}

sub CLEAR_SCREEN () { "\e[H\e[J" }



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
        avail_operators   => [ "REGEXP", "NOT REGEXP", "LIKE", "NOT LIKE", "IS NULL", "IS NOT NULL", "IN", "NOT IN",
                            "BETWEEN", "NOT BETWEEN", " = ", " != ", " <> ", " < ", " > ", " >= ", " <= ", "LIKE col",
                            "NOT LIKE col", "LIKE %col%", "NOT LIKE %col%", " = col", " != col", " <> col", " < col",
                            " > col", " >= col", " <= col" ], # "LIKE col%", "NOT LIKE col%", "LIKE %col", "NOT LIKE %col"
        hidd_func_pr      => { Epoch_to_Date => 'DATE', Truncate => 'TRUNC', Epoch_to_DateTime => 'DATETIME',
                               Bit_Length => 'BIT_LENGTH', Char_Length => 'CHAR_LENGTH' },
        keys_hidd_func_pr => [ qw( Epoch_to_Date Bit_Length Truncate Char_Length Epoch_to_DateTime ) ],
        connect_opt_pre   => {  SQLite => 'sqlite_', mysql => 'mysql_', Pg => 'pg_' },
        csv_opt           => [ qw( allow_loose_escapes allow_loose_quotes allow_whitespace auto_diag
                                   blank_is_undef binary empty_is_undef eol escape_char quote_char sep_char ) ],
    };
    return bless { info => $info }, $class;
}


sub __init {
    my ( $self ) = @_;
    my $home = decode( 'locale', File::HomeDir->my_home() );
    if ( ! $home ) {
        say "'File::HomeDir->my_home()' could not find the home directory!";
        say "'db-browser' requires a home directory";
        exit;
    }
    my $my_data = decode( 'locale', File::HomeDir->my_data() );
    my $app_dir = $my_data ? catdir( $my_data, 'db_browser_conf' ) : catdir( $home, '.db_browser_conf' );
    mkdir $app_dir or die $! if ! -d $app_dir;
    $self->{info}{app_dir}       = $app_dir;
    $self->{info}{conf_file_fmt} = catfile $app_dir, 'config_%s.json';
    $self->{info}{db_cache_file} = catfile $app_dir, 'cache_db_search.json';
    $self->{info}{input_files}   = catfile $app_dir, 'file_history.txt';

    if ( ! eval {
        my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, {} );
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
        my $util = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
        $util->__print_error_message( $@ );
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
    $self->{info}{sqlite_dirs} = @ARGV ? \@ARGV : $self->{opt}{SQLite}{dirs_sqlite_search} // [ $home ];
}


sub run {
    my ( $self ) = @_;
    $self->__init();
    my $lyt_3 = Term::Choose->new( $self->{info}{lyt_3} );
    my $util  = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
    my $db_plugin;

    DB_PLUGIN: while ( 1 ) {

        if ( @{$self->{opt}{db_plugins}} == 1 ) {
            $self->{info}{one_db_plugin} = 1;
            $db_plugin = $self->{opt}{db_plugins}[0];
        }
        else {
            $self->{info}{one_db_plugin} = 0;
            # Choose
            $db_plugin = $lyt_3->choose(
                [ undef, @{$self->{opt}{db_plugins}} ],
                { %{$self->{info}{lyt_1}}, prompt => 'Database Driver: ', undef => 'Quit' }
            );
            last DB_PLUGIN if ! defined $db_plugin;
        }
        $self->{info}{db_plugin} = $db_plugin;
        my $obj_db = App::DBBrowser::DB->new( $self->{info}, $self->{opt} );
        my $db_driver = $obj_db->db_driver();
        $self->{info}{db_driver} = $db_driver;
        my $login_cache = {}; #
        $self->fill_login_chache( $login_cache );


        my $databases = [];
        my $dbs_cached = 0;
        if ( ! eval {
            if ( $db_driver eq 'SQLite' ) {
                my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
                my $cache_key = $db_plugin . '_' . join ' ', @{$self->{info}{sqlite_dirs}};
                my $db_cache = $obj_opt->read_json( $self->{info}{db_cache_file} );
                if ( $self->{info}{sqlite_search} ) {
                    delete $db_cache->{$cache_key};
                    $self->{info}{sqlite_search} = 0;
                }
                if ( ! defined $db_cache->{$cache_key} ) {
                    ( $databases ) = $obj_db->available_databases( $self->{opt}{metadata}, $self->{info}{sqlite_dirs} );
                    $db_cache->{$cache_key} = $databases;
                    $obj_opt->write_json( $self->{info}{db_cache_file}, $db_cache );
                }
                else {
                    $dbs_cached = 1;
                    $databases = $db_cache->{$cache_key};
                }
            }
            else {
                my ( $user_db, $system_db ) = $obj_db->available_databases( $self->{opt}{metadata}, $login_cache );
                $system_db //= [];
                $databases = [ map( "- $_", @$user_db ), map( "  $_", @$system_db ) ];
                #$databases = $db_driver eq 'SQLite' ? [ @$user_db, @$system_db ] : [ map( "- $_", @$user_db ), map( "  $_", @$system_db ) ];
            }
            1 }
        ) {
            say 'Available databases:';
            $login_cache = {};
            $util->__print_error_message( $@ );
            next DB_PLUGIN;
        }
        if ( ! @$databases ) {
            $util->__print_error_message( "no $db_driver-databases found\n" );
            exit if @{$self->{opt}{db_plugins}} == 1;
            next DB_PLUGIN;
        }

        my $db;
        my $data = {};
        my $old_idx_db = 0;
        my $new_db_settings = 0;
        my $back = ( $db_driver eq 'SQLite' ? '' : ' ' x 2 ) . ( $self->{info}{one_db_plugin} ? 'Quit' : 'BACK' );
        my $prompt = 'Choose Database' . ( $dbs_cached ? ' (cached)' : '' );
        my $choices_db = [ undef, @$databases ];

        DATABASE: while ( 1 ) {

            if ( $new_db_settings ) {
                $new_db_settings = 0;
                $data = {};
            }
            else {
                # Choose
                my $idx_db = $lyt_3->choose(
                    $choices_db,
                    { prompt => $prompt, index => 1, default => $old_idx_db, undef => $back }
                );
                $db = undef;
                $db = $choices_db->[$idx_db] if defined $idx_db;
                if ( ! defined $db ) {
                    last DB_PLUGIN if   $self->{info}{one_db_plugin};
                    next DB_PLUGIN if ! $self->{info}{one_db_plugin};
                }
                if ( $self->{opt}{menus_db_memory} ) {
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
            $self->fill_login_chache( $login_cache, $db ); #


            my $dbh;
            if ( ! eval {
                my $db_key = $db_plugin . '_' . $db;
                my $db_arg = {};
                for my $option ( sort keys %{$self->{opt}{$db_plugin}} ) {
                    next if $option !~ /^\Q$self->{info}{connect_opt_pre}{$db_plugin}\E/;
                    $db_arg->{$option} = $self->{opt}{$db_key}{$option} // $self->{opt}{$db_plugin}{$option};
                }
                print CLEAR_SCREEN;
                print "DB: $db\n";
                $dbh = $obj_db->get_db_handle( $db, $db_arg, $login_cache );
                1 }
            ) {
                say 'Get database handle:';
                $login_cache = {};
                $util->__print_error_message( $@ );
                # remove database from @databases
                next DATABASE;
            }


            my $choices_schema = [];
            if ( ! eval {
                ## if ( ! defined $data->{$db}{schemas} ) {
                my ( $user_sma, $system_sma ) = $obj_db->get_schema_names( $dbh, $db, $self->{opt}{metadata} );
                $system_sma //= [];
                $data->{$db}{schemas} = [ @$user_sma, @$system_sma ];
                $choices_schema = [ map( "- $_", @$user_sma ), map( "  $_", @$system_sma ) ];
                1 }
            ) {
                say 'Get schema names:';
                $util->__print_error_message( $@ );
                next DATABASE;
            }
            my $old_idx_sch = 0;
            unshift @$choices_schema, undef;
            my $prompt = 'DB "'. basename( $db ) . '" - choose Schema:';

            SCHEMA: while ( 1 ) {

                my $schema;
                if ( @{$data->{$db}{schemas}} == 1 ) {
                    $schema = $data->{$db}{schemas}[0];
                }
                elsif ( @{$data->{$db}{schemas}} > 1 ) {
                    # Choose
                    my $idx_sch = $lyt_3->choose(
                        $choices_schema,
                        { prompt => $prompt, index => 1, default => $old_idx_sch }
                    );
                    $schema = $choices_schema->[$idx_sch] if defined $idx_sch;
                    next DATABASE if ! defined $schema;
                    if ( $self->{opt}{menus_db_memory} ) {
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


                my $choices_table = [];
                if ( ! eval {
                    ## if ( ! defined $data->{$db}{$schema}{tables} ) {
                    my ( $user_tbl, $system_tbl ) = $obj_db->get_table_names( $dbh, $schema, $self->{opt}{metadata} );
                    $system_tbl //= [];
                    $data->{$db}{$schema}{tables} = [ @$user_tbl, @$system_tbl ];
                    $choices_table = [ map( "- $_", @$user_tbl ), map( "  $_", @$system_tbl ) ];

                    1 }
                ) {
                    say 'Get table names:';
                    $util->__print_error_message( $@ );
                    next DATABASE;
                }
                my $old_idx_tbl = 0;
                my $join       = '  Join';
                my $union      = '  Union';
                my $db_setting = '  Database settings';
                unshift @$choices_table, undef;
                push    @$choices_table, $join, $union, $db_setting;
                my $prompt = 'DB: "'. basename( $db );##
                #$prompt .= '.' . $schema if defined $data->{$db}{schemas} && @{$data->{$db}{schemas}} > 1;
                $prompt .= '.' . $schema if @{$data->{$db}{schemas}} > 1;
                $prompt .= '"';##

                TABLE: while ( 1 ) {

                    # Choose
                    my $idx_tbl = $lyt_3->choose(
                        $choices_table,
                        { prompt => $prompt, index => 1, default => $old_idx_tbl }
                    );
                    my $table = $choices_table->[$idx_tbl] if defined $idx_tbl;
                    if ( ! defined $table ) {
                        next SCHEMA if defined $data->{$db}{schemas} && @{$data->{$db}{schemas}} > 1;
                        next DATABASE;
                    }
                    if ( $self->{opt}{menus_db_memory} ) {
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
                            $util->__print_error_message( $@ );
                        }
                        next DATABASE if $new_db_settings;
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
                            say 'Join tables:';
                            $util->__print_error_message( $@ );
                        }
                        next TABLE if ! defined $multi_table;
                    }
                    elsif ( $table eq $union ) {
                        if ( ! eval {
                            require App::DBBrowser::Join_Union;
                            my $obj_ju = App::DBBrowser::Join_Union->new( $self->{info}, $self->{opt} );
                            $multi_table = $obj_ju->__union_tables( $dbh, $db, $schema, $data );
                            if ( $obj_ju->{union_all} ) { #
                                $table = 'union_all_tables';
                            }
                            else {
                                $table = 'union_selected_tables';
                            }
                            1 }
                        ) {
                            say 'Union tables:';
                            $util->__print_error_message( $@ );
                        }
                        next TABLE if ! defined $multi_table;
                    }
                    else {
                        $table =~ s/^[-\ ]\s//;
                    }
                    if ( ! eval {
                        my $qt_columns = {};
                        my $pr_columns = [];
                        my $sql        = {};
                        $sql->{strg_keys} = [ qw( distinct_stmt set_stmt where_stmt group_by_stmt having_stmt order_by_stmt limit_stmt ) ];
                        $sql->{list_keys} = [ qw( chosen_cols set_args aggr_cols where_args group_by_cols having_args limit_args insert_into_args ) ];
                        $util->__reset_sql( $sql );

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
                        $self->{opt}{binary_filter}    =    $self->{opt}{$db_plugin . '_' . $db}{binary_filter}
                                                         || $self->{opt}{$db_plugin}{binary_filter};
                        my $obj_table = App::DBBrowser::Table->new( $self->{info}, $self->{opt} );

                        PRINT_TABLE: while ( 1 ) {
                            my $all_arrayref = $obj_table->__on_table( $sql, $dbh, $table, $select_from_stmt, $qt_columns, $pr_columns );
                            last PRINT_TABLE if ! defined $all_arrayref;
                            delete @{$self->{info}}{qw(width_head width_cols not_a_number)};
                            print_table( $all_arrayref, $self->{opt} );
                        }

                        1 }
                    ) {
                        say 'Print table:';
                        $util->__print_error_message( $@ );
                    }
                }
            }
            $dbh->disconnect();
        }
    }
}


sub fill_login_chache {
    my ( $self, $login_cache, $db ) = @_;
    my $db_plugin = $self->{info}{db_plugin};
    for my $key ( 'host', 'port', 'user', 'pass' ) {
        my $login_key = 'login_' . $key;
        if ( $self->{opt}{$login_key} == 2 ) {
            if ( exists $ENV{'DBI_' . uc $key} ) {
                $login_cache->{$key} = $ENV{'DBI_' . uc $key};
            }
            else {
                $self->{opt}{$login_key} = 0; ####
            }
        }
        $login_cache->{$login_key} = $self->{opt}{$login_key};
        #return if $self->{opt}{$login_key} >= 2;
        if ( $self->{opt}{$login_key} == 1 ) {
            if ( $db  ) {
                my $db_key = $db_plugin . '_' . $db;
                if ( defined $self->{opt}{$db_key}{$key} ) {
                    $login_cache->{$key} = $self->{opt}{$db_key}{$key};
                }
            }
            if ( ! defined $login_cache->{$key} ) {
                $login_cache->{'default_' . $key} = $self->{opt}{$db_plugin}{$key};
            }
        }
        elsif ( $self->{opt}{$login_key} == 0  ) {
            if ( defined $self->{opt}{$db_plugin}{$key} ) {
                $login_cache->{$key} = $self->{opt}{$db_plugin}{$key};
            }
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

Version 0.049_03

=head1 DESCRIPTION

See L<db-browser> for further information.

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012-2014 Matthäus Kiem.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut

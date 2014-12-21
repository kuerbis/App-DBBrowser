package App::DBBrowser;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.049_09';

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
        back      => 'BACK',
        confirm   => 'CONFIRM',
        ok        => '- OK -',
        _exit     => '  EXIT',
        _back     => '  BACK',
        _confirm  => '  CONFIRM',
        _continue => '  CONTINUE',
        _info     => '  INFO',
        _reset    => '  RESET',
        clear_screen      => "\e[H\e[J",
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
        my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
        $auxil->__print_error_message( $@, 'Configfile/Options' );
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
}


sub __prepare_connect_parameter {
    my ( $self, $db ) = @_;
    my $db_plugin = $self->{info}{db_plugin};
    my $connect_parameter = {};
    for my $option ( keys %{$self->{opt}{$db_plugin}} ) {
        if ( $option =~ /^\Q$self->{info}{driver_prefix}\E/ ) {
            $connect_parameter->{attributes}{$option} = $self->{opt}{$db_plugin}{$option};
        }
        else {
            next if $self->{opt}{$db_plugin}{error} && $option =~ /^(?:host|port|user|pass)/;
            $connect_parameter->{$option} = $self->{opt}{$db_plugin}{$option};
        }
    }
    delete $self->{opt}{$db_plugin}{error} if exists $self->{opt}{$db_plugin}{error};
    return $connect_parameter;
}


sub run {
    my ( $self ) = @_;
    $self->__init();
    my $lyt_3 = Term::Choose->new( $self->{info}{lyt_3} );
    my $auxil = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    my $auto_one = 0;

    DB_PLUGIN: while ( 1 ) {

        my $db_plugin;
        if ( @{$self->{opt}{db_plugins}} == 1 ) {
            $auto_one++;
            $db_plugin = $self->{opt}{db_plugins}[0];
        }
        else {
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
        $self->{info}{driver_prefix} = $obj_db->driver_prefix();

        # DATABASES

        my $databases = [];
        if ( ! eval {
            my $connect_parameter = $self->__prepare_connect_parameter();
            my ( $user_db, $system_db ) = $obj_db->available_databases( $connect_parameter );
            $system_db = [] if ! defined $system_db;
            if ( $db_driver eq 'SQLite' ) {
                $databases = [ @$user_db, @$system_db ]; #
            }
            else {
                $databases = [ map( "- $_", @$user_db ), map( "  $_", @$system_db ) ];
            }
            $self->{info}{sqlite_search} = 0 if $self->{info}{sqlite_search};
            1 }
        ) {
            $auxil->__print_error_message( $@, 'Available databases' );
            $self->{opt}{$self->{info}{db_plugin}}{error} = 1;
            next DB_PLUGIN;
        }
        if ( ! @$databases ) {
            $auxil->__print_error_message( "no $db_driver-databases found\n" );
            exit if @{$self->{opt}{db_plugins}} == 1;
            next DB_PLUGIN;
        }

        my $db;
        my $old_idx_db = 0;
        my $back = ( $db_driver eq 'SQLite' ? '' : ' ' x 2 ) . ( $auto_one ? 'Quit' : 'BACK' );
        my $prompt = 'Choose Database:';
        my $choices_db = [ undef, @$databases ];

        DATABASE: while ( 1 ) {

            #if ( @$databases == 1 ) {
            #    $db = $databases->[0];
            #    $auto_one++ if $auto_one == 1;
            #}
            #else {
                # Choose
                my $idx_db = $lyt_3->choose(
                    $choices_db,
                    { prompt => $prompt, index => 1, default => $old_idx_db, undef => $back }
                );
                $db = undef;
                $db = $choices_db->[$idx_db] if defined $idx_db;
                if ( ! defined $db ) {
                    last DB_PLUGIN if @{$self->{opt}{db_plugins}} == 1;
                    next DB_PLUGIN;
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
            #}
            $db =~ s/^[-\ ]\s// if $db_driver ne 'SQLite';
            die "'$db': $!. Maybe the cached data is not up to date." if $db_driver eq 'SQLite' && ! -f $db;

            # DB-HANDLE

            my $dbh;
            if ( ! eval {
                print $self->{info}{clear_screen};
                print "DB: $db\n";
                my $connect_parameter = $self->__prepare_connect_parameter();
                $dbh = $obj_db->get_db_handle( $db, $connect_parameter );
                1 }
            ) {
                $auxil->__print_error_message( $@, 'Get database handle' );
                # remove database from @databases
                $self->{opt}{$self->{info}{db_plugin}}{error} = 1;
                next DATABASE;
            }

            # SCHEMAS

            my $data = {};
            my $choices_schema = [];
            if ( ! eval {
                my ( $user_sma, $system_sma ) = $obj_db->get_schema_names( $dbh, $db );
                $system_sma = [] if ! defined $system_sma;
                $data->{$db}{schemas} = [ @$user_sma, @$system_sma ];
                $choices_schema = [ map( "- $_", @$user_sma ), map( "  $_", @$system_sma ) ];
                1 }
            ) {
                $auxil->__print_error_message( $@, 'Get schema names' );
                next DATABASE;
            }
            my $old_idx_sch = 0;
            unshift @$choices_schema, undef;
            my $back = $auto_one == 2 ? '  Quit' : '  BACK';
            my $prompt = 'DB "'. basename( $db ) . '" - choose Schema:';

            SCHEMA: while ( 1 ) {

                my $schema;
                #$data->{$db}{schemas}[0] = undef if ! defined $data->{$db}{schemas}[0];
                if ( @{$data->{$db}{schemas}} == 1 ) {
                    $schema = $data->{$db}{schemas}[0];
                    $auto_one++ if $auto_one == 2
                }
                elsif ( @{$data->{$db}{schemas}} > 1 ) { ###
                    # Choose
                    my $idx_sch = $lyt_3->choose(
                        $choices_schema,
                        { prompt => $prompt, index => 1, default => $old_idx_sch, undef => $back }
                    );
                    $schema = $choices_schema->[$idx_sch] if defined $idx_sch;
                    if ( ! defined $schema ) {
                        next DATABASE;
                        #next DATABASE  if @$databases                 > 1;
                        #next DB_PLUGIN if @{$self->{opt}{db_plugins}} > 1;
                        #last DB_PLUGIN;
                    }
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

                # TABLES

                my $choices_table = [];
                if ( ! eval {
                    my ( $user_tbl, $system_tbl ) = $obj_db->get_table_names( $dbh, $schema );
                    $system_tbl = [] if ! defined $system_tbl;
                    $data->{$db}{$schema}{tables} = [ @$user_tbl, @$system_tbl ];
                    $choices_table = [ map( "- $_", @$user_tbl ), map( "  $_", @$system_tbl ) ];
                    1 }
                ) {
                    $auxil->__print_error_message( $@, 'Get table names' );
                    next DATABASE;
                }
                my $old_idx_tbl = 0;
                my ( $join, $union, $db_setting ) = ( '  Join', '  Union', '  Database settings' );
                unshift @$choices_table, undef;
                push    @$choices_table, $join, $union, $db_setting;
                my $back = $auto_one == 3 ? '  Quit' : '  BACK';
                my $prompt = 'DB: "'. basename( $db ) . ( @{$data->{$db}{schemas}} > 1 ? '.' . $schema : '' ) . '"';

                TABLE: while ( 1 ) {

                    # Choose
                    my $idx_tbl = $lyt_3->choose(
                        $choices_table,
                        { prompt => $prompt, index => 1, default => $old_idx_tbl, undef => $back }
                    );
                    my $table = $choices_table->[$idx_tbl] if defined $idx_tbl;
                    if ( ! defined $table ) {
                        next SCHEMA    if @{$data->{$db}{schemas}}    > 1;
                        next DATABASE;
                        #next DATABASE  if @$databases                 > 1;
                        #next DB_PLUGIN if @{$self->{opt}{db_plugins}} > 1;
                        #last DB_PLUGIN;
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
                        my $new_db_settings;
                        if ( ! eval {
                            my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
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
                            if ( $obj_ju->{union_all} ) { #
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
                    if ( ! eval {
                         $self->__browse_the_table( $dbh, $db, $schema, $table, $multi_table );
                        1 }
                    ) {
                        $auxil->__print_error_message( $@, 'Print table' );
                        next TABLE;
                    }
                }
            }
            $dbh->disconnect();
        }
    }
}


sub __browse_the_table {
    my ( $self, $dbh, $db, $schema, $table, $multi_table ) = @_;
    my $auxil     = App::DBBrowser::Auxil->new( $self->{info}, $self->{opt} );
    my $obj_table = App::DBBrowser::Table->new( $self->{info}, $self->{opt} );
    my $db_plugin = $self->{info}{db_plugin};
    my $qt_columns = {};
    my $pr_columns = [];
    my $sql        = {};
    $sql->{strg_keys} = [ qw( distinct_stmt set_stmt where_stmt group_by_stmt having_stmt order_by_stmt limit_stmt ) ];
    $sql->{list_keys} = [ qw( chosen_cols set_args aggr_cols where_args group_by_cols having_args limit_args insert_into_args ) ];
    $auxil->__reset_sql( $sql );
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

    PRINT_TABLE: while ( 1 ) {
        my $all_arrayref = $obj_table->__on_table( $sql, $dbh, $table, $select_from_stmt, $qt_columns, $pr_columns );
        last PRINT_TABLE if ! defined $all_arrayref;
        delete @{$self->{info}}{qw(width_head width_cols not_a_number)};
        print_table( $all_arrayref, $self->{opt} );
    }
}




1;


__END__

=pod

=encoding UTF-8

=head1 NAME

App::DBBrowser - Browse SQLite/MySQL/PostgreSQL databases and their tables interactively.

=head1 VERSION

Version 0.049_09

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

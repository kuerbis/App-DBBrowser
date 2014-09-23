package App::DBBrowser;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.040_03';

use Encode                qw( decode );
use File::Basename        qw( basename );
use File::Spec::Functions qw( catfile catdir );
use Getopt::Long          qw( GetOptions );

use Encode::Locale         qw( decode_argv );
use File::HomeDir          qw();
use Term::Choose           qw();
use Term::TablePrint       qw( print_table );

use App::DBBrowser::Opt;
use App::DBBrowser::DB;
#use App::DBBrowser::Join_Union;  # "require"-d
use App::DBBrowser::Table;
use App::DBBrowser::Util;

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
    $self->{info}{argv} = @ARGV ? 1 : 0;
    $self->{info}{sqlite_dirs} = @ARGV ? \@ARGV : $self->{opt}{SQLite}{dirs_sqlite_search} // [ $home ];
}


sub run {
    my ( $self ) = @_;
    $self->__init();
    my $lyt_3 = Term::Choose->new( $self->{info}{lyt_3} );
    my $util = App::DBBrowser::Util->new( $self->{info}, $self->{opt} );
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
            delete $self->{info}{login};
            #delete $self->{info}{login}{$db_driver};
            $util->__print_error_message( $@ );
            next DB_DRIVER;
        }
        if ( ! @$databases ) {
            print_error_message( $self->{info}, "no $db_driver-databases found\n" );
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

            my $dbh;
            if ( ! eval {
                $dbh = $obj_db->get_db_handle( $db );
                $data->{$db}{schemas} = $obj_db->get_schema_names( $dbh, $db ) if ! defined $data->{$db}{schemas};
                1 }
            ) {
                say 'Get database handle and schema names:';
                delete $self->{info}{login}{$db_driver . '_' . $db};
                $util->__print_error_message( $@ );
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

                if ( ! eval {
                    if ( ! defined $data->{$db}{$schema}{tables} ) {
                        $data->{$db}{$schema}{tables} = $obj_db->get_table_names( $dbh, $schema );
                    }
                    1 }
                ) {
                    say 'Get table names:';
                    $util->__print_error_message( $@ );
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
                        $self->{opt}{binary_filter}    =    $self->{opt}{$db_driver . '_' . $db}{binary_filter}
                                                         || $self->{opt}{$db_driver}{binary_filter};
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




1;


__END__

=pod

=encoding UTF-8

=head1 NAME

App::DBBrowser - Browse SQLite/MySQL/PostgreSQL databases and their tables interactively.

=head1 VERSION

Version 0.040_03

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

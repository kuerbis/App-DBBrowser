package # hide from PAUSE
App::DBBrowser::DB;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.049_07';


=head1 NAME

App::DBBrowser database plugin documentation.

=head1 VERSION

Version 0.049_06

=head1 DESCRIPTION

A database plug-in provides the database specific methods. C<App::DBBrowser> considers a module whose name matches the
regex pattern C</^App::DBBrowser::DB::[\w-]+\.pm\z/> and is located in one of the C<@INC> directories as a database
plugins. Plug-ins with the name C<App::DBBrowser::DB::$database_driver.pm> should be for general public use.

The user can add an installed database plugin to the available plugins in the option menu (C<db-browser -h>) by
selecting I<DB> and then I<DB Plugins>.

A suitable database plugin provides the methods named in this documentation.

Column names in method arguments are already quoted with the C<DBI> C<quote_identifier> method.

=head1 METHODS

=head2 new

The constructor method.

=over

=item Arguments

A reference to a hash. The hash entries are:


        app_dir             # path application directoriy
        clear_screen        # clear screen ansi escape sequence

        db_plugin           # name of the database plugin
        metadata            # true or false

                            # ask     use environment variable    don't ask
        login_mode_host     # 0       1                           2
        login_mode_port     # 0       1                           2
        login_mode_user     # 0       1
        login_mode_pass     # 0       1


        # SQLite only:
        sqlite_search       if true, don't use cached database names
        db_cache_file       path to the file with the cached database names
        db_search_path      directories where to search for databases

=item return

The object.

=back

=cut

sub new {
    my ( $class, $info, $opt ) = @_; #
    die "Invalid character in the DB plugin name: $info->{db_plugin}" if $info->{db_plugin} !~ /^[\w_]+\z/;
    #die "Invalid character in the DB plugin name" if $info->{db_plugin} !~ /^[\w_:]+\z/;
    my $db_module = 'App::DBBrowser::DB::' . $info->{db_plugin};
    eval "require $db_module" or die $@;
    my $plugin = $db_module->new( {
        app_dir             => $info->{app_dir},
        db_plugin           => $info->{db_plugin},
        db_cache_file       => $info->{db_cache_file},
        sqlite_search       => $info->{sqlite_search},
        clear_screen        => $info->{clear_screen},
        metadata            => $opt->{metadata},
        db_search_path      => $opt->{SQLite}{db_search_path},
        login_mode_host     => $opt->{login_host},
        login_mode_port     => $opt->{login_port},
        login_mode_user     => $opt->{login_user},
        login_mode_pass     => $opt->{login_pass},
    } );
    bless { db_plugin => $plugin }, $class;
}



=head2 db_driver

=over

=item Arguments

none

=item return

The C<DBI> database driver name used by the plugin.

=back

=cut

sub db_driver {
    my ( $self ) = @_;
    my $db_driver = $self->{db_plugin}->db_driver();
    return $db_driver;
}



=head2 driver_prefix

=over

=item Arguments

none

=item return

The driver-private prefix.

=back

=cut

sub driver_prefix {
    my ( $self ) = @_;
    my $driver_prefix = $self->{db_plugin}->driver_prefix();
    $driver_prefix .= '_' if $driver_prefix !~ /_\z/;
    return $driver_prefix;
}



=head2 available_databases

=over

=item Arguments

A reference to a hash. If C<available_databases> uses the C<get_db_handle> method, the hash reference can be
passed to C<get_db_handle> as the second argument.

=item return

If the option I<metadata> is true, C<available_databases> returns the "user-databases" as an array-reference and the
"system-databases" (if any) as an array-reference.

If the option I<metadata> is not true, C<available_databases> returns only the "user-databases" as an array-reference.

=back

=cut

sub available_databases {
    my ( $self, $connect_parameter ) = @_;
    my ( $user_db, $system_db ) = $self->{db_plugin}->available_databases( $connect_parameter );
    return $user_db, $system_db;
}



=head2 get_db_handle

=over

=item Arguments

The database name and a hash reference with connection data.

The hash reference provides the settings from the option I<Database settings>.

The hash entry C<attributes> holds connection attributes as a hash reference.

    {
        host       => 'host',
        port       => 'port',
        user       => 'user',
        attributes => {
            key => value,
            ...
        },
        ...
    }

=item return

Database handle.

=back

=cut

sub get_db_handle {
    my ( $self, $db, $connect_parameter ) = @_;
    my $dbh = $self->{db_plugin}->get_db_handle( $db, $connect_parameter );
    return $dbh;
}



=head2 get_schema_names

=over

=item Arguments

The database handle and the database name.

=item return

If the option I<metadata> is true, C<get_schema_names> returns the "user-schemas" as an array-reference and the
"system-schemas" (if any) as an array-reference.

If the option I<metadata> is not true, C<get_schema_names> returns only the "user-schemas" as an array-reference.

=back

=cut

sub get_schema_names {
    my ( $self, $dbh, $db ) = @_;
    my ( $user_sma, $system_sma ) = $self->{db_plugin}->get_schema_names( $dbh, $db );
    return $user_sma, $system_sma;
}



=head2 get_table_names

=over

=item Arguments

The database handle and the schema name.

=item return

If the option I<metadata> is true, C<get_table_names> returns the "user-tables" as an array-reference and the
"system-tables" (if any) as an array-reference.

If the option I<metadata> is not true, C<get_table_names> returns only the "user-tables" as an array-reference.

=back

=cut

sub get_table_names {
    my ( $self, $dbh, $schema ) = @_;
    my ( $user_tbl, $system_tbl ) = $self->{db_plugin}->get_table_names( $dbh, $schema );
    return $user_tbl, $system_tbl;
}



=head2 column_names_and_types

The method C<column_names_and_types> is optional.

=over

=item Arguments

Database handle, database name, schema name, available tables as an array reference.

=item return

Two hash references - one for the column names and one for the column types:

    $col_names = {
        table_1 => [ column_1_name, column_2_name, ... ],
        table_2 => [ column_1_name, column_2_name, ... ],
        ...
    }

    $col_types = {
        table_1 => [ column_1_type, column_2_type, ... ],
        table_2 => [ column_1_type, column_2_type, ... ],
        ...
    }

=back

=cut

sub column_names_and_types {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    return if ! $self->{db_plugin}->can( 'column_names_and_types' );
    my ( $col_names, $col_types ) = $self->{db_plugin}->column_names_and_types( $dbh, $db, $schema, $tables );
    return $col_names, $col_types;
}



=head2 primary_and_foreign_keys

The method C<primary_and_foreign_keys> is optional.

=over

=item Arguments

Database handle, database name, schema name, available tables as an array reference.

=item return

Two hash references - one for the primary keys and one for the foreign keys:

    $primary_keys = {
        table_1 => [ 'primary_key_col_1' [ , ... ] ],
        table_2 => [ 'primary_key_col_1' [ , ... ] ],
        ...
    };

    $foreign_keys = {
        table_1 => {
            fk_name_1 => {
                foreign_key_col   => [ 'foreign_key_col_1' [ , ... ] ],
                reference_table   => 'Reference_table',
                reference_key_col => [ 'reference_key_col_1' [ , ... ] ],
            fk_name_2 => {
                ...
            }
        table_2 => {
            ...
        }
    };

=back

=cut

sub primary_and_foreign_keys {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    return if ! $self->{db_plugin}->can( 'primary_and_foreign_keys' );
    my ( $pk_cols, $fks ) = $self->{db_plugin}->primary_and_foreign_keys( $dbh, $db, $schema, $tables );
    return $pk_cols, $fks;
}



=head2 sql_regexp

=over

=item Arguments

Column name, $do_not_match_regexp (true/false), $case_sensitive (true/false).

=item return

The sql regexp substatement.

=back

Example form the plugin C<App::DBBrowser::DB::mysql>:

    sub sql_regexp {
        my ( $self, $col, $do_not_match_regexp, $case_sensitive ) = @_;
        if ( $do_not_match_regexp ) {
            return ' '. $col . ' NOT REGEXP ?'        if ! $case_sensitive;
            return ' '. $col . ' NOT REGEXP BINARY ?' if   $case_sensitive;
        }
        else {
            return ' '. $col . ' REGEXP ?'            if ! $case_sensitive;
            return ' '. $col . ' REGEXP BINARY ?'     if   $case_sensitive;
        }
    }

=cut

sub sql_regexp {
    my ( $self, $quote_col, $do_not_match_regexp, $case_sensitive ) = @_;
    my $sql_regexp = $self->{db_plugin}->sql_regexp( $quote_col, $do_not_match_regexp, $case_sensitive );
    $sql_regexp = ' ' . $sql_regexp if $sql_regexp !~ /^\ /;
    return $sql_regexp;
}



=head2 concatenate

=over

=item Arguments

A reference to an array of strings.

=item return

The sql substatement which concatenates the passed strings.

=back

Example form the plugin C<App::DBBrowser::DB::Pg>:

    sub concatenate {
        my ( $self, $arg ) = @_;
        return join( ' || ', @$arg );
    }

=cut

sub concatenate {
    my ( $self, $arg ) = @_;
    my $concatenated = $self->{db_plugin}->concatenate( $arg );
    return $concatenated;
}



# scalar functions


=head2 epoch_to_datetime

=over

=item Arguments

The column name and the interval.

The interval is 1 (seconds), 1000 (milliseconds) or 1000000 (microseconds).

=item return

The sql epoch to datetime substatement.

=back

Example form the plugin C<App::DBBrowser::DB::mysql>:

    sub epoch_to_datetime {
        my ( $self, $col, $interval ) = @_;
        return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d %H:%i:%s')";
    }

=cut

sub epoch_to_datetime {
    my ( $self, $quote_col, $interval ) = @_;
    my $quote_f = $self->{db_plugin}->epoch_to_datetime( $quote_col, $interval );
    return $quote_f;
}



=head2 epoch_to_date

=over

=item Arguments

The column name and the interval.

The interval is 1 (seconds), 1000 (milliseconds) or 1000000 (microseconds).

=item return

The sql epoch to date substatement.

=back

Example form the plugin C<App::DBBrowser::DB::mysql>:

    sub epoch_to_date {
        my ( $self, $col, $interval ) = @_;
        return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d')"; # example MySQL
    }

=cut

sub epoch_to_date {
    my ( $self, $quote_col, $interval ) = @_;
    my $quote_f = $self->{db_plugin}->epoch_to_date( $quote_col, $interval );
    return $quote_f;
}



=head2 truncate

=over

=item Arguments

The column name and the precision (int).

=item return

The sql truncate substatement.

=back

Example form the plugin C<App::DBBrowser::DB::mysql>:

    sub truncate {
        my ( $self, $col, $precision ) = @_;
        return "TRUNCATE($col,$precision)";
    }

=cut

sub truncate {
    my ( $self, $quote_col, $precision ) = @_;
    my $quote_f = $self->{db_plugin}->truncate( $quote_col, $precision );
    return $quote_f;
}



=head2 bit_length

=over

=item Arguments

The column name.

=item return

The sql bit length substatement.

=back

Example form the plugin C<App::DBBrowser::DB::Pg>:

The sql bit length substatement.

    sub bit_length {
        my ( $self, $col ) = @_;
        return "BIT_LENGTH($col)";
    }

=cut


sub bit_length {
    my ( $self, $quote_col ) = @_;
    my $quote_f = $self->{db_plugin}->bit_length( $quote_col );
    return $quote_f;
}



=head2 char_length

=over

=item Arguments

The column name.

=item return

The sql char length substatement.

=back

Example form the plugin C<App::DBBrowser::DB::Pg>:

    sub char_length {
        my ( $self, $col ) = @_;
        return "CHAR_LENGTH($col)";
    }


=cut

sub char_length {
    my ( $self, $quote_col ) = @_;
    my $quote_f = $self->{db_plugin}->char_length( $quote_col );
    return $quote_f;
}




1;


__END__


=pod

=encoding UTF-8

=head1 CREDITS

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright 2012-2014 Matthäus Kiem.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut

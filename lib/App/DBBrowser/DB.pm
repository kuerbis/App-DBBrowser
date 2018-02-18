package # hide from PAUSE
App::DBBrowser::DB;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_01';



sub new {
    my ( $class, $info, $opt ) = @_;
    my $db_module = 'App::DBBrowser::DB::' . $info->{plugin};
    eval "require $db_module" or die $@;

    my $plugin = $db_module->new( {
        app_dir              => $info->{app_dir},
        home_dir             => $info->{home_dir},
        plugin               => $info->{plugin},
        db_cache_file        => $info->{db_cache_file},
        sqlite_search        => $info->{sqlite_search},
        clear_screen         => $info->{clear_screen},
        add_metadata         => $opt->{G}{meta},
        qualified_table_name => $opt->{G}{qualified_table_name},
    } );
    bless { Plugin => $plugin }, $class;
}


sub message_method_undef_return {
    my ( $sf, $method ) = @_;
    return sprintf '%s method %s: no return value', ref $sf->{Plugin}, $method;
}


sub driver {
    my ( $sf ) = @_;
    my $driver = $sf->{Plugin}->driver();
    die $sf->message_method_undef_return( 'driver' ) if ! defined $driver;
    return $driver;
}


sub read_arguments {
    my ( $sf ) = @_;
    return undef, [] if ! $sf->{Plugin}->can( 'read_arguments' );
    my ( $driver_prefix, $read_args ) = $sf->{Plugin}->read_arguments();
    return $driver_prefix, [] if ! defined $read_args;
    return $driver_prefix, $read_args; # docu
}

sub env_variables {
    my ( $sf ) = @_;
    return [] if ! $sf->{Plugin}->can( 'env_variables' );
    my $env_variables = $sf->{Plugin}->env_variables();
    return [] if ! defined $env_variables;
    return $env_variables;
}

sub set_attributes {
    my ( $sf ) = @_;
    return [] if ! $sf->{Plugin}->can( 'set_attributes' );
    my $connect_attributes = $sf->{Plugin}->set_attributes();
    return [] if ! defined $connect_attributes;
    return $connect_attributes;
}


sub databases {
    my ( $sf, $connect_parameter ) = @_;
    my ( $user_db, $sys_db ) = $sf->{Plugin}->databases( $connect_parameter );
    $user_db = [] if ! defined $user_db;
    $sys_db  = [] if ! defined $sys_db;
    return $user_db, $sys_db;
}


sub db_handle {
    my ( $sf, $db, $connect_parameter ) = @_;
    my $dbh = $sf->{Plugin}->db_handle( $db, $connect_parameter );
    die $sf->message_method_undef_return( 'db_handle' ) if ! defined $dbh;
    return $dbh;
}


sub schemas { ##
    my ( $sf, $dbh, $db ) = @_;
    my ( $user_schema, $sys_schema );
    if ( $sf->{Plugin}->can( 'schemas' ) ) {
        ( $user_schema, $sys_schema ) = $sf->{Plugin}->schemas( $dbh, $db );
    }
    else {
        my $driver = $dbh->{Driver}{Name}; #
        if ( $driver eq 'SQLite' ) {
            $user_schema = [ 'main' ]; # [ undef ];
        }
        elsif( $driver eq 'mysql' ) {
            # MySQL 5.7 Reference Manual  /  MySQL Glossary:
            # In MySQL, physically, a schema is synonymous with a database.
            # You can substitute the keyword SCHEMA instead of DATABASE in MySQL SQL syntax,
            $user_schema = [ $db ];
        }
        elsif( $driver eq 'Pg' ) {
            my $sth = $dbh->table_info( undef, '%', undef, undef );
            # DBD::Pg  3.7.0:
            # The TABLE_SCHEM and TABLE_NAME will be quoted via quote_ident().
            # pg_schema: the unquoted name of the schema
            my $info = $sth->fetchall_hashref( 'pg_schema' );
            my $qr = qr/^(?:pg_|information_schema$)/;
            for my $schema ( keys %$info ) {
                if ( $schema =~ /$qr/ ) {
                    push @$sys_schema, $schema;
                }
                else {
                    push @$user_schema, $schema;
                }
            }
        }
        else {
            my $sth = $dbh->table_info( undef, '%', undef, undef );
            my $info = $sth->fetchall_hashref( 'TABLE_SCHEM' );
            $user_schema = [ keys %$info ];
        }
    }
    $user_schema = [] if ! defined $user_schema;
    $sys_schema  = [] if ! defined $sys_schema;
    return $user_schema, $sys_schema;
}


#sub primary_key_auto {
#    my ( $sf ) = @_;
#    return if ! $sf->{Plugin}->can( 'primary_key_auto' ); #
#    return $sf->{Plugin}->primary_key_auto();
#}


sub regexp_sql {
    my ( $sf, $col, $do_not_match_regexp, $case_sensitive ) = @_;
    if ( $sf->{Plugin}->can( 'sql_regexp' ) ) {
        my $sql_regexp = $sf->{Plugin}->sql_regexp( $col, $do_not_match_regexp, $case_sensitive );
        die $sf->message_method_undef_return( 'sql_regexp' ) if ! defined $sql_regexp;
        $sql_regexp = ' ' . $sql_regexp if $sql_regexp !~ /^\ /;
        return $sql_regexp;
    }
    if ( $sf->driver eq 'SQLite' ) {
        if ( $do_not_match_regexp ) {
            return sprintf ' NOT REGEXP(?,%s,%d)', $col, $case_sensitive;
        }
        else {
            return sprintf ' REGEXP(?,%s,%d)', $col, $case_sensitive;
        }
    }
    elsif ( $sf->driver eq 'mysql' ) {
        if ( $do_not_match_regexp ) {
            return ' '. $col . ' NOT REGEXP ?'        if ! $case_sensitive;
            return ' '. $col . ' NOT REGEXP BINARY ?' if   $case_sensitive;
        }
        else {
            return ' '. $col . ' REGEXP ?'            if ! $case_sensitive;
            return ' '. $col . ' REGEXP BINARY ?'     if   $case_sensitive;
        }
    }
    elsif ( $sf->driver eq 'Pg' ) {
        if ( $do_not_match_regexp ) {
            return ' '. $col . '::text' . ' !~* ?' if ! $case_sensitive;
            return ' '. $col . '::text' . ' !~ ?'  if   $case_sensitive;
        }
        else {
            return ' '. $col . '::text' . ' ~* ?'  if ! $case_sensitive;
            return ' '. $col . '::text' . ' ~ ?'   if   $case_sensitive;
        }
    }
}


sub concatenate {
    my ( $sf, $arg ) = @_;
    if ( $sf->{Plugin}->can( 'concatenate' ) ) {
        my $concatenated = $sf->{Plugin}->concatenate( $arg );
        die $sf->message_method_undef_return( 'concatenate' ) if ! defined $concatenated;
        return $concatenated;
    }
    return 'concat(' . join( ',', @$arg ) . ')'  if $sf->driver eq 'mysql';

    return join( ' || ', @$arg );
}


sub epoch_to_datetime {
    my ( $sf, $col, $interval ) = @_;
    return $sf->{Plugin}->epoch_to_datetime( $col, $interval )    if $sf->{Plugin}->can( 'epoch_to_datetime' );

    return "DATETIME($col/$interval,'unixepoch','localtime')"     if $sf->driver eq 'SQLite';

    # mysql: FROM_UNIXTIME doesn't work with negative timestamps
    return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d %H:%i:%s')"    if $sf->driver eq 'mysql';

    return "(TO_TIMESTAMP(${col}::bigint/$interval))::timestamp"  if $sf->driver eq 'Pg';
}


sub epoch_to_date {
    my ( $sf, $col, $interval ) = @_;
    return $sf->{Plugin}->epoch_to_date( $col, $interval )   if $sf->{Plugin}->can( 'epoch_to_date' );

    return "DATE($col/$interval,'unixepoch','localtime')"    if $sf->driver eq 'SQLite';

    return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d')"        if $sf->driver eq 'mysql';

    return "(TO_TIMESTAMP(${col}::bigint/$interval))::date"  if $sf->driver eq 'Pg';
}


sub truncate {
    my ( $sf, $col, $precision ) = @_;
    return $sf->{Plugin}->truncate( $col, $precision )  if $sf->{Plugin}->can( 'truncate' );

    return "TRUNC($col,$precision)"                     if $sf->driver eq 'Pg';

    return "TRUNCATE($col,$precision)";
}


sub bit_length {
    my ( $sf, $col ) = @_;
    return $sf->{Plugin}->bit_length( $col ) if $sf->{Plugin}->can( 'bit_length' );

    return "BIT_LENGTH($col)";
}


sub char_length {
    my ( $sf, $col ) = @_;
    return $sf->{Plugin}->char_length( $col ) if $sf->{Plugin}->can( 'char_length' );

    return "CHAR_LENGTH($col)";
}




1;


__END__


=head1 NAME

App::DBBrowser::DB - Database plugin documentation.

=head1 VERSION

Version 1.060_01

=head1 DESCRIPTION

A database plugin provides the database specific methods. C<App::DBBrowser> considers a module whose name matches
C</^App::DBBrowser::DB::[^:']+\z/> and which is located in one of the C<@INC> directories as a database plugin.
Plugins with the name C<App::DBBrowser::DB::$database_driver> should be for general use of C<$database_driver>
databases.

The user can add an installed database plugin to the available plugins in the option menu (C<db-browser -h>) by
selecting I<DB> and then I<DB Plugins>.

A suitable database plugin provides the methods named in this documentation.

=head1 METHODS

=head2 Required methods

=head3 new

The constructor method.

=over

=item Arguments

A reference to a hash. The hash entries are:

        app_dir             # path to the application directoriy
        home_dir            # path to the home directory
        plugin              # name of the database plugin
        add_metadata        # true or false

        # SQLite only:
        sqlite_search       # if true, don't use cached database names
        db_cache_file       # path to the file with the cached database names

=item return

The object.

=back

=head3 driver

=over

=item Arguments

none

=item return

The name of the C<DBI> database driver used by the plugin.

=back

=head3 databases

=over

=item Arguments

A reference to a hash. If C<databases> uses the method C<db_handle>, this hash reference can be passed to C<db_handle> as
the second argument. See L</db_handle> for more info about the passed hash reference.

=item return

Returns two array references: the first refers to the array of "user-databases" the second to the "system-databases"
(if any).

If the option I<add_metadata> is true, both - "user-databases" and "system-databases" - are used else only the
"user-databases" are used.

=back

=head3 db_handle

C<db-browser> expects the attribute I<RaiseError> to be enabled.

=over

=item Arguments

The database name and a reference to a hash of hashes.

The hash of hashes provides the settings gathered from the option I<Database settings>. Which I<Database settings> are
available depends on the methods C<read_arguments>, C<env_variables> and C<set_attributes>.

For example the hash of hashes held by C<$connect_parameter> for a C<mysql> plugin could look like this:

    $connect_parameter = {
        use_env_var => {
            DBI_HOST => 1,
            DBI_USER => 0,
            DBI_PASS => 0,
        },
        read_arg => {
            host => undef,
            pass => undef,
            user => 'db_user_name',
            port => undef
        },
        set_attr => {
            mysql_enable_utf8 => 1
        },
        required => {
            port => 0,
            user => 1,
            pass => 1,
            host => 1
        },
        keep_secret => {
            port => 0,
            host => 0,
            pass => 1,
            user => 0
        },
    };

This key is SQLite only:

        dir_sqlite => [ /path/dir, ... ],

The value is a reference to an array. This array contains directories in which to search for SQLite databases.

=item return

Database handle.

=back

=head2 Optional methods

=head4 schemas

=over

=item Arguments

The database handle and the database name.

=item return

Returns the "user-schemas" as an array-reference and the "system-schemas" (if any) as an array-reference.

If the option I<add_metadata> is true, both - "user-schemas" and "system-schemas" are used else only the
"user-schemas" are used.

=back

=head3 Connect

If the database driver is SQLite only C<set_attributes> is used.

=head4 read_arguments

=over

=item Arguments

none

=item return

A reference to an array of hashes. The hashes have two or three key-value pairs:

    { name => 'string', prompt => 'string', keep_secret => true/false }

C<name> holds the field name for example like "user" or "host".

The value of C<prompt> is used as the prompt string, when the user is asked for the data. The C<prompt> entry is
optional. If C<prompt> doesn't exist, the value of C<name> is used instead.

If C<keep_secret> is true, the user input should not be echoed to the terminal. Also the data is not stored in the
plugin configuration file if C<keep_secret> is true.

=back

An example C<read_arguments> method:

    sub read_arguments {
        my ( $self ) = @_;
        return [
            { name => 'host', prompt => "Host",     keep_secret => 0 },
            { name => 'port', prompt => "Port",     keep_secret => 0 },
            { name => 'user', prompt => "User",     keep_secret => 0 },
            { name => 'pass', prompt => "Password", keep_secret => 1 },
        ];
    }

The information returned by the method C<read_arguments> is used to build the entries of the C<db-browser> options
I<Fields> and I<Login Data>.

=head4 env_variables

=over

=item Arguments

none

=item return

A reference to an array of environment variables.

=back

An example C<env_variables> method:

    sub env_variables {
        my ( $self ) = @_;
        return [ qw( DBI_DSN DBI_HOST DBI_PORT DBI_USER DBI_PASS ) ];
    }

See the C<db-browser> option I<ENV Variables>.

=head4 set_attributes

=over

=item Arguments

none

=item return

The driver prefix and a reference to an array of hashes. The hashes have three or four key-value pairs:

    { name => 'string', prompt => 'string', default_index => index, avail_values => [ value_1, value_2, value_3, ... ] }

The value of C<name> is the name of the database connection attribute.

The value of C<prompt> is used as the prompt string. The C<prompt> entry is optional. If C<prompt> doesn't exist, the
value of C<name> is used instead.

C<avail_values> holds the available values for that attribute as an array reference.

The C<avail_values> array entry of the index position C<default_index> is used as the default value.

=back

Example form the plugin C<App::DBBrowser::DB::SQLite>:

    sub set_attributes {
        my ( $self ) = @_;
        return 'sqlite', [
            { name => 'sqlite_unicode',             default_index => 1, avail_values => [ 0, 1 ] },
            { name => 'sqlite_see_if_its_a_number', default_index => 1, avail_values => [ 0, 1 ] },
        ];
    }

C<set_attributes> determines the database handle attributes offered in the C<db-browser> option
I<DB Options>.

=head3 SQL

For SQLite/mysql/Pg the following methods are already built in.

If passed column names are already quoted or not depends on how C<db-browser> was configured.

=head4 regexp_sql

=over

=item Arguments

Column name, C<$do_not_match_regexp> (true/false), C<$case_sensitive> (true/false).

Use the placeholder instead of the string which should match or not match the regexp.

=item return

The sql regexp substatement.

=back

Example (C<mysql>):

    sub regexp_sql {
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

=head4 concatenate

=over

=item Arguments

A reference to an array of strings.

=item return

The sql substatement which concatenates the passed strings.

=back

Example (C<Pg>):

    sub concatenate {
        my ( $self, $arg ) = @_;
        return join( ' || ', @$arg );
    }

=head4 epoch_to_datetime

=over

=item Arguments

The column name and the interval.

The interval is 1 (seconds), 1000 (milliseconds) or 1000000 (microseconds).

=item return

The sql epoch to datetime substatement.

=back

Example (C<mysql>):

    sub epoch_to_datetime {
        my ( $self, $col, $interval ) = @_;
        return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d %H:%i:%s')";
    }

=head4 epoch_to_date

=over

=item Arguments

The column name and the interval.

The interval is 1 (seconds), 1000 (milliseconds) or 1000000 (microseconds).

=item return

The sql epoch to date substatement.

=back

Example (C<mysql>):

    sub epoch_to_date {
        my ( $self, $col, $interval ) = @_;
        return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d')";
    }

=head4 truncate

=over

=item Arguments

The column name and the precision (int).

=item return

The sql truncate substatement.

=back

Example (C<mysql>):

    sub truncate {
        my ( $self, $col, $precision ) = @_;
        return "TRUNCATE($col,$precision)";
    }

=head4 bit_length

=over

=item Arguments

The column name.

=item return

The sql bit length substatement.

=back

Example (C<Pg>):

The sql bit length substatement.

    sub bit_length {
        my ( $self, $col ) = @_;
        return "BIT_LENGTH($col)";
    }

=head4 char_length

=over

=item Arguments

The column name.

=item return

The sql char length substatement.

=back

Example (C<Pg>):

    sub char_length {
        my ( $self, $col ) = @_;
        return "CHAR_LENGTH($col)";
    }

=pod

=encoding UTF-8

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright 2012-2018 Matthäus Kiem.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0. For
details, see the full text of the licenses in the file LICENSE.

=cut

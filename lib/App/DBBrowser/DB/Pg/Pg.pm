package # hide from PAUSE
App::DBBrowser::DB::Pg::Pg;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

#our $VERSION = '';

use DBI qw();

use App::DBBrowser::DB_Credentials;



sub new {
    my ( $class, $opt ) = @_;
    $opt->{db_driver} = 'Pg';
    $opt->{driver_prefix} = 'pg';
    bless $opt, $class;
}


sub db_driver {
    my ( $self ) = @_;
    return $self->{db_driver};
}


sub driver_prefix {
    my ( $self ) = @_;
    return $self->{driver_prefix};
}


sub get_db_handle {
    my ( $self, $db, $connect_parameter ) = @_;
    my $obj_db_cred = App::DBBrowser::DB_Credentials->new( { connect_arg => $connect_parameter } );
    my $host   = $obj_db_cred->get_login( 'host', $self->{login_mode_host} );
    my $port   = $obj_db_cred->get_login( 'port', $self->{login_mode_port} );
    my $user   = $obj_db_cred->get_login( 'user', $self->{login_mode_user} );
    my $passwd = $obj_db_cred->get_login( 'pass', $self->{login_mode_pass} );
    my $dsn  = "dbi:$self->{db_driver}:dbname=$db";
    $dsn .= ";host=$host" if length $host;
    $dsn .= ";port=$port" if length $port;
    my $dbh = DBI->connect( $dsn, $user, $passwd, {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %{$connect_parameter->{attributes}},
    } ) or die DBI->errstr;
    return $dbh;
}


sub available_databases {
    my ( $self, $connect_parameter ) = @_;
    return \@ARGV if @ARGV;
    my @regex_system_db = ( '^postgres$', '^template0$', '^template1$' );
    my $stmt = "SELECT datname FROM pg_database";
    if ( ! $self->{metadata} ) {
        $stmt .= " WHERE " . join( " AND ", ( "datname !~ ?" ) x @regex_system_db );
    }
    $stmt .= " ORDER BY datname";
    my $info_database = 'postgres';
    print $self->{clear_screen};
    print "DB: $info_database\n";
    my $dbh = $self->get_db_handle( $info_database, $connect_parameter );
    my $databases = $dbh->selectcol_arrayref( $stmt, {}, $self->{metadata} ? () : @regex_system_db );
    $dbh->disconnect(); ##
    if ( $self->{metadata} ) {
        my $regexp = join '|', @regex_system_db;
        my $user_db   = [];
        my $system_db = [];
        for my $database ( @{$databases} ) {
            if ( $database =~ /(?:$regexp)/ ) {
                push @$system_db, $database;
            }
            else {
                push @$user_db, $database;
            }
        }
        return $user_db, $system_db;
    }
    else {
        return $databases;
    }
}


sub get_schema_names {
    my ( $self, $dbh, $db ) = @_;
    my @regex_system_sma = ( '^pg_', '^information_schema$' );;
    my $stmt = "SELECT schema_name FROM information_schema.schemata";
    if ( ! $self->{metadata} ) {
        $stmt .= " WHERE " . join( " AND ", ( "schema_name !~ ?" ) x @regex_system_sma );
    }
    $stmt .= " ORDER BY schema_name";
    my $schemas = $dbh->selectcol_arrayref( $stmt, {}, $self->{metadata} ? () : @regex_system_sma );
    if ( $self->{metadata} ) {
        my $regexp = join '|', @regex_system_sma;
        my $user_sma   = [];
        my $system_sma = [];
        for my $schema ( @{$schemas} ) {
            if ( $schema =~ /(?:$regexp)/ ) {
                push @$system_sma, $schema;
            }
            else {
                push @$user_sma, $schema;
            }
        }
        return $user_sma, $system_sma;
    }
    else {
        return $schemas;
    }
}


sub get_table_names {
    my ( $self, $dbh, $schema ) = @_;
    my $stmt = "SELECT table_name FROM information_schema.tables
                    WHERE table_schema = ?
                    ORDER BY table_name";
                    # AND table_type = 'BASE TABLE'
    my $tables = $dbh->selectcol_arrayref( $stmt, {}, ( $schema ) );
    return $tables;
}


sub column_names_and_types {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my ( $col_names, $col_types );
    my $stmt = "SELECT table_name, column_name, data_type
                    FROM information_schema.columns
                    WHERE table_schema = ?";
    my $sth = $dbh->prepare( $stmt );
    $sth->execute( $schema );
    while ( my $row = $sth->fetchrow_arrayref() ) {
        my ( $table, $col_name, $col_type ) = @$row;
        push @{$col_names->{$table}}, $col_name;
        push @{$col_types->{$table}}, $col_type;
    }
    return $col_names, $col_types;
}


sub primary_and_foreign_keys {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my $pk_cols = {};
    my $fks     = {};
    for my $table ( @$tables ) {
        my $sth = $dbh->foreign_key_info( undef, undef, undef, undef, $schema, $table );
        if ( defined $sth ) {
            while ( my $row = $sth->fetchrow_hashref ) {
                my $fk_name = $row->{FK_NAME};
                push @{$fks->{$table}{$fk_name}{foreign_key_col  }}, $row->{FK_COLUMN_NAME};
                push @{$fks->{$table}{$fk_name}{reference_key_col}}, $row->{UK_COLUMN_NAME};
                if ( ! $fks->{$table}{$fk_name}{reference_table} ) {
                    $fks->{$table}{$fk_name}{reference_table} = $row->{UK_TABLE_NAME};
                }
            }
        }
        $pk_cols->{$table} = [ $dbh->primary_key( undef, $schema, $table ) ];
    }
    return $pk_cols, $fks;
}


sub sql_regexp {
    my ( $self, $quote_col, $do_not_match_regexp, $case_sensitive ) = @_;
    if ( $do_not_match_regexp ) {
        return ' '. $quote_col . '::text' . ' !~* ?' if ! $case_sensitive;
        return ' '. $quote_col . '::text' . ' !~ ?'  if   $case_sensitive;
    }
    else {
        return ' '. $quote_col . '::text' . ' ~* ?'  if ! $case_sensitive;
        return ' '. $quote_col . '::text' . ' ~ ?'   if   $case_sensitive;
    }
}


sub concatenate {
    my ( $self, $arg ) = @_;
    return join( ' || ', @$arg );
}


# scalar functions

sub epoch_to_datetime {
    my ( $self, $col, $interval ) = @_;
    return "(TO_TIMESTAMP(${col}::bigint/$interval))::timestamp";
}

sub epoch_to_date {
    my ( $self, $col, $interval ) = @_;
    return "(TO_TIMESTAMP(${col}::bigint/$interval))::date";
}

sub truncate {
    my ( $self, $col, $precision ) = @_;
    return "TRUNC($col,$precision)";
}

sub bit_length {
    my ( $self, $col ) = @_;
    return "BIT_LENGTH($col)";
}

sub char_length {
    my ( $self, $col ) = @_;
    return "CHAR_LENGTH($col)";
}




1;


__END__

package # hide from PAUSE
App::DBBrowser::DB::Pg;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

#our $VERSION = '';

use DBI qw();

use App::DBBrowser::Credentials;



sub new {
    my ( $class, $ref ) = @_;
    $ref->{driver} = 'Pg';
    bless $ref, $class;
}


sub driver {
    my ( $sf ) = @_;
    return $sf->{driver};
}


sub env_variables {
    my ( $sf ) = @_;
    return [ qw( DBI_DSN DBI_HOST DBI_PORT DBI_USER DBI_PASS ) ];
}


sub read_arguments {
    my ( $sf ) = @_;
    return [
        { name => 'host', prompt => "Host",     keep_secret => 0 },
        { name => 'port', prompt => "Port",     keep_secret => 0 },
        { name => 'user', prompt => "User",     keep_secret => 0 },
        { name => 'pass', prompt => "Password", keep_secret => 1 },
    ];
}


sub set_attributes {
    my ( $sf ) = @_;
    return 'pg', [
        { name => 'pg_enable_utf8', default_index => 2, avail_values => [ 0, 1, -1 ] },
    ];
}


sub db_handle {
    my ( $sf, $db, $connect_parameter ) = @_;
    my $obj_db_cred = App::DBBrowser::Credentials->new( { connect_parameter => $connect_parameter } );
    my $dsn;
    if ( ! ( $connect_parameter->{use_env_var}{DBI_DSN} &&  exists $ENV{DBI_DSN} ) ) {
        my $host = $obj_db_cred->get_login( 'host' );
        my $port = $obj_db_cred->get_login( 'port' );
        $dsn = "dbi:$sf->{driver}:dbname=$db";
        $dsn .= ";host=$host" if length $host;
        $dsn .= ";port=$port" if length $port;
    }
    my $user   = $obj_db_cred->get_login( 'user' );
    my $passwd = $obj_db_cred->get_login( 'pass' );
    my $dbh = DBI->connect( $dsn, $user, $passwd, {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %{$connect_parameter->{set_attr}},
    } ) or die DBI->errstr;
    return $dbh;
}


sub databases {
    my ( $sf, $connect_parameter ) = @_;
    return \@ARGV if @ARGV;
    my @regex_system_db = ( '^postgres$', '^template0$', '^template1$' );
    my $stmt = "SELECT datname FROM pg_database";
    if ( ! $sf->{add_metadata} ) {
        $stmt .= " WHERE " . join( " AND ", ( "datname !~ ?" ) x @regex_system_db );
    }
    $stmt .= " ORDER BY datname";
    my $info_database = 'postgres';
    print $sf->{clear_screen};
    print "DB: $info_database\n";
    my $dbh = $sf->db_handle( $info_database, $connect_parameter );
    my $databases = $dbh->selectcol_arrayref( $stmt, {}, $sf->{add_metadata} ? () : @regex_system_db );
    $dbh->disconnect(); ##
    if ( $sf->{add_metadata} ) {
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


#sub primary_key_auto {
#    return "SERIAL PRIMARY KEY";
#}


#sub sql_regexp {
#    my ( $sf, $quote_col, $do_not_match_regexp, $case_sensitive ) = @_;
#    if ( $do_not_match_regexp ) {
#        return ' '. $quote_col . '::text' . ' !~* ?' if ! $case_sensitive;
#        return ' '. $quote_col . '::text' . ' !~ ?'  if   $case_sensitive;
#    }
#    else {
#        return ' '. $quote_col . '::text' . ' ~* ?'  if ! $case_sensitive;
#        return ' '. $quote_col . '::text' . ' ~ ?'   if   $case_sensitive;
#    }
#}

#sub concatenate {
#    my ( $sf, $arg ) = @_;
#    return join( ' || ', @$arg );
#}


# scalar functions

#sub epoch_to_datetime {
#    my ( $sf, $col, $interval ) = @_;
#    return "(TO_TIMESTAMP(${col}::bigint/$interval))::timestamp";
#}

#sub epoch_to_date {
#    my ( $sf, $col, $interval ) = @_;
#    return "(TO_TIMESTAMP(${col}::bigint/$interval))::date";
#}

#sub truncate {
#    my ( $sf, $col, $precision ) = @_;
#    return "TRUNC($col,$precision)";
#}

#sub bit_length {
#    my ( $sf, $col ) = @_;
#    return "BIT_LENGTH($col)";
#}

#sub char_length {
#    my ( $sf, $col ) = @_;
#    return "CHAR_LENGTH($col)";
#}




1;


__END__

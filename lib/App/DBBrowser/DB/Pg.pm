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
        { name => 'host', prompt => "Host",     secret => 0 },
        { name => 'port', prompt => "Port",     secret => 0 },
        { name => 'user', prompt => "User",     secret => 0 },
        { name => 'pass', prompt => "Password", secret => 1 },
    ];
}


sub set_attributes {
    my ( $sf ) = @_;
    return [
        { name => 'pg_enable_utf8', default => 2, values => [ 0, 1, -1 ] },
    ];
}


sub db_handle {
    my ( $sf, $db, $parameter ) = @_;
    my $obj_db_cred = App::DBBrowser::Credentials->new( { parameter => $parameter } );
    my $dsn;
    if ( ! $parameter->{use_env_var}{DBI_DSN} || ! exists $ENV{DBI_DSN} ) {
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
        %{$parameter->{attributes}},
    } ) or die DBI->errstr;
    return $dbh;
}


sub databases {
    my ( $sf, $parameter ) = @_;
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
    my $dbh = $sf->db_handle( $info_database, $parameter );
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



1;


__END__

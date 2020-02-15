package # hide from PAUSE
App::DBBrowser::DB::MariaDB;

use warnings;
use strict;
use 5.010001;

use File::Basename qw( basename );

use DBI qw();

use App::DBBrowser::Credentials;
use App::DBBrowser::Opt::DBGet;


sub new {
    my ( $class, $info, $opt ) = @_;
    my $sf = {
        i => $info,
        o => $opt
    };
    bless $sf, $class;
}


sub get_db_driver {
    my ( $sf ) = @_;
    return 'MariaDB';
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
        { name => 'mariadb_bind_type_guessing', default => 1, values => [ 0, 1 ] },
    ];
}


sub get_db_handle {
    my ( $sf, $db ) = @_;
    my $db_opt_get = App::DBBrowser::Opt::DBGet->new( $sf->{i}, $sf->{o} );
    my $login_data  = $db_opt_get->login_data( $db );
    my $env_var_yes = $db_opt_get->enabled_env_vars( $db );
    my $attributes  = $db_opt_get->attributes( $db );
    my $cred = App::DBBrowser::Credentials->new( $sf->{i}, $sf->{o} );
    my $settings = { login_data => $login_data, env_var_yes => $env_var_yes };
    my $dsn;
    my $show_sofar = 'DB '. basename( $db );
    if ( ! $env_var_yes->{DBI_DSN} || ! exists $ENV{DBI_DSN} ) {
        $dsn = "dbi:$sf->{i}{driver}:dbname=$db";
        my $host = $cred->get_login( 'host', $show_sofar, $settings );
        if ( defined $host ) {
            $show_sofar .= "\n" . 'Host: ' . $host;
            $dsn .= ";host=$host" if length $host;
        }
        my $port = $cred->get_login( 'port', $show_sofar, $settings );
        if ( defined $port ) {
            $show_sofar .= "\n" . 'Port: ' . $port;
            $dsn .= ";port=$port" if length $port;
        }
    }
    my $user   = $cred->get_login( 'user', $show_sofar, $settings );
    $show_sofar .= "\n" . 'User: ' . $user if defined $user;
    my $passwd = $cred->get_login( 'pass', $show_sofar, $settings );
    my $dbh = DBI->connect( $dsn, $user, $passwd, {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %$attributes,
    } ) or die DBI->errstr;
    return $dbh;
}


sub get_databases {
    my ( $sf ) = @_;
    return \@ARGV if @ARGV;
    my @regex_system_db = ( '^mysql$', '^information_schema$', '^performance_schema$' );
    my $stmt = "SELECT schema_name FROM information_schema.schemata";
    if ( ! $sf->{o}{G}{metadata} ) {
        $stmt .= " WHERE " . join( " AND ", ( "schema_name NOT REGEXP ?" ) x @regex_system_db );
    }
    $stmt .= " ORDER BY schema_name";
    my $info_database = 'information_schema';
    #print $sf->{clear_screen};
    #print "DB: $info_database\n";
    my $dbh = $sf->get_db_handle( $info_database );
    my $databases = $dbh->selectcol_arrayref( $stmt, {}, $sf->{o}{G}{metadata} ? () : @regex_system_db );
    $dbh->disconnect(); #
    if ( $sf->{o}{G}{metadata} ) {
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










1;


__END__

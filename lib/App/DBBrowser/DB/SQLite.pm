package # hide from PAUSE
App::DBBrowser::DB::SQLite;

use warnings FATAL => 'all';
use strict;
use 5.010000;
no warnings 'utf8';

#our $VERSION = '';

use Encode     qw( encode decode );
#use File::Find qw( find );  # "require"-d

use DBI            qw();
use Encode::Locale qw();

use App::DBBrowser::Opt;


sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


#sub database_driver {
#    my ( $self ) = @_;
#    return 'SQLite';
#}


sub get_db_handle {
    my ( $self, $db, $db_arg ) = @_;
    #return if ! defined $db;
    my $dsn = 'dbi:SQLite:dbname=' . $db; #
    my $dbh = DBI->connect( $dsn, '', '', {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %$db_arg,
    } ) or die DBI->errstr;
    $dbh->sqlite_create_function( 'regexp', 2, sub {
            my ( $regex, $string ) = @_;
            $string //= '';
            return $string =~ m/$regex/ism;
        }
    );
    $dbh->sqlite_create_function( 'truncate', 2, sub {
            my ( $number, $places ) = @_;
            return if ! defined $number;
            return $number if ! looks_like_number( $number );
            return sprintf "%.*f", $places, int( $number * 10 ** $places ) / 10 ** $places;
        }
    );
    $dbh->sqlite_create_function( 'bit_length', 1, sub {
            use bytes;
            return length $_[0];
        }
    );
    $dbh->sqlite_create_function( 'char_length', 1, sub {
            return length $_[0];
        }
    );
    return $dbh;
}


sub available_databases {
    my ( $self, $metadata ) = @_;
    my $obj_opt = App::DBBrowser::Opt->new( $self->{info}, $self->{opt} );
    my $cache_key = 'SQLite_' . join ' ', @{$self->{info}{sqlite_dirs}}; ###
    $self->{info}{cache} = $obj_opt->read_json( $self->{info}{db_cache_file} );
    if ( $self->{info}{sqlite_search} ) {
        delete $self->{info}{cache}{$cache_key};
        $self->{info}{sqlite_search} = 0;
    }
    if ( $self->{info}{cache}{$cache_key} ) {
        $self->{info}{cached} = ' (cached)';
        return $self->{info}{cache}{$cache_key};
    }
    else {
        my $databases = [];
        require File::Find;
        say 'Searching...';
        for my $dir ( @{$self->{info}{sqlite_dirs}} ) {  ###
            File::Find::find( {
                wanted     => sub {
                    my $file = $File::Find::name;
                    return if ! -f $file;
                    return if ! -s $file; #
                    return if ! -r $file; #
                    #say $file;
                    if ( ! eval {
                        open my $fh, '<:raw', $file or die "$file: $!";
                        defined( read $fh, my $string, 13 ) or die "$file: $!";
                        close $fh;
                        push @$databases, decode( 'locale_fs', $file ) if $string eq 'SQLite format';
                        1 }
                    ) {
                        utf8::decode( $@ );
                        print $@;
                    }
                },
                no_chdir   => 1,
            },
            encode( 'locale_fs', $dir ) );
        }
        say 'Ended searching';
        $self->{info}{cache}{$cache_key} = $databases;
        $obj_opt->write_json( $self->{info}{db_cache_file}, $self->{info}{cache} );
        return $databases;
    }
}


sub get_schema_names {
    my ( $self, $dbh, $db, $metadata ) = @_;
    return [ 'main' ];
}


sub get_table_names {
    my ( $self, $dbh, $schema, $metadata ) = @_;
    my $regexes = regexp_system( $self, 'table' );
    my $stmt = "SELECT name FROM sqlite_master WHERE type = 'table'";
    if ( ! $metadata ) {
        $stmt .= " AND " . join( " AND ", ( "name NOT REGEXP ?" ) x @$regexes );
    }
    $stmt .= " ORDER BY name";
    my $tables = $dbh->selectcol_arrayref( $stmt, {}, $metadata ? () : @$regexes );
    if ( $metadata ) {
        my $regexp = join '|', @$regexes; #
        my $user_tbl   = []; ###
        my $system_tbl = [];
        for my $table ( @{$tables} ) {
            if ( $table =~ /(?:$regexp)/ ) {
                push @$system_tbl, $table;
            }
            else {
                push @$user_tbl, $table;
            }
        }
        push @$system_tbl, 'sqlite_master';
        return $user_tbl, $system_tbl;
    }
    else {
        return $tables, []; ##
    }
}


sub regexp_system {
    my ( $self, $level ) = @_;
    return                if $level eq 'database'; #
    return                if $level eq 'schema';
    return [ '^sqlite_' ] if $level eq 'table';
}


sub column_names_and_types {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my ( $col_names, $col_types );
    for my $table ( @$tables ) {
        my $sth = $dbh->prepare( "SELECT * FROM " . $dbh->quote_identifier( undef, undef, $table ) );
        $col_names->{$table} = $sth->{NAME};
        $col_types->{$table} = $sth->{TYPE};
    }
    return $col_names, $col_types;
}


sub primary_and_foreign_keys {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my $pk_cols = {};
    my $fks     = {};
    for my $table ( @$tables ) {
        for my $c ( @{$dbh->selectall_arrayref( "pragma foreign_key_list( $table )" )} ) {
            $fks->{$table}{$c->[0]}{foreign_key_col}  [$c->[1]] = $c->[3];
            $fks->{$table}{$c->[0]}{reference_key_col}[$c->[1]] = $c->[4];
            $fks->{$table}{$c->[0]}{reference_table} = $c->[2];
        }
        $pk_cols->{$table} = [ $dbh->primary_key( undef, $schema, $table ) ];
    }
    return $pk_cols, $fks;
}


sub sql_regexp {
    my ( $self, $quote_col, $is_not_regexp, $case_sensitive ) = @_;
    if ( $is_not_regexp ) {
        return ' '. $quote_col . ' NOT REGEXP ?';
    }
    else {
        return ' '. $quote_col . ' REGEXP ?';
    }
}


sub concatenate {
    my ( $self, $arg ) = @_;
    return join( ' || ', @$arg );
}



# scalar functions

sub epoch_to_datetime {
    my ( $self, $col, $interval ) = @_;
    return "DATETIME($col/$interval,'unixepoch','localtime')";
}

sub epoch_to_date {
    my ( $self, $col, $interval ) = @_;
    return "DATE($col/$interval,'unixepoch','localtime')";
}

sub truncate {
    my ( $self, $col, $precision ) = @_;
    return "TRUNCATE($col,$precision)";
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

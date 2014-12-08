package # hide from PAUSE
App::DBBrowser::DB::SQLite;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

#our $VERSION = '';

use Encode       qw( encode decode );
#use File::Find   qw( find );  # "require"-d
use Scalar::Util qw( looks_like_number );

use DBI            qw();
use Encode::Locale qw();



sub new {
    my ( $class, $opt ) = @_;
    bless $opt, $class;
}


sub db_driver { #
    my ( $self ) = @_;
    return 'SQLite';
}


sub get_db_handle {
    my ( $self, $db, $db_arg ) = @_;
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
            $string = '' if ! defined $string;
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
    my ( $self, $db_arg, $sqlite_dirs ) = @_;
    my $databases = [];
    require File::Find;
    print 'Searching...' . "\n";
    for my $dir ( @$sqlite_dirs ) {
        File::Find::find( {
            wanted     => sub {
                my $file = $File::Find::name; #
                return if ! -f $file;
                return if ! -s $file; #
                return if ! -r $file; #
                #print "$file\n";
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
    print 'Ended searching' . "\n";
    return $databases;
}


sub get_schema_names {
    my ( $self, $dbh, $db ) = @_;
    return [ 'main' ];
}


sub get_table_names {
    my ( $self, $dbh, $schema ) = @_;
    my $regexp_system_tbl = '^sqlite_';
    my $stmt = "SELECT name FROM sqlite_master WHERE type = 'table'";
    if ( ! $self->{metadata} ) {
        $stmt .= " AND name NOT REGEXP ?";
    }
    $stmt .= " ORDER BY name";
    my $tables = $dbh->selectcol_arrayref( $stmt, {}, $self->{metadata} ? () : ( $regexp_system_tbl ) );
    if ( $self->{metadata} ) {
        my $user_tbl   = [];
        my $system_tbl = [];
        for my $table ( @{$tables} ) {
            if ( $table =~ /(?:$regexp_system_tbl)/ ) {
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

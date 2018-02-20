package # hide from PAUSE
App::DBBrowser::DB::SQLite;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

#our $VERSION = '';

use Encode       qw( encode decode );
use File::Find   qw( find );
use Scalar::Util qw( looks_like_number );

use DBI            qw();
use Encode::Locale qw();

use App::DBBrowser::Auxil;



sub new {
    my ( $class, $ref ) = @_;
    $ref->{driver} = 'SQLite';
    bless $ref, $class;
}


sub driver {
    my ( $sf ) = @_;
    return $sf->{driver};
}


sub set_attributes {
    my ( $sf ) = @_;
    return 'sqlite', [
        { name => 'sqlite_unicode',             default => 1, values => [ 0, 1 ] },
        { name => 'sqlite_see_if_its_a_number', default => 1, values => [ 0, 1 ] },
    ];
}


sub db_handle {
    my ( $sf, $db, $parameter ) = @_;
    my $dsn = "dbi:$sf->{driver}:dbname=$db";
    my $dbh = DBI->connect( $dsn, '', '', {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %{$parameter->{attributes}},
    } ) or die DBI->errstr;
    $dbh->sqlite_create_function( 'regexp', 3, sub {
            my ( $regex, $string, $case_sensitive ) = @_;
            $string = '' if ! defined $string;
            return $string =~ m/$regex/sm if $case_sensitive;
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


sub databases {
    my ( $sf, $parameter ) = @_;
    return \@ARGV if @ARGV;
    my $dirs = $parameter->{dir_sqlite};
    my $cache_key = $sf->{plugin} . '_' . join ' ', @$dirs;
    my $ax = App::DBBrowser::Auxil->new( {}, {} );
    my $db_cache = $ax->read_json( $sf->{db_cache_file} );
    if ( $sf->{sqlite_search} ) {
        delete $db_cache->{$cache_key};
    }
    my $databases = [];
    if ( ! defined $db_cache->{$cache_key} ) {
        print 'Searching...' . "\n";
        for my $dir ( @$dirs ) {
            File::Find::find( {
                wanted => sub {
                    my $file = $_;
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
                no_chdir => 1,
            },
            encode( 'locale_fs', $dir ) );
        }
        print 'Ended searching' . "\n";
        $db_cache->{$cache_key} = $databases;
        $ax->write_json( $sf->{db_cache_file}, $db_cache );
    }
    else {
        $databases = $db_cache->{$cache_key};
    }
    return $databases;
}


#sub primary_key_auto {
#    return "INTEGER PRIMARY KEY";
#}


#sub sql_regexp {
#    my ( $sf, $quote_col, $do_not_match_regexp, $case_sensitive ) = @_;
#    if ( $do_not_match_regexp ) {
#        return sprintf ' NOT REGEXP(?,%s,%d)', $quote_col, $case_sensitive;
#    }
#    else {
#        return sprintf ' REGEXP(?,%s,%d)', $quote_col, $case_sensitive;
#    }
#}

#sub concatenate {
#    my ( $sf, $arg ) = @_;
#    return join( ' || ', @$arg );
#}


# scalar functions

#sub epoch_to_datetime {
#    my ( $sf, $col, $interval ) = @_;
#    return "DATETIME($col/$interval,'unixepoch','localtime')";
#}

#sub epoch_to_date {
#    my ( $sf, $col, $interval ) = @_;
#    return "DATE($col/$interval,'unixepoch','localtime')";
#}

#sub truncate {
#    my ( $sf, $col, $precision ) = @_;
#    return "TRUNCATE($col,$precision)";
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

package # hide from PAUSE
App::DBBrowser::DB::SQLite;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

#our $VERSION = '';

use Encode                qw( encode decode );
use File::Find            qw( find );
use File::Spec::Functions qw( catfile );

use DBI            qw();
use Encode::Locale qw();

use App::DBBrowser::Auxil;


sub new {
    my ( $class, $info ) = @_;
    my $self = {
        driver  => 'SQLite',
        app_dir => $info->{app_dir},
        reset_search_cache => $info->{reset_search_cache},
        sqlite_directories => $info->{sqlite_directories},
    };
    bless $self, $class;
}


sub get_db_driver {
    my ( $self ) = @_;
    return $self->{driver};
}


sub set_attributes {
    my ( $self ) = @_;
    return [
        { name => 'sqlite_unicode',             default => 1, values => [ 0, 1 ] },
        { name => 'sqlite_see_if_its_a_number', default => 1, values => [ 0, 1 ] },
    ];
}


sub get_db_handle {
    my ( $self, $db, $parameter ) = @_;
    my $dsn = "dbi:$self->{driver}:dbname=$db";
    my $dbh = DBI->connect( $dsn, '', '', {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %{$parameter->{attributes}},
    } ) or die DBI->errstr;
    return $dbh;
}


sub get_databases {
    my ( $self ) = @_;
    return \@ARGV if @ARGV;
    my $dirs = $self->{sqlite_directories};
    my $cache_key = __PACKAGE__ . '_' . join ' ', @$dirs;
    my $ax = App::DBBrowser::Auxil->new( {}, {} );
    my $cache_sqlite_files = catfile $self->{app_dir}, 'cache_SQLite_files.json';
    my $db_cache = $ax->read_json( $cache_sqlite_files ); #
    if ( $self->{reset_search_cache} ) {
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
        $ax->write_json( $cache_sqlite_files, $db_cache );
    }
    else {
        $databases = $db_cache->{$cache_key};
    }
    return $databases;
}


#sub primary_key_auto {
#    return "INTEGER PRIMARY KEY";
#}



1;


__END__

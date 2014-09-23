package # hide from PAUSE
App::DBBrowser::DB;

use warnings;
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.040_05';

use Encode       qw( encode decode );
#use File::Find   qw( find );  # "require"-d
use Scalar::Util qw( looks_like_number );

use DBI                    qw();
use Encode::Locale         qw();
use Term::Choose           qw( choose );
use Term::ReadLine::Simple qw();

sub CLEAR_SCREEN () { "\e[H\e[J" }



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub __get_host_or_port {
    my ( $self, $db, $key ) = @_;
    my $db_driver = $self->{info}{db_driver};
    my $db_key = $db_driver . '_' . $db;
    my $prompt = ucfirst( $key ) . ': ';
    my $env_key = 'DBI_' . uc( $key );
    return '' if $db_driver eq 'SQLite';
    if ( $self->{opt}{ask_host_port_per_db} ) {
        return $self->{info}{login}{$db_key}{$key} if defined $self->{info}{login}{$db_key}{$key};
        if ( length $self->{opt}{$db_key}{$key} ) {
            say $prompt . $self->{opt}{$db_key}{$key};
            return $self->{opt}{$db_key}{$key};
        }
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $new = $trs->readline( $prompt, { default => $self->{opt}{$db_driver}{$key} } ); #
        $self->{info}{login}{$db_key}{$key} = $new;
        return $new;
    }
    else {
        return $ENV{$env_key}                 if $self->{opt}{'use_env_dbi_' . $key} && exists $ENV{$env_key};
        return $self->{opt}{$db_driver}{$key} if exists $self->{opt}{$db_driver}{$key} && length $self->{opt}{$db_driver}{$key};
    }
    return;
}


sub __get_user {
    my ( $self, $db ) = @_;
    my $db_driver = $self->{info}{db_driver};
    my $db_key = $db_driver . '_' . $db;
    return '' if $db_driver eq 'SQLite';
    if ( $self->{opt}{ask_user_pass_per_db} ) {
        return $self->{info}{login}{$db_key}{user} if defined $self->{info}{login}{$db_key}{user};
        if ( length $self->{opt}{$db_key}{user} ) {
            say 'User :' . $self->{opt}{$db_key}{user};
            return $self->{opt}{$db_key}{user};
        }
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $new = $trs->readline( 'User: ', { default => $self->{opt}{$db_driver}{user} } ); #
        $self->{info}{login}{$db_key}{user} = $new;
        return $new;
    }
    else {
        return $self->{info}{login}{$db_driver}{user} if defined $self->{info}{login}{$db_driver}{user};
        return $ENV{DBI_USER}                         if $self->{opt}{use_env_dbi_user} && exists $ENV{DBI_USER};
        #return $self->{opt}{$db_key}{user}            if length $self->{opt}{$db_key}{user};
        return $self->{opt}{$db_driver}{user}         if exists $self->{opt}{$db_driver}{user} && length $self->{opt}{$db_driver}{user};
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $new = $trs->readline( 'User: ' );
        $self->{info}{login}{$db_driver}{user} = $new;
        return $new;
    }
}


sub __get_password {
    my ( $self, $db, $user ) = @_;
    my $db_driver = $self->{info}{db_driver};
    my $db_key = $db_driver . '_' . $db;
    return '' if $db_driver eq 'SQLite';
    if ( $self->{opt}{ask_user_pass_per_db} ) {
        return $self->{info}{login}{$db_key}{$user}{passwd} if defined $self->{info}{login}{$db_key}{$user}{passwd};
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $passwd = $trs->readline( 'Password: ', { no_echo => 1 } );
        $self->{info}{login}{$db_key}{$user}{passwd} = $passwd;
        return $passwd;
    }
    else {
        return $self->{info}{login}{$db_driver}{$user}{passwd} if defined $self->{info}{login}{$db_driver}{$user}{passwd};
        return $ENV{DBI_PASS}                                  if $self->{opt}{use_env_dbi_pass} && exists $ENV{DBI_PASS};
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $passwd = $trs->readline( 'Password: ', { no_echo => 1 }  );
        $self->{info}{login}{$db_driver}{$user}{passwd} = $passwd;
        return $passwd;
    }
}


sub get_db_handle {
    my ( $self, $db ) = @_;
    my $db_driver = $self->{info}{db_driver};
    return if ! defined $db && $db_driver eq 'SQLite';
    my $db_key = $db_driver . '_' . $db;
    my $db_arg = {};
    for my $option ( sort keys %{$self->{opt}{$db_driver}} ) {
        next if $option !~ /^\Q$self->{info}{connect_opt_pre}{$db_driver}\E/;
        $db_arg->{$option} = $self->{opt}{$db_key}{$option} // $self->{opt}{$db_driver}{$option};
    }
    print CLEAR_SCREEN;
    print "DB: $db\n";
    my $host = $self->__get_host_or_port( $db, 'host' );
    my $port = $self->__get_host_or_port( $db, 'port' );
    my $dsn = 'dbi:' . $db_driver . ':dbname=' . $db;
    $dsn .= ';host=' . $host if length $host;
    $dsn .= ';port=' . $port if length $port;
    my $user   = $self->__get_user( $db );
    my $passwd = $self->__get_password( $db, $user );
    my $dbh = DBI->connect( $dsn, $user, $passwd, {
        PrintError => 0,
        RaiseError => 1,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        %$db_arg,
    } ) or die DBI->errstr;
    if ( $db_driver eq 'SQLite' ) {
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
    }
    return $dbh;
}


sub available_databases {
    my ( $self, $dbh ) = @_;
    my $databases = [];
    if ( $self->{info}{db_driver} eq 'SQLite' ) {
        require File::Find;
        say 'Searching...';
        for my $dir ( @{$self->{info}{sqlite_dirs}} ) {
            File::Find::find( {
                wanted     => sub {
                    my $file = $File::Find::name;
                    return if ! -f $file;
                    return if ! -s $file; #
                    return if ! -r $file; #
                    say $file;
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
    }
    elsif( $self->{info}{db_driver} eq 'Pg' ) {
        my $regexp = [];
        my $stmt = "SELECT datname FROM pg_database";
        if ( ! $self->{opt}{metadata} ) {
            $regexp = regexp_system( $self, 'database' );
            $stmt .= " WHERE " . join( " AND ", ( "datname !~ ?" ) x @$regexp ) if @$regexp;
        }
        $stmt .= " ORDER BY datname";
        $databases = $dbh->selectcol_arrayref( $stmt, {}, @$regexp );
    }
    elsif( $self->{info}{db_driver} eq 'mysql' ) {
        my $regexp = [];
        my $stmt = "SELECT schema_name FROM information_schema.schemata";
        if ( ! $self->{opt}{metadata} ) {
            $regexp = regexp_system( $self, 'database' );
            $stmt .= " WHERE " . join( " AND ", ( "schema_name NOT REGEXP ?" ) x @$regexp ) if @$regexp;
        }
        $stmt .= " ORDER BY schema_name";
        $databases = $dbh->selectcol_arrayref( $stmt, {}, @$regexp );
    }
    return $databases;
}


sub info_database {
    my ( $self ) = @_;
    return                      if $self->{info}{db_driver} eq 'SQLite';
    return 'information_schema' if $self->{info}{db_driver} eq 'mysql';
    return 'postgres'           if $self->{info}{db_driver} eq 'Pg';
}


sub regexp_system {
    my ( $self, $level ) = @_;
    if ( $self->{info}{db_driver} eq 'SQLite' ) {
        return                if $level eq 'database';
        return                if $level eq 'schema';
        return [ '^sqlite_' ] if $level eq 'table';
    }
    elsif ( $self->{info}{db_driver} eq 'mysql' ) {
        return [ '^mysql$', '^information_schema$', '^performance_schema$' ] if $level eq 'database';
        return                                                               if $level eq 'schema';
        return                                                               if $level eq 'table';
    }
    elsif ( $self->{info}{db_driver} eq 'Pg' ) {
        return [ '^postgres$', '^template0$', '^template1$' ] if $level eq 'database';
        return [ '^pg_', '^information_schema$' ]             if $level eq 'schema';
        return                                                if $level eq 'table';
    }
    else {
        return;
    }
}


sub get_schema_names {
    my ( $self, $dbh, $db ) = @_;
    if ( $self->{info}{db_driver} eq 'SQLite' ) {
        return [ 'main' ];
    }
    elsif ( $self->{info}{db_driver} eq 'Pg' ) {
        my $regexp = [];
        my $stmt = "SELECT schema_name FROM information_schema.schemata";
        if ( ! $self->{opt}{metadata} ) {
            $regexp = regexp_system( $self, 'schema' );
            $stmt .= " WHERE " . join( " AND ", ( "schema_name !~ ?" ) x @$regexp ) if @$regexp;
        }
        $stmt .= " ORDER BY schema_name";
        my $schemas = $dbh->selectcol_arrayref( $stmt, {}, @$regexp );
        return $schemas;
    }

    else {
        return [ $db ];
    }
}


sub get_table_names {
    my ( $self, $dbh, $schema ) = @_;
    my $tables = [];
    if ( $self->{info}{db_driver} eq 'SQLite' ) {
        my $regexp = [];
        my $stmt = "SELECT name FROM sqlite_master WHERE type = 'table'";
        if ( ! $self->{opt}{metadata} ) {
            $regexp = regexp_system( $self, 'table' );
            $stmt .= " AND " . join( " AND ", ( "name NOT REGEXP ?" ) x @$regexp ) if @$regexp;
        }
        $stmt .= " ORDER BY name";
        $tables = $dbh->selectcol_arrayref( $stmt, {}, @$regexp );
        push @$tables, 'sqlite_master' if $self->{opt}{metadata};
    }
    else {
        my $stmt = "SELECT table_name FROM information_schema.tables
                       WHERE table_schema = ?
                       ORDER BY table_name";
                        # AND table_type = 'BASE TABLE'
        $tables = $dbh->selectcol_arrayref( $stmt, {}, ( $schema ) );
    }
    return $tables;
}


sub column_names_and_types {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    if ( $self->{info}{db_driver} eq 'SQLite' ) {
        for my $table ( @{$data->{$db}{$schema}{tables}} ) {
            my $sth = $dbh->prepare( "SELECT * FROM " . $dbh->quote_identifier( undef, undef, $table ) );
            $data->{$db}{$schema}{col_names}{$table} = $sth->{NAME};
            $data->{$db}{$schema}{col_types}{$table} = $sth->{TYPE};
        }
    }
    else {
        my $stmt;
        if ( $self->{info}{db_driver} eq 'mysql' ) {
            $stmt = "SELECT table_name, column_name, column_type
                        FROM information_schema.columns
                        WHERE table_schema = ?";
        }
        else {
            $stmt = "SELECT table_name, column_name, data_type
                        FROM information_schema.columns
                        WHERE table_schema = ?";
        }
        my $sth = $dbh->prepare( $stmt );
        $sth->execute( $schema );
        while ( my $row = $sth->fetchrow_arrayref() ) {
            my ( $table, $col_name, $col_type ) = @$row;
            push @{$data->{$db}{$schema}{col_names}{$table}}, $col_name;
            push @{$data->{$db}{$schema}{col_types}{$table}}, $col_type;
        }
    }
    return $data;
}


sub primary_and_foreign_keys {
    my ( $self, $dbh, $db, $schema, $data ) = @_;
    my $pk_cols = {};
    my $fks     = {};
    for my $table ( @{$data->{$db}{$schema}{tables}} ) {
        if ( $self->{info}{db_driver} eq 'SQLite' ) {
            for my $c ( @{$dbh->selectall_arrayref( "pragma foreign_key_list( $table )" )} ) {
                $fks->{$table}{$c->[0]}{foreign_key_col}  [$c->[1]] = $c->[3];
                $fks->{$table}{$c->[0]}{reference_key_col}[$c->[1]] = $c->[4];
                $fks->{$table}{$c->[0]}{reference_table} = $c->[2];
            }
        }
        elsif ( $self->{info}{db_driver} eq 'mysql' ) {
            my $stmt = "SELECT constraint_name, table_name, column_name, referenced_table_name,
                               referenced_column_name, position_in_unique_constraint
                           FROM information_schema.key_column_usage
                           WHERE table_schema = ? AND table_name = ? AND referenced_table_name IS NOT NULL";
            my $sth = $dbh->prepare( $stmt );
            $sth->execute( $schema, $table );
            while ( my $row = $sth->fetchrow_hashref ) {
                my $fk_name = $row->{constraint_name};
                my $pos     = $row->{position_in_unique_constraint} - 1;
                $fks->{$table}{$fk_name}{foreign_key_col}  [$pos] = $row->{column_name};
                $fks->{$table}{$fk_name}{reference_key_col}[$pos] = $row->{referenced_column_name};
                if ( ! $fks->{$table}{$fk_name}{reference_table} ) {
                    $fks->{$table}{$fk_name}{reference_table} = $row->{referenced_table_name};
                }
            }
        }
        else {
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
        }
        $pk_cols->{$table} = [ $dbh->primary_key( undef, $schema, $table ) ];
    }
    return $pk_cols, $fks;
}


sub sql_regexp {
    my ( $self, $quote_col, $not_regexp ) = @_;
    if ( $self->{info}{db_driver} eq 'SQLite' ) {
        if ( $not_regexp ) {
            return ' '. $quote_col . ' NOT REGEXP ?';
        }
        else {
            return ' '. $quote_col . ' REGEXP ?';
        }
    }
    elsif ( $self->{info}{db_driver} eq 'mysql' ) {
        if ( $not_regexp ) {
            return ' '. $quote_col . ' NOT REGEXP ?'        if ! $self->{opt}{regex_case};
            return ' '. $quote_col . ' NOT REGEXP BINARY ?' if   $self->{opt}{regex_case};
        }
        else {
            return ' '. $quote_col . ' REGEXP ?'            if ! $self->{opt}{regex_case};
            return ' '. $quote_col . ' REGEXP BINARY ?'     if   $self->{opt}{regex_case};
        }
    }
    elsif ( $self->{info}{db_driver} eq 'Pg' ) {
        if ( $not_regexp ) {
            return ' '. $quote_col . '::text' . ' !~* ?' if ! $self->{opt}{regex_case};
            return ' '. $quote_col . '::text' . ' !~ ?'  if   $self->{opt}{regex_case};
        }
        else {
            return ' '. $quote_col . '::text' . ' ~* ?'  if ! $self->{opt}{regex_case};
            return ' '. $quote_col . '::text' . ' ~ ?'   if   $self->{opt}{regex_case};
        }
    }
    elsif ( $self->{info}{db_driver} eq 'oracle' ) {
        if ( $not_regexp ) {
            return ' NOT REGEXP_LIKE(' . $quote_col . ',?,\'i\')' if ! $self->{opt}{regex_case};
            return ' NOT REGEXP_LIKE(' . $quote_col . ',?)'       if   $self->{opt}{regex_case};
        }
        else {
            return ' REGEXP_LIKE(' . $quote_col . ',?,\'i\')'     if ! $self->{opt}{regex_case};
            return ' REGEXP_LIKE(' . $quote_col . ',?)'           if   $self->{opt}{regex_case};
        }
    }
    die 'No entry for "' . $self->{info}{db_driver} . '"!';
}


sub concatenate {
    my ( $self, $arg ) = @_;
    return 'concat(' . join( ',', @$arg ) . ')' if $self->{info}{db_driver} eq 'mysql';
    return join( ' || ', @$arg );
}


sub col_functions {
    my ( $self, $func, $quote_col, $print_col ) = @_;
    my $db_driver = $self->{info}{db_driver};
    my ( $quote_f, $print_f );
    $print_f = $self->{info}{hidd_func_pr}{$func} . '(' . $print_col . ')';
    if ( $func =~ /^Epoch_to_Date(?:Time)?\z/ ) {
        my $prompt = "$print_f\nInterval:";
        my ( $microseconds, $milliseconds, $seconds ) = (
            '  ****************   Micro-Second',
            '  *************      Milli-Second',
            '  **********               Second' );
        my $choices = [ undef, $microseconds, $milliseconds, $seconds ];
        # Choose
        my $interval = choose(
            $choices,
            { %{$self->{info}{lyt_stmt_v}}, prompt => $prompt }
        );
        return if ! defined $interval;
        my $div = $interval eq $microseconds ? 1000000 :
                  $interval eq $milliseconds ? 1000 : 1;
        if ( $func eq 'Epoch_to_DateTime' ) {
            $quote_f = "FROM_UNIXTIME($quote_col/$div,'%Y-%m-%d %H:%i:%s')"    if $db_driver eq 'mysql';
            $quote_f = "(TO_TIMESTAMP(${quote_col}::bigint/$div))::timestamp"  if $db_driver eq 'Pg';
            $quote_f = "DATETIME($quote_col/$div,'unixepoch','localtime')"     if $db_driver eq 'SQLite';
        }
        else {
            # mysql: FROM_UNIXTIME doesn't work with negative timestamps
            $quote_f = "FROM_UNIXTIME($quote_col/$div,'%Y-%m-%d')"       if $db_driver eq 'mysql';
            $quote_f = "(TO_TIMESTAMP(${quote_col}::bigint/$div))::date" if $db_driver eq 'Pg';
            $quote_f = "DATE($quote_col/$div,'unixepoch','localtime')"   if $db_driver eq 'SQLite';
        }
    }
    elsif ( $func eq 'Truncate' ) {
        my $prompt = "TRUNC $print_col\nDecimal places:";
        my $choices = [ undef, 0 .. 9 ];
        my $precision = choose( $choices, { %{$self->{info}{lyt_stmt_h}}, prompt => $prompt } );
        return if ! defined $precision;
        if ( $db_driver eq 'Pg' ) {
            $quote_f = "TRUNC($quote_col,$precision)";
        }
        else {
            $quote_f = "TRUNCATE($quote_col,$precision)";
        }
    }
    elsif ( $func eq 'Bit_Length' ) {
        $quote_f = "BIT_LENGTH($quote_col)";
    }
    elsif ( $func eq 'Char_Length' ) {
        $quote_f = "CHAR_LENGTH($quote_col)";
    }
    return $quote_f, $print_f;
}


1;


__END__

package # hide from PAUSE
App::DBBrowser::DB;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.049_06';


sub new {
    my ( $class, $info, $opt ) = @_; #
    die "Invalid character in the DB plugin name" if $info->{db_plugin} !~ /^[\w_]+\z/;
    my $db_module = 'App::DBBrowser::DB::' . $info->{db_plugin};
    eval "require $db_module";
    my $plugin = $db_module->new( {
        home_dir            => $info->{home_dir},
        app_dir             => $info->{app_dir},
        db_plugin           => $info->{db_plugin},
        db_cache_file       => $info->{db_cache_file},
        sqlite_search       => $info->{sqlite_search},
        clear_screen        => $info->{clear_screen},
        debug               => $opt->{debug},
        metadata            => $opt->{metadata},
        dirs_sqlite_search  => $opt->{dirs_sqlite_search},
        connect_arg         => $opt->{$info->{db_plugin}},
        login_mode_host     => $opt->{login_host},
        login_mode_port     => $opt->{login_port},
        login_mode_user     => $opt->{login_user},
        login_mode_pass     => $opt->{login_pass},
    } );
    bless { db_plugin => $plugin }, $class;
}


sub db_driver {
    my ( $self ) = @_;
    my $db_driver = $self->{db_plugin}->db_driver();
    return $db_driver;
}


sub available_databases {
    my ( $self ) = @_;
    my ( $user_db, $system_db ) = $self->{db_plugin}->available_databases();
    return $user_db, $system_db;
}


sub get_db_handle {
    my ( $self, $db, $connect_arg_db ) = @_;
    my $dbh = $self->{db_plugin}->get_db_handle( $db, $connect_arg_db );
    return $dbh;
}


sub get_schema_names {
    my ( $self, $dbh, $db ) = @_;
    my ( $user_sma, $system_sma ) = $self->{db_plugin}->get_schema_names( $dbh, $db );
    return $user_sma, $system_sma;
}


sub get_table_names {
    my ( $self, $dbh, $schema ) = @_;
    my ( $user_tbl, $system_tbl ) = $self->{db_plugin}->get_table_names( $dbh, $schema );
    return $user_tbl, $system_tbl;
}


sub column_names_and_types {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my ( $col_names, $col_types ) = $self->{db_plugin}->column_names_and_types( $dbh, $db, $schema, $tables );
    return $col_names, $col_types;
}


sub primary_and_foreign_keys {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my ( $pk_cols, $fks ) = $self->{db_plugin}->primary_and_foreign_keys( $dbh, $db, $schema, $tables );
    return $pk_cols, $fks;
}


sub sql_regexp {
    my ( $self, $quote_col, $is_not_regexp, $case_sensitive ) = @_;
    my $sql_regexp = $self->{db_plugin}->sql_regexp( $quote_col, $is_not_regexp, $case_sensitive );
    return $sql_regexp;
}


sub concatenate {
    my ( $self, $arg ) = @_;
    my $concatenated = $self->{db_plugin}->concatenate( $arg );
    return $concatenated;
}



# scalar functions

sub epoch_to_datetime {
    my ( $self, $quote_col, $interval ) = @_;
    my $quote_f = $self->{db_plugin}->epoch_to_datetime( $quote_col, $interval );
    return $quote_f;
}


sub epoch_to_date {
    my ( $self, $quote_col, $interval ) = @_;
    my $quote_f = $self->{db_plugin}->epoch_to_date( $quote_col, $interval );
    return $quote_f;
}


sub truncate {
    my ( $self, $quote_col, $precision ) = @_;
    my $quote_f = $self->{db_plugin}->truncate( $quote_col, $precision );
    return $quote_f;
}


sub bit_length {
    my ( $self, $quote_col ) = @_;
    my $quote_f = $self->{db_plugin}->bit_length( $quote_col );
    return $quote_f;
}


sub char_length {
    my ( $self, $quote_col ) = @_;
    my $quote_f = $self->{db_plugin}->char_length( $quote_col );
    return $quote_f;
}




1;


__END__

package # hide from PAUSE
App::DBBrowser::DB;

use warnings FATAL => 'all';
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.049_02';


use Term::Choose qw( choose );

sub CLEAR_SCREEN () { "\e[H\e[J" }



sub new {
    my ( $class, $info, $opt ) = @_;

    my $db_module = 'App::DBBrowser::DB::' . $info->{db_driver};
    eval "require $db_module";
    my $new_db_module = $db_module->new( $info, $opt );

    bless { info => $info, opt => $opt, new_db_module => $new_db_module }, $class;
}



sub get_db_handle {
    my ( $self, $db ) = @_;
    my $db_driver = $self->{info}{db_driver};
    return if $db_driver eq 'SQLite' && ! defined $db;
    my $db_key = $db_driver . '_' . $db;
    my $db_arg = {};
    for my $option ( sort keys %{$self->{opt}{$db_driver}} ) {
        next if $option !~ /^\Q$self->{info}{connect_opt_pre}{$db_driver}\E/;
        $db_arg->{$option} = $self->{opt}{$db_key}{$option} // $self->{opt}{$db_driver}{$option};
    }
    print CLEAR_SCREEN;
    print "DB: $db\n";
    my $dbh    = $self->{new_db_module}->get_db_handle( $db, $db_arg );
    return $dbh;
}


sub available_databases {
    my ( $self, $metadata ) = @_;
    my ( $user_db, $system_db ) = $self->{new_db_module}->available_databases( $metadata );
    return $user_db, $system_db;
}


sub get_schema_names {
    my ( $self, $dbh, $db, $metadata ) = @_;
    my ( $user_sma, $system_sma ) = $self->{new_db_module}->get_schema_names( $dbh, $db, $metadata );
    return $user_sma, $system_sma;
}


sub get_table_names {
    my ( $self, $dbh, $schema, $metadata ) = @_;
    my ( $user_tbl, $system_tbl ) = $self->{new_db_module}->get_table_names( $dbh, $schema, $metadata );
    return $user_tbl, $system_tbl;
}


sub column_names_and_types {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my ( $col_names, $col_types ) = $self->{new_db_module}->column_names_and_types( $dbh, $db, $schema, $tables );
    return $col_names, $col_types;
}


sub primary_and_foreign_keys {
    my ( $self, $dbh, $db, $schema, $tables ) = @_;
    my ( $pk_cols, $fks ) = $self->{new_db_module}->primary_and_foreign_keys( $dbh, $db, $schema, $tables );
    return $pk_cols, $fks;
}


sub sql_regexp {
    my ( $self, $quote_col, $is_not_regexp, $case_sensitive ) = @_;
    my $sql_regexp = $self->{new_db_module}->sql_regexp( $quote_col, $is_not_regexp, $case_sensitive );
    return $sql_regexp;
}


sub concatenate {
    my ( $self, $arg ) = @_;
    my $concatenated = $self->{new_db_module}->concatenate( $arg );
    return $concatenated;
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
            $quote_f = $self->{new_db_module}->epoch_to_datetime( $quote_col, $interval );
        }
        else {
            $quote_f = $self->{new_db_module}->epoch_to_date( $quote_col, $interval );
        }
    }
    elsif ( $func eq 'Truncate' ) {
        my $prompt = "TRUNC $print_col\nDecimal places:";
        my $choices = [ undef, 0 .. 9 ];
        my $precision = choose( $choices, { %{$self->{info}{lyt_stmt_h}}, prompt => $prompt } );
        return if ! defined $precision;
        $quote_f = $self->{new_db_module}->truncate( $quote_col, $precision );
    }
    elsif ( $func eq 'Bit_Length' ) {
        $quote_f = $self->{new_db_module}->bit_length( $quote_col );
    }
    elsif ( $func eq 'Char_Length' ) {
        $quote_f = $self->{new_db_module}->char_length( $quote_col );
    }
    return $quote_f, $print_f;
}


1;


__END__

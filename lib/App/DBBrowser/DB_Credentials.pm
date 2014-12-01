package # hide from PAUSE
App::DBBrowser::DB_Credentials;

use warnings FATAL => 'all';
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.049_02';

use Term::ReadLine::Simple qw();

#sub CLEAR_SCREEN () { "\e[H\e[J" }



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



1;


__END__

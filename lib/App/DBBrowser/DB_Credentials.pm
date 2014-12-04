package # hide from PAUSE
App::DBBrowser::DB_Credentials;

use warnings FATAL => 'all';
use strict;
use 5.010000;
no warnings 'utf8';

our $VERSION = '0.049_03';

use Term::ReadLine::Simple qw();



sub new {
    my ( $class ) = @_;
    bless {}, $class;
}


sub get_login {
    my ( $self, $key, $login_cache ) = @_;
    my $login_key = 'login_' . $key;
    $login_cache->{$login_key} //= 1;
    my $prompt = ucfirst( $key ) . ': ';
    my $trs = Term::ReadLine::Simple->new();
    if ( $login_cache->{$login_key} == 0 ) {
        #if ( length $login_cache->{$key} ) {
        if ( defined $login_cache->{$key} ) {
            say $prompt . $login_cache->{$key};
            return $login_cache->{$key};
        }
        # Readline
        my $new = $trs->readline( $prompt );
        $login_cache->{$key} = $new;
        return $new;
    }
    elsif ( $login_cache->{$login_key} == 1 ) {
        if ( length $login_cache->{$key} ) {
            say $prompt . $login_cache->{$key};
            return $login_cache->{$key};
        }
        # Readline
        my $new = $trs->readline( $prompt, $login_cache->{'default_' . $key} );
        return $new;
    }
    elsif ( $login_cache->{$login_key} == 2 ) {
        say $prompt . $login_cache->{$key};
        return $login_cache->{$key};
    }
    elsif ( $login_cache->{$login_key} == 3 ) {
        return;
    }
}


sub get_password {
    my ( $self, $login_cache ) = @_;
    $login_cache->{login_pass} //= 1;
    my $trs = Term::ReadLine::Simple->new();
    if ( $login_cache->{login_pass} == 0 ) {
        return $login_cache->{pass} if length $login_cache->{pass};
        # Readline
        my $passwd = $trs->readline( 'Password: ', { no_echo => 1 } );
        $login_cache->{pass} = $passwd;
        return $passwd;
    }
    elsif ( $login_cache->{login_pass} == 1 ) {
        # Readline
        my $passwd = $trs->readline( 'Password: ', { no_echo => 1 } );
        return $passwd;
    }
    elsif ( $login_cache->{login_pass} == 2 ) {
        return $login_cache->{pass};
    }

}



1;


__END__

package # hide from PAUSE
App::DBBrowser::DB_Credentials;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.001';

use Term::ReadLine::Simple qw();



sub new {
    my ( $class, $opt ) = @_;
    bless $opt, $class;
}


sub get_login {
    my ( $self, $key ) = @_;
    my $login_mode  = $self->{connect_parameter}{login_mode}{$key};
    my $keep_secret = $self->{connect_parameter}{keep_secret}{$key};
    my $saved_value = $self->{connect_parameter}{login_data}{$key};
    my $prompt = ucfirst( $key ) . ': ';
    if ( $login_mode == 2 ) {
        return;
    }
    elsif ( $login_mode == 1 && exists $ENV{'DBI_' . uc $key} ) {
        print $prompt . $ENV{'DBI_' . uc $key}, "\n" if ! $keep_secret;
        return $ENV{'DBI_' . uc $key};
    }
    elsif ( defined $saved_value ) {
        print $prompt . $saved_value, "\n" if ! $keep_secret;
        return $saved_value;
    }
    else {
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $new;
        if ( $key eq 'pass' ) {
            $new = $trs->readline( $prompt, { no_echo => $keep_secret } );
        }
        else {
            $new = $trs->readline( $prompt );
        }
        return $new;
    }
}



1;


__END__

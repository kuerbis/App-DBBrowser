package # hide from PAUSE
App::DBBrowser::Credentials;

use warnings;
use strict;
use 5.010001;

use Term::Choose::Constants qw( :screen );
use Term::Form              qw();


sub new {
    my ( $class, $opt ) = @_;
    bless $opt, $class;
}


sub get_login {
    my ( $sf, $key, $info ) = @_;
    if ( ! exists $sf->{login_data}{$key} ) {
        return;
    }
    my $default = $sf->{login_data}{$key}{default};
    my $no_echo = $sf->{login_data}{$key}{secret};
    my $env_var = 'DBI_' . uc $key;
    if ( $sf->{env_var_yes}{$env_var} && exists $ENV{$env_var} ) {
        return $ENV{$env_var}; #
    }
    elsif ( defined $default && length $default ) {
        return $default;
    }
    else {
        my $prompt = ucfirst( $key ) . ': ';
        my $tf = Term::Form->new();
        # Readline
        my $new = $tf->readline( $prompt,
            { info => $info, no_echo => $no_echo }
        );
        print HIDE_CURSOR;
        return $new;
    }
}



1;


__END__

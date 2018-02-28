package # hide from PAUSE
App::DBBrowser::Credentials;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '2.000';

use Term::Form qw();


sub new {
    my ( $class, $opt ) = @_;
    bless $opt, $class;
}


sub get_login {
    my ( $sf, $key ) = @_;
    my $keep_secret = $sf->{parameter}{secret}{$key};
    my $saved_value = $sf->{parameter}{arguments}{$key};
    if ( ! $sf->{parameter}{required}{$key} ) {
        return;
    }
    my $prompt = ucfirst( $key ) . ': ';
    my $env_var = 'DBI_' . uc $key;
    if ( $sf->{parameter}{use_env_var}{$env_var} && exists $ENV{$env_var} ) {
        if ( ! $keep_secret ) {
            print $prompt . $ENV{$env_var}, "\n";
        }
        return $ENV{$env_var}; #
    }
    elsif ( defined $saved_value && length $saved_value ) {
        if ( ! $keep_secret ) {
            print $prompt . $saved_value, "\n";
        }
        return $saved_value;
    }
    else {
        my $trs = Term::Form->new();
        # Readline
        my $new = $trs->readline( $prompt, { no_echo => $keep_secret } );
        return $new;
    }
}



1;


__END__

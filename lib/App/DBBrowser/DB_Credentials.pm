package # hide from PAUSE
App::DBBrowser::DB_Credentials;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '0.049_08';

use Term::ReadLine::Simple qw();



sub new {
    my ( $class, $opt ) = @_;
    bless $opt, $class;
}


sub get_login {
    my ( $self, $key, $login_mode ) = @_;
    my $prompt = ucfirst( $key ) . ': ';
    $self->{connect_arg}{$key} = undef if $self->{connect_arg}{error};
    if ( $login_mode == 2 ) {
        return;
    }
    elsif ( $login_mode == 1 && exists $ENV{'DBI_' . uc $key} ) {
        print $prompt . $ENV{'DBI_' . uc $key}, "\n" if $key ne 'pass';
        return $ENV{'DBI_' . uc $key};
    }
    elsif ( defined $self->{connect_arg}{$key} ) {
        print $prompt . $self->{connect_arg}{$key}, "\n" if $key ne 'pass';
        return $self->{connect_arg}{$key}
    }
    else {
        my $trs = Term::ReadLine::Simple->new();
        # Readline
        my $new;
        if ( $key eq 'pass' ) {
            $new = $trs->readline( $prompt, { no_echo => 1 } );
        }
        else {
            $new = $trs->readline( $prompt );
        }
        return $new;
    }
}



1;


__END__

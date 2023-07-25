package # hide from PAUSE
App::DBBrowser::Table::Extensions::Arithmetic;

use warnings;
use strict;
use 5.014;

use Term::Choose           qw();
use Term::Form::ReadLine   qw();

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Extensions;


sub new {
    my ( $class, $info, $options, $d ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $d
    }, $class;
}



sub arithmetics {
    my ( $sf, $sql, $clause, $r_data ) = @_;
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my $tr = Term::Form::ReadLine->new( $sf->{i}{tr_default} );
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my ( $num, $op ) = ( '[num]', '[op]' );
    my @pre = ( undef, $sf->{i}{ok}, $sf->{i}{menu_addition}, $op , $num);
    my $menu = [ @pre, @{$sql->{cols}} ];
    my $info = $ax->get_sql_info( $sql );
    my $subset = [];
    my $prompt = 'Your choice:';
    my @bu;

    COLUMNS: while ( 1 ) { ##
        my $fill_string = join( ' ', @$subset, '?' );
        $fill_string =~ s/\(\s/(/g;
        $fill_string =~ s/\s\)/)/g;
        my $tmp_info = $info . "\n" . $fill_string;
        # Choose
        my $idx = $tc->choose(
            $menu,
            { %{$sf->{i}{lyt_h}}, info => $tmp_info, prompt => $prompt, index => 1 }
        );
        if ( ! $idx ) {
            if ( @bu ) {
                $subset = pop @bu;
                next COLUMNS;
            }
            return;
        }
        push @bu, [ @$subset ];
        if ( $menu->[$idx] eq $sf->{i}{ok} ) {
            #shift @idx;
            #push @$subset, @{$menu}[@idx];
            if ( ! @$subset ) {
                return;
            }
            my $result = join ' ', @$subset;
            $result =~ s/\(\s/(/g;
            $result =~ s/\s\)/)/g;
            return $result;
        }
        elsif ( $menu->[$idx] eq $sf->{i}{menu_addition} ) {
            my $ext = App::DBBrowser::Table::Extensions->new( $sf->{i}, $sf->{o}, $sf->{d} );
            my $complex_col = $ext->complex_unit( $sql, $clause, $r_data, { from => 'arithmetic', info => $tmp_info } );
            if ( ! defined $complex_col ) {
                next COLUMNS;
            }
            push @$subset, $complex_col;
        }
        elsif ( $menu->[$idx] eq $op ) {
            # Choose
            my $operator = $tc->choose(
                [ undef, '  +  ',   '  -  ', '  *  ', '  /  ', '  %  ', '  (  ', '  )  ' ],
                { %{$sf->{i}{lyt_v}}, info => $tmp_info . "\n" . $prompt, prompt => '', undef => '<=' }
            );
            if ( ! defined $operator ) {
                next COLUMNS;
                return;
            }
            push @$subset, $operator =~ s/^\s+|\s+\z//gr;
        }
        elsif ( $menu->[$idx] eq $num ) {
            my $number = $tr->readline(
                'Number: ',
                { info => $tmp_info . "\n" . $prompt }
            );
            if ( ! defined $number ) {
                next COLUMNS;
            }
            push @$subset, $number;
        }
        else {
            push @$subset, $menu->[$idx];
        }
    }
}




1;


__END__

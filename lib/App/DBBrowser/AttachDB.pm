package # hide from PAUSE
App::DBBrowser::AttachDB;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_01';

use File::Basename qw( basename );
use List::Util     qw( any );

use Term::Choose       qw( choose );
use Term::Choose::Util qw( choose_a_subset );
use Term::Form         qw();

use App::DBBrowser::Auxil;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { i => $info, o => $opt }, $class;
}


sub attach_db {
    my ( $sf, $dbh, $data ) = @_;
    my $tc = Term::Choose->new( { clear_screen => 1 } ); # opt
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $cur;
    if ( -s $sf->{i}{file_attached_db} ) {
        my $h_ref = $ax->read_json( $sf->{i}{file_attached_db} );
        $cur = $h_ref->{$data->{db}} || [];
    }
    my $choices = [ undef, @{$data->{user_dbs}}, @{$data->{sys_dbs}} ];
    my $new = [];
    my $root = 'DB: "' . basename( $data->{db} ) . "\"\n";

    ATTACH: while ( 1 ) {

        DB: while ( 1 ) {
            my $info = $root;
            for my $ref ( @$cur, @$new ) {
                $info .= sprintf "ATTACH DATABASE %s AS %s\n", @$ref;
            }
            my $prompt = $info;
            $prompt .= "\nATTACH DATABASE";
            my $db = $tc->choose( $choices, { prompt => $prompt, undef => '<<' } );
            if ( ! defined $db ) {
                if ( @$new ) {
                    shift @$new;
                    next DB;
                }
                return;
            }
            my $tfr = Term::Form->new();
            $info .= "\nATTACH DATABASE $db AS";

            ALIAS: while ( 1 ) {
                my $prompt = 'alias: ';
                my $alias = $tfr->readline( $prompt, { clear_screen => 1, info => $info } );
                if ( ! length $alias ) {
                    last ALIAS;
                }
                elsif ( any { $_->[1] eq $alias } @$cur, @$new ) {
                    my $retry = $tc->choose(
                        [ undef, 'New alias' ],
                        { prompt => "alias '$alias' already used:", undef => 'Back', clear_screen => 0 }
                    );
                    last ALIAS if ! defined $retry;
                    next ALIAS;
                }
                else {
                    push @$new, [ $db, $alias ]; # 2 x $db with different $alias ?
                    last ALIAS;
                }
            }

            NO_OK: while ( 1 ) {
                $info = $root;
                $info .= join( "\n", map { "ATTACH DATABASE $_->[0] AS $_->[1]" } @$cur, @$new );
                my ( $ok, $more ) = ( 'OK', '++' );
                my $choice = $tc->choose( [ undef, $ok, $more ], { prompt => $info . "\n\nChoose:", undef => '<<' } );
                if ( ! defined $choice ) {
                    if ( @$new > 1 ) {
                        pop @$new;
                        next NO_OK;
                    }
                    return;
                }
                elsif ( $choice eq $ok ) {
                    if ( ! @$new ) {
                        return;
                    }
                    my $h_ref = $ax->read_json( $sf->{i}{file_attached_db} );
                    $h_ref->{$data->{db}} = [ sort( @$cur, @$new  ) ];;
                    $ax->write_json( $sf->{i}{file_attached_db}, $h_ref );
                    return 1;
                }
                elsif ( $choice eq $more ) {
                    next DB;
                }
            }
        }
    }
}


sub detach_db {
    my ( $sf, $dbh, $data ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $info = 'DB: "' . basename( $data->{db} ) . "\"";
    my $attached_db;
    if ( -s $sf->{i}{file_attached_db} ) {
        my $h_ref = $ax->read_json( $sf->{i}{file_attached_db} );
        $attached_db = $h_ref->{$data->{db}} || [];
    }
    my @choices;
    for my $elem ( @$attached_db ) {
        push @choices, sprintf 'DETACH DATABASE %s  (%s)', @$elem[1,0];
    }
    my $prompt = 'Choose:';
    my $idx = choose_a_subset( [ @choices ], { info => $info, index => 1, show_fmt => 2, keep_chosen => 0 } ); # prompt
    if ( ! defined $idx || ! @$idx ) {
        return;
    }
    my $detach = [];
    for my $i ( reverse @$idx ) {
        my $ref = splice( @$attached_db, $i, 1 );
    }
    my $h_ref = $ax->read_json( $sf->{i}{file_attached_db} );
    if ( @$attached_db ) {
        $h_ref->{$data->{db}} = $attached_db;
    }
    else {
        delete $h_ref->{$data->{db}};
    }
    $ax->write_json( $sf->{i}{file_attached_db}, $h_ref );
    return 1;
}









1;

__END__

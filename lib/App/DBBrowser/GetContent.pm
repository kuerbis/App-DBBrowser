package # hide from PAUSE
App::DBBrowser::GetContent;

use warnings;
use strict;
use 5.010001;

use Encode::Locale  qw();

use Term::Choose qw();

use App::DBBrowser::GetContent::Filter;
use App::DBBrowser::GetContent::Parse;
use App::DBBrowser::GetContent::Read;
#use App::DBBrowser::Opt::Set               # required

use open ':encoding(locale)';


sub new {
    my ( $class, $info, $options, $data ) = @_;
    my $sf = {
        i => $info,
        o => $options,
        d => $data,
    };
    bless $sf, $class;
}



sub __setting_menu_entries {
    my ( $sf, $all ) = @_;
    my $groups = [
        { name => 'group_insert', text => '' }
    ];
    my $options = [
        { name => '_parse_file',    text => "- Parse tool for File",         section => 'insert' },
        { name => '_parse_copy',    text => "- Parse tool for Copy & Paste", section => 'insert' },
        { name => '_split_config',  text => "- Settings 'split'",            section => 'split'  },
        { name => '_csv_char',      text => "- Settings 'CSV-a'",            section => 'csv'    },
        { name => '_csv_options',   text => "- Settings 'CSV-b'",            section => 'csv'    },
    ];
    if ( ! $all ) {
        if ( defined $sf->{i}{gc}{source_type} ) {
            if ( $sf->{i}{gc}{source_type} eq 'file' ) {
                splice @$options, 1, 1;
            }
            elsif ( $sf->{i}{gc}{source_type} eq 'copy' ) {
                splice @$options, 0, 1;
            }
        }
    }
    return $groups, $options;
}



sub get_content {
    my ( $sf, $sql, $skip_to ) = @_;
    my $cr = App::DBBrowser::GetContent::Read->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $cp = App::DBBrowser::GetContent::Parse->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $cf = App::DBBrowser::GetContent::Filter->new( $sf->{i}, $sf->{o}, $sf->{d} );
    my $tc = Term::Choose->new( $sf->{i}{tc_default} );
    my @choices = (
        [ 'plain', '- Plain' ],
        [ 'copy',  '- Copy & Paste' ],
        [ 'file',  '- From File' ],
    );
    my $old_idx = 1;
    my $data_source_choice = $sf->{o}{insert}{'data_source_' . $sf->{i}{stmt_types}[0]};

    MENU: while ( 1 ) {
        if ( ! $skip_to ) {
            if ( $data_source_choice == 3 ) {
                my $hidden = "Choose type of data source:";
                my @pre = ( $hidden, undef );
                my $menu = [ @pre, map( $_->[1], @choices ) ];
                # Choose
                my $idx = $tc->choose(
                    $menu,
                    { %{$sf->{i}{lyt_v_clear}}, prompt => '', index => 1, default => $old_idx, undef => '  <=' }
                );
                if ( ! defined $idx || ! defined $menu->[$idx] ) {
                    return;
                }
                if ( $sf->{o}{G}{menu_memory} ) {
                    if ( $old_idx == $idx && ! $ENV{TC_RESET_AUTO_UP} ) {
                        $old_idx = 1;
                        next MENU;
                    }
                    $old_idx = $idx;
                }
                if ( $menu->[$idx] eq $hidden ) {
                    require App::DBBrowser::Opt::Set;
                    my $opt_set = App::DBBrowser::Opt::Set->new( $sf->{i}, $sf->{o} );
                    $opt_set->set_options( $sf->__setting_menu_entries( 1 ) );
                    next MENU;
                }
                $sf->{i}{gc}{source_type} = $choices[$idx-@pre][0];
            }
            else {
                $sf->{i}{gc}{source_type} = $choices[ $data_source_choice ][0];
            }
        }

        GET_DATA: while ( 1 ) {
            my ( $aoa, $open_mode );
            if ( ! $skip_to ) {
                delete $sf->{i}{ct}{default_table_name};
                #$sf->{i}{gc}{previous_file_fs} = $sf->{i}{gc}{file_fs} // ''; # DBBrowser.pm 635
                my $ok;
                if ( $sf->{i}{gc}{source_type} eq 'plain' ) {
                    ( $ok, $sf->{i}{gc}{file_fs} ) = $cr->from_col_by_col( $sql );
                }
                elsif ( $sf->{i}{gc}{source_type} eq 'copy' ) {
                    ( $ok, $sf->{i}{gc}{file_fs} ) = $cr->from_copy_and_paste( $sql );
                }
                elsif ( $sf->{i}{gc}{source_type} eq 'file' ) {
                    ( $ok, $sf->{i}{gc}{file_fs} ) = $cr->from_file( $sql );
                }
                if ( ! $ok ) {
                    return if $data_source_choice < 3;
                    next MENU;
                }
            }
            my $file_fs = $sf->{i}{gc}{file_fs};
            if ( ! defined $sf->{i}{S_R}{$file_fs}{book} ) {
                delete $sf->{i}{S_R};
            }

            PARSE: while ( 1 ) {
                if ( ! $skip_to || $skip_to eq 'PARSE' ) {
                    my ( $parse_mode_idx, $open_mode );
                    if ( $sf->{i}{gc}{source_type} eq 'plain' ) {
                        $parse_mode_idx = -1;
                        $open_mode = '<';
                    }
                    elsif ( $sf->{i}{gc}{source_type} eq 'copy' ) {
                        $parse_mode_idx = $sf->{o}{insert}{parse_mode_input_copy};
                        $open_mode = '<';
                    }
                    elsif ( $sf->{i}{gc}{source_type} eq 'file' ) {
                        $parse_mode_idx = $sf->{o}{insert}{parse_mode_input_file};
                        $open_mode = '<:encoding(' . $sf->{o}{insert}{file_encoding} . ')';
                    }
                    $sql->{insert_into_args} = [];
                    if ( $parse_mode_idx < 3 && -T $file_fs ) {
                        open my $fh, $open_mode, $file_fs or die $!;
                        my $parse_ok;
                        if ( $parse_mode_idx == -1 ) {
                            $parse_ok = $cp->__parse_plain( $sql, $fh );
                        }
                        elsif ( $parse_mode_idx == 0 ) {
                            $parse_ok = $cp->__parse_with_Text_CSV( $sql, $fh );
                        }
                        elsif ( $parse_mode_idx == 1 ) {
                            $parse_ok = $cp->__parse_with_split( $sql, $fh );
                        }
                        elsif ( $parse_mode_idx == 2 ) {
                            $parse_ok = $cp->__parse_with_template( $sql, $fh );
                            if ( $parse_ok && $parse_ok == -1 ) {
                                next PARSE;
                            }
                        }
                        if ( ! $parse_ok ) {
                            next GET_DATA;
                        }
                        if ( ! @{$sql->{insert_into_args}} ) {
                            $tc->choose(
                                [ 'empty file!' ],
                                { prompt => 'Press ENTER' }
                            );
                            close $fh;
                            next GET_DATA;
                        }
                    }
                    else {
                        SHEET: while ( 1 ) {
                            my $ok = $cp->__parse_with_Spreadsheet_Read( $sql, $file_fs );
                            if ( ! $ok ) {
                                $skip_to = '';
                                next GET_DATA;
                            }
                            if ( ! @{$sql->{insert_into_args}} ) { #
                                next SHEET if $sf->{i}{S_R}{$file_fs}{sheet_count} >= 2;
                                $skip_to = '';
                                next GET_DATA;
                            }
                            last SHEET;
                        }
                    }
                    $sf->{i}{gc}{bu_insert_into_args} = [ map { [ @$_ ] } @{$sql->{insert_into_args}} ];
                }
                $skip_to = '';

                FILTER: while ( 1 ) {
                    my $ok = $cf->input_filter( $sql );
                    if ( ! $ok ) {
                        if (    exists $sf->{i}{S_R}{$file_fs}{sheet_count}
                            && defined $sf->{i}{S_R}{$file_fs}{sheet_count}
                            && $sf->{i}{S_R}{$file_fs}{sheet_count} >= 2 ) {
                            next PARSE;
                        }
                        next GET_DATA;
                    }
                    elsif ( $ok == -1 ) {
                        #if ( ! -T $file_fs ) {
                        #    $tc->choose(
                        #        [ 'Press ENTER' ],
                        #        { prompt => 'Not a text file: "Spreadsheet::Read" is used automatically' }
                        #    );
                        #    next FILTER;
                        #}
                        require App::DBBrowser::Opt::Set;
                        my $opt_set = App::DBBrowser::Opt::Set->new( $sf->{i}, $sf->{o} );
                        $sf->{o} = $opt_set->set_options( $sf->__setting_menu_entries() );
                        next PARSE;
                    }
                    return 1;
                }
            }
        }
    }
}









1;


__END__

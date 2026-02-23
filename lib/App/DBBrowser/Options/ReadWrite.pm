package # hide from PAUSE
App::DBBrowser::Options::ReadWrite;

use warnings;
use strict;
use 5.016;

use App::DBBrowser::Auxil;
use App::DBBrowser::Options::Defaults;


sub new {
    my ( $class, $info, $options ) = @_;
    bless {
        i => $info,
        o => $options
    }, $class;
}


sub write_config_file {
    my ( $sf, $lo, $driver, $plugin, $db ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, {} );
    if ( $db ) {
        my $file_fs = sprintf( $sf->{i}{db_config_file_fmt}, $plugin );
        my $conf = {};
        if ( -s $file_fs ) {
            $conf = $ax->read_json( $file_fs );
        }
        $conf->{$db} = $lo;
        $ax->write_json( $file_fs, $conf );
    }
    elsif ( $plugin ) {
        my $file_fs = sprintf( $sf->{i}{plugin_config_file_fmt}, $plugin );
        $ax->write_json( $file_fs, $lo  );
    }
    else {
        $ax->write_json( $sf->{i}{f_global_settings}, $lo );
    }
}


sub read_config_file {
    my ( $sf, $driver, $plugin, $db ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o}, {} );
    my $op_df = App::DBBrowser::Options::Defaults->new( $sf->{i}, {} );
    my $lo = {};
    if ( $db ) {
        my $file_fs = sprintf( $sf->{i}{db_config_file_fmt}, $plugin );
        my $conf = $ax->read_json( $file_fs ) // {};
        if ( ! %{$conf->{$db}//{}} ) {
            my $file_fs = sprintf( $sf->{i}{plugin_config_file_fmt}, $plugin );
            $conf = $ax->read_json( $file_fs ) // {};
            if ( ! %$conf ) {
                $conf = $op_df->defaults( $driver );
            }
            $lo->{connect_data} = $conf->{connect_data};
            $lo->{connect_attr} = $conf->{connect_attr};
        }
        else {
            $lo = $conf->{$db};
        }
    }
    elsif ( $plugin ) {
        my $file_fs = sprintf( $sf->{i}{plugin_config_file_fmt}, $plugin );
        $lo = $ax->read_json( $file_fs ) // {};
        if ( ! %{$lo//{}} ) {
            $lo = $op_df->defaults( $driver );
        }

        ####### 19.02.2026 ############
        if ( exists $lo->{table}{max_width_exp} || exists $lo->{table}{min_col_width} || ! exists $lo->{table}{expanded_line_spacing}) {
            $lo->{table}{expanded_line_spacing} = 1 if ! exists $lo->{table}{expanded_line_spacing};

            $lo->{table}{expanded_max_width} = delete $lo->{table}{max_width_exp} if exists $lo->{table}{max_width_exp};
            $lo->{table}{col_trim_threshold} = delete $lo->{table}{min_col_width} if exists $lo->{table}{min_col_width};

            my $file_fs = sprintf( $sf->{i}{plugin_config_file_fmt}, $plugin );
            $sf->write_config_file( $lo, $driver, $plugin ) if -f $file_fs;
        }
        ###############################

    }
    else {
        $lo = $ax->read_json( $sf->{i}{f_global_settings} ) // {};
        if ( ! %{$lo//{}} ) {
            $lo = $op_df->defaults_pre_plugin();
        }
        $sf->{i}{tc_default}{mouse} = $lo->{table}{mouse};
        $sf->{i}{tcu_default}{mouse} = $lo->{table}{mouse};
    }



    if ( defined wantarray ) {
        return $lo;
    }

    for my $section ( keys %$lo ) {
        for my $opt ( keys %{$lo->{$section}} ) {
            $sf->{o}{$section}{$opt} = $lo->{$section}{$opt};
        }
    }
}





1;


__END__

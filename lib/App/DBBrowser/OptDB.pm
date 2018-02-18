package # hide from PAUSE
App::DBBrowser::OptDB;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_01';

use File::Basename qw( basename );

use Term::Choose       qw( choose );
use Term::Choose::Util qw( choose_a_subset settings_menu choose_dirs );
use Term::Form         qw();

use App::DBBrowser::DB;
use App::DBBrowser::Auxil;



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { i => $info, o => $opt }, $class;
}


sub __settings_menu_wrap_db {
    my ( $sf, $db_o, $section, $sub_menu, $prompt ) = @_;
    my $changed = settings_menu( $sub_menu, $db_o->{$section}, { prompt => $prompt } );
    return if ! $changed;
    $sf->{i}{write_config}++;
}


sub __group_readline_db {
    my ( $sf, $db_o, $section, $items, $prompt ) = @_;
    my $list = [ map {
        [
            exists $_->{prompt} ? $_->{prompt} : $_->{name},
            $db_o->{$section}{$_->{name}}
        ]
    } @{$items} ];
    my $trs = Term::Form->new();
    my $new_list = $trs->fill_form(
        $list,
        { prompt => $prompt, auto_up => 2, confirm => $sf->{i}{_confirm}, back => $sf->{i}{_back} }
    );
    if ( $new_list ) {
        for my $i ( 0 .. $#$items ) {
            $db_o->{$section}{$items->[$i]{name}} = $new_list->[$i][1];
        }
        $sf->{i}{write_config}++;
    }
}


sub __choose_dirs_wrap_db {
    my ( $sf, $db_o, $section, $option ) = @_;
    my $current = $db_o->{$section}{$option};
    # Choose_dirs
    my $dirs = choose_dirs( { mouse => $sf->{o}{table}{mouse}, current => $current } );
    return if ! defined $dirs;
    return if ! @$dirs;
    $db_o->{$section}{$option} = $dirs;
    $sf->{i}{write_config}++;
    return;
}


sub connect_parameter {
    my ( $sf, $db ) = @_;
    my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $env_variables = $obj_db->env_variables();
    my $read_arg = $obj_db->read_arguments();
    my ( $driver_prefix, $set_attr ) = $obj_db->set_attributes();
    my $connect_parameter = {
        use_env_var => {},
        required    => {},
        keep_secret => {},
        read_arg    => {},
        set_attr  => {},
        dir_sqlite  => [],
    };
    my $db_o = $sf->__read_db_config_files();
    my $db_plugin = $sf->{i}{plugin};
    my $section = $db ? $db_plugin . '_' . $db : $db_plugin;
    for my $env_var ( @$env_variables ) {
        if ( defined $db && ! defined $db_o->{$section}{$env_var} ) {
            $section = $db_plugin;
        }
        $connect_parameter->{use_env_var}{$env_var} = $db_o->{$section}{$env_var};
    }
    for my $option ( keys %{$db_o->{$db_plugin}} ) {
        if ( defined $db && ! defined $db_o->{$section}{$option} ) {
            $section = $db_plugin;
        }
        if ( defined $driver_prefix && $option =~ /^\Q$driver_prefix\E/ ) {
            $connect_parameter->{set_attr}{$option} = $db_o->{$section}{$option};
        }
    }
    for my $attr ( @$set_attr ) {
        my $name = $attr->{name};
        if ( defined $db && ! defined $db_o->{$section}{$name} ) {
            $section = $db_plugin;
        }
        if ( ! defined $db_o->{$section}{$name} ) {
            $db_o->{$section}{$name} = $attr->{avail_values}[$attr->{default_index}];
        }
        $connect_parameter->{set_attr}{$name} = $db_o->{$section}{$name};
    }
    for my $item ( @$read_arg ) {
        my $name = $item->{name};
        my $required_field = 'field_' . $name;
        $connect_parameter->{keep_secret}{$name} = $item->{keep_secret};
        if ( defined $db && ! defined $db_o->{$section}{$required_field} ) {
            $section = $db_plugin;
        }
        if ( ! defined $db_o->{$section}{$required_field} ) {
            $db_o->{$section}{$required_field} = 1; # All fields required by default
        }
        $connect_parameter->{required}{$name} = $db_o->{$section}{$required_field};
        if ( ! $sf->{i}{login_error} ) {
            if ( defined $db && ! defined $db_o->{$section}{$name} ) {
                $section = $db_plugin;
            }
            $connect_parameter->{read_arg}{$name} = $db_o->{$section}{$name};
        }
    }
    if ( $sf->{i}{driver} eq 'SQLite' && ! defined $db_o->{$db_plugin}{directories_sqlite} ) {
        $db_o->{$db_plugin}{directories_sqlite} = [ $sf->{i}{home_dir} ];
    }
    $connect_parameter->{dir_sqlite} = $db_o->{$db_plugin}{directories_sqlite}; #
    if ( exists $sf->{i}{login_error} ) {
        delete $sf->{i}{login_error}; #
    }
    return $connect_parameter;
}



sub database_setting {
    my ( $sf, $db ) = @_;
    my $changed = 0;
    SECTION: while ( 1 ) {
        my ( $driver, $db_plugin, $section );
        if ( defined $db ) {
            $db_plugin = $sf->{i}{plugin};
            $driver = $sf->{i}{driver};
            $section   = $db_plugin . '_' . $db;
            for my $option ( keys %{$sf->{o}{$db_plugin}} ) {
                next if $option eq 'directories_sqlite';
                if ( ! defined $sf->{o}{$section}{$option} ) {
                    $sf->{o}{$section}{$option} = $sf->{o}{$db_plugin}{$option};
                }
            }
        }
        else {
            if ( @{$sf->{o}{G}{plugins}} == 1 ) {
                $db_plugin = $sf->{o}{G}{plugins}[0];
            }
            else {
                # Choose
                $db_plugin = choose(
                    [ undef, map( "- $_", @{$sf->{o}{G}{plugins}} ) ],
                    { %{$sf->{i}{lyt_3}}, undef => $sf->{i}{back_short} }
                );
                return if ! defined $db_plugin;
            }
            $db_plugin =~ s/^-\ //;
            $sf->{i}{plugin} = $db_plugin;
            $section = $db_plugin;
        }
        my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
        $driver = $obj_db->driver() if ! $driver;
        my $env_variables = $obj_db->environment_variables();
        my $login_data    = $obj_db->read_arguments();
        my $connect_attr  = $obj_db->choose_arguments();
        my $items = {
            required => [ map { {
                    name         => 'field_' . $_->{name},
                    prompt       => exists $_->{prompt} ? $_->{prompt} : $_->{name},
                    avail_values => [ 'NO', 'YES' ]
                } } @$login_data ],
            env_variables => [ map { {
                    name         => $_,
                    prompt       => $_,
                    avail_values => [ 'NO', 'YES' ]
                } } @$env_variables ],
            read_argument   => [
                    grep { ! $_->{keep_secret} } @$login_data
                ],
            choose_argument => $connect_attr,
        };
        my @groups;
        push @groups, [ 'required',        "- Fields"             ] if @{$items->{required}};
        push @groups, [ 'env_variables',   "- ENV Variables"      ] if @{$items->{env_variables}};
        push @groups, [ 'read_argument',   "- Login Data"         ] if @{$items->{read_argument}};
        push @groups, [ 'choose_argument', "- DB Options"         ];
        push @groups, [ 'sqlite_dir',      "- Sqlite directories" ] if $driver eq 'SQLite';
        my $prompt = defined $db ? 'DB: "' . ( $driver eq 'SQLite' ? basename $db : $db )
                                 : 'Plugin "' . $db_plugin . '"';
        my $db_o = $sf->__read_db_config_files();
        my $old_idx_group = 0;

        GROUP: while ( 1 ) {
            my $reset = '  Reset DB';
            my @pre = ( undef );
            my $choices = [ @pre, map( $_->[1], @groups ) ];
            push @$choices, $reset if ! defined $db;
            # Choose
            my $idx_group = choose(
                $choices,
                { %{$sf->{i}{lyt_3}}, prompt => $prompt, index => 1,
                  default => $old_idx_group, undef => $sf->{i}{back_short} }
            );
            if ( ! defined $idx_group || ! defined $choices->[$idx_group] ) {
                if ( $sf->{i}{write_config} ) {
                    $sf->__write_db_config_files( $db_o );
                    delete $sf->{i}{write_config};
                    $changed++;
                }
                next SECTION if ! $db && @{$sf->{o}{G}{plugins}} > 1;
                return $changed;
            }
            if ( $sf->{o}{G}{menu_memory} ) {
                if ( $old_idx_group == $idx_group ) {
                    $old_idx_group = 0;
                    next GROUP;
                }
                else {
                    $old_idx_group = $idx_group;
                }
            }
            if ( $choices->[$idx_group] eq $reset ) {
                my @databases;
                for my $section ( keys %$db_o ) {
                    push @databases, $1 if $section =~ /^\Q$db_plugin\E_(.+)\z/;
                }
                if ( ! @databases ) {
                    choose(
                        [ 'No databases with customized settings.' ],
                        { %{$sf->{i}{lyt_stop}}, prompt => 'Press ENTER' }
                    );
                    next GROUP;
                }
                my $choices = choose_a_subset(
                    [ sort @databases ],
                    { p_new => 'Reset DB: ' }
                );
                if ( ! $choices->[0] ) {
                    next GROUP;
                }
                for my $db ( @$choices ) {
                    my $section = $db_plugin . '_' . $db;
                    delete $db_o->{$section};
                }
                $sf->{i}{write_config}++;
                next GROUP;;
            }
            my $group  = $groups[$idx_group-@pre][0];
            if ( $group eq 'required' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $required = $item->{name};
                    push @$sub_menu, [ $required, '- ' . $item->{prompt}, $item->{avail_values} ];
                    if ( ! defined $db_o->{$section}{$required} ) {
                        if ( defined $db_o->{$db_plugin}{$required} ) {
                            $db_o->{$section}{$required} = $db_o->{$db_plugin}{$required};
                        }
                        else {
                            $db_o->{$section}{$required} = 1;  # All fields required by default
                        }
                    }
                }
                my $prompt = 'Required fields (' . $db_plugin . '):';
                $sf->__settings_menu_wrap_db( $db_o, $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'env_variables' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $env_variable = $item->{name};
                    push @$sub_menu, [ $env_variable, '- ' . $item->{prompt}, $item->{avail_values} ];
                    if ( ! defined $db_o->{$section}{$env_variable} ) {
                        if ( defined $db_o->{$db_plugin}{$env_variable} ) {
                            $db_o->{$section}{$env_variable} = $db_o->{$db_plugin}{$env_variable};
                        }
                        else {
                            $db_o->{$section}{$env_variable} = 0;
                        }
                    }
                }
                my $prompt = 'Use ENV variables (' . $db_plugin . '):';
                $sf->__settings_menu_wrap_db( $db_o, $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'read_argument' ) {
               for my $item ( @{$items->{$group}} ) {
                    my $option = $item->{name};
                    if ( ! defined $db_o->{$section}{$option} ) {
                        if ( defined $db_o->{$db_plugin}{$option} ) {
                            $db_o->{$section}{$option} = $db_o->{$db_plugin}{$option};
                        }
                    }
                }
                my $prompt = 'Default login data (' . $db_plugin . '):';
                $sf->__group_readline_db( $db_o, $section, $items->{$group}, $prompt );
            }
            elsif ( $group eq 'choose_argument' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $option = $item->{name};
                    my $prompt = '- ' . ( exists $item->{prompt} ? $item->{prompt} : $item->{name} );
                    push @$sub_menu, [ $option, $prompt, $item->{avail_values} ];
                    if ( ! defined $db_o->{$section}{$option} ) {
                        if ( defined $db_o->{$db_plugin}{$option} ) {
                            $db_o->{$section}{$option} = $db_o->{$db_plugin}{$option};
                        }
                        else {
                            $db_o->{$section}{$option} = $item->{avail_values}[$item->{default_index}];
                        }
                    }
                }
                my $prompt = 'Options (' . $db_plugin . '):';
                $sf->__settings_menu_wrap_db( $db_o, $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'sqlite_dir' ) {
                my $option = 'directories_sqlite';
                $sf->__choose_dirs_wrap_db( $db_o, $section, $option );
                next GROUP;
            }
        }
    }
}


sub __write_db_config_files {
    my ( $sf, $db_o ) = @_;
    my $regexp_db_plugins = join '|', map quotemeta, @{$sf->{o}{G}{plugins}};
    my $fmt = $sf->{i}{conf_file_fmt};
    my $tmp = {};
    for my $section ( sort keys %$db_o ) {
        if ( $section =~ /^($regexp_db_plugins)(?:_(.+))?\z/ ) {
            my ( $db_plugin, $conf_sect ) = ( $1, $2 );
            $conf_sect = '*' . $db_plugin if ! defined $conf_sect;
            for my $option ( keys %{$db_o->{$section}} ) {
                $tmp->{$db_plugin}{$conf_sect}{$option} = $db_o->{$section}{$option};
            }
        }
    }
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    for my $section ( keys %$tmp ) {
        my $file_name =  $section;
        $ax->write_json( sprintf( $fmt, $file_name ), $tmp->{$section}  );
    }
}


sub __read_db_config_files {
    my ( $sf ) = @_;
    my $fmt = $sf->{i}{conf_file_fmt};
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $db_o;
    for my $db_plugin ( @{$sf->{o}{G}{plugins}} ) {
        my $file = sprintf( $fmt, $db_plugin );
        if ( -f $file && -s $file ) {
            my $tmp = $ax->read_json( $file );
            for my $conf_sect ( keys %$tmp ) {
                my $section = $db_plugin . ( $conf_sect =~ /^\*\Q$db_plugin\E\z/ ? '' : '_' . $conf_sect );
                for my $option ( keys %{$tmp->{$conf_sect}} ) {
                    $db_o->{$section}{$option} = $tmp->{$conf_sect}{$option};
                }
            }
        }
    }
    return $db_o;
}




1;


__END__

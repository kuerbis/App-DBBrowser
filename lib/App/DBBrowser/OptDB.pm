package # hide from PAUSE
App::DBBrowser::OptDB;

use warnings;
use strict;
use 5.008003;
no warnings 'utf8';

our $VERSION = '1.060_02';

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
    my $changed = settings_menu( $sub_menu, $db_o->{$section}, { prompt => $prompt, mouse => $sf->{o}{table}{mouse} } );
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
    my ( $sf, $db_o, $section, $opt ) = @_;
    my $current = $db_o->{$section}{$opt};
    # Choose_dirs
    my $dirs = choose_dirs( { mouse => $sf->{o}{table}{mouse}, current => $current } );
    return if ! defined $dirs;
    return if ! @$dirs;
    $db_o->{$section}{$opt} = $dirs;
    $sf->{i}{write_config}++;
    return;
}


sub connect_parameter {
    my ( $sf, $db ) = @_;
    my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
    my $db_o = $sf->__read_db_config_files();
    my $plugin = $sf->{i}{plugin};
    my $cp = {
        use_env_var => {},
        required    => {},
        secret      => {},
        arguments   => {},
        attributes  => {},
        dir_sqlite  => [],
    };

    my $env_vars = $obj_db->env_variables();
    for my $env_var ( @$env_vars ) {
        if ( ! defined $db || defined $db && ! defined $db_o->{$db}{$env_var} ) {
            $cp->{use_env_var}{$env_var} = $db_o->{$plugin}{$env_var};
        }
        else {
            $cp->{use_env_var}{$env_var} = $db_o->{$db}{$env_var};
        }
    }

    my ( $driver_prefix, $attrs ) = $obj_db->set_attributes();
    $driver_prefix ||= '';
    for my $opt ( keys %{$db_o->{$plugin}} ) {
        if ( ! defined $db || defined $db && ! defined $db_o->{$db}{$opt} ) {
            $cp->{attributes}{$opt} = $db_o->{$plugin}{$opt} if $opt =~ /^\Q$driver_prefix\E/;
        }
        else {
            $cp->{attributes}{$opt} = $db_o->{$db}{$opt}     if $opt =~ /^\Q$driver_prefix\E/;
        }
    }
    for my $attr ( @$attrs ) {
        my $name = $attr->{name};
        if ( ! defined $db || defined $db && ! defined $db_o->{$db}{$name} ) {
            if ( ! defined $db_o->{$plugin}{$name} ) {
                $db_o->{$plugin}{$name} = $attr->{values}[$attr->{default}];
                $cp->{attributes}{$name} = $db_o->{$plugin}{$name};
            }
        }
        else {
            if ( ! defined $db_o->{$db}{$name} ) {
                $db_o->{$db}{$name} = $attr->{values}[$attr->{default}];
                $cp->{attributes}{$name} = $db_o->{$db}{$name};
            }
        }
    }

    my $arg = $obj_db->read_arguments();
    for my $item ( @$arg ) {
        my $name = $item->{name};
        my $required = 'field_' . $name;
        $cp->{secret}{$name} = $item->{secret};
        if ( ! defined $db || defined $db && ! defined $db_o->{$db}{$required} ) {
            if ( ! defined $db_o->{$plugin}{$required} ) {
                $db_o->{$plugin}{$required} = 1; # All fields required by default
                $cp->{required}{$name} = $db_o->{$plugin}{$required};
            }
        }
        else {
            if ( ! defined $db_o->{$db}{$required} ) {
                $db_o->{$db}{$required} = 1; # All fields required by default
                $cp->{required}{$name} = $db_o->{$db}{$required};
            }
        }
        if ( ! $sf->{i}{login_error} ) {
            if ( ! defined $db || defined $db && ! defined $db_o->{$db}{$name} ) {
                $cp->{arguments}{$name} = $db_o->{$plugin}{$name};
            }
            else {
                $cp->{arguments}{$name} = $db_o->{$db}{$name};
            }
        }
    }

    if ( $sf->{i}{driver} eq 'SQLite' && ! defined $db_o->{$plugin}{directories_sqlite} ) {
        $db_o->{$plugin}{directories_sqlite} = [ $sf->{i}{home_dir} ];
    }
    $cp->{dir_sqlite} = $db_o->{$plugin}{directories_sqlite}; #
    if ( exists $sf->{i}{login_error} ) {
        delete $sf->{i}{login_error}; #
    }
    return $cp;
}



sub database_setting {
    my ( $sf, $db ) = @_;
    my $changed = 0;
    SECTION: while ( 1 ) {
        my ( $driver, $plugin, $section );
        if ( defined $db ) {
            $plugin = $sf->{i}{plugin};
            $driver = $sf->{i}{driver};
            $section = $db;
            for my $opt ( keys %{$sf->{o}{$plugin}} ) {
                next if $opt eq 'directories_sqlite';
                if ( ! defined $sf->{o}{$section}{$opt} ) {
                    $sf->{o}{$section}{$opt} = $sf->{o}{$plugin}{$opt};
                }
            }
        }
        else {
            if ( @{$sf->{o}{G}{plugins}} == 1 ) {
                $plugin = $sf->{o}{G}{plugins}[0];
            }
            else {
                # Choose
                $plugin = choose(
                    [ undef, map( "- $_", @{$sf->{o}{G}{plugins}} ) ],
                    { %{$sf->{i}{lyt_3}}, undef => $sf->{i}{back_short} }
                );
                return if ! defined $plugin;
            }
            $plugin =~ s/^-\ //;
            $plugin = 'App::DBBrowser::DB::' . $plugin;
            $sf->{i}{plugin} = $plugin;
            $section = $plugin;
        }
        my $obj_db = App::DBBrowser::DB->new( $sf->{i}, $sf->{o} );
        $driver = $obj_db->driver() if ! $driver;
        my $env_var    = $obj_db->env_variables();
        my $login_data = $obj_db->read_arguments();
        my $attr       = $obj_db->set_attributes();
        my $items = {
            required => [ map { {
                    name         => 'field_' . $_->{name},
                    prompt       => exists $_->{prompt} ? $_->{prompt} : $_->{name},
                    values => [ 'NO', 'YES' ]
                } } @$login_data ],
            env_variables => [ map { { #
                    name         => $_,
                    prompt       => $_,
                    values => [ 'NO', 'YES' ]
                } } @$env_var ],
            arguments => [
                    grep { ! $_->{secret} } @$login_data
                ],
            attributes => $attr,
        };
        my @groups;
        push @groups, [ 'required',      "- Fields"             ] if @{$items->{required}};
        push @groups, [ 'env_variables', "- ENV Variables"      ] if @{$items->{env_variables}};
        push @groups, [ 'arguments',     "- Login Data"         ] if @{$items->{arguments}};
        push @groups, [ 'attributes',    "- DB Options"         ];
        push @groups, [ 'sqlite_dir',    "- Sqlite directories" ] if $driver eq 'SQLite';
        my $prompt = defined $db ? 'DB: "' . ( $driver eq 'SQLite' ? basename $db : $db )
                                 : 'Plugin "' . $plugin . '"';
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
                    push @databases, $section if $section ne $plugin; # $1 if $section =~ /^\Q$plugin\E_(.+)\z/;
                }
                if ( ! @databases ) {
                    choose(
                        [ 'No databases with customized settings.' ],
                        { %{$sf->{i}{lyt_m}}, prompt => 'Press ENTER' }
                    );
                    next GROUP;
                }
                my $choices = choose_a_subset(
                    [ sort @databases ],
                    { p_new => 'Reset DB: ', mouse => $sf->{o}{table}{mouse} }
                );
                if ( ! $choices->[0] ) {
                    next GROUP;
                }
                for my $db ( @$choices ) {
                    delete $db_o->{$db};
                }
                $sf->{i}{write_config}++;
                next GROUP;;
            }
            my $group  = $groups[$idx_group-@pre][0];
            if ( $group eq 'required' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $required = $item->{name};
                    push @$sub_menu, [ $required, '- ' . $item->{prompt}, $item->{values} ];
                    if ( ! defined $db_o->{$section}{$required} ) {
                        if ( defined $db_o->{$plugin}{$required} ) {
                            $db_o->{$section}{$required} = $db_o->{$plugin}{$required};
                        }
                        else {
                            $db_o->{$section}{$required} = 1;  # All fields required by default
                        }
                    }
                }
                my $prompt = 'Required fields (' . $plugin . '):';
                $sf->__settings_menu_wrap_db( $db_o, $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'env_variables' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $env_variable = $item->{name};
                    push @$sub_menu, [ $env_variable, '- ' . $item->{prompt}, $item->{values} ];
                    if ( ! defined $db_o->{$section}{$env_variable} ) {
                        if ( defined $db_o->{$plugin}{$env_variable} ) {
                            $db_o->{$section}{$env_variable} = $db_o->{$plugin}{$env_variable};
                        }
                        else {
                            $db_o->{$section}{$env_variable} = 0;
                        }
                    }
                }
                my $prompt = 'Use ENV variables (' . $plugin . '):';
                $sf->__settings_menu_wrap_db( $db_o, $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'arguments' ) {
               for my $item ( @{$items->{$group}} ) {
                    my $opt = $item->{name};
                    if ( ! defined $db_o->{$section}{$opt} ) {
                        if ( defined $db_o->{$plugin}{$opt} ) {
                            $db_o->{$section}{$opt} = $db_o->{$plugin}{$opt};
                        }
                    }
                }
                my $prompt = 'Default login data (' . $plugin . '):';
                $sf->__group_readline_db( $db_o, $section, $items->{$group}, $prompt );
            }
            elsif ( $group eq 'attributes' ) {
                my $sub_menu = [];
                for my $item ( @{$items->{$group}} ) {
                    my $opt = $item->{name};
                    my $prompt = '- ' . ( exists $item->{prompt} ? $item->{prompt} : $item->{name} );
                    push @$sub_menu, [ $opt, $prompt, $item->{values} ];
                    if ( ! defined $db_o->{$section}{$opt} ) {
                        if ( defined $db_o->{$plugin}{$opt} ) {
                            $db_o->{$section}{$opt} = $db_o->{$plugin}{$opt};
                        }
                        else {
                            $db_o->{$section}{$opt} = $item->{values}[$item->{default}];
                        }
                    }
                }
                my $prompt = 'Options (' . $plugin . '):';
                $sf->__settings_menu_wrap_db( $db_o, $section, $sub_menu, $prompt );
                next GROUP;
            }
            elsif ( $group eq 'sqlite_dir' ) {
                my $opt = 'directories_sqlite';
                $sf->__choose_dirs_wrap_db( $db_o, $section, $opt );
                next GROUP;
            }
        }
    }
}


sub __write_db_config_files {
    my ( $sf, $db_o ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $plugin = $sf->{i}{plugin};
    $plugin=~ s/^App::DBBrowser::DB:://;
    my $file_name = sprintf( $sf->{i}{conf_file_fmt}, $plugin );
    $file_name=~ s/^App::DBBrowser::DB:://;
    $ax->write_json( $file_name, $db_o );
}


sub __read_db_config_files {
    my ( $sf ) = @_;
    my $ax = App::DBBrowser::Auxil->new( $sf->{i}, $sf->{o} );
    my $plugin = $sf->{i}{plugin};
    $plugin=~ s/^App::DBBrowser::DB:://;
    my $file_name = sprintf( $sf->{i}{conf_file_fmt}, $plugin );
    my $db_o;
    if ( -f $file_name && -s $file_name ) {
        $db_o = $ax->read_json( $file_name ) || {};
    }
    return $db_o;
}




1;


__END__

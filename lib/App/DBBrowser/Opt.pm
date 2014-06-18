package # hide from PAUSE
App::DBBrowser::Opt;

use warnings;
use strict;
use 5.010001;

our $VERSION = '0.034';

use Encode                qw( encode );
use File::Basename        qw( basename );
use File::Spec::Functions qw( catfile );
use FindBin               qw( $RealBin $RealScript );
#use Pod::Usage            qw( pod2usage );             # "require"-d in options/help

use Clone              qw( clone );
use Encode::Locale     qw();
use JSON::XS           qw( decode_json );
use Term::Choose       qw( choose );
use Term::Choose::Util qw( insert_sep print_hash util_readline choose_a_number choose_a_subset choose_multi );

sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
}


sub options {
    my ( $self ) = @_;
    my $menus = [
        [ 'db_defaults',    "- DB Defaults" ],
        [ 'db_drivers',     "- DB Drivers" ],
        [ 'db_login_once',  "- DB Login" ],
        [ '_env_dbi',       "- ENV DBI" ],
        [ '_enchant',       "- Enchant" ],
        [ 'lock_stmt',      "- Lock" ],
        [ 'max_rows',       "- Max Rows" ],
        [ 'metadata',       "- Metadata" ],
        [ 'mouse',          "- Mouse Mode" ],
        [ 'min_col_width',  "- Colwidth" ],
        [ 'operators',      "- Operators" ],
        [ '_parentheses',   "- Parentheses" ],
        [ 'progress_bar',   "- ProgressBar" ],
        [ 'regexp_case',    "- Regexp Case" ],
        [ 'sssc_mode',      "- Sssc Mode" ],
        [ 'tab_width',      "- Tabwidth" ],
        [ 'undef',          "- Undef" ],
    ];
    my $sub_menus = {
       _enchant      => [
            [ 'keep_db_choice',     "- Choose Database", [ 'Simple', 'Memory' ] ],
            [ 'keep_schema_choice', "- Choose Schema",   [ 'Simple', 'Memory' ] ],
            [ 'keep_table_choice',  "- Choose Table",    [ 'Simple', 'Memory' ] ],
            [ 'table_expand',       "- Print  Table",    [ 'Simple', 'Expand' ] ],
            [ 'keep_header',        "- Table Header",    [ 'Simple', 'Each page' ] ],
        ],
        _parentheses => [
            [ 'w_parentheses', "- Parentheses in WHERE",     [ 'NO', '(YES', 'YES(' ] ],
            [ 'h_parentheses', "- Parentheses in HAVING TO", [ 'NO', '(YES', 'YES(' ] ],
        ],
        _env_dbi     => [
            [ 'env_dbi_user', "- Use DBI_USER", [ 'NO', 'YES' ] ],
            [ 'env_dbi_pass', "- Use DBI_PASS", [ 'NO', 'YES' ] ],
        ],
    };
    my $path = '  Path';
    my @pre = ( undef, $self->{info}{_continue}, $self->{info}{_help}, $path );
    my @real = map( $_->[1], @$menus );
    my $choices = [ @pre, @real ];

    OPTION: while ( 1 ) {
        # Choose
        my $idx = choose(
            $choices,
            { %{$self->{info}{lyt_3}}, index => 1, undef => $self->{info}{_exit} }
        );
        exit if ! defined $idx;
        my $key;
        if ( $idx <= $#pre ) {
            $key = $pre[$idx];
        }
        else {
            $idx -= @pre;
            $key = $menus->[$idx][0];
            die if $key !~ /^_/ && ! exists $self->{opt}{$key};
        }
        if ( ! defined $key ) {
            if ( $self->{info}{write_config} ) {
                $self->__write_config_file( $self->{info}{config_file} );
                delete $self->{info}{write_config};
            }
            exit();
        }
        elsif ( $key eq $self->{info}{_continue} ) {
            if ( $self->{info}{write_config} ) {
                $self->__write_config_file( $self->{info}{config_file} );
                delete $self->{info}{write_config};
            }
            return $self->{opt};
        }
        elsif ( $key eq $self->{info}{_help} ) {
            require Pod::Usage;
            Pod::Usage::pod2usage( {
                -input => 'bin/db-browser',
                -exitval => 'NOEXIT',
                -verbose => 2 } );
        }
        elsif ( $key eq $path ) {
            my $version = 'version';
            my $bin     = '  bin  ';
            my $app_dir = 'app-dir';
            my $path = {
                $version => $main::VERSION,
                $bin     => catfile( $RealBin, $RealScript ),
                $app_dir => $self->{info}{app_dir},
            };
            my $keys = [ $version, $bin, $app_dir ];
            print_hash( $path, { keys => $keys, preface => ' Close with ENTER' } );
        }
        elsif ( $key eq 'tab_width' ) {
            my $digits = 3;
            my $prompt = 'Tab width';
            $self->__opt_number_range( $key, $prompt, $digits );
        }
        elsif ( $key eq 'min_col_width' ) {
            my $digits = 3;
            my $prompt = 'Minimum Column width';
            $self->__opt_number_range( $key, $prompt, $digits );
        }
        elsif ( $key eq 'undef' ) {
            my $prompt = 'Print replacement for undefined table vales';
            $self->__opt_readline( $key, $prompt );
        }
        elsif ( $key eq 'progress_bar' ) {
            my $digits = 7;
            my $prompt = '"Threshold ProgressBar"';
            $self->__opt_number_range( $key, $prompt, $digits );
        }
        elsif ( $key eq 'max_rows' ) {
            my $digits = 7;
            my $prompt = '"Max rows"';
            $self->__opt_number_range( $key, $prompt, $digits );
        }
        elsif ( $key eq 'lock_stmt' ) {
            my $list = [ 'Lk0', 'Lk1' ];
            my $prompt = 'Keep statement';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq 'metadata' ) {
            my $list = $self->{info}{yes_no};
            my $prompt = 'Enable Metadata';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq 'regexp_case' ) {
            my $list = $self->{info}{yes_no};
            my $prompt = 'REGEXP case sensitiv';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq '_parentheses' ) {
            my $sub_menu = $sub_menus->{$key};
            $self->__opt_choose_multi( $sub_menu );
        }
        elsif ( $key eq 'db_login_once' ) {
            my $list = [ 'per-DB', 'once' ];
            my $prompt = 'Ask for credentials';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq '_env_dbi' ) {
            my $sub_menu = $sub_menus->{$key};
            $self->__opt_choose_multi( $sub_menu );
        }
        elsif ( $key eq 'db_defaults' ) {
            $self->database_setting();
        }
        elsif ( $key eq 'sssc_mode' ) {
            my $list = [ 'simple', 'compat' ];
            my $prompt = 'Sssc mode';
            $self->__opt_choose_index( $key, $prompt, $list );
        }
        elsif ( $key eq 'operators' ) {
            my $available = $self->{info}{avail_operators};
            $self->__opt_choose_a_list( $key, $available );
        }
        elsif ( $key eq 'db_drivers' ) {
            my $available = $self->{info}{avail_db_drivers};
            $self->__opt_choose_a_list( $key, $available );
        }
        elsif ( $key eq 'mouse' ) {
            my $max = 4;
            my $prompt = 'Mouse mode';
            $self->__opt_number( $key, $prompt, $max );
        }
        elsif ( $key eq '_enchant' ) {
            my $sub_menu = $sub_menus->{$key};
            $self->__opt_choose_multi( $sub_menu );
        }
        else { die "Unknown option: $key" }
    }
}


sub __opt_choose_multi {
    my ( $self, $sub_menu ) = @_;
    my $changed = choose_multi( $sub_menu, $self->{opt} );
    return if ! $changed;
    $self->{info}{write_config}++;
}


sub __opt_choose_index {
    my ( $self, $key, $prompt, $list ) = @_;
    my $yn = 0;
    my $current = $list->[$self->{opt}{$key}];
    # Choose
    my $idx = choose(
        [ undef, @$list ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', index => 1 }
    );
    return if ! defined $idx;
    return if $idx == 0;
    $idx--;
    $self->{opt}{$key} = $idx;
    $self->{info}{write_config}++;
    return;
}

sub __opt_choose_a_list {
    my ( $self, $key, $available ) = @_;
    my $current = $self->{opt}{$key};
    # Choose_list
    my $list = choose_a_subset( $available, { current => $current } );
    return if ! defined $list;
    $self->{opt}{$key} = $list;
    $self->{info}{write_config}++;
    return;
}

sub __opt_number {
    my ( $self, $key, $prompt, $max ) = @_;
    my $current = $self->{opt}{$key};
    # Choose
    my $choice = choose(
        [ undef, 0 .. $max ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', justify => 1 }
    );
    return if ! defined $choice;
    $self->{opt}{$key} = $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_number_range {
    my ( $self, $key, $prompt, $digits ) = @_;
    my $current = $self->{opt}{$key};
    $current = insert_sep( $current, $self->{opt}{thsd_sep} );
    # Choose_a_number
    my $choice = choose_a_number( $digits, { name => $prompt, current => $current } );
    return if ! defined $choice;
    $self->{opt}{$key} = $choice eq '--' ? undef : $choice;
    $self->{info}{write_config}++;
    return;
}

sub __opt_readline {
    my ( $self, $key, $prompt ) = @_;
    my $current = $self->{opt}{$key};
    $prompt .= ' ["' . $current . '"]: ';
    # Readline
    my $choice = util_readline( $prompt );
    return if ! defined $choice;
    $self->{opt}{$key} = $choice;
    $self->{info}{write_config}++;
    return;
}


sub database_setting {
    my ( $self, $db ) = @_;
    my ( $db_driver, $section );
    if ( ! defined $db ) {
        if ( @{$self->{opt}{db_drivers}} == 1 ) {
            $db_driver = $self->{opt}{db_drivers}[0];
        }
        else {
            # Choose
            $db_driver = choose(
                [ undef, @{$self->{opt}{db_drivers}} ],
                { %{$self->{info}{lyt_1}} }
            );
            return if ! defined $db_driver;
        }
        $section = $db_driver;
    }
    else {
        $db_driver = $self->{info}{db_driver};
        $section   = $db_driver . '_' . $db;
        for my $key ( keys %{$self->{opt}{$db_driver}} ) {
            $self->{opt}{$section}{$key} //= $self->{opt}{$db_driver}{$key};
        }
    }

    my $orig = clone( $self->{opt} );
    my $menus = {
        SQLite => [
            [ 'sqlite_unicode',             "- Unicode" ],
            [ 'sqlite_see_if_its_a_number', "- See if its a number" ],
            [ '_binary_filter',             "- Binary Filter" ],
        ],
        mysql => [
            [ 'host',              "- Host" ],
            [ 'port',              "- Port" ],
            [ 'mysql_enable_utf8', "- Enable utf8" ],
            [ '_binary_filter',    "- Binary Filter" ],
        ],
        Pg => [
            [ 'host',           "- Host" ],
            [ 'port',           "- Port" ],
            [ 'pg_enable_utf8', "- Enable utf8" ],
            [ '_binary_filter', "- Binary Filter" ],
        ],
    };
    my $prompt;
    if ( defined $db ) {
        $prompt = 'DB: "' . ( $db_driver eq 'SQLite' ? basename( $db ) : $db ) . '"';
    }
    else {
        $prompt = 'Driver: ' . $db_driver;
    }
    my @pre = ( undef, $self->{info}{_confirm} );
    my @real = map { $_->[1] } @{$menus->{$db_driver}};
    my $choices = [ @pre, @real ];
    push @$choices, "  RESET" if defined $db;

    DB_OPTION: while ( 1 ) {
        # Choose
        my $idx = choose(
            $choices,
            { %{$self->{info}{lyt_3}}, index => 1, prompt => $prompt  }
        );
        exit if ! defined $idx;
        my $key;
        if ( $idx <= $#pre ) {
            $key = $pre[$idx];
        }
        elsif ( $idx == @pre + @real ) {
            for my $key ( keys %{$self->{opt}{$section}} ) {
                $self->{opt}{$section}{$key} = undef;
            }
            $self->{info}{write_config}++;
            next;
        }
        else {
            $idx -= @pre;
            $key = $menus->{$db_driver}[$idx][0];
            die if ! exists $self->{opt}{$db_driver}{$key};
        }
        if ( ! defined $key ) {
            if ( $self->{info}{write_config} ) {
                $self->{opt} = clone( $orig );
            }
            return;
        }
        if ( $key eq $self->{info}{_confirm} ) {
            if ( $self->{info}{write_config} ) {
                $self->__write_config_file( $self->{info}{config_file} );
                delete $self->{info}{write_config};
                return 1;
            }
            return;
        }
        if ( $db_driver eq "SQLite" ) {
            if ( $key eq 'sqlite_unicode' ) {
                my $list = $self->{info}{yes_no};
                my $prompt = 'Unicode';
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
            }
            elsif ( $key eq 'sqlite_see_if_its_a_number' ) {
                my $list = $self->{info}{yes_no};
                my $prompt = 'See if its a number';
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
            }
            elsif ( $key eq '_binary_filter' ) {
                my $list = $self->{info}{yes_no};
                my $prompt = 'Enable Binary Filter';
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
            }
            else { die "Unknown key: $key" }
        }
        elsif ( $db_driver eq "mysql" ) {
            if ( $key eq 'mysql_enable_utf8' ) {
                my $list = $self->{info}{yes_no};
                my $prompt = 'Enable utf8';
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
            }
            elsif ( $key eq 'host' ) {
                my $prompt = 'Host';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'port' ) {
                my $prompt = 'Port';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq '_binary_filter' ) {
                my $list = $self->{info}{yes_no};
                my $prompt = 'Enable Binary Filter';
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
            }
            else { die "Unknown key: $key" }
        }
        elsif ( $db_driver eq "Pg" ) {
            if ( $key eq 'pg_enable_utf8' ) {
                my $prompt = 'Enable utf8';
                my $list = [ @{$self->{info}{yes_no}}, 'AUTO' ];
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
                $self->{opt}{$section}{$key} = -1 if $self->{opt}{$section}{$key} == 2;
            }
            elsif ( $key eq 'host' ) {
                my $prompt = 'Host';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq 'port' ) {
                my $prompt = 'Port';
                $self->__db_opt_readline( $section, $key, $prompt );
            }
            elsif ( $key eq '_binary_filter' ) {
                my $list = $self->{info}{yes_no};
                my $prompt = 'Enable Binary Filter';
                $self->__db_opt_choose_index( $section, $key, $prompt, $list );
            }
            else { die "Unknown key: $key" }
        }
    }
}


sub __db_opt_choose_index {
    my ( $self, $section, $key, $prompt, $list ) = @_;
    my $current = $list->[$self->{opt}{$section}{$key}];
    # Choose
    my $idx = choose(
        [ undef, @$list ],
        { %{$self->{info}{lyt_1}}, prompt => $prompt . ' [' . $current . ']:', index => 1 }
    );
    return if ! defined $idx;
    return if $idx == 0;
    $idx--;
    $self->{opt}{$section}{$key} = $idx;
    $self->{info}{write_config}++;
    return;
}


sub __db_opt_readline {
    my ( $self, $section, $key, $prompt ) = @_;
    my $current = $self->{opt}{$section}{$key};
    $prompt .= ' ["' . $current . '"]: ';
    # Readline
    my $choice = util_readline( $prompt );
    return if ! defined $choice;
    $self->{opt}{$section}{$key} = $choice;
    $self->{info}{write_config}++;
    return;
}


sub __write_config_file {
    my ( $self, $file ) = @_;
    my $tmp = {};
    for my $section ( sort keys %{$self->{opt}} ) {
        if ( ref( $self->{opt}{$section} ) eq 'HASH' ) {
            for my $key ( keys %{$self->{opt}{$section}} ) {
                $tmp->{$section}{$key} = $self->{opt}{$section}{$key};
            }
        }
        else {
            my $key = $section;
            my $section = $self->{info}{sect_generic};
            $tmp->{$section}{$key} = $self->{opt}{$key};
        }
    }
    $self->write_json( $file, $tmp );
}


sub read_config_file {
    my ( $self, $file ) = @_;
    my $tmp = $self->read_json( $file );
    for my $section ( keys %$tmp ) {
        for my $key ( keys %{$tmp->{$section}} ) {
            if ( $section eq $self->{info}{sect_generic} ) {
                $self->{opt}{$key} = $tmp->{$section}{$key};
            }
            else {
                $self->{opt}{$section}{$key} = $tmp->{$section}{$key};
            }
        }
    }
    return $self->{opt};
}


sub write_json {
    my ( $self, $file, $h_ref ) = @_;
    my $json = JSON::XS->new->pretty->canonical->encode( $h_ref );
    open my $fh, '>', encode( 'locale_fs', $file ) or die $!;
    print $fh $json;
    close $fh;
}


sub read_json {
    my ( $self, $file ) = @_;
    return {} if ! -f encode( 'locale_fs', $file );
    open my $fh, '<', encode( 'locale_fs', $file ) or die $!;
    my $json = do { local $/; <$fh> };
    close $fh;
    my $h_ref = {};
    $h_ref = decode_json( $json ) if $json;
    return $h_ref;
}


1;


__END__

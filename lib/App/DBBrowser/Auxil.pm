package # hide from PAUSE
App::DBBrowser::Auxil;

use warnings;
use strict;
use 5.008003;

our $VERSION = '1.014';

use Encode qw( encode );

use Encode::Locale         qw();
use JSON                   qw( decode_json );
use Term::Choose           qw( choose );
use Term::Choose::Util     qw( term_size );
use Text::LineFold         qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';



sub new {
    my ( $class, $info ) = @_;
    bless { info => $info }, $class;
}


sub __print_sql_statement {
    my ( $self, $sql, $table, $sql_type ) = @_;
    my %type_sql = (
        Select => "SELECT",
        Delete => "DELETE",
        Update => "UPDATE",
        Insert => "INSERT INTO",
    );
    my $str = $type_sql{$sql_type};
    if ( $sql_type eq 'Insert' ) {
        $str .= ' ' . $table . " (";
        $str .= " " . join( ', ', @{$sql->{print}{chosen_cols}} ) . " " if @{$sql->{print}{chosen_cols}};
        $str .= ")\n";
        $str .= "  VALUES(\n";
        for my $insert_row ( @{$sql->{quote}{insert_into_args}} ) {
            $str .= ( ' ' x 4 ) . join( ', ', map { defined $_ ? $_ : '' } @$insert_row ) . "\n";
        }
        $str .= "  )\n";
    }
    else {
        my $cols_sql;
        if ( $sql_type eq 'Select' ) {
            if ( $sql->{select_type} eq '*' ) {
                $cols_sql = ' *';
            }
            elsif ( $sql->{select_type} eq 'chosen_cols' ) {
                $cols_sql = ' ' . join( ', ', @{$sql->{print}{chosen_cols}} );
            }
            elsif ( @{$sql->{print}{aggr_cols}} || @{$sql->{print}{group_by_cols}} ) {
                $cols_sql = ' ' . join( ', ', @{$sql->{print}{group_by_cols}}, @{$sql->{print}{aggr_cols}} );
            }
            else {
                $cols_sql = ' *';
            }
        }
        $str .= $sql->{print}{distinct_stmt}              if $sql->{print}{distinct_stmt};
        $str .= $cols_sql                          . "\n" if $cols_sql;
        $str .= " FROM $table"                     . "\n";
        $str .= ' ' . $sql->{print}{set_stmt}      . "\n" if $sql->{print}{set_stmt};
        $str .= ' ' . $sql->{print}{where_stmt}    . "\n" if $sql->{print}{where_stmt};
        $str .= ' ' . $sql->{print}{group_by_stmt} . "\n" if $sql->{print}{group_by_stmt};
        $str .= ' ' . $sql->{print}{having_stmt}   . "\n" if $sql->{print}{having_stmt};
        $str .= ' ' . $sql->{print}{order_by_stmt} . "\n" if $sql->{print}{order_by_stmt};
        $str .= ' ' . $sql->{print}{limit_stmt}    . "\n" if $sql->{print}{limit_stmt};
    }
    $str .= "\n";
    my $line_fold = Text::LineFold->new( %{$self->{info}{line_fold}}, ColMax => ( term_size() )[0] - 2 );
    print $self->{info}{clear_screen};
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $str );
}


sub __print_error_message {
    my ( $self, $message, $title ) = @_;
    print "$title:\n" if $title;
    utf8::decode( $message );
    print $message;
    choose(
        [ 'Press ENTER to continue' ],
        { %{$self->{info}{lyt_stop}}, prompt => '' }
    );
}


sub __reset_sql {
    my ( $self, $sql ) = @_;
    $sql->{select_type} = '*';
    @{$sql->{print}}{ @{$sql->{strg_keys}} } = ( '' ) x  @{$sql->{strg_keys}};
    @{$sql->{quote}}{ @{$sql->{strg_keys}} } = ( '' ) x  @{$sql->{strg_keys}};
    @{$sql->{print}}{ @{$sql->{list_keys}} } = map{ [] } @{$sql->{list_keys}};
    @{$sql->{quote}}{ @{$sql->{list_keys}} } = map{ [] } @{$sql->{list_keys}};
    $sql->{pr_col_with_scalar_func} = [];
    delete $sql->{scalar_func_backup_pr_col};
}


sub write_json {
    my ( $self, $file, $h_ref ) = @_;
    my $json = JSON->new->utf8( 1 )->pretty->canonical->encode( $h_ref );
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
    if ( ! eval {
        $h_ref = decode_json( $json ) if $json;
        1 }
    ) {
        die "In '$file':\n$@";
    }
    return $h_ref;
}




1;

__END__

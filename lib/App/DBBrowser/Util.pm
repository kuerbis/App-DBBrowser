package # hide from PAUSE
App::DBBrowser::Util;

use warnings;
use strict;
use 5.010000;

our $VERSION = '0.045';

use Term::Choose           qw( choose );
use Term::Choose::Util     qw( term_size );
use Text::LineFold         qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

sub CLEAR_SCREEN () { "\e[H\e[J" }



sub new {
    my ( $class, $info, $opt ) = @_;
    bless { info => $info, opt => $opt }, $class;
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
    print CLEAR_SCREEN;
    print $line_fold->fold( '', ' ' x $self->{info}{stmt_init_tab}, $str );
}


sub __print_error_message {
    my ( $self, $message ) = @_;
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
    $sql->{pr_col_with_hidd_func} = [];
    delete $sql->{pr_backup_in_hidd};
}



1;

__END__

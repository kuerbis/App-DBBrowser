package # hide from PAUSE
App::DBBrowser::Table::ScalarFunctions::SQL;

use warnings;
use strict;
use 5.014;


sub new {
    my ( $class, $info, $options, $d ) = @_;
    bless {
        i => $info,
        o => $options,
        d => $d
    }, $class;
}


sub function_with_no_col {
    my ( $sf, $func ) = @_;
    my $driver = $sf->{i}{driver};
    $func = uc( $func );
    if ( $func =~ /^NOW\z/i ) {
        return "strftime('%Y-%m-%d %H-%M-%S','now')" if $driver eq 'SQLite';
        return "timestamp 'NOW'"                     if $driver eq 'Firebird';
        return "CURRENT"                             if $driver eq 'Informix'; # "CURRENT YEAR TO SECOND"
        return "CURRENT_TIMESTAMP"                   if $driver =~ /^(?:DB2|Oracle)\z/; # "CURRENT_TIMESTAMP(9)"
        return "NOW()";
    }
    else {
        return "$func()"; # none
    }
}


sub function_with_col {
    my ( $sf, $func, $col ) = @_;
    my $driver = $sf->{i}{driver};
    $func = uc( $func );
    if ( $func =~ /^LTRIM\z/i ) {
        return "TRIM(LEADING FROM $col)"  if $driver =~ /^(?:Pg|Firebird|Informix)\z/;
        return "LTRIM($col)";
    }
    elsif ( $func =~ /^RTRIM\z/i ) {
        return "TRIM(TRAILING FROM $col)" if $driver =~ /^(?:Pg|Firebird|Informix)\z/;
        return "RTRIM($col)";
    }
    elsif ( $func =~ /^OCTET_LENGTH\z/i ) {
        return "LENGTHB($col)"            if $driver eq 'Oracle';
        return "OCTET_LENGTH($col)";
    }
    elsif ( $func =~ /^CHAR_LENGTH\z/i ) {
        return "LENGTH($col)"             if $driver =~ /^(?:SQLite|Oracle)\z/;
        return "CHAR_LENGTH($col)";
    }
    else {
        return "$func($col)";
    }
}


sub function_with_col_and_arg {
    my ( $sf, $func, $col, $arg ) = @_;
    $func = uc( $func );
    if ( $func =~ /^CAST\z/i ) {
        return "CAST($col AS $arg)";
    }
    elsif ( $func =~ /^EXTRACT\z/i ) {
        if ( $sf->{i}{driver} eq 'SQLite' ) {
            my %map = ( YEAR => '%Y', MONTH => '%m', WEEK => '%W', DAY => '%d', HOUR => '%H', MINUTE => '%M', SECOND => '%S',
                        DOY => '%j', DOW => '%w'
            );
            if ( $map{ uc( $arg ) } ) {
                $arg = "'" . $map{ uc( $arg ) } . "'";
            }
            return "strftime($arg,$col)";
        }
        else {
            return "EXTRACT($arg FROM $col)";
        }
    }
    elsif ( $func =~ /^ROUND\z/i ) {
        if ( length $arg ) {
            return "ROUND($col,$arg)";
        }
        else {
            return "ROUND($col)";
        }
    }
    elsif ( $func =~ /^TRUNCATE\z/i ) {
        if ( $sf->{i}{driver} =~ /^(?:Pg|Firebird|Informix|Oracle)\z/ ) {
            return "TRUNC($col,$arg)" if length $arg;
            return "TRUNC($col)";
        }
        else {
            return "TRUNCATE($col,$arg)" if length $arg;
            return "TRUNCATE($col)";
        }
    }
    elsif ( $func =~ /^INSTR\z/i ) {
        my $substring = $sf->{d}{dbh}->quote( $arg );
        return "POSITION($substring IN $col)" if $sf->{i}{driver} =~ /^(?:Pg|Firebird)\z/;
        return "INSTR($col,$substring)";
        # DB2, informix, Oracle: INSTR(string, substring, start, count)
        # Firebird: position(substring, string, start)
    }
    #elsif ( $func =~ /^LEFT\z/i ) {
    #    return "SUBSTR($col,1,$arg)" if $sf->{i}{driver} eq 'SQLite';
    #    return "LEFT($col,$arg)";
    #}
    #elsif ( $func =~ /^RIGHT\z/i ) {
    #    return "SUBSTR($col,-$arg)" if $sf->{i}{driver} eq 'SQLite';
    #    return "RIGHT($col,$arg)";
    #}
    else {
        return "$func($col,$arg)";
    }
}


sub function_with_col_and_2args {
    my ( $sf, $func, $col, $arg1, $arg2 ) = @_;
    my $driver = $sf->{i}{driver};
    if ( $func =~ /^REPLACE\z/i ) {
        my $string_to_replace =  $sf->{d}{dbh}->quote( $arg1 );
        my $replacement_string = $sf->{d}{dbh}->quote( $arg2 );
        return "REPLACE($col,$string_to_replace,$replacement_string)";
    }
    elsif ( $func =~ /^SUBSTR\z/i ) {
        my $startpos = $arg1;
        my $length = $arg2;
        if ( $driver =~ /^(?:SQLite|mysql|MariaDB|Oracle)\z/ ) {
            return "SUBSTR($col,$startpos,$length)" if length $length;
            return "SUBSTR($col,$startpos)";
        }
        else {
            return "SUBSTRING($col FROM $startpos FOR $length)" if length $length;
            return "SUBSTRING($col FROM $startpos)";
        }
    }
    elsif ( $func =~ /^LPAD\z/i ) {
        my $length = $arg1;
        my $fill = $arg2;
        if ( $sf->{i}{driver} eq 'SQLite' ) {
            $fill = ' ' if ! length $fill;
            $fill = $sf->{d}{dbh}->quote( $fill x $length );
            return "SUBSTR($fill||$col,-$length,$length)";
        }
        else {
            return "LPAD($col,$length)" if ! length $fill;
            $fill = $sf->{d}{dbh}->quote( $fill );
            return "LPAD($col,$length,$fill)";
        }
    }
    elsif ( $func =~ /^RPAD\z/i ) {
        my $length = $arg1;
        my $fill = $arg2;
        if ( $sf->{i}{driver} eq 'SQLite' ) {
            $fill = ' ' if ! length $fill;
            $fill = $sf->{d}{dbh}->quote( $fill x $length );
            return "SUBSTR($col||$fill,1,$length)";
        }
        else {
            return "RPAD($col,$length)" if ! length $fill;
            $fill = $sf->{d}{dbh}->quote( $fill );
            return "RPAD($col,$length,$fill)";
        }
    }
    else {
        return "$func($col,$arg1,$arg2)"; # none
    }
}


sub concatenate {
    my ( $sf, $cols, $sep ) = @_;
    my $arg;
    if ( defined $sep && length $sep ) {
        my $qt_sep = $sf->{d}{dbh}->quote( $sep );
        for ( @$cols ) {
            push @$arg, $_, $qt_sep;
        }
        pop @$arg;
    }
    else {
        $arg = $cols
    }
    return "CONCAT(" . join( ',', @$arg ) . ")"  if $sf->{i}{driver} =~ /^(?:mysql|MariaDB)\z/;
    return join( " || ", @$arg );
}


sub coalesce {
    my ( $sf, $cols ) = @_;
    return "COALESCE(" . join( ',', @$cols ) . ")"

}


sub epoch_to_date {
    my ( $sf, $col, $interval ) = @_;
    my $driver = $sf->{i}{driver};
    return "DATE($col/$interval,'unixepoch','localtime')"                                  if $driver eq 'SQLite';
    return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d')"                                      if $driver =~ /^(?:mysql|MariaDB)\z/;
    return "TO_TIMESTAMP(${col}::bigint/$interval)::date"                                  if $driver eq 'Pg';
    return "DATEADD(CAST($col AS BIGINT)/$interval SECOND TO DATE '1970-01-01')"           if $driver eq 'Firebird';
    return "TIMESTAMP('1970-01-01') + ($col/$interval) SECONDS"                            if $driver eq 'DB2';
    return "TO_CHAR(DBINFO('utc_to_datetime',$col/$interval),'%Y-%m-%d')"                  if $driver eq 'Informix';
    return "TO_DATE('1970-01-01','YYYY-MM-DD') + NUMTODSINTERVAL($col/$interval,'SECOND')" if $driver eq 'Oracle';
}


sub epoch_to_datetime {
    my ( $sf, $col, $interval ) = @_;
    my $driver = $sf->{i}{driver};
    if ( $driver eq 'SQLite' ) {
        if ( $interval == 1 ) {
            return "DATETIME($col,'unixepoch','localtime')";
        }
        else {
            return "STRFTIME('%Y-%m-%d %H:%M:%f',$col/$interval.0, 'unixepoch','localtime')";
        }
    }
    elsif ( $driver =~ /^(?:mysql|MariaDB)\z/ ) {
        # mysql: FROM_UNIXTIME doesn't work with negative timestamps
        if ( $interval == 1 ) {
            return "FROM_UNIXTIME($col)";
        }
        elsif ( $interval == 1_000 ) {
            return "FROM_UNIXTIME($col * 0.001)";
        }
        else {
            return "FROM_UNIXTIME($col * 0.000001)";
        }
    }
    elsif ( $driver eq 'Pg' ) {
        if ( $interval == 1 ) {
            return "TO_TIMESTAMP(${col}::bigint)::timestamp"
        }
        elsif ( $interval == 1_000 ) {
            return "TO_CHAR(TO_TIMESTAMP(${col}::bigint/$interval.0) at time zone 'UTC','yyyy-mm-dd hh24:mi:ss.ff3')";
        }
        else {
            return "TO_CHAR(TO_TIMESTAMP(${col}::bigint/$interval.0) at time zone 'UTC','yyyy-mm-dd hh24:mi:ss.ff6')";
        }
    }
    elsif ( $driver eq 'Firebird' ) {
        if ( $interval == 1 ) {
            return "SUBSTRING(CAST(DATEADD(SECOND,CAST($col AS BIGINT),TIMESTAMP '1970-01-01 00:00:00') AS VARCHAR(24)) FROM 1 FOR 19)";
        }
        elsif ( $interval == 1_000 ) {
            $interval /= 1_000;
            return "SUBSTRING(CAST(DATEADD(MILLISECOND,CAST($col AS BIGINT)/$interval,TIMESTAMP '1970-01-01 00:00:00') AS VARCHAR(24)) FROM 1 FOR 23)";
        }
        else {
            $interval /= 1_000;                        # don't remove the ".0"
            return "CAST(DATEADD(MILLISECOND,CAST($col AS BIGINT)/$interval.0,TIMESTAMP '1970-01-01 00:00:00') AS VARCHAR(24))";
        }
    }
    elsif ( $driver eq 'DB2' ) {
        if ( $interval == 1 ) {
            return "TIMESTAMP('1970-01-01 00:00:00',0) + $col SECONDS";
        }
        elsif ( $interval == 1_000 ) {
            return "TIMESTAMP('1970-01-01 00:00:00',3) + ($col/$interval) SECONDS";
        }
        else {
            return "TIMESTAMP('1970-01-01 00:00:00',6) + ($col/$interval) SECONDS";
        }
    }
    elsif ( $driver eq 'Informix' ) {
        return "DBINFO('utc_to_datetime',$col/$interval)";
    }
    elsif ( $driver eq 'Oracle' ) {
        if ( $interval == 1 ) {
            return "TO_CHAR(TO_TIMESTAMP('19700101000000','YYYYMMDDHH24MISS')+NUMTODSINTERVAL($col,'SECOND'),'YYYY-MM-DD HH24:MI:SS')";
        }
        elsif ( $interval == 1_000 ) {
            return "TO_CHAR(TO_TIMESTAMP('19700101000000','YYYYMMDDHH24MISS')+NUMTODSINTERVAL($col/$interval,'SECOND'),'YYYY-MM-DD HH24:MI:SS.FF3')";
        }
        else {
            return "TO_CHAR(TO_TIMESTAMP('19700101000000','YYYYMMDDHH24MISS')+NUMTODSINTERVAL($col/$interval,'SECOND'),'YYYY-MM-DD HH24:MI:SS.FF6')";
        }
    }
}





1;

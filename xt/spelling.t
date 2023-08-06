use 5.010000;
use strict;
use warnings;
use Test::More;

use Test::Spelling;

#set_spell_cmd('aspell list -l en -p /dev/null');
set_spell_cmd('hunspell -l -d en_US');


add_stopwords( <DATA> );

all_pod_files_spelling_ok( 'bin', 'lib' );



__DATA__
AVG
BNRY
Cols
Colwidth
Concat
Ctrl
DB2
Dir
ENV
IFS
Kiem
LTrim
Maths
MERCHANTIBILITY
MSWin32
Matthäus
Multirow
Pg
PrintTable
ProgressBar
RTrim
RaiseError
SGR
SQ
Schemas
Subqueries
Substatements
Tabwidth
Trunc
csv
de
dir
eol
fract
mappable
preselected
preselection
repexp
schemas
sql
stackoverflow
subqueries
subquery
substatement
substatements
utf8

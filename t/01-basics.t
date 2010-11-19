#!perl -Tw

use strict;
use Test::More tests => 8;
use Data::Format::Pretty::Console qw(format_pretty);

{
    local $Data::Format::Pretty::Console::Interactive = 1;

    like(format_pretty("foo"),       qr/foo/, "scalar");
    like(format_pretty([1]),         qr/---/, "list");
    like(format_pretty({a=>1}),      qr/---/, "hash");
    like(format_pretty([[1]]),       qr/---/, "aoa");
    like(format_pretty([{a=>1}]),    qr/---/, "aoh");
    like(format_pretty({a=>[[1]]}),  qr/---/, "hot");
    like(format_pretty({a=>{b=>1}}), qr/b: 1/, "unknown structure");

}

{
    local $Data::Format::Pretty::Console::Interactive = 0;

    like(format_pretty([1,2]),       qr/\A1\n2\n\z/, "list (ni)");
}

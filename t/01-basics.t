#!perl -Tw

use strict;
use Test::More tests => 8;
use Data::Format::Pretty::Console qw(format_pretty);

my @data = (
    {
        data        => undef,
        detect      => "scalar",
        output      => "\n",
    },

    {
        data        => "foo",
        detect      => "scalar",
        output      => "foo\n",
    },

    {
        data        => [],
        detect      => "aoa",
    },

    {
        data        => [ [1,2],[3,4] ],
        detect      => "aoa",
        output_re   => qr/---/,
        ouput_ni    => "1\t2\n3\t4\n",
    },

    {
        data        => [{}],
        detect      => "aoh",
    },

    {
        data        => [{}],
        detect      => "aoh",
    },

);

sub test_dnf { # detect and format
}

{
    local $Data::Format::Pretty::Console::Interactive = 1;


}

{
    local $Data::Format::Pretty::Console::Interactive = 0;

    like(format_pretty([1,2]),       qr/\A1\n2\n\z/, "list (ni)");
}

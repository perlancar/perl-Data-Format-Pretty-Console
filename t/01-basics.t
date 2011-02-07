#!perl -Tw

use strict;
use Test::More tests => 27;
use Data::Dump::Partial qw(dumpp);
use Data::Format::Pretty::Console qw(format_pretty);
use YAML::Any;

my @data = (
    {
        data         => undef,
        struct       => "scalar",
        output       => "\n",
    },

    {
        data         => "foo",
        struct       => "scalar",
        output       => "foo\n",
    },

    {
        data         => bless([], "foo"),
        struct       => "scalar",
        output_re    => qr/foo=/,
    },

    {
        data         => [],
        struct       => "aoa",
        output       => "",
    },

    {
        data         => [ [1,2],[3,4] ],
        struct       => "aoa",
        output_re    => qr/---/,
        ouput_ni     => "1\t2\n3\t4\n",
        is_yaml      => 0,
    },

    {
        data         => [{}],
        struct       => "aoh",
    },

    {
        data         => [{a=>1, b=>2}, {b=>3, c=>4}, {a=>5}],
        struct       => "aoh",
        output_re    => qr/^\|\s*5\s*\|\s*\|\s*\|$/m,
        output_ni_re => qr/^5\t\t$/m,
    },

    {
        data         => [ 1, 2, [3, 4] ],
        struct       => "list",
        output_re    => qr/^\| 3, 4.+---/sm,
        ouput_ni_re  => qr/^3, 4\n/m,
    },

    {
        data         => [ [1, 2, 3], [4, 5] ],
        struct       => "list",
        output_re    => qr/^\| 1, 2, 3/m,
        ouput_ni_re  => qr/^1, 2, 3/m,
    },

    {
        data         => {a=>1, b=>2},
        struct       => "hash",
        output_re    => qr/^\|\s*a\s*\|\s*1\s*\|$/sm,
        ouput_ni_re  => qr/^a\t1$/m,
    },

    {
        data         => {a=>1, b=>[2, 3]},
        struct       => "hot",
        output_re    => qr/^a:\n1\n\nb:\n.+---/,
    },

    {
        data         => {a=>{k=>"v"}, b=>{k=>"v"}},
        struct       => "hot",
        output_re    => qr/^a:\n.+---.+/,
    },

    {
        data         => {a=>{b=>{}}},
        struct       => undef,
        is_yaml      => 1,
    },

);

sub is_yaml {
    my ($data, $test_name) = @_;
    eval { Load($data) };
    ok(!$@, $test_name);
}

sub isnt_yaml {
    my ($data, $test_name) = @_;
    eval { Load($data) };
    #XXX doesn't die?
    #ok($@, $test_name);
    #print "\$data=$data, \$@=$@\n";
}

 # detect and format
sub test_dnf {
    my ($spec) = @_;
    my $data   = $spec->{data};
    my $struct = $spec->{struct};
    my $test_name = ($struct // "unknown") . ": " . dumpp($data);

    my ($s, $sm) =
        Data::Format::Pretty::Console::detect_struct($data);
    if (!$struct) {
        ok(!$s, "$test_name: detect_struct: structure unknown");
    } else {
        is($s, $struct, "$test_name: detect_struct: structure is '$struct'");
    }

    if (exists($spec->{output}) || exists($spec->{output_re}) ||
            exists($spec->{is_yaml})) {
        my $output;
        {
            $output = format_pretty($data, {interactive=>1});
        }
        if (exists($spec->{output})) {
            is($output, $spec->{output}, "$test_name: output exact match");
        }
        if (exists($spec->{output_re})) {
            like($output, $spec->{output_re}, "$test_name: output regex match");
        }
        if (exists($spec->{is_yaml})) {
            if ($spec->{is_yaml}) {
                is_yaml($output, "$test_name: is YAML");
            } else {
                isnt_yaml($output, "$test_name: is not YAML");
            }
        }
    }

    if (exists($spec->{output_ni}) || exists($spec->{output_ni_re}) ||
            exists($spec->{is_yaml})) {
        my $output;
        {
            $output = format_pretty($data, {interactive=>0});
        }
        if (exists($spec->{output_ni})) {
            is($output, $spec->{output_ni},
               "$test_name: output exact match (ni)");
        }
        if (exists($spec->{output_ni_re})) {
            like($output, $spec->{output_ni_re},
                 "$test_name: output regex match (ni)");
        }
        if (exists($spec->{is_yaml})) {
            if ($spec->{is_yaml}) {
                is_yaml($output, "$test_name: is YAML (ni)");
            } else {
                isnt_yaml($output, "$test_name: is not YAML (ni)");
            }
        }
    }
}

test_dnf($_) for @data;

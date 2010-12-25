package Data::Format::Pretty::Console;
# ABSTRACT: Pretty-print data structure for console output

=head1 SYNOPSIS

In your program:

 use Data::Format::Pretty::Console qw(format_pretty);
 ...
 print format_pretty($result);

Some example output:

Scalar, format_pretty("foo"):

 foo

List, format_pretty([qw/foo bar baz qux/]):

 .------.
 | data |
 +------+
 | foo  |
 | bar  |
 | baz  |
 | qux  |
 '------'

The same list, when program output is being piped (that is, (-t STDOUT) is
false):

 foo
 bar
 baz
 qux

Hash, format_pretty({foo=>"data", bar=>"format", baz=>"pretty", qux=>"console"}):

 .---------------.
 | key | value   |
 +-----+---------+
 | bar | format  |
 | baz | pretty  |
 | foo | data    |
 | qux | console |
 '-----+---------'

2-dimensional array, format_pretty([ [1, 2, ""], [28, "bar", 3], ["foo", 3,
undef] ]):

 .-----------------------------.
 | column0 | column1 | column2 |
 +---------+---------+---------+
 |       1 |       2 |         |
 |      28 | bar     |       3 |
 | foo     |       3 |         |
 '---------+---------+---------'

An array of hashrefs, such as commonly found if you use DBI's fetchrow_hashref()
and friends, format_pretty([ {a=>1, b=>2}, {b=>2, c=>3}, {c=>4} ]):

 .-----------.
 | a | b | c |
 +---+---+---+
 | 1 | 2 |   |
 |   | 2 | 3 |
 |   |   | 4 |
 '---+---+---'

Some more complex data, format_pretty({summary => "Blah...", users =>
[{name=>"budi", domains=>["foo.com", "bar.com"], quota=>"1000"}, {name=>"arif",
domains=>["baz.com"], quota=>"2000"}], verified => 0}):

 summary:
 Blah...

 users:
 .---------------------------------.
 | domains          | name | quota |
 +------------------+------+-------+
 | foo.com, bar.com | budi |  1000 |
 | baz.com          | arif |  2000 |
 '------------------+------+-------'

 verified:
 0

Structures which can't be handled yet will simply be output as YAML,
format_pretty({a {b=>1}}):

 ---
 a:
   b: 1


=head1 DESCRIPTION

This module is meant to output data structure in a "pretty" or "nice" format,
suitable for console programs. The idea of this module is that for you to just
merrily dump data structure to the console, and this module will figure out how
to best display your data to the end-user.

Currently this module tries to display the data mostly as a nice ASCII table (or
a series of ASCII tables), and failing that, display it as YAML.

This module takes piping into consideration, and will output a simpler, more
suitable format when your user pipes your program's output into some other
program.

Most of the time, you don't have to configure anything. But in the future some
formatting settings will be tweakable.

=cut

use 5.010;
use strict;
use warnings;

use Text::ASCIITable;
use YAML::Any;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(format_pretty);

our $Interactive;

=head1 FUNCTIONS

=head2 format_pretty($data, %opts)

Return formatted data structure. Currently there is no options.

=cut

sub format_pretty {
    my ($data, $opts) = @_;
    $opts //= {};
    _format($data, $opts);
}

# return a string when data can be represented as a cell, otherwise undef. what
# can be put in a table cell? a string or array of strings that is quite "short".
sub format_cell {
    my ($data) = @_;

    # XXX currently hardcoded limits
    my $maxlen = 1000;

    if (!ref($data)) {
        return "" if !defined($data);
        return if length($data) > $maxlen;
        return $data;
    } elsif (ref($data) eq 'ARRAY') {
        return if grep {ref($_)} @$data;
        my $s = join(", ", map {$_//""} @$data);
        return if length($s)   > $maxlen;
        return $s;
    } else {
        return;
    }
}

sub is_cell { defined(format_cell($_[0])) }

sub detect_struct {
    my ($data, $opts) = @_;
    $opts //= {};
    my $struct;
    my $struct_meta = {};

    # XXX perhaps, use Data::Schema later?
  CHECK_FORMAT:
    {
      CHECK_SCALAR:
        {
            if (!ref($data)) {
                $struct = "scalar";
                last CHECK_FORMAT;
            }
        }

      CHECK_AOA:
        {
            if (ref($data) eq 'ARRAY') {
                my $numcols;
                for my $row (@$data) {
                    last CHECK_AOA unless ref($row) eq 'ARRAY';
                    last CHECK_AOA if defined($numcols) && $numcols != @$row;
                    last CHECK_AOA if grep { !is_cell($_) } @$row;
                    $numcols = @$row;
                }
                $struct = "aoa";
                last CHECK_FORMAT;
            }
        }

      CHECK_AOH:
        {
            if (ref($data) eq 'ARRAY') {
                $struct_meta->{columns} = {};
                for my $row (@$data) {
                    last CHECK_AOH unless ref($row) eq 'HASH';
                    for my $k (keys %$row) {
                        last CHECK_AOH if !is_cell($row->{$k});
                        $struct_meta->{columns}{$k} = 1;
                    }
                }
                $struct = "aoh";
                last CHECK_FORMAT;
            }
        }

        # list of scalars/cells
      CHECK_LIST:
        {
            if (ref($data) eq 'ARRAY') {
                for (@$data) {
                    last CHECK_LIST unless is_cell($_);
                }
                $struct = "list";
                last CHECK_FORMAT;
            }
        }

        # hash which contains at least one "table" (list/aoa/aoh)
      CHECK_HOT:
        {
            last CHECK_HOT if $opts->{skip_hot};
            last CHECK_HOT unless ref($data) eq 'HASH';
            my $has_t;
            while (my ($k, $v) = each %$data) {
                my ($s2, $sm2) = detect_struct($v, {skip_hot=>1});
                last CHECK_HOT unless $s2;
                $has_t = 1 if $s2 =~ /^(?:list|aoa|aoh|hash)$/;
            }
            last CHECK_HOT unless $has_t;
            $struct = "hot";
            last CHECK_FORMAT;
        }

        # hash of scalars/cells
      CHECK_HASH:
        {
            if (ref($data) eq 'HASH') {
                for (values %$data) {
                    last CHECK_HASH unless is_cell($_);
                }
                $struct = "hash";
                last CHECK_FORMAT;
            }
        }

    }

    ($struct, $struct_meta);
}

sub _format {
    my ($data, $opts) = @_;

    my $is_interactive = $Interactive // (-t STDOUT);
    my ($struct, $struct_meta) = detect_struct($data);

    if (!$struct) {

        return Dump($data);

    } elsif ($struct eq 'scalar') {

        return ($data // "") . "\n";

    } elsif ($struct eq 'list') {

        if ($is_interactive) {
            my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
            $t->setCols("data");
            for my $i (0..@$data-1) {
                $t->addRow(format_cell($data->[$i]));
            }
            return "$t"; # stringify
        } else {
            my @rows;
            for my $row (@$data) {
                push @rows, ($row // "") . "\n";
            }
            return join("", @rows);
        }

    } elsif ($struct eq 'hash') {

        if ($is_interactive) {
            # show hash as two-column table
            my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
            $t->setCols("key", "value");
            for my $k (sort keys %$data) {
                $t->addRow($k, format_cell($data->{$k}));
            }
            return "$t"; # stringify
        } else {
            my @t;
            for my $k (sort keys %$data) {
                push @t, $k, "\t", ($data->{$k} // ""), "\n";
            }
            return join("", @t);
        }

    } elsif ($struct eq 'aoa') {

        if ($is_interactive) {
            my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
            $t->setCols(map { "column$_" } 0..@{ $data->[0] }-1);
            for my $i (0..@$data-1) {
                $t->addRow(map {format_cell($_)} @{ $data->[$i] });
            }
            return "$t"; # stringify
        } else {
            # tab-separated
            my @t;
            for my $row (@$data) {
                push @t, join("\t", map { format_cell($_) } @$row) . "\n";
            }
            return join("", @t);
        }

    } elsif ($struct eq 'aoh') {

        my @cols = sort keys %{$struct_meta->{columns}};
        if ($is_interactive) {
            my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
            $t->setCols(@cols);
            for my $i (0..@$data-1) {
                my $row = $data->[$i];
                $t->addRow(map {format_cell($row->{$_})} @cols);
            }
            return "$t"; # stringify
        } else {
            # tab-separated
            my @t;
            for my $row (@$data) {
                my @row = map {format_cell($row->{$_})} @cols;
                push @t, join("\t", @row) . "\n";
            }
            return join("", @t);
        }

    } elsif ($struct eq 'hot') {

        my @t;
        for my $k (sort keys %$data) {
            push @t, "$k:\n", _format($data->{$k}), "\n";
        }
        return join("", @t);

    } else {

        die "BUG: Unknown format `$struct`";

    }
}

=head1 SEE ALSO

Modules used for formatting: L<Text::ASCIITable>, L<YAML>.

=cut

1;

package Data::Format::Pretty::Console;

use 5.010;
use strict;
use warnings;

use Log::Any '$log';
use Scalar::Util qw(blessed);
use Text::ASCIITable;
use YAML::Any;
use JSON;

my $json = JSON->new->allow_nonref;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(format_pretty);

# VERSION

sub content_type { "text/plain" }

sub format_pretty {
    my ($data, $opts) = @_;
    $opts //= {};
    __PACKAGE__->new($opts)->_format($data);
}

# OO interface is nto documented, we use it just to subclass
# Data::Format::Pretty::HTML
sub new {
    my ($class, $opts) = @_;
    $opts //= {};
    $opts->{interactive} //= (-t STDOUT);
    $opts->{table_column_orders} //= $json->decode(
        $ENV{FORMAT_PRETTY_TABLE_COLUMN_ORDERS})
        if defined($ENV{FORMAT_PRETTY_TABLE_COLUMN_ORDERS});
    $opts->{table_column_formats} //= $json->decode(
        $ENV{FORMAT_PRETTY_TABLE_COLUMN_FORMATS})
        if defined($ENV{FORMAT_PRETTY_TABLE_COLUMN_FORMATS});
    bless {opts=>$opts}, $class;
}

sub _is_cell_or_format_cell {
    my ($self, $data, $is_format) = @_;

    # XXX currently hardcoded limits
    my $maxlen = 1000;

    if (!ref($data) || blessed($data)) {
        if (!defined($data)) {
            return "" if $is_format;
            return 1;
        }
        if (length($data) > $maxlen) {
            return;
        }
        return "$data" if $is_format;
        return 1;
    } elsif (ref($data) eq 'ARRAY') {
        if (grep {ref($_) && !blessed($_)} @$data) {
            return;
        }
        my $s = join(", ", map {defined($_) ? "$_":""} @$data);
        if (length($s) > $maxlen) {
            return;
        }
        return $s if $is_format;
        return 1;
    } else {
        return;
    }
}

# return a string when data can be represented as a cell, otherwise undef. what
# can be put in a table cell? a string (or stringified object) or array of
# strings (stringified objects) that is quite "short".
sub _format_cell { _is_cell_or_format_cell(@_, 1) }

sub _is_cell     { _is_cell_or_format_cell(@_, 0) }

sub _detect_struct {
    my ($self, $data) = @_;
    my $struct;
    my $struct_meta = {};

    # XXX perhaps, use Data::Schema later?
  CHECK_FORMAT:
    {
      CHECK_SCALAR:
        {
            if (!ref($data) || blessed($data)) {
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
                    last CHECK_AOA if grep { !$self->_is_cell($_) } @$row;
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
                        last CHECK_AOH if !$self->_is_cell($row->{$k});
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
                    last CHECK_LIST unless $self->_is_cell($_);
                }
                $struct = "list";
                last CHECK_FORMAT;
            }
        }

        # hash which contains at least one "table" (list/aoa/aoh)
      CHECK_HOT:
        {
            last CHECK_HOT if $self->{opts}{skip_hot};
            last CHECK_HOT unless ref($data) eq 'HASH';
            my $has_t;
            while (my ($k, $v) = each %$data) {
                my ($s2, $sm2) = $self->_detect_struct($v, {skip_hot=>1});
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
                    last CHECK_HASH unless $self->_is_cell($_);
                }
                $struct = "hash";
                last CHECK_FORMAT;
            }
        }

    }

    ($struct, $struct_meta);
}

sub _format_table_columns {
    require Data::Unixish::Apply;

    my ($self, $t, $tcf) = @_;

    my $num_rows = @{ $t->{tbl_rows} };
    for my $col (keys %$tcf) {
        my $fmt = $tcf->{$col};
        my $i;
        for (0..@{ $t->{tbl_cols} }-1) {
            do { $i = $_; last } if $col eq $t->{tbl_cols}[$_];
        }
        next unless defined $i; # col not found in table
        # extract column values from table
        my @vals = map { $t->{tbl_rows}[$_][$i] } 0..$num_rows-1;
        my $res = Data::Unixish::Apply::apply(in => \@vals, functions => $fmt);
        unless ($res->[0] == 200) {
            $log->warnf("Can't format column %s with %s, skipped", $col, $fmt);
            next;
        }
        # inject back column values into table
        @vals = @{ $res->[2] };
        for (0..@vals-1) { $t->{tbl_rows}[$_][$i] = $vals[$_] }
    }
}

sub _render_table {
    my ($self, $t) = @_;

    my $colfmts;

    # does table match this setting?
    my $tcff = $self->{opts}{table_column_formats};
    if ($tcff) {
        for my $tcf (@$tcff) {
            my $match = 1;
            my @tcols = @{ $t->{tbl_cols} };
            for my $scol (keys %$tcf) {
                do { $match = 0; last } unless $scol ~~ @tcols;
            }
            if ($match) {
                $colfmts = $tcf;
                last;
            }
        }
    }

    # if not, pick some defaults (e.g. date)
    unless ($colfmts) {
        $colfmts = {};
        for (@{ $t->{tbl_cols} }) {
            if (/(?:[^A-Za-z]|\A)date(?:[^A-Za-z]|\z)/) {
                $colfmts->{$_} = 'date';
            }
        }
        $colfmts = undef unless keys %$colfmts;
    }

    $self->_format_table_columns($t, $colfmts) if $colfmts;
    "$t";
}

# format unknown structure, the default is to dump YAML structure
sub _format_unknown {
    my ($self, $data) = @_;
    Dump($data);
}

sub _format_scalar {
    my ($self, $data) = @_;

    my $sdata = defined($data) ? "$data" : "";
    return $sdata =~ /\n\z/s ? $sdata : "$sdata\n";
}

sub _format_list {
    my ($self, $data) = @_;
    # format list as as one-column table, elements as rows
    if ($self->{opts}{interactive}) {
        my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
        $t->setCols("data");
        for my $i (0..@$data-1) {
            $t->addRow($self->_format_cell($data->[$i]));
        }
        $t->setOptions({hide_HeadRow=>1, hide_HeadLine=>1});
        return $self->_render_table($t);
    } else {
        my @rows;
        for my $row (@$data) {
            push @rows, ($row // "") . "\n";
        }
        return join("", @rows);
    }
}

sub _format_hash {
    my ($self, $data) = @_;
    # format hash as two-column table
    if ($self->{opts}{interactive}) {
        my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
        $t->setCols("key", "value");
        for my $k (sort keys %$data) {
            $t->addRow($k, $self->_format_cell($data->{$k}));
        }
        $t->setOptions({hide_HeadRow=>1, hide_HeadLine=>1});
        return $self->_render_table($t);
    } else {
        my @t;
        for my $k (sort keys %$data) {
            push @t, $k, "\t", ($data->{$k} // ""), "\n";
        }
        return join("", @t);
    }
}

sub _format_aoa {
    my ($self, $data) = @_;
    # show aoa as table
    if ($self->{opts}{interactive}) {
        if (@$data) {
            my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
            $t->setCols(map { "column$_" } 0..@{ $data->[0] }-1);
            for my $i (0..@$data-1) {
                $t->addRow(map {$self->_format_cell($_)} @{ $data->[$i] });
            }
            $t->setOptions({hide_HeadRow=>1, hide_HeadLine=>1});
            return $self->_render_table($t);
        } else {
            return "";
        }
    } else {
        # tab-separated
        my @t;
        for my $row (@$data) {
            push @t, join("\t", map { $self->_format_cell($_) } @$row) .
                "\n";
        }
        return join("", @t);
    }
}

sub _format_aoh {
    my ($self, $data, $struct_meta) = @_;
    # show aoh as table
    my @cols = @{ $self->_order_table_columns(
        [keys %{$struct_meta->{columns}}]) };
    if ($self->{opts}{interactive}) {
        my $t = Text::ASCIITable->new(); #{headingText => 'blah'}
        $t->setCols(@cols);
        for my $i (0..@$data-1) {
            my $row = $data->[$i];
            $t->addRow(map {$self->_format_cell($row->{$_})} @cols);
        }
        return $self->_render_table($t);
    } else {
        # tab-separated
        my @t;
        for my $row (@$data) {
            my @row = map {$self->_format_cell($row->{$_})} @cols;
            push @t, join("\t", @row) . "\n";
        }
        return join("", @t);
    }
}

sub _format_hot {
    my ($self, $data) = @_;
    # show hot as paragraphs:
    #
    # key:
    # value (table)
    #
    # key2:
    # value ...
    my @t;
    for my $k (sort keys %$data) {
        push @t, "$k:\n", $self->_format($data->{$k}), "\n";
    }
    return join("", @t);
}

sub _format {
    my ($self, $data) = @_;

    my ($struct, $struct_meta) = $self->_detect_struct($data);

    if (!$struct) {
        return $self->_format_unknown($data, $struct_meta);
    } elsif ($struct eq 'scalar') {
        return $self->_format_scalar($data, $struct_meta);
    } elsif ($struct eq 'list') {
        return $self->_format_list($data, $struct_meta);
    } elsif ($struct eq 'hash') {
        return $self->_format_hash($data, $struct_meta);
    } elsif ($struct eq 'aoa') {
        return $self->_format_aoa($data, $struct_meta);
    } elsif ($struct eq 'aoh') {
        return $self->_format_aoh($data, $struct_meta);
    } elsif ($struct eq 'hot') {
        return $self->_format_hot($data, $struct_meta);
    } else {
        die "BUG: Unknown format `$struct`";
    }
}

sub _order_table_columns {
    #$log->tracef('=> _order_table_columns(%s)', \@_);
    my ($self, $cols) = @_;

    my $found; # whether we found an ordering in table_column_orders
    my $tco = $self->{opts}{table_column_orders};
    my %orders; # colname => idx
    if ($tco) {
        die "table_column_orders should be an arrayref"
            unless ref($tco) eq 'ARRAY';
      CO:
        for my $co (@$tco) {
            die "table_column_orders elements must all be arrayrefs"
                unless ref($co) eq 'ARRAY';
            for (@$co) {
                next CO unless $_ ~~ @$cols;
            }

            $found++;
            for (my $i=0; $i<@$co; $i++) {
                $orders{$co->[$i]} = $i;
            }
            $found++;
            last CO;
        }
    }

    my @ocols;
    if ($found) {
        @ocols = sort {
            (defined($orders{$a}) && defined($orders{$b}) ?
                 $orders{$a} <=> $orders{$b} : 0)
                || $a cmp $b
        } @$cols;
    } else {
        @ocols = sort @$cols;
    }

    \@ocols;
}

1;
# ABSTRACT: Pretty-print data structure for console output
__END__

=head1 SYNOPSIS

In your program:

 use Data::Format::Pretty::Console qw(format_pretty);
 ...
 print format_pretty($result);

Some example output:

Scalar, format_pretty("foo"):

 foo

List, format_pretty([qw/foo bar baz qux/]):

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

Hash, format_pretty({foo=>"data",bar=>"format",baz=>"pretty",qux=>"console"}):

 +-----+---------+
 | bar | format  |
 | baz | pretty  |
 | foo | data    |
 | qux | console |
 '-----+---------'

2-dimensional array, format_pretty([ [1, 2, ""], [28, "bar", 3], ["foo", 3,
undef] ]):

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

Most of the time, you don't have to configure anything, but some options are
provided to tweak the output.

This module uses L<Log::Any> for logging.


=head1 FUNCTIONS

=for Pod::Coverage new

=head2 format_pretty($data, \%opts)

Return formatted data structure. Options:

=over 4

=item * interactive => BOOL (optional, default undef)

If set, will override interactive terminal detection (-t STDOUT). Simpler
formatting will be done if terminal is non-interactive (e.g. when output is
piped). Using this option will force simpler/full formatting.

=item * table_column_orders => [[COLNAME1, COLNAME2], ...]

Specify column orders when drawing a table. If a table has all the columns, then
the column names will be ordered according to the specification. For example,
when table_column_orders is [[qw/foo bar baz/]], this table's columns will not
be reordered because it doesn't have all the mentioned columns:

 |foo|quux|

But this table will:

 |apple|bar|baz|foo|quux|

into:

 |apple|foo|bar|baz|quux|

=back

=item * table_column_formats => [{COLNAME=>FMT, ...}, ...]

Specify formats for columns. Each table format specification is a hashref
{COLNAME=>FMT, COLNAME2=>FMT2, ...}. It will be applied to a table if the table
has all the columns. FMT is a format specification according to
L<Data::Unixish::Apply>, it's basically either a name of a dux function (e.g.
'date') or an array of function name + arguments (e.g. ['date', [align =>
{align=>'middle'}]].

=back


=head1 ENVIRONMENT

=over 4

=item * FORMAT_PRETTY_TABLE_COLUMN_FORMATS

To set table_column_formats, interpreted as JSON.

=item * FORMAT_PRETTY_TABLE_COLUMN_ORDERS

To set table_column_orders, interpreted as JSON.

=back


=head1 SEE ALSO

Modules used for formatting: L<Text::ASCIITable>, L<YAML>.

L<Data::Format::Pretty>

=cut

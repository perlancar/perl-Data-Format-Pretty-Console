package Data::Format::Pretty::SimpleText;

use 5.010;
use strict;
use warnings;

use Data::Format::Pretty::Console ();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(format_pretty);

# VERSION

sub content_type { "text/plain" }

sub format_pretty {
    my ($data, $opts) = @_;
    my %opts = $opts ? %$opts : ();
    $opts{interactive} = 0;
    Data::Format::Pretty::Console::format_pretty($data, \%opts);
}

1;
# ABSTRACT: Pretty-print data structure as simple text

=for Pod::Coverage ^(content_type)$

=head1 SYNOPSIS

In your program:

 use Data::Format::Pretty::SimpleText qw(format_pretty);
 print format_pretty($data);

Some example output:

=over 4

=item * format_pretty([qw/foo bar baz qux/])

 foo
 bar
 baz
 qux

=back


=head1 DESCRIPTION

This module just calls L<Data::Format::Pretty::Console::format_pretty> with
C<interactive>=0 option.


=head1 FUNCTIONS

=head2 format_pretty($data, \%opts)

Return formatted data structure. See L<Data::Format::Pretty::Console> for
details.


=head1 SEE ALSO

L<Data::Format::Pretty::Console>

=cut

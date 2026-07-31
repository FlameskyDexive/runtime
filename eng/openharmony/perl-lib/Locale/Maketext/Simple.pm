package Locale::Maketext::Simple;

use strict;
use Exporter 'import';
our @ISA = ('Exporter');

our @EXPORT = qw(loc);

sub import {
    my ($class, %options) = @_;
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::loc"} = \&loc;
}

sub loc {
    my ($message, @arguments) = @_;
    for my $index (0 .. $#arguments) {
        my $placeholder = '%' . ($index + 1);
        $message =~ s/\Q$placeholder\E/$arguments[$index]/g;
    }
    return $message;
}

1;

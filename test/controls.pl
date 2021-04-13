#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper qw(Dumper);
use File::Basename;

my $dirname = dirname(__FILE__);

sub controls_parse($) {
    my ($fname) = @_;

    open(my $fh, "<", $fname) or die;

    my $ra = [];

    while (my $line = <$fh>)  {
        chomp($line);
        my @r = split(/ /, $line);
        push(@$ra, \@r);
    }

    close($fh);
    return $ra;

}

my @mod_dirs = ("$dirname/../modules/tronferno/controls_tronferno.txt",
                "$dirname/../modules/sduino/controls_fernotron.txt");

foreach my $fn (@mod_dirs) {
    my $ra = controls_parse($fn);
    my $dir = dirname($fn);

    foreach my $r (@$ra) {
        my $fn = $dir . "/" . $$r[3];
        my $fs = $$r[2];
        my $afs = -s $fn;

        $afs == $fs or die "Filesize for <$fn> was $afs (expected $fs)";
    }
}

#!/usr/bin/perl

use File::Basename;
use POSIX qw(strftime);
use strict;

my @filenames = ('00_TronfernoMCU.pm', '10_Tronferno.pm');

my $prefix = "FHEM";
my $filename = "";
foreach $filename (@filenames)
{
  my @statOutput = stat($prefix."/".$filename);
  
  if (scalar @statOutput != 13)
  {
    printf("error: stat has unexpected return value for ".$prefix."/".$filename."\n");
    next;
  }

  my $mtime = $statOutput[9];
  my $date = POSIX::strftime("%Y-%m-%d", localtime($mtime));
  my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
  my $filetime = $date."_".$time;

  my $filesize = $statOutput[7];

  printf("UPD ".$filetime." ".$filesize." ".$prefix."/".$filename."\n");
}



# Local Variables:
# compile-command: "perl -cw -MO=Lint ./make_controlfile.pl"
# End:

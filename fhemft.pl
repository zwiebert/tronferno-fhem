#!/usr/bin/perl -w    
#  experimental code
#  TODO: maybe store toggle counter in environment variable
#

use Getopt::Long;
use File::Tail;    # apt install libfile-tail-perl
use File::Basename;
use lib dirname(__FILE__);

use tronferno;

my $opt_a          = 0;
my $opt_g          = 0;
my $opt_m          = 0;
my $opt_c          = "";
my $opt_scan_log   = 0;
my $opt_sd_verbose = -1;
my $opt_send       = 0;
my $opt_help       = 0;
my $logfile        = "";
my $opt_n          = "sduino";

GetOptions(
  "n=s"  => \$opt_n,
  "a=s"  => \$opt_a,
  "g=i"  => \$opt_g,
  "m=i"  => \$opt_m,
  "c=s"  => \$opt_c,
  "scan" => \$opt_scan_log,
  "f=s"  => \$logfile,
  "v=i"  => \$opt_sd_verbose,
  "send" => \$opt_send,
  "h"    => \$opt_help,
  "help" => \$opt_help,
) or die("Error in command line arguments\n");

sub print_help() {
  print "Usage:  fhemft.pl command [options ...]

commands: --scan, --send, --help

  --send            build and send a Fernotron command-message via FHEM
   -a=ID            ferntron ID (hex number), e.g. the ID of the 2411 main controller unit
   -g=N             group number 1 ... 7,  or 0 for send to all groups
   -m=N             member number 1 ... 7.  or 0 for send to all members
   -c=string        command string: up, down, stop, sun-down, sun-inst, set

   -n=string        name of SIGNALduino in FHEM (default: sduino)

  --scan            scan the current FHEM logfile for received Fernotron commands
    -f FILE         use this fhem log file insted of default
    -v=N            set verbose level of SIGNALduino. Must be at least level 4 to make it work.
"
}

if ($opt_help eq 1) {
  print_help();
  exit;
}

#
# read device ID from live fhem logfile and print it
#
# TODO: setting SIGNALduino verbose level from code
#

## read data from fhem logfile
#
if ($opt_scan_log eq 1) {

  # find current logfile name
  if ($logfile eq "") {
    my @lt    = localtime();
    my $month = $lt[4] + 1;
    my $year  = $lt[5] + 1900;
    $logfile = "/opt/fhem/log/fhem-$year-$month.log";
  }

  # change SIGNALduino verbose level
  if ($opt_sd_verbose ne -1) {
    my $sd_cmd  = "attr $opt_n verbose $opt_sd_verbose";
    my $sys_cmd = "$tronferno::fhem_system '$sd_cmd'";
    print "$sys_cmd\n";
    system $sys_cmd;
  }

  # open logfile tail
  $file = File::Tail->new(name => $logfile, maxinterval => 1, tail => 0);

  print "Now press a button on your Fernotron controller device! Press Ctrl-C if you are done\n";

  while (defined(my $line = $file->read)) {
    if ($line =~ /sduino\/msg READ:\s+\x02(M[US];.+)\x03/) {
      my @bytes = tronferno::rx_sd2bytes($line);

      if ($#bytes >= 4) {

        printf(
          "id=%6x, tgl=%d, memb=%d, grp=%d, cmd=%d,  \n",
          tronferno::rx_get_devID(@bytes),
          tronferno::rx_get_ferTgl(@bytes),
          (tronferno::rx_get_ferMemb(@bytes) == 0 ? 0 : (tronferno::rx_get_ferMemb(@bytes) - 7)),
          tronferno::rx_get_ferGrp(@bytes),
          tronferno::rx_get_ferCmd(@bytes)
        );

      }

    }

  }
}

###send commands to fhem
#
if ($opt_send eq 1) {

  my %args = (
    'command' => 'send',
    'a'       => hex("$opt_a"),
    'g'       => int($opt_g),     # group number
    'm'       => int($opt_m),     # number in group
    'c'       => "$opt_c",        # command: up, down, stop ... (defined in %map_fcmd)
  );

  my $fsb = tronferno::args2cmd(\%args);
  if ($fsb != -1) {
    print "generated fernotron command message: " . tronferno::fsb2string($fsb) . "\n";

    my $tx_data = tronferno::cmd2dString($fsb);
    my $tx_cmd  = "set $opt_n raw $tronferno::p_string$tx_data";
    my $sys_cmd = "$tronferno::fhem_system '$tx_cmd'";

    print "generated FHEM system command: $sys_cmd\n";

    print "now send the command to fhem\n";
    system $sys_cmd;
  }
}

# Local Variables:
# compile-command: "perl -w fhemft.pl"
# End:

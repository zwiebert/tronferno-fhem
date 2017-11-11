#!/usr/bin/perl -w
#  experimental code
#  
#

use Getopt::Long;
use File::Tail; # apt install libfile-tail-perl
use File::Basename;
use lib dirname (__FILE__);

use tronferno;


my $opt_a = 0;
my $opt_g = 0;
my $opt_m = 0;
my $opt_c = "";
my $opt_scan_log = 0;
my $opt_sd_verbose = -1;
my $opt_send = 0;
my $opt_help = 0;
my $logfile = "";
my $opt_n = "sduino";

GetOptions (
            "n=s"   => \$opt_n, 
	    "a=s"   => \$opt_a,    
	    "g=i"   => \$opt_g,    
	    "m=i"   => \$opt_m,
	    "c=s"  => \$opt_c,
	    "scan"  => \$opt_scan_log,
            "f=s" => \$logfile,
            "v=i" => \$opt_sd_verbose, 
	    "send"   => \$opt_send,
	    "h"  => \$opt_help,    
	    "help"  => \$opt_help,    
    )
    or die("Error in command line arguments\n");




sub print_help() {
    print
	"Usage:  fhemft.pl command [options ...]

commands: --scan, --send, --help

  --send            build and send a Fernotron command-message via FHEM
   -a=ID            ferntron ID (hex number), e.g. the ID of the 2411 main controller unit
   -g=N             group number 1 ... 7,  or 0 for send to all groups
   -m=N             member number 1 ... 7.  or 0 for send to all members
   -c=string        command string: up, down, stop, sun-down, sun-inst, set

   -n=string        name of SIGNALduino in FHEM (default: sduino)

  --scan            scan the current FHEM logfile for received Fernotron commands
    -f FILE         use this fhem log file insted of default
    -v=N            set verbose level of SIGNALduino (must be at least 4 to receive commands)
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

if ($logfile eq "") {
my @lt =  localtime();
my $month = $lt[4] + 1;
my $year = $lt[5] + 1900;
$logfile = "/opt/fhem/log/fhem-$year-$month.log";
}

if ($opt_sd_verbose ne -1) {
    my $sd_cmd = "attr $opt_n verbose $opt_sd_verbose";
    my $sys_cmd = "$tronferno::fhem_system '$sd_cmd'";
    print "$sys_cmd\n";
    system $sys_cmd;
}
    
$file=File::Tail->new(name=>$logfile, maxinterval=>1,  tail=> 0);

print "Now press a button on your Fernotron controller device! Press Ctrl-C if you are done\n";

    
while (defined(my $line=$file->read)) {
    if ($line =~ /sduino\/msg READ:\s+\x02(M[US];.+)\x03/) {
	#print "$1\n";
        my $devID = tronferno::rx_get_devID($1);
	if ($devID > 0) {
	    printf("fernotron-device-id=%x (hex)\n", $devID);
	}
    }
    
}
}

###send commands to fhem
#
if ($opt_send eq 1) {

my %args = (
    'command' => 'send',
    'a' => hex("$opt_a"),
    'g' => $opt_g + 0,    # group number
    'm' => $opt_m + 0,    # number in group
    'c' => $opt_c,        # command: up, down, stop ... (defined in %map_fcmd)
    );


my $fsb = tronferno::args2cmd(\%args);
if ($fsb != -1) {
    print "generated fernotron command: " . tronferno::fsb2string($fsb) . "\n";

    my $tx_data = tronferno::cmd2dString($fsb);
    my $tx_cmd = "set $opt_n raw $tronferno::p_string$tx_data";
    my $sys_cmd = "$tronferno::fhem_system '$tx_cmd'";

    print "generated FHEM system command: $sys_cmd\n";

    print "now send the command to fhem\n";
     system $sys_cmd; ## <<<----------------------------------------------
}


}

printf "$opt_scan_log a=%s g=%d m=%d\n", $opt_a, $opt_g, $opt_m;

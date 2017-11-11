#  experimental code
#  
#


use File::Tail; # apt install libfile-tail-perl
use File::Basename;
use lib dirname (__FILE__);

use tronferno;



#
# read device ID from live fhem logfile and print it
#
# TODO: setting SIGNALduino verbose level from code
#
my @lt =  localtime();
my $month = $lt[4] + 1;
my $year = $lt[5] + 1900;
my $logfile = "/opt/fhem/log/fhem-$year-$month.log";



$file=File::Tail->new(name=>$logfile, maxinterval=>1, adjustafter=>7, tail=>C0);

print "Now press a button on your Fernotron controller device!\n";
    
while (defined(my $line=$file->read)) {
    if ($line =~ /sduino\/msg READ:\s+\x02(M[US];.+)\x03/) {
	#print "$1\n";
        my $devID = tronferno::rx_get_devID($1);
	if ($devID > 0) {
	    printf("fernotron-device-id=%x (hex)\n", $devID);
	}
    }
    
}

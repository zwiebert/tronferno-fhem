################################################################################
## *experimental* FHEM I/O device module for Tronferno-MCU hardware
##
##
##  - file: /opt/fhem/FHEM/00_TronfernoMCU.pm
################################################################################
## Author: Bert Winkelmann <tf.zwiebert@online.de>
## Project: https://github.com/zwiebert/tronferno-fhem
################################################################################


use DevIo;
use strict;
use warnings;
use 5.14.0;

package TronfernoMCU {

    my $def_mcuaddr = 'fernotron.fritz.box.';
    my $mcu_port = 7777;
    my $mcu_baud = 115200;

# called when a new definition is created (by hand or from configuration read on FHEM startup)
sub TronfernoMCU_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];
  
  # $a[1] is always equals the module name "MY_MODULE"
  
  # first argument is the hostname or IP address of the device (e.g. "192.168.1.120")
  my $dev = $a[2];
  
  $dev = $def_mcuaddr unless($dev); # FIXME: remove this line

  return "no device given" unless($dev);

  #append default baudrate / portnumber
  if (index($dev, '/dev/') == 0) {
      #serial device
      $dev .= '@' . "$mcu_baud" if (index($dev, '@') < 0);
  } else {
      #TCP/IP connection
      $dev .= ":$mcu_port" if(index($dev, ':') < 0);
  }
 
  
  $hash->{DeviceName} = $dev;
  
  # close connection if maybe open (on definition modify)
  main::DevIo_CloseDev($hash) if(main::DevIo_IsOpen($hash));  
  
  # open connection with custom init and error callback function (non-blocking connection establishment)
  main::DevIo_OpenDev($hash, 0, "TronfernoMCU::TronfernoMCU_Init", "TronfernoMCU::TronfernoMCU_Callback"); 
 
  return undef;
}

# called when definition is undefined 
# (config reload, shutdown or delete of definition)
sub TronfernoMCU_Undef($$)
{
  my ($hash, $name) = @_;
 
  # close the connection 
  main::DevIo_CloseDev($hash);
  
  return undef;
}

# called repeatedly if device disappeared
sub TronfernoMCU_Ready($)
{
  my ($hash) = @_;
  
  # try to reopen the connection in case the connection is lost
  return main::DevIo_OpenDev($hash, 1, "TronfernoMCU::TronfernoMCU_Init", "TronfernoMCU::TronfernoMCU_Callback"); 
}

# called when data was received
sub TronfernoMCU_Read($$)
{
  # if DevIo_Expect() returns something we call this function with an additional argument
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  # read the available data (or don't if called from TronfernoMCU_Set)
  $data = main::DevIo_SimpleRead($hash) unless (defined($data));
  # stop processing if no data is available (device disconnected)
  return if(!defined($data));

  my $buf = $hash->{PARTIAL} . $data;
  
  main::Log3 $name, 5, "TronfernoMCU ($name) - received data: >>>$data<<<"; 

  my $remain = '';
  foreach my $line (split(/^/m, $buf)) {
      if (index($line, "\n") < 0) {
	  $remain = $line;
	  last;
      }

      $line =~ tr/\r\n//d;

      main::Log3 $name, 4, "TronfernoMCU ($name) - received line: >>>>>$line<<<<<"; 

      if ($line =~ /^U:position:\s*(.+);$/) {
	  main::Log3 $name, 3, "TronfernoMCU ($name): position_update: $1";
	  main::Dispatch($hash, "TFMCU#$line");
      }
  }

  $hash->{PARTIAL} = $remain;
}

# called if set command is executed
sub TronfernoMCU_Set($$@)
{
    my ($hash, $name, $cmd) = @_;
    
    my $usage = "unknown argument $cmd, choose one of statusRequest:noArg on:noArg off:noArg";
    $usage = "unknown argument $cmd";

    if($cmd eq "statusRequest")
    {
         #main::DevIo_SimpleWrite($hash, "get_status\r\n", 2);
    }
    elsif($cmd eq "on")
    {
         #main::DevIo_SimpleWrite($hash, "on\r\n", 2);
    }
    elsif($cmd eq "off")
    {
         #main::DevIo_SimpleWrite($hash, "off\r\n", 2);
    }
    else
    {
        return $usage;
    }
}
    
# will be executed upon successful connection establishment (see main::DevIo_OpenDev())
sub TronfernoMCU_Init($)
{
    my ($hash) = @_;

    # send a status request to the device
    main::DevIo_SimpleWrite($hash, "mcu cs=?;\n", 2);  #FIXME: need better cli option for this
    
    return undef; 
}

# will be executed if connection establishment fails (see main::DevIo_OpenDev())
sub TronfernoMCU_Callback($)
{
    my ($hash, $error) = @_;
    my $name = $hash->{NAME};

    # create a log emtry with the error message
    main::Log3 $name, 5, "TronfernoMCU ($name) - error while connecting: $error" if ($error); 
    
    return undef; 
}

sub TronfernoMCU_Write ($$)
{
	my ( $hash, $addr, $msg) = @_;
	my $name = $hash->{NAME};

	main::Log3 $name, 5, "TronfernoMCU ($name) _Write(): $addr: $msg";
	main::DevIo_SimpleWrite($hash, $msg, 2, 1);
	return undef;
}
    
}

package main {
    sub TronfernoMCU_Initialize($) {
        my ($hash) = @_;

        $hash->{SetFn}    = 'TronfernoMCU::TronfernoMCU_Set';
        $hash->{DefFn} = 'TronfernoMCU::TronfernoMCU_Define';
        $hash->{ReadFn} = 'TronfernoMCU::TronfernoMCU_Read';
        $hash->{ReadyFn} = 'TronfernoMCU::TronfernoMCU_Ready';
        $hash->{WriteFn} = 'TronfernoMCU::TronfernoMCU_Write';
        $hash->{UndefFn} = 'TronfernoMCU::TronfernoMCU_Undef';

	$hash->{Clients} = 'Tronferno';
	$hash->{MatchList} = { '1:Tronferno' => '^TFMCU#.+' };
    }
}

1;

=pod
=item device
=item summary I/O device which communicates with Tronferno-MCU
=item summary_DE E/A Gerät welches mit Tronferno-MCU kommuniziert

=begin html

<a name="TronfernoMCU"></a>

<h3>TronfernoMCU</h3>

<i>TronfernoMCU</i> is a physical module to talk to <i>Tronferno-MCU</i> via USB or TCP/IP using FHEM's DevIo mechanism.
<br>
<br>
<br>     Examples:
<br>
<br> 1) MCU module is connected via TCP/IP
<br>
<br>    define tfmcu TronfernoMCU  192.168.1.123
<br>    define shutter_11 Tronferno g=1 m=1
<br>    define shutter_12 Tronferno g=1 m=2
<br>     ..
<br>    define shutter_77 Tronferno g=7 m=7
<br>
<br> 2) MCU module is connected via USB port /dev/ttyUSB1
<br>
<br>    define tfmcu TronfernoMCU /dev/ttyUSB1
<br>    define shutter_11 Tronferno g=1 m=1
<br>    define shutter_12 Tronferno g=1 m=2
<br>     ..
<br>    define shutter_77 Tronferno g=7 m=7
<br>
<br>  ### Make sure the I/O device tfmcu is defined before any shutter_xx device ###
<br>  ### Otherwise the shutter_xx devices can't find their I/O device (because its not defined yet) ###

=end html

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./00_TronfernoMCU.pm"
# End:


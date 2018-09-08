#############################################
## experimental FHEM I/O device module for Tronferno-MCU hardware
#
#  Author:  Bert Winkelmann <tf.zwiebert@online.de>
#
# - copy or softlink file 00_TronfernoMCU.pm to /opt/fhem/FHEM/00_TronfernoMCU.pm
# - copy or softlink this file to /opt/fhem/FHEM/10_Tronferno.pm
# - do 'reload 00_TronfernoMCU' and 'reload 10_Tronferno'
#
#     Example:
#
#    define tfmcu TronfernoMCU  192.168.1.123
#    define roll_11 Tronferno g=1 m=1
#    define roll_12 Tronferno g=1 m=2
#    define roll_13 Tronferno g=1 m=3
#    define roll_14 Tronferno g=1 m=4
#     ..
#    define roll_77 Tronferno g=7 m=7
#
#  ### Make sure the I/O device tfmcu is defined before any roll_xx device ###
#  ### Otherwise the roll_xx devices can't find their I/O device (because its not defined yet) ###
#
#
# TODO
# - ...


use DevIo; # load DevIo.pm if not already loaded
use strict;
use warnings;
use 5.14.0;

package TronfernoMCU {

    my $def_mcuaddr = 'fernotron.fritz.box.';
    my $mcu_port = '7777';



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
  
  # add a default port, if not explicitly given by user
  $dev .= ":$mcu_port" if(not $dev =~ m/:\d+$/);
  
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
sub TronfernoMCU_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  # read the available data
  my $buf = main::DevIo_SimpleRead($hash);
  
  # stop processing if no data is available (device disconnected)
  return if(!defined($buf));
  
  main::Log3 $name, 5, "TronfernoMCU ($name) - received: $buf"; 

  foreach my $line (split(/^/m, $buf)) {
      if ($line =~ /^U:position:\s*(.+);$/) {
	  main::Log3 $name, 4, "TronfernoMCU ($name): position_update: $1";
	  main::Dispatch($hash, "TFMCU#$line");
      }
  }
  #
  # do something with $buf, e.g. generate readings, send answers via main::DevIo_SimpleWrite(), ...
  #
   
}

# called if set command is executed
sub TronfernoMCU_Set($$@)
{
    my ($hash, $name, $cmd) = @_;
    
    my $usage = "unknown argument $cmd, choose one of statusRequest:noArg on:noArg off:noArg";

    if($cmd eq "statusRequest")
    {
         main::DevIo_SimpleWrite($hash, "get_status\r\n", 2);
    }
    elsif($cmd eq "on")
    {
         main::DevIo_SimpleWrite($hash, "on\r\n", 2);
    }
    elsif($cmd eq "off")
    {
         main::DevIo_SimpleWrite($hash, "off\r\n", 2);
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
    main::DevIo_SimpleWrite($hash, "get_status\r\n", 2);
    
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
	my ( $hash, $message, $address) = @_;
     my $name = $hash->{NAME};

	main::Log3 $name, 5, "TronfernoMCU ($name): $message: $address";	

	main::DevIo_SimpleWrite($hash, $address, 2);

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
#        $hash->{ShutdownFn} = 'TronfernoMCU::TronfernoMCU_Shutdown';

	#        $hash->{AttrList} = '';

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

<i>TronfernoMCU</i> is a physical module to talk to <i>Tronferno-MCU</i> via TCP/IP using FHEM's DevIo mechanism.

<br>#
<br># - copy or softlink file 00_TronfernoMCU.pm to /opt/fhem/FHEM/00_TronfernoMCU.pm
<br># - copy or softlink this file to /opt/fhem/FHEM/10_Tronferno.pm
<br># - do 'reload 00_TronfernoMCU' and 'reload 10_Tronferno'
<br>#
<br>#     Example:
<br>#
<br>#    define tfmcu TronfernoMCU  192.168.1.123
<br>#    define roll_11 Tronferno g=1 m=1
<br>#    define roll_12 Tronferno g=1 m=2
<br>#    define roll_13 Tronferno g=1 m=3
<br>#    define roll_14 Tronferno g=1 m=4
<br>#     ..
<br>#    define roll_77 Tronferno g=7 m=7
<br>#
<br>#  ### Make sure the I/O device tfmcu is defined before any roll_xx device ###
<br>#  ### Otherwise the roll_xx devices can't find their I/O device (because its not defined yet) ###
<br>#
<br>#

=end html

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./00_TronfernoMCU.pm"
# End:





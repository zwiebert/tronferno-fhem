################################################################################
## *experimental* FHEM I/O device module for Tronferno-MCU hardware
##
##
##  - file: /opt/fhem/FHEM/00_TronfernoMCU.pm
################################################################################
## Author: Bert Winkelmann <tf.zwiebert@online.de>
## Project: https://github.com/zwiebert/tronferno-fhem
## Related Hardware-Project: https://github.com/zwiebert/tronferno-mcu
################################################################################


use DevIo;
use strict;
use warnings;
use 5.14.0;

package TronfernoMCU {

    my $def_mcuaddr = 'fernotron.fritz.box.';
    my $mcu_port = 7777;
    my $mcu_baud = 115200;

my $mcfg_prefix = 'mcu-config.';
my $mco = {
    MCFG_CU => 'cu',
    MCFG_RTC => 'rtc',
    MCFG_BAUD => 'baud',
    MCFG_WLAN_SSID => 'wlan-ssid',
    MCFG_WLAN_PASSWD => 'wlan-password',
    MCFG_LONGITUDE => 'longitude',
    MCFG_LATITUDE => 'latitude',
    MCFG_TZ => 'tz',
    MCFG_VERBOSE => 'verbose',
    MCFG_RESTART => 'restart',
};
    
my $mcof = {};
my $mcor = {};
my $usage = '';

    while(my($k, $v) = each %$mco) {
        my $vp = $mcfg_prefix.$v;
        $mcof->{$vp} = $v;
        $mcor->{$v} = $vp;
        if ($k eq 'MCFG_VERBOSE') {
            $usage .= " $vp:0,1,2,3,4,5";
        } elsif ($k eq 'MCFG_RESTART') {
            $usage .= " $vp:1";
        } else {
            $usage .= " $vp";
        }
    }


# called when a new definition is created (by hand or from configuration read on FHEM startup)
sub X_Define($$)
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
  main::DevIo_OpenDev($hash, 0, "TronfernoMCU::X_Init", "TronfernoMCU::X_Callback"); 
 
  return undef;
}

# called when definition is undefined 
# (config reload, shutdown or delete of definition)
sub X_Undef($$)
{
  my ($hash, $name) = @_;
 
  # close the connection 
  main::DevIo_CloseDev($hash);
  
  return undef;
}

# called repeatedly if device disappeared
sub X_Ready($)
{
  my ($hash) = @_;
  
  # try to reopen the connection in case the connection is lost
  return main::DevIo_OpenDev($hash, 1, "TronfernoMCU::X_Init", "TronfernoMCU::X_Callback"); 
}

# called when data was received
sub X_Read($$)
{
  # if DevIo_Expect() returns something we call this function with an additional argument
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  # read the available data (or don't if called from X_Set)
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
      } elsif ($line =~ /^[Cc]:.*;$/) {
	  main::Log3 $name, 3, "TronfernoMCU ($name): msg received $line";
	  main::Dispatch($hash, "TFMCU#$line");
      } elsif ($line =~ /^config (.*);$/) {
          for my $kv (split (' ', $1)) {
              my ($k, $v) = split('=', $kv);
              $k = $mcor->{$k};
              $hash->{$k} = $v;
          }
      }
  }

  $hash->{PARTIAL} = $remain;
}

sub mcu_read_all_config($) {
    my ($hash) = @_;
    main::DevIo_SimpleWrite($hash, "config longitude=? latitude=? tz=? wlan-ssid=?;", 2);
    main::DevIo_SimpleWrite($hash, "config cu=? baud=? verbose=?;", 2);

}

sub mcu_read_config($$) {
    my ($hash, @args) = @_;
    my $msg = "";
    for my $o (@args) {
        $msg .= "$o=?";
    }
    main::DevIo_SimpleWrite($hash, "config $msg;", 2);
}

sub mcu_config($$$) {
    my ($hash, $opt, $arg) = @_;
    main::DevIo_SimpleWrite($hash, "config $opt=$arg $opt=?;", 2);
}

    
    $usage .= ' xxx.flash-firmware.esp32:no,latest-version,restore';
    $usage .= ' xxx.flash-firmware.esp8266:no,latest-version,restore';
    $usage .= ' xxx.flash-firmware.atmega328:no,latest-version,restore';
    
# called if set command is executed
sub X_Set($$@)
{
    my ($hash, $name, $cmd, @args) = @_;
    my ($a1, $a2, $a3, $a4) = @args;

    return "\"set $name\" needs at least one argument" unless (defined($cmd));

    my $u = "unknown argument $cmd choose one of ";
    $u .= $usage;
    
    if ($cmd eq '?') {
        return $u;
    } elsif($mcof->{$cmd}) {
        mcu_config($hash, $mcof->{$cmd}, $a1) if defined($a1); 
    } elsif($cmd eq 'xxx.flash-firmware.esp32') {
    } elsif($cmd eq 'xxx.flash-firmware.esp8266') {
    } elsif($cmd eq 'xxx.flash-firmware.atmega328') {
    } elsif($cmd eq '') {
    } elsif($cmd eq '') {
    } elsif($cmd eq '') {
    } elsif($cmd eq '') {
     } elsif($cmd eq "statusRequest") {
         #main::DevIo_SimpleWrite($hash, "get_status\r\n", 2);
    } elsif($cmd eq "on") {
         #main::DevIo_SimpleWrite($hash, "on\r\n", 2);
    } elsif($cmd eq "off") {
         #main::DevIo_SimpleWrite($hash, "off\r\n", 2);
    } else {
        return $u;
    }
    
    return undef;
}
    
# will be executed upon successful connection establishment (see main::DevIo_OpenDev())
sub X_Init($)
{
    my ($hash) = @_;

    # send a status request to the device
    main::DevIo_SimpleWrite($hash, "mcu cs=?;", 2);  #FIXME: need better cli option for this
    mcu_read_all_config($hash);
    return undef; 
}

# will be executed if connection establishment fails (see main::DevIo_OpenDev())
sub X_Callback($)
{
    my ($hash, $error) = @_;
    my $name = $hash->{NAME};

    # create a log emtry with the error message
    main::Log3 $name, 5, "TronfernoMCU ($name) - error while connecting: $error" if ($error); 
    
    return undef; 
}

sub X_Write ($$)
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

        $hash->{SetFn}   = 'TronfernoMCU::X_Set';
        $hash->{DefFn}   = 'TronfernoMCU::X_Define';
        $hash->{ReadFn}  = 'TronfernoMCU::X_Read';
        $hash->{ReadyFn} = 'TronfernoMCU::X_Ready';
        $hash->{WriteFn} = 'TronfernoMCU::X_Write';
        $hash->{UndefFn} = 'TronfernoMCU::X_Undef';

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


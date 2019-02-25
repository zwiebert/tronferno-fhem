################################################################################
## *experimental* FHEM module for Fernotron devices
##
##
##  - file: /opt/fhem/FHEM/10_Tronferno.pm
##  - needs IODev TronfernoMCU
##  - to send command to Fernotron devices
##  - to receive position status from tronferno-mcu hardware
##  - currently it does not receive commands from Fernotron controllers (TODO)
##
################################################################################
## Author: Bert Winkelmann <tf.zwiebert@online.de>
## Project: https://github.com/zwiebert/tronferno-fhem
## Related Hardware-Project: https://github.com/zwiebert/tronferno-mcu
################################################################################

use strict;
use warnings;
use 5.14.0;

use IO::Socket;

package Tronferno {

    my $def_mcuaddr = 'fernotron.fritz.box.';

    sub Tronferno_Define($$) {
        my ($hash, $def) = @_;
        my @a       = split("[ \t][ \t]*", $def);
        my $name    = $a[0];
        my $address = $a[1];

        my ($a, $g, $m, $iodev, $mcu_addr) = (0, 0, 0, undef, $def_mcuaddr);
        my $u = 'wrong syntax: define <name> Tronferno a=ID [g=N] [m=N]';

        return $u if ($#a < 2);

        shift(@a);
        shift(@a);
        foreach my $o (@a) {
            my ($key, $value) = split('=', $o);

            if ($key eq 'a') {
                $a = hex($value);
            } elsif ($key eq 'g') {
                $g = int($value);
                return "out of range value $g for g. expected: 0..7" unless (0 <= $g && $g <= 7);
            } elsif ($key eq 'm') {
                $m = int($value);
                return "out of range value $m for m. expected: 0..7" unless (0 <= $m && $m <= 7);
            } elsif ($key eq 'iodev') {
		$iodev = $value;
            } elsif ($key eq 'mcu_addr') {
		$mcu_addr = $value;
            } else {
                return "$name: unknown argument $o in define";    #FIXME add usage text
            }
        }

        $hash->{helper}{ferid_a} = $a;
        $hash->{helper}{ferid_g} = $g;
        $hash->{helper}{ferid_m} = $m;
        $hash->{helper}{mcu_addr} = $mcu_addr;

	main::AssignIoPort($hash, $iodev);

	my $def_match = "$a,$g,$m";
	$hash->{helper}{def_match} = $def_match;

	$main::modules{Fernotron}{defptr}{$def_match} = $hash;
	#main::Log3($hash, 0, "def_match: $def_match");

        return undef;
    }

    
    sub Tronferno_Undef($$) {
	my ($hash, $name) = @_;

	my $def_match = $hash->{helper}{def_match};
	
	undef ($main::modules{Fernotron}{defptr}{$def_match});

	return undef;
    }

    sub Tronferno_transmit_by_socket($$$) {
        my ($hash, $name, $req) = @_;
        my $socket = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerPort => 7777,
            PeerAddr => main::AttrVal($name, 'mcuaddr', $hash->{helper}{mcu_addr}),  
        ) or return "\"no socket\"";

        $socket->autoflush(1);
        $socket->send($req . "\n");
        $socket->close();

	return undef;
}

    sub Tronferno_transmit($$$) {
        my ($hash, $name, $req) = @_;
        my $io   = $hash->{IODev};

	if (exists($io->{NAME})) {
	    # send message to pyhsical I/O device TronfernoMCU
	    return 'error: IO device not open' unless (main::ReadingsVal($io->{NAME}, 'state', '') eq 'opened');
	    main::IOWrite($hash, 'mcu', $req);
	    return undef;
	} else {
	    #no I/O device seems to be defined. send directly via TCP socket
	    return Tronferno_transmit_by_socket ($hash, $name, $req);
	}
	
	return undef;
    }

    sub Tronferno_build_cmd($$$$) {
        my ($hash, $name, $cmd, $c) = @_;
        my $a   = ($cmd eq 'pair') ? '?' : $hash->{helper}{ferid_a};
        my $g   = $hash->{helper}{ferid_g};
        my $m   = $hash->{helper}{ferid_m};
	my $r   = int(main::AttrVal($name, 'repeats', '1'));
	
        my $msg = "$cmd a=$a g=$g m=$m c=$c r=$r mid=82;";
        main::Log3($hash, 3, "$name:command: $msg");
        return $msg;
    }

    my $map_send_cmds = {
        up         => 'up',
        down       => 'down',
        stop       => 'stop',
        set        => 'set',
        'sun-down' => 'sun-down',
        'sun-up'   => 'sun-up',
        'sun-inst' => 'sun-inst',
    };

    my $map_pair_cmds = {
        xxx_pair         => 'pair',
        xxx_unpair       => 'unpair',
    };


    sub get_commandlist()   { return keys %$map_send_cmds, keys %$map_pair_cmds; }

    sub Tronferno_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;

        return "\"set $name\" needs at least one argument" unless (defined($cmd));

        if ($cmd eq '?') {
            my $res = "unknown argument $cmd choose one of ";
            foreach my $key (get_commandlist()) {
                $res .= " $key:noArg";
            }
            return $res .  ' position:slider,0,50,100';
	  } elsif (exists $map_send_cmds->{$cmd}) {
            my $req = Tronferno_build_cmd($hash, $name, 'send', $map_send_cmds->{$cmd});
            my $res = Tronferno_transmit($hash, $name, $req);
	    return $res if ($res);
	  } elsif (exists $map_pair_cmds->{$cmd}) {
            my $req = Tronferno_build_cmd($hash, $name, 'pair', $map_pair_cmds->{$cmd});
            my $res = Tronferno_transmit($hash, $name, $req);
	    return $res if ($res);
	} elsif ($cmd eq 'position') {
	    return "\"set $name $cmd\" needs one argument" unless (defined($args[0]));
	    my $percent = $args[0];
	    my $c = 'up';
	    if ($percent eq '0') {
		$c = 'down';
	    } elsif ($percent eq '50') {
		$c = 'sun-down';
	    } elsif ($percent eq '99') {
		$c = 'stop';
	    }

	    
            my $req = Tronferno_build_cmd($hash, $name, 'send', $c);
            my $res = Tronferno_transmit($hash, $name, $req);
        } else {
            return "unknown argument $cmd choose one of " . join(' ', get_commandlist()) . 'position';
        }

        return undef;
    }

    sub Tronferno_Parse {
      my ($io_hash, $message) = @_;
      my $name = $io_hash->{NAME};
      my ($a, $g, $m, $p, $mm) = (0, 0, 0, 0, undef);
      my $result = undef;
      
      if ($message =~ /^TFMCU#U:position:\s*(.+);$/) {
	foreach my $arg (split(/\s+/, $1)) {
	  my ($key, $value) = split('=', $arg);

	  if ($key eq 'a') {
	    $a = hex($value);

	  } elsif ($key eq 'g') {
	    $g = int($value);
	    return "out of range value $g for g. expected: 0..7" unless (0 <= $g && $g <= 7);
	  } elsif ($key eq 'm') {
	    $m = int($value);
	    return "out of range value $m for m. expected: 0..7" unless (0 <= $m && $m <= 7);
	  } elsif ($key eq 'mm') {
	    my @mask_arr = split(/\,/, $value);
	    $mm = \@mask_arr;
	  return "out of range value $m for m. expected: 0..7" unless (0 <= $m && $m <= 7);
	} elsif ($key eq 'p') {
	  $p = $value;
	  return "out of range value $p for p. expected: 0..100" unless (0 <= $p && $m <= 100);
	}
      }

      if (defined ($mm)) {
	for $g (0..7) {
	  my $gm =hex($$mm[$g]);
	  for $m (0..7) {
	    if ($gm & (1 << $m)) {
	      my $def_match = "0,$g,$m";
	      my $hash = $main::modules{Fernotron}{defptr}{$def_match}; #FIXME: add support for $a different than zero
	      if ($hash) {
		main::readingsSingleUpdate($hash, 'state',  $p, 0);
		$result = $hash->{NAME};
	      }
	    }
	  }
	}

	return $result;

      } else {
	my $def_match = "0,$g,$m";
	#main::Log3($io_hash, 3, "def_match: $def_match");
	my $hash = $main::modules{Fernotron}{defptr}{$def_match}; #FIXME: add support for $a different than zero

	if ($hash) {
	  main::readingsSingleUpdate($hash, 'state',  $p, 0);
	  # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.
	  return $hash->{NAME};
	} elsif ($g == 0) {
	  for $g (1..7) {
	    for $m (1..7) {
	      my $hash = $main::modules{Fernotron}{defptr}{"0,$g,$m"};
	      if ($hash) {
		main::readingsSingleUpdate($hash, 'state',  $p, 0);
		$result = $hash->{NAME};
	      }
	    }
	  }
	  return $result;
	} elsif ($m == 0) {
	  for $m (1..7) {
	    my $hash = $main::modules{Fernotron}{defptr}{"0,$g,$m"};
	    if ($hash) {
	      main::readingsSingleUpdate($hash, 'state',  $p, 0);
	      $result = $hash->{NAME};
	    }
	  }
	  return $result;
	}
      }
    }
    return undef;
    }


    
    sub Tronferno_Attr(@) {
        my ($cmd, $name, $attrName, $attrValue) = @_;

        # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
        # $name - Gerätename
        # $attrName/$attrValue sind Attribut-Name und Attribut-Wert

        if ($cmd eq "set") {
            if ($attrName eq 'repeats') {
                my $r = int($attrValue);
                return "invalid argument '$attrValue'. Expected: 0..5" unless (0 <= $r and $r <= 5);
            }
        }
        return undef;
    }


}

package main {

    sub Tronferno_Initialize($) {
        my ($hash) = @_;

        $hash->{DefFn} = 'Tronferno::Tronferno_Define';
        $hash->{SetFn} = 'Tronferno::Tronferno_Set';
        $hash->{ParseFn} = 'Tronferno::Tronferno_Parse';
        $hash->{UndefFn} = 'Tronferno::Tronferno_Undef';
        $hash->{AttrFn}  =  'Tronferno::Tronferno_Attr';

	$hash->{AttrList} = 'IODev repeats:0,1,2,3,4,5';
	$hash->{Match} = '^TFMCU#.+';
    }
}

1;
=pod
=item device
=item summary controls shutters via Tronferno-MCU
=item summary_DE steuert Rolläden über Tronferno-MCU

=begin html

<a name="Tronferno"></a>

<h3>Tronferno</h3>

<i>Tronferno</i> is a logic module to control Fernotron shutters by sending commands to <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a> micro controller hardware.

<ul>
<li>Required I/O device: <i>TronfernoMCU</i></li>
<li>Tronferno-MCU is a micro-controller to control Fernotron shutters via radio frequency. It can also programm the built-in timers.</li>
<li>00_TronfernoMCU.pm is the FHEM I/O module which talks to the MCU via USB or TCP/IP (using FHEM's DevIo)
<li>Pairing: Senders have 6 digit Hex-Numbers as ID.  To pair, the receiver learns IDs of its paired Senders.</li>
<li>Sending directly: Motors have also an ID wich can be used to address messages to it without pairing.</li>
</ul>


<h4>Defining Devices</h4>

<h5>1. FHEM devices to control Fernotron devices</h5>

Each output device may control a single shutter, or a group of shutters depending on the parameters given in the define statement.

<p>
  <code>
    define <my_shutter> Tronferno [a=ID] [g=GN] [m=MN]<br>
  </code>			
		
<p> 
  ID : the device ID.  A six digit hexadecimal number. 10xxxx=plain controller, 20xxxx=sun sensor, 80xxxx=central controller unit, 90xxxx=receiver. 0 (default) for using the default central unit of Tronferno-MCU<br>
  GN : group number (1-7) or 0 (default) for all groups<br>
  MN : member number  (1-7) or  0 (default) for all group members<br>

<p>
  'g' or  'n' are only useful combined with an ID of the central controller type.


<h4>Adressing and Pairing in Detail</h4>

<h5>Three different methods to make messsages find their target Fernotron receiver</h5>
<ol>
  <li>Scan IDs of physical Fernotron controllers you own and copy their IDs in our FHEM output devices.  Use default Input device Fernotron_Scan to scan the ID first. Then use the ID to define your device. Here we have scanned the ID of our 2411 central resulting to 801234. Now define devices by using it
  </li>

  <li>Define Fernotron devices using invented IDs (like 100001, 100002, ...). Then pair these devices by sending a STOP command from it while the physical Fernotron receiver/motor is in pairing-mode (aka set-mode).
  </li>

<li> Receiver IDs to send directly to without pairing: RF controlled shutters may have a 5 digit code printed on or on a small cable sticker.
  Prefix that number with a 9 to get an valid ID for defining a device.</li>
</ol>

<h4>Making Groups</h4>

<ol>
  <li>groups and members are the same like in 2411. Groups are adressed using the 0 as wildcard.  (g=1 m=0 or g=0 m=1 or g=0 m=0) </li>

  <li> Like with plain controllers or sun sensors. Example: a (virtual) plain controller paired with each shutter of the entire floor.</li>

  <li> not possible with receiver IDs</li>
</ol>

<h4>Commands</h4>
<ul>
  <li>up</li>
  <li>down</li>
  <li>stop</li>
  <li>set  - activate set mode to make receiver ready to pair/unpair</li>
  <li>sun-down - move to sun position (but only if sun automatic is enabled and shutter is currently above this position)</li>
  <li>sun-up - when at sun-position the shutter will be fully opened with this command (does nothing when not at sun position)</li>
  <li>sun-inst - set the current position as sun position</li>
  <li>position - set position to 0 (down), 50 (sun-down), 100 (up), 99 (stop). (used  by alexa)</li>
  <li>xxx_pair - Lets MCU pair the next received sender to this shutter (Paired senders will influence the shutter position)</li>
  <li>xxx_unpair - Lets MCU unpair the next received Sender to this shutter</li>
</ul>


<h4>Examples</h4>


<ul>
      <li>first define the I/O device, so it exists before any rollo_xx devices which depends on it.<br>
      <code>define tfmcu TronfernoMCU 192.168.1.123</code></li>
</ul>

<h5>Adressing and Pairing in Detail</h5>
<ol>
  <li>
    <code>define myShutterGroup1 Tronferno a=801234 g=1 m=0</code><br>
    <code>define myShutter11 Tronferno a=801234 g=1 m=1</code><br>
    <code>define myShutter12 Tronferno a=801234 g=1 m=2</code><br>
    ...
    <code>define myShutterGroup2 Tronferno a=801234 g=2 m=0</code><br>
    <code>define myShutter21 Tronferno a=801234 g=2 m=1</code><br>
    <code>define myShutter22 Tronferno a=801234 g=2 m=2</code><br>
      </li>

  <li>
    <code>define myShutter1 Tronferno a=100001</code><br>
    <code>define myShutter2 Tronferno a=100002</code><br>
    Now activate Set-mode on the Fernotron receiver and send a STOP by the newly defined device you wish to pair with it.
 ...</li>

<li><code>define myShutter__0d123 Tronferno a=90d123</code></li>
</ol>

<h5>More Examples</h5>
<ul>
<li>Attribute for alexa module:<br>
<code>attr myShutter_42 genericDeviceType blind</code><br>
<code>attr myShutter_42 alexaName bedroom shutter</code><br>
</li>
<li>GUI buttons<br>
<code>attr myShutter_42 webCmd down:stop:up</code><br>
</li>
</ul>

=end html

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Tronferno.pm"
# End:

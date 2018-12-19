#############################################
## *experimental* FHEM module Tronferno
#  Logical FHEM module to control Fernotron devices via physical module 00_TronfernoMCU.pm
#
#  Author:  Bert Winkelmann <tf.zwiebert@online.de>
#
# - copy or softlink file 00_TronfernoMCU.pm to /opt/fhem/FHEM/00_TronfernoMCU.pm
# - copy or softlink this file to /opt/fhem/FHEM/10_Tronferno.pm
# - do 'reload 00_TronfernoMCU' and 'reload 10_Tronferno'
#
#  device arguments
#      a - 6 digit Fernotron hex ID or 0 (default: 0)
#      g - group number: 0..7 (default: 0)
#      m - member number: 0..7 (default: 0)
#      iodev - if you have more than one Fernotron-MCU
#      mcu_addr - only needed if you don't want to use FernotronMCU as IO device
#
#     Examples:
#
# 1) MCU module is connected via TCP/IP
#
#    define tfmcu TronfernoMCU  192.168.1.123
#    define roll_11 Tronferno g=1 m=1
#    define roll_12 Tronferno g=1 m=2
#     ..
#    define roll_77 Tronferno g=7 m=7
#
# 2) MCU module is connected via USB port /dev/ttyUSB1
#
#    define tfmcu TronfernoMCU /dev/ttyUSB1
#    define roll_11 Tronferno g=1 m=1
#    define roll_12 Tronferno g=1 m=2
#     ..
#    define roll_77 Tronferno g=7 m=7
#
# 3) Connect to multiple TronfernoMCU
#
#    define tfmcu_A TronfernoMCU /dev/tty/USB1
#    define tfmcu_B TronfernoMCU 192.168.1.123
#    define tfmcu_C TronfernoMCU computer.domain.com
#
#    define roll_A_11 Tronferno g=1 m=1 iodev=tfmcu_A
#     ...
#    define roll_B_11 Tronferno g=1 m=1 iodev=tfmcu_B
#     ...
#    define roll_C_11 Tronferno g=1 m=1 iodev=tfmcu_C
#
#  ### Make sure the I/O device tfmcu is defined before any roll_xx device ###
#  ### Otherwise the roll_xx devices can't find their I/O device (because its not defined yet) ###
#
#  device set commands
#      down, stop, up, set, sun-inst, sun-down, sup-up
#
# TODO
# - ...


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
            return $res;
	  } elsif (exists $map_send_cmds->{$cmd}) {
            my $req = Tronferno_build_cmd($hash, $name, 'send', $map_send_cmds->{$cmd});
            my $res = Tronferno_transmit($hash, $name, $req);
	    return $res if ($res);
	  } elsif (exists $map_pair_cmds->{$cmd}) {
            my $req = Tronferno_build_cmd($hash, $name, 'pair', $map_pair_cmds->{$cmd});
            my $res = Tronferno_transmit($hash, $name, $req);
	    return $res if ($res);
        } else {
            return "unknown argument $cmd choose one of " . join(' ', get_commandlist());
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

	$hash->{AttrList} = 'repeats:0,1,2,3,4,5';
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

<i>Tronferno</i> is a logic module to control shutters by sending commands to <i>Tronferno-MCU</i> via USB port or TCP/IP.

<h4>Basics</h4>

Tronferno-MCU is a micro-controller to control Fernotron shutters. It can also programm the built-in timers.

<p>00_TronfernoMCU.pm is the FHEM I/O module which talks to the MCU via USB or TCP/IP (using FHEM's DevIo)

<h4>Defining Devices</h4>

Each device may control a single shutter, but could also control an entire group.
This depends on the ID and the group and member numbers.

<p>
				    
  <code>
    define <my_shutter> Tronferno [a=ID] [g=GN] [m=MN]<br>
  </code>			
		
<p> 
  ID : the device ID.  A six digit hexadecimal number. 10xxxx=plain controller, 20xxxx=sun sensor, 80xxxx=central controller unit, 90xxxx=receiver. 0 (default for using the default central unit of Tronferno-MCU<br>
  GN : group number (1-7) or 0 (default) for all groups<br>
  MN : member number  (1-7) or  0 (default) for all group members<br>

<p>
  'g' and  'm' can only be combined with a central controller type. 

<h4>Different Kinds of Adressing</h4>

<ol>
  <li> Scanning physical controllers and use their IDs.
    Example: Using the  ID of a  2411 controller to access shutters via group and member numbers.</li>

  <li> Make up IDs and pair them with shutters.
    Example: Pair shutter 1 with ID 100001, shutter  2 with 100002, ...</li>

<li> Receiver IDs: RF controlled shutters may have a 5 digit code printed on or on a small cable sticker.
  Prefix a 9 with it and you get an ID.</li>
</ol>

<h4>Making Groups</h4>

<ol>
  <li>groups and members are the same like in 2411. Groups are adressed using the 0 as wildcard.  (g=1 m=0 or g=0 m=1 or g=0 m=0) </li>

  <li> Like with plain controllers. Example: a (virtual) plain controller paired with each shutter of the entire floor.</li>

  <li> not possible with reeiver IDs</li>
</ol>


<h4>Kommandos</h4>

<ul>
  <li>up</li>
  <li>down</li>
  <li>stop</li>
  <li>set  - make receiver ready to pair</li>
  <li>sun-down - move down until sun position (but only, if sun automatic is enabled)</li>
  <li>sun-inst - set the current position as sun position</li>
</ul>

<h4>Examples</h4>

<ol>
  <li><ul>
      <li>first define the I/O device, so it exists before any rollo_xx devices which depends on it.</li>
      <li><code>define tfmcu TronfernoMCU 192.168.1.123</code></li>
  </ul></li>

  <li><ul>
      <li><code>define rollo42 Tronferno g=4 m=2</code></li>
  </ul></li>

  <li><ul>
      <li><code>define rollo1 Tronferno a=100001 </code></li>
      <li>enable set mode on the receiver</li>
      <li>press stop for rollo1</li>
  </ul></li>

  <li><ul>
      <li><code>define rollo_0d123 Fernotron a=90d123</code></li>
  </ul></li>
</ol>

<br>     Examples:
<br>
<br> 1) MCU module is connected via TCP/IP
<br>
<br>    define tfmcu TronfernoMCU  192.168.1.123
<br>    define roll_11 Tronferno g=1 m=1
<br>    define roll_12 Tronferno g=1 m=2
<br>     ..
<br>    define roll_77 Tronferno g=7 m=7
<br>
<br> 2) MCU module is connected via USB port /dev/ttyUSB1
<br>
<br>    define tfmcu TronfernoMCU /dev/ttyUSB1
<br>    define roll_11 Tronferno g=1 m=1
<br>    define roll_12 Tronferno g=1 m=2
<br>     ..
<br>    define roll_77 Tronferno g=7 m=7
<br>
<br> 3) Connect to multiple TronfernoMCU
<br>
<br>    define tfmcu_A TronfernoMCU /dev/tty/USB1
<br>    define tfmcu_B TronfernoMCU 192.168.1.123
<br>    define tfmcu_C TronfernoMCU computer.domain.com
<br>
<br>    define roll_A_11 Tronferno g=1 m=1 iodev=tfmcu_A
<br>     ...
<br>    define roll_B_11 Tronferno g=1 m=1 iodev=tfmcu_B
<br>     ...
<br>    define roll_C_11 Tronferno g=1 m=1 iodev=tfmcu_C
<br>
<br>  ### Make sure the I/O device tfmcu is defined before any roll_xx device ###
<br>  ### Otherwise the roll_xx devices can't find their I/O device (because its not defined yet) ###

=end html

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Tronferno.pm"
# End:

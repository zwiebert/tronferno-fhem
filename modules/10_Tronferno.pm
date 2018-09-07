#############################################
## *experimental* FHEM module Tronferno
#  FHEM module to control Fernotron devices via Tronferno-MCU ESP8266 hardware
#
#  Author:  Bert Winkelmann <tf.zwiebert@online.de>
#
#
# - copy or softlink this file to /opt/fhem/FHEM/10_Tronferno.pm
# - do 'reload 10_Tronferno'
#
#  device arguments
#      a - 6 digit Fernotron hex ID or 0 (default: 0)
#      g - group number: 0..7 (default: 0)
#      m - member number: 0..7 (default: 0)
#
#     Example: define roll12 Tronferno g=1 m=2
#
#  device attributes:
#      mcuaddr - IP4 address/hostname of tronferno-mcu hardware (default: fernotron.fritz.box.)
#
#  device set commands
#      down, stop, up, set, sun-inst, sun-down, sup-up
#
# TODO
# - doc
# - ...
# - states

use strict;
use warnings;
use 5.14.0;

use IO::Socket;

#use IO::Select;

package Tronferno {

    my $def_mcuaddr = 'fernotron.fritz.box.';

    sub Tronferno_Define($$) {
        my ($hash, $def) = @_;
        my @a       = split("[ \t][ \t]*", $def);
        my $name    = $a[0];
        my $address = $a[1];

        my ($a, $g, $m) = (0, 0, 0);
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
            } else {
                return "$name: unknown argument $o in define";    #FIXME add usage text
            }
        }

        $hash->{helper}{ferid_a} = $a;
        $hash->{helper}{ferid_g} = $g;
        $hash->{helper}{ferid_m} = $m;

	main::AssignIoPort($hash, 'tfmcu');

        return undef;
    }

    sub Tronferno_transmit($$$) {
        my ($hash, $name, $req) = @_;
        my $io   = $hash->{IODev};

	return 'error: IO device not open' unless (exists($io->{NAME}) and main::ReadingsVal($io->{NAME}, 'state', '') eq 'opened');

	
	main::IOWrite($hash, 'mcu', $req);

	return undef;
    }

    sub Tronferno_build_cmd($$$$) {
        my ($hash, $name, $cmd, $c) = @_;
        my $a   = $hash->{helper}{ferid_a};
        my $g   = $hash->{helper}{ferid_g};
        my $m   = $hash->{helper}{ferid_m};
        my $msg = "$cmd a=$a g=$g m=$m c=$c;";
        main::Log3($hash, 3, "$name:command: $msg");
        return $msg;
    }

    my $map_tcmd = {
        up         => 'up',
        down       => 'down',
        stop       => 'stop',
        set        => 'set',
        'sun-down' => 'sun-down',
        'sun-up'   => 'sun-up',
        'sun-inst' => 'sun-inst',
    };

    sub get_commandlist()   { return keys %$map_tcmd; }
    sub is_command_valid($) { return exists $map_tcmd->{ $_[0] }; }

    sub Tronferno_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;

        return "\"set $name\" needs at least one argument" unless (defined($cmd));

        if ($cmd eq '?') {
            my $res = "unknown argument $cmd choose one of ";
            foreach my $key (get_commandlist()) {
                $res .= " $key:noArg";
            }
            return $res;
        } elsif (is_command_valid($cmd)) {
            my $req = Tronferno_build_cmd($hash, $name, 'send', $map_tcmd->{$cmd});
            my $res = Tronferno_transmit($hash, $name, $req);
            main::readingsSingleUpdate($hash, 'state', $cmd, 0) unless ($res);
	    return $res if ($res);
        } else {
            return "unknown argument $cmd choose one of " . join(' ', get_commandlist());
        }

        return undef;
    }

}

package main {

    sub Tronferno_Initialize($) {
        my ($hash) = @_;

        $hash->{DefFn} = 'Tronferno::Tronferno_Define';
        $hash->{SetFn} = "Tronferno::Tronferno_Set";

        $hash->{AttrList} = 'mcuaddr';
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

<i>Tronferno</i> is a logic module to control shutters by sending commands to <i>Tronferno-MCU</i> via TCP/IP.

<h4>Basics</h4>

Tronferno-MCU is a micro-controller to control Fernotron shutters. It can also programm the built-in timers.

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
      <li>first scan the ID of the 2411 using fhemft.pl (FIXME)</li>
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
=end html

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Tronferno.pm"
# End:

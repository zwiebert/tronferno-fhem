#############################################
## *experimental* FHEM module Tronferno
#  FHEM module to control Fernotron devices via Tronferno-MCU ESP8266 hardware
#
#  written by Bert Winkelmann <tf.zwiebert@online.de>
#
#
# - copy or softink this file to /opt/fhem/FHEM/10_Tronferno.pm
# - submit command 'rereadcfg' to fhem  (maybe try 'reload 10_Tronferno' too)
#
#
# Bugs:
#  - this needs the latest firmware of tronferno-mcu
#  - ...

use strict;
use warnings;
use 5.14.0;

use IO::Socket;

#use IO::Select;

package Tronferno {

  my $def_mcuaddr = 'fernotron.fritz.box.';
 

    sub Tronferno_Define($$) {
        my ($hash, $def) = @_;
        my $name = $hash->{NAME};

        my @a = split("[ \t][ \t]*", $def);
        my ($a, $g, $m) = (0, 0, 0);
        my $u = 'wrong syntax: define <name> Fernotron a=ID [g=N] [m=N]';

        return $u if ($#a < 2);

        shift(@a);
        shift(@a);
        foreach my $o (@a) {
            my ($key, $value) = split('=', $o);

            if ($key eq 'a') {
                $a = hex($value);
            }
            elsif ($key eq 'g') {
                $g = int($value);
            }
            elsif ($key eq 'm') {
                $m = int($value);
            }
            else {
                return "$name: unknown argument $o in define";    #FIXME add usage text
            }
        }

        #FIXME-bw/24-Nov-17: validate options
        $hash->{helper}{ferid_a} = $a;
        $hash->{helper}{ferid_g} = $g;
        $hash->{helper}{ferid_m} = $m;

        return undef;
    }

    sub Tronferno_transmit($$) {
        my ($name, $req) = @_;
        my $socket = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerPort => 7777,
            PeerAddr => main::AttrVal($name, 'mcuaddr', $def_mcuaddr),
        ) or return "\"no socket\"";

        $socket->autoflush(1);
        $socket->send($req . "\n");
        $socket->close();
    }

    sub Tronferno_build_cmd($$$$) {
        my ($hash, $name, $cmd, $c) = @_;
          my $a = $hash->{helper}{ferid_a};
          my $g = $hash->{helper}{ferid_g};
          my $m = $hash->{helper}{ferid_m};
	my $msg = "$cmd g=$g m=$m c=$c;";
	print("$msg\n");
	return $msg;
    }

    my $map_tcmd = {
        up         => 'up',
        down       => 'down',
        stop       => 'stop',
        set        => 'set',
        'sun-down' => 'sun-down',
        'sun-inst' => 'sun-inst',
    };

    sub Tronferno_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;

        return "\"set $name\" needs at least one argument" unless (defined($cmd));

        if ($cmd eq '?') {
            my $res = "unknown argument $cmd choose one of ";
            foreach my $key (keys %$map_tcmd) {
                $res .= " $key:noArg";
            }
            return $res;
        }

        if (exists $map_tcmd->{$cmd}) {
            my $req = Tronferno_build_cmd($hash, $name, 'send', $map_tcmd->{$cmd});
            Tronferno_transmit($name, $req);
        }
        else {
            return "unknown argument $cmd choose one of " . join(' ', keys(%$map_tcmd));
        }

        return undef;
    }

}

package main {

    sub Tronferno_Initialize($) {
        my ($hash) = @_;

        $hash->{DefFn} = 'Tronferno::Tronferno_Define';

        $hash->{AttrList} = 'mcuaddr';
        $hash->{SetFn}    = "Tronferno::Tronferno_Set";
    }
}

1;

=pod
=item summary    supporting devices using the SOMFY RTS protocol - window shades 
=item summary_DE für Geräte, die das SOMFY RTS protocol unterstützen - Rolläden 
=begin html

<a name="SOMFY"></a>
<h3>SOMFY - Somfy RTS / Simu Hz protocol</h3>
<ul>
  The Somfy RTS (identical to Simu Hz) protocol is used by a wide range of devices,
  which are either senders or receivers/actuators.
  Right now only SENDING of Somfy commands is implemented in the CULFW, so this module currently only
  supports devices like blinds, dimmers, etc. through a <a href="#CUL">CUL</a> device (which must be defined first).
  Reception of Somfy remotes is only supported indirectly through the usage of an FHEMduino 
  <a href="http://www.fhemwiki.de/wiki/FHEMduino">http://www.fhemwiki.de/wiki/FHEMduino</a>
  which can then be used to connect to the SOMFY device.

  <br><br>

  <a name="SOMFYdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SOMFY &lt;address&gt; [&lt;encryption-key&gt;] [&lt;rolling-code&gt;] </code>
    <br><br>

   The address is a 6-digit hex code, that uniquely identifies a single remote control channel.
   It is used to pair the remote to the blind or dimmer it should control.
   <br>
   Pairing is done by setting the blind in programming mode, either by disconnecting/reconnecting the power,
   or by pressing the program button on an already associated remote.
   <br>
   Once the blind is in programming mode, send the "prog" command from within FHEM to complete the pairing.
   The blind will move up and down shortly to indicate completion.
   <br>
   You are now able to control this blind from FHEM, the receiver thinks it is just another remote control.

   <ul>
   <li><code>&lt;address&gt;</code> is a 6 digit hex number that uniquely identifies FHEM as a new remote control channel.
   <br>You should use a different one for each device definition, and group them using a structure.
   </li>
   <li>The optional <code>&lt;encryption-key&gt;</code> is a 2 digit hex number (first letter should always be A)
   that can be set to clone an existing remote control channel.</li>
   <li>The optional <code>&lt;rolling-code&gt;</code> is a 4 digit hex number that can be set
   to clone an existing remote control channel.<br>
   If you set one of them, you need to pick the same address as an existing remote.
   Be aware that the receiver might not accept commands from the remote any longer,<br>
   if you used FHEM to clone an existing remote.
   <br>
   This is because the code is original remote's codes are out of sync.</li>
   </ul>
   <br>

    Examples:
    <ul>
      <code>define rollo_1 SOMFY 000001</code><br>
      <code>define rollo_2 SOMFY 000002</code><br>
      <code>define rollo_3_original SOMFY 42ABCD A5 0A1C</code><br>
    </ul>
  </ul>
  <br>

  <a name="SOMFYset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    go-my
    stop
    pos value (0..100) # see note
    prog  # Special, see note
    on-for-timer
    off-for-timer
	</pre>
    Examples:
    <ul>
      <code>set rollo_1 on</code><br>
      <code>set rollo_1,rollo_2,rollo_3 on</code><br>
      <code>set rollo_1-rollo_3 on</code><br>
      <code>set rollo_1 off</code><br>
      <code>set rollo_1 pos 50</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>prog is a special command used to pair the receiver to FHEM:
      Set the receiver in programming mode (eg. by pressing the program-button on the original remote)
      and send the "prog" command from FHEM to finish pairing.<br>
      The blind will move up and down shortly to indicate success.
      </li>
      <li>on-for-timer and off-for-timer send a stop command after the specified time,
      instead of reversing the blind.<br>
      This can be used to go to a specific position by measuring the time it takes to close the blind completely.
      </li>
      <li>pos value<br>
		
			The position is variying between 0 completely open and 100 for covering the full window.
			The position must be between 0 and 100 and the appropriate
			attributes drive-down-time-to-100, drive-down-time-to-close,
			drive-up-time-to-100 and drive-up-time-to-open must be set. See also positionInverse attribute.<br>
			</li>
			</ul>

		The position reading distinuishes between multiple cases
    <ul>
      <li>Without timing values (see attributes) set only generic values are used for status and position: <pre>open, closed, moving</pre> are used
      </li>
			<li>With timing values set but drive-down-time-to-close equal to drive-down-time-to-100 and drive-up-time-to-100 equal 0 
			the device is considered to only vary between 0 and 100 (100 being completely closed)
      </li>
			<li>With full timing values set the device is considerd a window shutter (Rolladen) with a difference between 
			covering the full window (position 100) and being completely closed (position 200)
      </li>
		</ul>

  </ul>
  <br>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="SOMFYattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. An example for the physical device is a CUL.<br>
        Note: The IODev has to be set, otherwise no commands will be sent!<br>
        If you have both a CUL868 and CUL433, use the CUL433 as IODev for increased range.
		</li><br>

    <a name="positionInverse"></a>
    <li>positionInverse<br>
        Inverse operation for positions instead of 0 to 100-200 the positions are ranging from 100 to 10 (down) and then to 0 (closed). The pos set command will point in this case to the reversed pos values. This does NOT reverse the operation of the on/off command, meaning that on always will move the shade down and off will move it up towards the initial position.
		</li><br>

    <a name="additionalPosReading"></a>
    <li>additionalPosReading<br>
        Position of the shutter will be stored in the reading <code>pos</code> as numeric value. 
        Additionally this attribute might specify a name for an additional reading to be updated with the same value than the pos.
		</li><br>

    <a name="rolling-code"></a>
    <li>rolling-code &lt; 4 digit hex &gt; <br>
        Can be used to overwrite the rolling-code manually with a new value (rolling-code will be automatically increased with every command sent)
        This requires also setting enc-key: only with bot attributes set the value will be accepted for the internal reading
		</li><br>

    <a name="enc-key"></a>
    <li>enc-key &lt; 2 digit hex &gt; <br>
        Can be used to overwrite the enc-key manually with a new value 
        This requires also setting rolling-code: only with bot attributes set the value will be accepted for the internal reading
		</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values, each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or comma(,)
        then split not by space but by this character, enabling to embed spaces.
        Examples:<ul><code>
        attr store eventMap on:open off:closed<br>
        attr store eventMap /on-for-timer 10:open/off:closed/<br>
        set store open
        </code></ul>
        </li><br>

    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <a name="attrdummy"></a>
    <li>dummy<br>
    Set the device attribute dummy to define devices which should not
    output any radio signals. Associated notifys will be executed if
    the signal is received. Used e.g. to react to a code from a sender, but
    it will not emit radio signal if triggered in the web frontend.
    </li><br>

    <li><a href="#loglevel">loglevel</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the model type of the device.
        The attributes will (currently) not be used by the fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands
        (e.g. "on" or "off" to a switch, "dim..%" to dimmers etc.).<br>
        The spelling of the model names are as quoted on the printed
        documentation which comes which each device. This name is used
        without blanks in all lower-case letters. Valid characters should be
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should be ommited.<br>
        Here is a list of "official" devices:<br>
          <b>Receiver/Actor</b>: somfyblinds<br>
    </li><br>


    <a name="ignore"></a>
    <li>ignore<br>
        Ignore this device, e.g. if it belongs to your neighbour. The device
        won't trigger any FileLogs/notifys, issued commands will silently
        ignored (no RF signal will be sent out, just like for the <a
        href="#attrdummy">dummy</a> attribute). The device won't appear in the
        list command (only if it is explicitely asked for it), nor will it
        appear in commands which use some wildcard/attribute as name specifiers
        (see <a href="#devspec">devspec</a>). You still get them with the
        "ignored=1" special devspec.
        </li><br>

    <a name="drive-down-time-to-100"></a>
    <li>drive-down-time-to-100<br>
        The time the blind needs to drive down from "open" (pos 0) to pos 100.<br>
		In this position, the lower edge touches the window frame, but it is not completely shut.<br>
		For a mid-size window this time is about 12 to 15 seconds.
        </li><br>

    <a name="drive-down-time-to-close"></a>
    <li>drive-down-time-to-close<br>
        The time the blind needs to drive down from "open" (pos 0) to "close", the end position of the blind.<br>
        Note: If set, this value always needs to be higher than drive-down-time-to-100
		This is about 3 to 5 seonds more than the "drive-down-time-to-100" value.
        </li><br>

    <a name="drive-up-time-to-100"></a>
    <li>drive-up-time-to-100<br>
        The time the blind needs to drive up from "close" (endposition) to "pos 100".<br>
		This usually takes about 3 to 5 seconds.
        </li><br>

    <a name="drive-up-time-to-open"></a>
    <li>drive-up-time-to-open<br>
        The time the blind needs drive up from "close" (endposition) to "open" (upper endposition).<br>
        Note: If set, this value always needs to be higher than drive-down-time-to-100
		This value is usually a bit higher than "drive-down-time-to-close", due to the blind's weight.
        </li><br>

  </ul>
</ul>



=end html
=cut

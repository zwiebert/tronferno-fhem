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

package Tronferno;

use constant MODNAME => 'Tronferno';
use constant {
    FDT_SUN => 'sun',
    FDT_PLAIN => 'plain',
    FDT_CENTRAL => 'central',
    FDT_RECV => 'receiver',
    DEF_INPUT_DEVICE => 'default',
    ATTR_AUTOCREATE_NAME => 'create',
    ATTR_AUTOCREATE_IN => 'in',
    ATTR_AUTOCREATE_OUT => 'out',
    ATTR_AUTOCREATE_DEFAULT => 'default',
};
my $msb2fdt = { '10' => FDT_PLAIN, '20' => FDT_SUN, '80' => FDT_CENTRAL,  '90' => FDT_RECV };

my $def_mcuaddr = 'fernotron.fritz.box.';

sub X_Define($$) {
    my ($hash, $def) = @_;
    my @a       = split("[ \t][ \t]*", $def);
    my $name    = $a[0];
    my $address = $a[1];
    my $defptr  = $main::modules{+MODNAME}{defptr};
    my $is_iDev = 0;

    my ($a, $g, $m, $iodev, $mcu_addr) = (0, 0, 0, undef, $def_mcuaddr);
    my $u = 'wrong syntax: define <name> Tronferno a=ID [g=N] [m=N]';
    my $scan = 0;
    my $input = 0;

    $defptr->{oDevs} = {} unless $defptr->{oDevs};
    $defptr->{iDevs} = {} unless $defptr->{iDevs};
    $defptr->{aDevs} = {} unless $defptr->{aDevs};

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
        } elsif ($key eq 'scan' or $key eq 'input' && $value eq 'all') {
            $is_iDev = 1;
            $scan = 1;
            $main::modules{+MODNAME}{defptr}{+DEF_INPUT_DEVICE} = $hash;
            $hash->{helper}{inputKey} = DEF_INPUT_DEVICE;
            $hash->{helper}{ferInputType} = 'scan';
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

    $main::modules{+MODNAME}{defptr}{$def_match} = $hash;
    #main::Log3($hash, 0, "def_match: $def_match");

    $defptr->{aDevs}{"$hash"} = $hash;
    if ($is_iDev) {
        $defptr->{iDevs}{"$hash"} = $hash;
        delete ($defptr->{oDevs}{"$hash"});
    } else {
        delete ($defptr->{iDevs}{"$hash"});
        $defptr->{oDevs}{"$hash"} = $hash;
    }

    return undef;
}


sub X_Undef($$) {
    my ($hash, $name) = @_;
    my $defptr  = $main::modules{+MODNAME}{defptr};

    # remove deleted input devices from defptr
    my $key = $hash->{helper}{inputKey};
    delete $defptr->{$key} if (defined($key));

    delete ($defptr->{aDevs}{"$hash"});
    delete ($defptr->{oDevs}{"$hash"});
    delete ($defptr->{iDevs}{"$hash"});

    return undef;
}

sub transmit_by_socket($$) {
    my ($hash, $req) = @_;
    my $name = $hash->{NAME};

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

sub transmit($$) {
    my ($hash, $req) = @_;
    my $io   = $hash->{IODev};
    my $name = $hash->{NAME};


    if (exists($io->{NAME})) {
        # send message to pyhsical I/O device TronfernoMCU
        return 'error: IO device not open' unless (main::ReadingsVal($io->{NAME}, 'state', '') eq 'opened');
        main::IOWrite($hash, 'mcu', $req);
        return undef;
    } else {
        #no I/O device seems to be defined. send directly via TCP socket
        return transmit_by_socket ($hash, $req);
    }

    return undef;
}

sub build_cmd_cli($$$) {
    my ($hash, $cmd, $c) = @_;
    my $name = $hash->{NAME};

    my $a   = ($cmd eq 'pair') ? '?' : $hash->{helper}{ferid_a};
    my $g   = $hash->{helper}{ferid_g};
    my $m   = $hash->{helper}{ferid_m};
    my $r   = int(main::AttrVal($name, 'repeats', '1'));

    my $msg = "$cmd a=$a g=$g m=$m c=$c r=$r mid=82;";
    main::Log3($hash, 3, "$name:command: $msg");
    return $msg;
}

sub build_cmd_json($$$) {
    my ($hash, $cmd, $c) = @_;
    my $name = $hash->{NAME};

    my $a   = ($cmd eq 'pair') ? '"?"' : $hash->{helper}{ferid_a};
    my $g   = $hash->{helper}{ferid_g};
    my $m   = $hash->{helper}{ferid_m};
    my $r   = int(main::AttrVal($name, 'repeats', '1'));

    my $msg = "{\"to\":\"tfmcu\",\"$cmd\":{\"a\":$a,\"g\":$g,\"m\":$m,\"c\":\"$c\",\"r\":$r,\"mid\":82}};";
    main::Log3($hash, 3, "$name:command: $msg");
    return $msg;
}

sub build_cmd($$$) {
    my ($hash, $cmd, $c) = @_;
    my $mcu_chip = $hash->{IODev}->{'mcu-chip'};
    print "test: $mcu_chip\n";
    if ($mcu_chip && $mcu_chip eq 'esp32') {
        build_cmd_json($hash, $cmd, $c);
    } else {
        build_cmd_cli($hash, $cmd, $c);
    }
}

sub build_timer($$) {
    my ($hash, $opts) = @_;
    my $name = $hash->{NAME};

    my $a   = $hash->{helper}{ferid_a};
    my $g   = $hash->{helper}{ferid_g};
    my $m   = $hash->{helper}{ferid_m};
    #my $r   = int(main::AttrVal($name, 'repeats', '1'));
    $opts = " $opts" if $opts;
    my $msg = "timer a=$a g=$g m=$m mid=82$opts;";
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

sub X_Set($$@) {
    my ($hash, $name, $cmd, $a1) = @_;
    my $is_on = ($a1 // 0) eq 'on';
    my $is_off = ($a1 // 0) eq 'off';
    my $result = undef;

    return "\"set $name\" needs at least one argument" unless (defined($cmd));

    my $u = "unknown argument $cmd choose one of ";


    # handle input devices here
    my $inputType = $hash->{helper}{ferInputType};
    if (defined($inputType)) {
        if ($cmd eq '?') {
            if ($hash->{helper}{ferInputType} eq FDT_SUN) {
                return $u . 'on:noArg off:noArg';
            } elsif ($hash->{helper}{ferInputType} eq FDT_PLAIN) {
                return $u . 'up:noArg down:noArg stop:noArg';
            } elsif ($hash->{helper}{ferInputType} eq FDT_CENTRAL) {
                return $u . 'up:noArg down:noArg stop:noArg';
            }
            return $u; #default input device takes no arguments
        }

        if ($inputType eq FDT_PLAIN) {
            if ($cmd eq 'stop' || $cmd eq 'up' || $cmd eq 'down') {
                main::readingsSingleUpdate($hash, 'state', $cmd, 1)
            }
        } elsif ($inputType eq FDT_CENTRAL) {
            if ($cmd eq 'stop' || $cmd eq 'up' || $cmd eq 'down') {
                main::readingsSingleUpdate($hash, 'state', $cmd, 1)
            }
        } elsif ($inputType eq FDT_SUN) {
            if ($cmd eq 'on' || $cmd eq 'off') {
                main::readingsSingleUpdate($hash, 'state', $cmd, 1)
            }
        } else {
            return "unsupported input type: $inputType";
        }
        return undef;
    }

    #handle output devices here
    if ($cmd eq '?') {
        my $res = "unknown argument $cmd choose one of ";
        foreach my $key (get_commandlist()) {
            $res .= " $key:noArg";
        }
        return $res
            . ' position:slider,0,50,100'
            . ' manual:on,off'
            . ' sun-auto:on,off'
            . ' random:on,off'
            . ' astro:on,off,-60,-50,-30,-20,-10,+10,+20,+30,+40,+50,+60'
            . ' daily'
            . ' weekly'
            ;
    } elsif (exists $map_send_cmds->{$cmd}) {
        my $req = build_cmd($hash, 'send', $map_send_cmds->{$cmd});
        my $res = transmit($hash, $req);
        return $res if ($res);
    } elsif (exists $map_pair_cmds->{$cmd}) {
        my $req = build_cmd($hash, 'pair', $map_pair_cmds->{$cmd});
        my $res = transmit($hash, $req);
        return $res if ($res);
    } elsif ($cmd eq 'position') {
        return "\"set $name $cmd\" needs one argument" unless (defined($a1));
        my $percent = $a1;
        my $c = 'up';
        if ($percent eq '0') {
            $c = 'down';
        } elsif ($percent eq '50') {
            $c = 'sun-down';
        } elsif ($percent eq '99') {
            $c = 'stop';
        }
        my $req = build_cmd($hash, 'send', $c);
        my $res = transmit($hash, $req);
    } elsif ($cmd eq 'manual') {
        return transmit($hash, build_timer($hash, $is_on ? 'f=kMi' : 'f=kmi'));
    } elsif ($cmd eq 'sun-auto') {
        return transmit($hash, build_timer($hash, $is_on ? 'f=kSi' : 'f=ksi'));
    } elsif ($cmd eq 'random') {
        return transmit($hash, build_timer($hash, $is_on ? 'f=kRi' : 'f=kri'));
    } elsif ($cmd eq 'astro') {
        #TODO: check validity of of $a1
        my $minutes = $is_on ? 0 : int($a1);
        my $msg = $is_off ? 'f=kai' : 'f=kAi astro='.$minutes;
        return transmit($hash, build_timer($hash, $msg));
    } elsif ($cmd eq 'daily') {
        #TODO: check validity of of $a1
        my $msg = $is_off ? 'f=kdi daily=--' : 'f=kDi daily='.$a1;
        return transmit($hash, build_timer($hash, $msg));
    } elsif ($cmd eq 'weekly') {
        #TODO: check validity of of $a1
        my $msg = $is_off ? 'f=kwi weekly=--++++++' : 'f=kWi weekly='.$a1;
        return transmit($hash, build_timer($hash, $msg));
    } else {
        return "unknown argument $cmd choose one of "
            . join(' ', get_commandlist())
            . ' position manual sun-auto random astro daily weekly';
    }

    return undef;
}

sub X_Get($$$@) {
    my ($hash, $name, $opt, $a1, $a2, $a3) = @_;
    my $result = undef;

    return "\"get $name\" needs at least one argument" unless (defined($opt));

    my $u = "unknown argument $opt, choose one of ";


    # handle input devices here
    my $inputType = $hash->{helper}{ferInputType};
    if (defined($inputType)) {
        return $u; #input device has not options to get
    }

    #handle output devices here
    if ($opt eq '?') {
        return $u . 'timer:noArg';
    } elsif ($opt eq 'timer') {
        return transmit($hash, build_timer($hash, 'f=ukI'));
    } else {
        return $u . 'timer';
    }

    return undef;
}


sub parse_position {
    my ($io_hash, $data) = @_;
    my $name = $io_hash->{NAME};
    my ($a, $g, $m, $p, $mm) = (0, 0, 0, 0, undef);
    my $result = undef;
    foreach my $arg (split(/\s+/, $data)) {
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
                    my $hash = $main::modules{+MODNAME}{defptr}{$def_match}; #FIXME: add support for $a different than zero
                    if ($hash) {
                        main::readingsSingleUpdate($hash, 'state',  $p, 1);
                        $result = $hash->{NAME};
                    }
                }
            }
        }

        return $result;

    } else {
        my $def_match = "0,$g,$m";
        #main::Log3($io_hash, 3, "def_match: $def_match");
        my $hash = $main::modules{+MODNAME}{defptr}{$def_match}; #FIXME: add support for $a different than zero

        if ($hash) {
            main::readingsSingleUpdate($hash, 'state',  $p, 1);
            # R�ckgabe des Ger�tenamens, f�r welches die Nachricht bestimmt ist.
            return $hash->{NAME};
        } elsif ($g == 0) {
            for $g (1..7) {
                for $m (1..7) {
                    my $hash = $main::modules{+MODNAME}{defptr}{"0,$g,$m"};
                    if ($hash) {
                        main::readingsSingleUpdate($hash, 'state',  $p, 1);
                        $result = $hash->{NAME};
                    }
                }
            }
            return $result;
        } elsif ($m == 0) {
            for $m (1..7) {
                my $hash = $main::modules{+MODNAME}{defptr}{"0,$g,$m"};
                if ($hash) {
                    main::readingsSingleUpdate($hash, 'state',  $p, 1);
                    $result = $hash->{NAME};
                }
            }
            return $result;
        }
    }
    return undef;
}

# update Reading of default input device, if there was no matching input device
sub defaultInputMakeReading($$$$$$) {
    my ($hash, $fdt, $a, $g, $m, $c) = @_;

    my $kind = $fdt;
    $a = sprintf("%06x", $a);

    return undef unless $kind;

    my $gm = $kind eq FDT_CENTRAL ? " g=$g m=$m" : '';

    ### combine parts and update reading
    my $human_readable = "$kind a=$a$gm c=$c";
    my $state = "$kind:$a" . ($kind eq FDT_CENTRAL ? "-$g-$m" : '')  . ":$c";
    $state =~ tr/ /:/; # don't want spaces in reading
    my $do_trigger =  !($kind eq FDT_RECV || $kind eq 'unknown'); # unknown and receiver should not trigger events

    $hash->{received_HR} = $human_readable;
    main::readingsSingleUpdate($hash, 'state',  $state, $do_trigger);
    return 1;
}

sub parse_c {
    my ($io_hash, $data) = @_;
    my $name = $io_hash->{NAME};
    my ($a, $g, $m, $p, $fdt, $c) = (0, 0, 0, 0, "", "");
    my $result = undef;
    foreach my $arg (split(/\s+/, $data)) {
        my ($key, $value) = split('=', $arg);

        if ($key eq 'a') {
            $a = hex($value);
        } elsif ($key eq 'g') {
            $g = int($value);
            return "out of range value $g for g. expected: 0..7" unless (0 <= $g && $g <= 7);
        } elsif ($key eq 'm') {
            $m = int($value);
            return "out of range value $m for m. expected: 0..7" unless (0 <= $m && $m <= 7);
        } elsif ($key eq 'c') {
            $c = $value;
        } elsif ($key eq 'type') {
            $fdt = $value;
        }
    }

    my $default =  $main::modules{+MODNAME}{defptr}{+DEF_INPUT_DEVICE};
    my $hash = $default;# getInputDeviceByA($a);

    return 'UNDEFINED Tronferno_Scan Tronferno scan' unless ($default || $hash); # autocreate default input device

    if ($hash->{helper}{ferInputType} eq 'scan') {
        defaultInputMakeReading($default, $fdt, $a, $g, $m, $c) or return undef;
    } else {
        #inputMakeReading($fsb, $hash) or return undef;
    }
    return $hash->{NAME}
}

sub parse_timer {
    my ($io_hash, $data) = @_;
    my $name = $io_hash->{NAME};
    my ($a, $g, $m, $p, $fdt, $c) = (0, 0, 0, 0, "", "");
    my $defptr  = $main::modules{+MODNAME}{defptr};
    my $result = undef;
    my $timer_string = '';
    my $flags = '';
    my $timer = {
        daily => 'off',
        weekly => 'off',
        astro => 'off',
    };


    foreach my $arg (split(/\s+/, $data)) {
        my ($key, $value) = split('=', $arg);

        if ($key eq 'a') {
            $a = hex($value);
        } elsif ($key eq 'g') {
            $g = int($value);
            return undef unless (0 <= $g && $g <= 7);
        } elsif ($key eq 'm') {
            $m = int($value);
            return undef unless (0 <= $m && $m <= 7);
        } elsif ($key) {
            $timer_string .= "$key=$value ";
            if ($key eq 'f') {
                $flags = $value;
            } else {
                $timer->{$key} = $value;
            }
        }
    }

    # do it here to overwrite any long options using 1/0 instead on/off
    if ($flags) {
        $timer->{'sun-auto'} = index($flags, 'S') >= 0 ? 'on' : 'off';
        $timer->{'random'} = index($flags, 'R') >= 0 ? 'on' : 'off';
        $timer->{'manual'} = index($flags, 'M') >= 0 ? 'on' : 'off';
#       $timer->{'daily'} = index($flags, 'D') >= 0 ? 'on' : 'off';
#       $timer->{'weekly'} = index($flags, 'W') >= 0 ? 'on' : 'off';
#       $timer->{'astro'} = index($flags, 'A') >= 0 ? 'on' : 'off';
    }

    main::Log3($io_hash, 4, "Tronferno: a=$a, g=$g, m=$m");


    my $hash = undef;

    foreach my $h (values %{$defptr->{oDevs}}) {
        if ($h->{helper}{ferid_g} eq "$g"
            && $h->{helper}{ferid_m} eq "$m") {
            $hash = $h;
            main::readingsBeginUpdate($hash);
            $hash->{'debug.timer.string'} = $timer_string;
            while(my($k, $v) = each %$timer) {
            #    $hash->{"automatic.$k"} = "$v";
                main::readingsBulkUpdateIfChanged($hash, "automatic.$k", "$v");
            }
            main::readingsEndUpdate($hash, 1);
        }
    }

    return $hash->{NAME}
}


sub X_Parse {
    my ($io_hash, $message) = @_;
    my $name = $io_hash->{NAME};
    my $result = undef;

    if ($message =~ /^TFMCU#U:position:\s*(.+)$/) {
        return parse_position($io_hash, $1);
    } elsif ($message =~ /^TFMCU#[Cc]:(.+)$/) {
        return parse_c($io_hash, $1);
    } elsif ($message =~ /^TFMCU#timer (.+)$/) {
        return parse_timer($io_hash, $1);
    }
    return undef;
}



sub X_Attr(@) {
    my ($cmd, $name, $attrName, $attrValue) = @_;

    # $cmd  - Vorgangsart - kann die Werte "del" (l�schen) oder "set" (setzen) annehmen
    # $name - Ger�tename
    # $attrName/$attrValue sind Attribut-Name und Attribut-Wert

    if ($cmd eq "set") {
        if ($attrName eq 'repeats') {
            my $r = int($attrValue);
            return "invalid argument '$attrValue'. Expected: 0..5" unless (0 <= $r and $r <= 5);
        }
    }
    return undef;
}




package main;

sub Tronferno_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = 'Tronferno::X_Define';
    $hash->{SetFn}    = 'Tronferno::X_Set';
    $hash->{GetFn}    = 'Tronferno::X_Get';
    $hash->{ParseFn}  = 'Tronferno::X_Parse';
    $hash->{UndefFn}  = 'Tronferno::X_Undef';
    $hash->{AttrFn}   =  'Tronferno::X_Attr';
    $hash->{AttrList} = 'IODev repeats:0,1,2,3,4,5';
    $hash->{Match}    = '^TFMCU#.+';
}


1;
=pod
=item device
=item summary controls shutters via Tronferno-MCU
=item summary_DE steuert Roll�den �ber Tronferno-MCU

=begin html

<a name="Tronferno"></a>

<h3>Tronferno</h3>

<i>Tronferno</i> is a logic module to control Fernotron shutters via radio frequency. To do this, it utilizes the <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a> micro controller hardware.

<ul>
<li>Required I/O device: <i>TronfernoMCU</i></li>
<li>Protocol limitations: It's uni-directional. No information of the receivers status is available. So it's not best suited for automation without user attention.</li>
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

<a name="Tronfernoattr"></a>
<h6>Attributes</h6>
<ul>
  <li><a name="repeats">repeats N</a><br>
        repeat sent messages N additional times to increase the chance of successfull delivery (default: 1 repeat)
  </li>
</ul>

<a name=Tronfernoset></a>
<h4>Set Commands</h4>
<ul>
  <a name=up></a>
  <li>up - open shutter</li>

  <a name=down></a>
  <li>down - close shutter</li>

  <a name=stop></a>
  <li>stop - stop moving shutter</li>

  <a name=set></a>
  <li>set  - activate pair/unpair mode on Fernotron receiver</li>

  <a name=sun-down></a>
  <li>sun-down - move shutter to sun position (but only if sun automatic is enabled and not below sun position)</li>

  <a name=sun-up></a>
  <li>sun-up - when at sun-position the shutter will be fully opened with this command (does nothing when not at sun position)</li>

  <a name=sun-inst></a>
  <li>sun-inst - set the current position as sun position</li>

  <a name=position></a>
  <li>position - set position to 0 (down), 50 (sun-down), 100 (up), 99 (stop). (used  by alexa)</li>

  <a name=sun-auto></a>
  <li>sun-auto - switch on/off sun-sensor commands of a Fernotron device. (if off, it ignores command sun-down)</li>

  <a name=random></a>
  <li>random - switch on/of random-timer of Fernotron device</li>

  <a name=manual></a>
  <li>manual - switch on/off automatic shutter movement<br>
     The manual mode prevents all automatic shutter movement by internal timers or paired sensors<br>
  <ul>
   <li><code>set NAME manual on</code></li>
   <li><code>set NAME manual off</code></li>
  </ul>

    <p><small>Note: This is a kludge. It reprograms the Fernotron device with empty timers and disables sun-auto. When 'manual' is switched off again, the timer data, which was stored inside the MCU will be reprogrammed.  Not sure why this is done this way by the original central 2411. There are Fernotron receivers with a button for manual-mode, but the RF controlled motors seems to have no manual flag?</small>
</li>

<a name=random></a>
<li>random - switch on/off the random timer of a Fernotron device</li>

<a name=daily></a>
<li>daily - switch off or set the daily timer of a Fernotron device<br>
   Format: HHMMHHMM for up/down timers. Use '-' instead HHMM to disable the up or down timer.<br>
   <ul>
    <li><code>set NAME daily off</code> disables daily-timer</li>
    <li><code>set NAME daily "0700-"</code> up by daily-timer at 0700</li>
    <li><code>set NAME daily "-1200"</code> down at 1200</li>
  </ul>
</li>

<a name=weekly></a>
<li>weekly - switch off or set the weekly timer of a Fernotron device<br>
   Format: like daily (HHMMHHMM) but seven times. Starts at Monday. A '+' can be used to copy the previous day.<br>
   <ul>
     <li><code>set NAME weeky off</code> disables weekly-timer</li>
     <li><code>set NAME weekly "0700-++++0900-+"</code>  up by weekly-timer at Mon-Fri=0700, Sat-Sun=0900</li>
     <li><code>set NAME weekly "0600-0530-+++1130-0800-"</code> up at Mon=0600, Tue-Fri=0530, Sat=1130, Sun=0800</li>
   </ul>
</li>

<a name=astro></a>
<li>astro - switch on/off or set the astro (civil dusk) timer of a Fernotron device<br>
    The shutter goes down at civil dusk or some minutes before or after if you provide a -/+ minute offset.<br>
    <ul>
      <li><code>set NAME astro off</code> disables astro-timer</li>
      <li><code>set NAME astro on</code> down by astro-timer at civil dusk</li>
      <li><code>set NAME astro "-10"</code> down at 10 minutes before civil dusk</li>
      <li><code>set NAME astro 10</code> down at 10 minutes after civil dusk</li>
    </ul>
</li>

  <a name=xxx_pair></a>
  <li>xxx_pair - Lets MCU pair the next received sender to this shutter (Paired senders will influence the shutter position)</li>

  <a name=xxx_unpair></a>
  <li>xxx_unpair - Lets MCU unpair the next received Sender to this shutter</li>
</ul>


<h4>Examples</h4>


<ul>
      <li>first define the I/O device, so it exists before any myShutter_xx devices which are depending on it.<br>
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
# eval: (my-buffer-local-set-key (kbd "C-c C-c") (lambda () (interactive) (shell-command "cd ../../.. && ./build.sh")))
# eval: (my-buffer-local-set-key (kbd "C-c c") 'compile)
# End:

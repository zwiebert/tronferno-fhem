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

package main;

sub AssignIoPort($;$);
sub AttrVal($$$);
sub IOWrite($@);
sub Log3($$$);
sub ReadingsVal($$$);
sub readingsBeginUpdate($);
sub readingsBulkUpdateIfChanged($$$@);
sub readingsEndUpdate($$);
sub readingsSingleUpdate($$$$);

sub Tronferno_Initialize($);

sub JSON::from_json;

package Tronferno;

sub X_Attr(@);
sub X_Define($$);
sub X_Get($$$@);
sub X_Parse($$);
sub X_Set($$@);
sub X_Undef($$);
sub req_build_cmd($$$);
sub req_build_cmd_cli($$$);
sub req_build_cmd_json($$$);
sub req_build_timer_cli($$);
sub defaultInputMakeReading($$$$$$);
sub mod_dispatch_pct($$$$);
sub mod_dispatch_pct_obj($$);
sub get_commandlist();
sub mod_parse_cmd($$);
sub mod_parse_json($$);
sub mod_parse_position($$);
sub mod_parse_timer($$);
sub pctReadingsUpdate($$);
sub pctTrans($$);
sub req_build_position($);
sub req_position($);
sub transmit($$);
sub transmit_by_socket($$);

sub mod_dispatch_shs($$$$);
sub mod_dispatch_shs_obj($$);
sub mod_getMatchingDevices($);

use IO::Socket;
require JSON;


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

sub X_Define($$) {
    my ($hash, $def) = @_;
    my @args    = split("[ \t][ \t]*", $def);
    my $name    = $args[0];
    my $address = $args[1];
    my $defptr  = $main::modules{+MODNAME}{defptr};
    my $is_iDev = 0;

    my ($ad, $g, $m, $iodev, $mcu_addr) = (0, 0, 0, undef, '');
    my $u = 'wrong syntax: define NAME Tronferno a=ID [g=N] [m=N]';
    my $scan = 0;
    my $input = 0;

    $defptr->{oDevs} = {} unless $defptr->{oDevs};
    $defptr->{iDevs} = {} unless $defptr->{iDevs};
    $defptr->{aDevs} = {} unless $defptr->{aDevs};
    $defptr->{cDevs} = {} unless $defptr->{cDevs};

    return $u if ($#args < 2);

    shift(@args);
    shift(@args);
    foreach my $o (@args) {
        my ($key, $value) = split('=', $o);

        if ($key eq 'a') {
            $ad = hex($value);
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
        } elsif ($key eq 'scan' || ($key eq 'input' && $value eq 'all')) {
            $is_iDev = 1;
            $scan = 1;
            $main::modules{+MODNAME}{defptr}{+DEF_INPUT_DEVICE} = $hash;
            $hash->{helper}{inputKey} = DEF_INPUT_DEVICE;
            $hash->{helper}{ferInputType} = 'scan';
        } else {
            return "$name: unknown argument $o in define";    #FIXME add usage text
        }
    }

    $hash->{helper}{ferid_a} = $ad;
    $hash->{helper}{ferid_g} = $g;
    $hash->{helper}{ferid_m} = $m;
    $hash->{helper}{mcu_addr} = $mcu_addr;

    main::AssignIoPort($hash, $iodev);

    $defptr->{aDevs}{"$hash"} = $hash;
    if ($is_iDev) {
        $defptr->{iDevs}{"$hash"} = $hash;
        delete ($defptr->{oDevs}{"$hash"});
    } else {
        delete ($defptr->{iDevs}{"$hash"});
        $defptr->{oDevs}{"$hash"} = $hash;
    }

    $defptr->{cDevs} = $hash unless $ad;

    req_position($hash);

    return undef;
}

sub pctTrans($$) {
    my ($hash, $pct) = @_;
    return $pct if 0 == main::AttrVal($hash->{NAME}, 'pctInverse', 0);
    return 100 - $pct;
}
sub pctReadingsUpdate($$) {
        my ($hash, $pct) = @_;
        main::readingsSingleUpdate($hash, 'state',  pctTrans($hash, $pct), 1);
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
    delete ($defptr->{cDevs}{"$hash"});

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

sub req_build_cmd_cli($$$) {
    my ($hash, $cmd, $c) = @_;
    my $name = $hash->{NAME};

    my $ad   = ($cmd eq 'pair') ? '?' : $hash->{helper}{ferid_a};
    my $g   = $hash->{helper}{ferid_g};
    my $m   = $hash->{helper}{ferid_m};
    my $r   = int(main::AttrVal($name, 'repeats', '1'));
    my $x   =  ($c =~ /^[0-9?]+$/) ? 'p' : 'c';

    my $msg = "$cmd a=$ad g=$g m=$m $x=$c r=$r mid=82;";
    main::Log3($hash, 3, "$name:command: $msg");
    return $msg;
}

sub req_build_cmd_json($$$) {
    my ($hash, $cmd, $c) = @_;
    my $name = $hash->{NAME};

    my $ad   = ($cmd eq 'pair') ? '"?"' : $hash->{helper}{ferid_a};
    my $g   = $hash->{helper}{ferid_g};
    my $m   = $hash->{helper}{ferid_m};
    my $r   = int(main::AttrVal($name, 'repeats', '1'));
    my $x   =  ($c =~ /^[0-9]+$/) ? 'p' : 'c';


    my $msg = "{\"to\":\"tfmcu\",\"$cmd\":{\"a\":$ad,\"g\":$g,\"m\":$m,\"$x\":\"$c\",\"r\":$r,\"mid\":82}};";
    main::Log3($hash, 3, "$name:command: $msg");
    return $msg;
}

sub req_build_cmd($$$) {
    my ($hash, $cmd, $c) = @_;
    my $mcu_chip = $hash->{IODev}->{'mcu-chip'};
    if ($mcu_chip && $mcu_chip eq 'esp32') {
        req_build_cmd_json($hash, $cmd, $c);
    } else {
        req_build_cmd_cli($hash, $cmd, $c);
    }
}

sub req_build_timer_cli($$) {
    my ($hash, $opts) = @_;
    my $name = $hash->{NAME};

    my $ad   = $hash->{helper}{ferid_a};
    my $g   = $hash->{helper}{ferid_g};
    my $m   = $hash->{helper}{ferid_m};
    #my $r   = int(main::AttrVal($name, 'repeats', '1'));
    $opts = " $opts" if $opts;
    my $msg = "timer a=$ad g=$g m=$m mid=82$opts;";
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

sub req_build_position($) {
    my ($hash) = @_;
    return req_build_cmd($hash, 'send', '?');
}
sub req_position($) {
    my ($hash) = @_;
    my $req = req_build_position($hash);
    my $res = transmit($hash, $req);
    return $res;
}

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
            . ' position:slider,0,5,100'
            . ' pct:slider,0,5,100'
            . ' manual:on,off'
            . ' sun-auto:on,off'
            . ' random:on,off'
            . ' astro:on,off,-60,-50,-30,-20,-10,+10,+20,+30,+40,+50,+60'
            . ' daily'
            . ' weekly'
            ;
    } elsif (exists $map_send_cmds->{$cmd}) {
        my $req = req_build_cmd($hash, 'send', $map_send_cmds->{$cmd});
        my $res = transmit($hash, $req);
        return $res if ($res);
    } elsif (exists $map_pair_cmds->{$cmd}) {
        my $req = req_build_cmd($hash, 'pair', $map_pair_cmds->{$cmd});
        my $res = transmit($hash, $req);
        return $res if ($res);
    } elsif ($cmd eq 'position' || $cmd eq 'pct') {
        return "\"set $name $cmd\" needs one argument" unless (defined($a1));
        my $percent = pctTrans($hash, $a1);
        my $c = $percent;
        #use some special percent number as commands (for alexa)
        if ($percent eq '2') {
            $c = 'sun-down';
        } elsif ($percent eq '1') {
            $c = 'stop';
        }
        my $req = req_build_cmd($hash, 'send', $c);
        my $res = transmit($hash, $req);
    } elsif ($cmd eq 'manual') {
        return transmit($hash, req_build_timer_cli($hash, $is_on ? 'f=kMi' : 'f=kmi'));
    } elsif ($cmd eq 'sun-auto') {
        return transmit($hash, req_build_timer_cli($hash, $is_on ? 'f=kSi' : 'f=ksi'));
    } elsif ($cmd eq 'random') {
        return transmit($hash, req_build_timer_cli($hash, $is_on ? 'f=kRi' : 'f=kri'));
    } elsif ($cmd eq 'astro') {
        #TODO: check validity of of $a1
        my $minutes = $is_on ? 0 : int($a1);
        my $msg = $is_off ? 'f=kai' : 'f=kAi astro='.$minutes;
        return transmit($hash, req_build_timer_cli($hash, $msg));
    } elsif ($cmd eq 'daily') {
        #TODO: check validity of of $a1
        my $msg = $is_off ? 'f=kdi daily=--' : 'f=kDi daily='.$a1;
        return transmit($hash, req_build_timer_cli($hash, $msg));
    } elsif ($cmd eq 'weekly') {
        #TODO: check validity of of $a1
        my $msg = $is_off ? 'f=kwi weekly=--++++++' : 'f=kWi weekly='.$a1;
        return transmit($hash, req_build_timer_cli($hash, $msg));
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
        return transmit($hash, req_build_timer_cli($hash, 'f=ukI'));
    } else {
        return $u . 'timer';
    }

    return undef;
}

sub mod_transmit_json() {
}

sub mod_dispatch_forEachHash_callSub($$) {
    my ($hashes,$subRef) = @_;
    while (my ($key, $hash) = each (%$hashes)) {
        my @args = ($hash);
        $subRef->(@args);
    }
}

sub dispatch_mcuReappeared() {
    my $defptr = $main::modules{+MODNAME}{defptr};
    mod_dispatch_forEachHash_callSub($defptr->{cDevs}, \&req_position);
}

sub shsReadingsUpdate($$) {
    my ($hash, $shsgm) = @_;
    main::readingsSingleUpdate($hash, 'mcu.tag.NAME',  $shsgm->{'tag.NAME'}, 1) if exists($shsgm->{'tag.NAME'});
}

sub mod_getMatchingDevices($) {
    my ($args) = @_;
    my $defptr = $main::modules{+MODNAME}{defptr};
    my @result = ();
    for my $hash (values(%{$defptr->{aDevs}})) {
        next if exists($args->{m}) && $args->{m} != $hash->{helper}{ferid_m};
        next if exists($args->{g}) && $args->{g} != $hash->{helper}{ferid_g};
        next if exists($args->{IODev}) && $args->{IODev} != $hash->{IODev};
        next if exists($args->{a}) && $args->{a} != $hash->{helper}{ferid_a};
        next if exists($args->{inputType}) && $args->{ferInputType} != $hash->{helper}{ferInputType};
       # next if exists($args->{XX}) && $args->{XX} != $hash->{helper}{ferid_XX};

        $result[$#result+1] = $hash;
    }
    return \@result;
}
sub mod_dispatch_shs($$$$) {
    my ($io_hash, $g, $m, $shsgm) = @_;
    my $io_name = $io_hash->{NAME};
    my $hashes = mod_getMatchingDevices({IODev => $io_hash, g => $g, m => $m });
    my $result = undef;
    for my $hash (@$hashes) {
        shsReadingsUpdate($hash, $shsgm);
        $result = $hash;
    }
    return $result;
}

sub mod_dispatch_shs_obj($$) {
    my ($io_hash, $shs) = @_;
    my $hash = undef;
    while (my ($key, $value) = each (%$shs)) {
    	my $g = substr($key,0,1);
    	my $m = substr($key,1,1);
    	my $tmp = mod_dispatch_shs($io_hash,$g,$m,$value);
    	$hash = $tmp if $tmp;
    }
    return $hash->{NAME} if $hash;
    return undef;
}


sub mod_dispatch_pct_obj($$) {
    my ($io_hash, $pct) = @_;
    my $hash = undef;
    while (my ($key, $value) = each (%$pct)) {
    	my $g = substr($key,0,1);
    	my $m = substr($key,1,1);
    	my $tmp = mod_dispatch_pct($io_hash,$g,$m,$value);
    	$hash = $tmp if $tmp;
    }
    return $hash->{NAME} if $hash;
    return undef;
}

sub mod_dispatch_pct($$$$) {
    my ($io_hash, $g, $m, $p) = @_;
    my $hashes = mod_getMatchingDevices({IODev => $io_hash, g => $g, m => $m });
    print("$g,$m,$#$hashes <----hashes idx\n");
    my $result = undef;
    for my $hash (@$hashes) {
        pctReadingsUpdate($hash, $p);
        $result = $hash;
    }
    return $result;
}

sub mod_parse_position($$) {
    my ($io_hash, $data) = @_;
    my $name = $io_hash->{NAME};
    my ($ad, $g, $m, $p, $mm) = (0, 0, 0, 0, undef);
    my $result = undef;
    foreach my $arg (split(/\s+/, $data)) {
        my ($key, $value) = split('=', $arg);

        if ($key eq 'a') {
            $ad = hex($value);

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
        for my $g (0..7) {
            my $gm =hex($$mm[$g]);
            for my $m (0..7) {
                if ($gm & (1 << $m)) {
                    my $hash = mod_dispatch_pct($io_hash, $g,$m,$p);
                    $result =  $hash->{NAME} if $hash;
                }
            }
        }
    } else {
        my $hash = mod_dispatch_pct($io_hash, $g,$m,$p);
        $result =  $hash->{NAME} if $hash;
    }
    # TODO: is there a way to consume non matching postion events to avoid help-me messages in log file?

    return $result;
}

# update Reading of default input device, if there was no matching input device
sub defaultInputMakeReading($$$$$$) {
    my ($hash, $fdt, $ad, $g, $m, $c) = @_;

    my $kind = $fdt;
    $ad = sprintf("%06x", $ad);

    return undef unless $kind;

    my $gm = $kind eq FDT_CENTRAL ? " g=$g m=$m" : '';

    ### combine parts and update reading
    my $human_readable = "$kind a=$ad$gm c=$c";
    my $state = "$kind:$ad" . ($kind eq FDT_CENTRAL ? "-$g-$m" : '')  . ":$c";
    $state =~ tr/ /:/; # don't want spaces in reading
    my $do_trigger =  !($kind eq FDT_RECV || $kind eq 'unknown'); # unknown and receiver should not trigger events

    $hash->{received_HR} = $human_readable;
    main::readingsSingleUpdate($hash, 'state',  $state, $do_trigger);
    return 1;
}

sub mod_parse_cmd($$) {
    my ($io_hash, $data) = @_;
    my $name = $io_hash->{NAME};
    my ($ad, $g, $m, $p, $fdt, $c) = (0, 0, 0, 0, "", "");
    my $result = undef;
    foreach my $arg (split(/\s+/, $data)) {
        my ($key, $value) = split('=', $arg);

        if ($key eq 'a') {
            $ad = hex($value);
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
    my $hash = $default;# getInputDeviceByA($ad);

    return 'UNDEFINED Tronferno_Scan Tronferno scan' unless ($default || $hash); # autocreate default input device

    if ($hash->{helper}{ferInputType} eq 'scan') {
        defaultInputMakeReading($default, $fdt, $ad, $g, $m, $c) or return undef;
    } else {
        #inputMakeReading($fsb, $hash) or return undef;
    }
    return $hash->{NAME}
}

sub mod_parse_timer($$) {
    my ($io_hash, $data) = @_;
    my $name = $io_hash->{NAME};
    my ($ad, $g, $m, $p, $fdt, $c) = (0, 0, 0, 0, "", "");
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
            $ad = hex($value);
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

    main::Log3($io_hash, 4, "Tronferno: a=$ad, g=$g, m=$m");


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

sub mod_parse_json($$) {
    my ($io_hash, $json) = @_;
    my $obj = JSON::from_json($json);
    my $from = $obj->{from};
    return mod_dispatch_pct_obj($io_hash, $obj->{pct}) if (exists($obj->{pct}));
    return mod_dispatch_shs_obj($io_hash, $obj->{shs}) if (exists($obj->{shs}));
    return undef;
}

sub X_Parse($$) {
    my ($io_hash, $message) = @_;
    my $name = $io_hash->{NAME};
    my $result = undef;

    if ($message =~ /^TFMCU#[AU]:position:\s*(.+)$/) {
        return mod_parse_position($io_hash, $1);
    } elsif ($message =~ /^TFMCU#[Cc]:(.+)$/) {
        return mod_parse_cmd($io_hash, $1);
    } elsif ($message =~ /^TFMCU#timer (.+)$/) {
        return mod_parse_timer($io_hash, $1);
    } elsif ($message =~ /^TFMCU#JSON:(.+)$/) {
        return mod_parse_json($io_hash, $1);
    }
    return undef;
}



sub X_Attr(@) {
    my ($cmd, $name, $attrName, $attrValue) = @_;

    # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
    # $name - Gerätename
    # $attrName/$attrValue sind Attribut-Name und Attribut-Wert

    if ($cmd eq "set") {
        if ($attrName eq 'repeats') {
            my $r = int($attrValue);
            return "invalid argument '$attrValue'. Expected: 0..5" unless (0 <= $r and $r <= 5);
        }
        if ($attrName eq 'pctInverse') {
            my $v = int($attrValue);
            return "invalid argument '$attrValue'. Expected: 0..1" unless (0 <= $v and $v <= 1);
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
    $hash->{AttrFn}   = 'Tronferno::X_Attr';
    $hash->{AttrList} = 'IODev repeats:0,1,2,3,4,5 pctInverse:1,0';
    $hash->{Match}    = '^TFMCU#.+';
}


1;
=pod
=encoding utf-8
=item device
=item summary controls shutters via Tronferno-MCU
=item summary_DE steuert Rolläden über Tronferno-MCU

=begin html

<a name="Tronferno"></a>

<h3>Tronferno</h3>

<i>Tronferno</i> is a logic FHEM module to control Fernotron shutters via radio frequency. To do this, it utilizes the <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a> micro controller firmware.is a logic FHEM module to control shutters and power plugs and receive commands from transmitters and sensors using Fernotron protocol. This requires the pyhsical TronfernoMCU module and the  <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a>  MCU firmware.


<h4>Define</h4>

<p>
  <code>
    define  &lt;name&gt; Tronferno [a=ID] [g=N] [m=N] [input[=(plain|sun|central)]] [scan]<br>
  </code>

<p>
<ul>
  <li>a=ID : Device ID. Default is the ID of the original Central (stored in the MCU). To use, if a different ID needs to be used.<br>
             6-digit hex number following the pattern: 10xxxx=plain controller, 20xxxx=sun sensor, 80xxxx=central controller unit, 90xxxx=receiver</li>
  <li>g=N : group number (1-7)  or 0 (default) for all groups</li>
  <li>m=N : group member number (1-7) or 0 (default) for all group members</li>
  <li>scan : Defines a devie which receives alll incoming Fernotron message, if not comsumed by an explicit defined input device. This device will be auto-created as "Tronferno_Scan"</li>
  <li>input: Defines a device to receive Fernotron message for a given address (a/g/m)<br>
             The transmitter-types plain, sun oder central can be omitted, and will then be determined by the ID number<br>
 <li>Note: The options a/g/m have default value 0. It does not matter if these options are just omitted or set to value 0 like in a=0 g=0 m=0.</li>
</ul>

<p>  Incoming data is handled by input devices. There is one default input device, who handles all messages not matchin a defined input device. The default input device will be auto-created.
<p> Input devices are defined just like output devices, but with the parameter 'input' given in the define.

<h5>Examples of devices for transmitting</h5>
<ul>
<li><code>define tfmcu TronfernoMCU /dev/ttyUSB0</code> (define the required physical device first)</li>
<li><code>define roll21 Tronferno g=2 m=1</code> (shutter 1 in group 2)</li>
<li><code>define roll10 Tronferno g=1</code> (shutter-group 1)</li>
<li><code>define roll00 Tronferno</code> (all shutter-groups)</li>
<li><code>define plain_101234 Tronferno a=101234</code> (simulated plain sender 101234</li>
<li><code>define motor_0abcd Tronferno a=90abcd</code> (transmits direct to motor 0abcd. Add the leading digit 9 to the motor code to form an ID!)</li>
<li><code></code> </li>
</ul>
<h5>Examples of devices to receive</h5>
<ul>
<li><code>define myFernoSwitch Tronferno a=10abcd input</code> (plain transmitter as switch for up/down/stop)</li>
<li><code>define myFernoSun Tronferno a=20abcd input</code>  (sun sensor as on/off switch  (on: sun, off: no sun))</li>
<li><code> myFernoSwitch2 Tronferno g=2 m=3 input </code> (central unit as switch for up/down/stop)</li>
<li><code>define n_toggleHUEDevice3 notify myFernoSwitch:stop set HUEDevice3 toggle</code> (toggle Hue-lamp when pressing stop)</li>
<li><code>define n_toggleHUEDevice3 notify Tronferno_Scan:plain:1089ab:stop set HUEDevice3 toggle</code> (...like above but using the catch-all input device "scan")</li>
<li><code></code> </li>
</ul>




<h5>Three different methods to make messsages find their target Fernotron receiver</h5>
<ol>
  <li>Scan IDs of physical Fernotron controllers you own and copy their IDs in our FHEM output devices.  Use default Input device Fernotron_Scan to scan the ID first. Then use the ID to define your device. Here we have scanned the ID of our 2411 central resulting to 801234. Now define devices by using it
  </li>

  <li>Define Fernotron devices using invented IDs (like 100001, 100002, ...). Then pair these devices by sending a STOP command from it while the physical Fernotron receiver/motor is in pairing-mode (aka set-mode).
  </li>

<li> Receiver IDs to send directly to without pairing: RF controlled shutters may have a 5 digit code printed on or on a small cable sticker.
  Prefix that number with a 9 to get an valid ID for defining a device.</li>
</ol>

<h5>Three kinds of grouping</h5>

<ol>
  <li>groups and members are the same like in 2411. Groups are adressed using the 0 as wildcard.  (g=1 m=0 or g=0 m=1 or g=0 m=0) </li>

  <li> Like with plain controllers or sun sensors. Example: a (virtual) plain controller paired with each shutter of the entire floor.</li>

  <li> not possible with receiver IDs</li>
</ol>

<h5>Three examples</h5>
<ol>
  <li>
    <code>define myShutterGroup1 Tronferno g=1 m=0</code><br>
    <code>define myShutter11 Tronferno g=1 m=1</code><br>
    <code>define myShutter12 Tronferno g=1 m=2</code><br>
    ...
    <code>define myShutterGroup2 Tronferno g=2 m=0</code><br>
    <code>define myShutter21 Tronferno g=2 m=1</code><br>
    <code>define myShutter22 Tronferno g=2 m=2</code><br>
      </li>

  <li>
    <code>define myShutter1 Tronferno a=100001</code><br>
    <code>define myShutter2 Tronferno a=100002</code><br>
    Now activate Set-mode on the Fernotron receiver and send a STOP by the newly defined device you wish to pair with it.
 ...</li>

<li><code>define myShutter__0d123 Tronferno a=90d123</code></li>
</ol>

<a name="Tronfernoattr"></a>
<h4>Attributes</h4>
<ul>
  <li><a name="repeats">repeats N</a><br>
        repeat sent messages N additional times to increase the chance of successfull delivery (default: 1 repeat)
  </li>
  <li><a name="pctInverse">pctInverse 1|0</a><br>
        Invert position percents. Normal: Open=100%, Closed=0%. Inverted: Open=0%, Closed=100%
  </li>
</ul>

<a name=Tronfernoset></a>
<h4>Set</h4>
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
  <li>position - set position in percent. 0 is down/closed. 100 is up/open.  (for alexa: 1% is stop, 2% is sun-down)</li>

  <a name=pct></a>
  <li>pct - set position in percent. 0 is down/closed. 100 is up/open.  (for alexa: 1% is stop, 2% is sun-down)</li>

  <a name=sun-auto></a>
  <li>sun-auto - switch on/off sun-sensor commands of a Fernotron device. (if off, it ignores command sun-down)</li>

   <a name=manual></a>
  <li>manual - switch on/off automatic shutter movement<br>
     The manual mode prevents all automatic shutter movement by internal timers or paired sensors<br>
  <ul>
   <li><code>set &lt;name&gt; manual on</code></li>
   <li><code>set &lt;name&gt; manual off</code></li>
  </ul>

    <p><small>Note: This is a kludge. It reprograms the Fernotron device with empty timers and disables sun-auto. When 'manual' is switched off again, the timer data, which was stored inside the MCU will be reprogrammed.  Not sure why this is done this way by the original central 2411. There are Fernotron receivers with a button for manual-mode, but the RF controlled motors seems to have no manual flag?</small>
</li>

<a name=random></a>
<li>random - switch on/off the random timer of a Fernotron device</li>

<a name=daily></a>
<li>daily - switch off or set the daily timer of a Fernotron device<br>
   Format: HHMMHHMM for up/down timers. Use '-' instead HHMM to disable the up or down timer.<br>
   <ul>
    <li><code>set &lt;name&gt; daily off</code> disables daily-timer</li>
    <li><code>set &lt;name&gt; daily "0700-"</code> up by daily-timer at 0700</li>
    <li><code>set &lt;name&gt; daily "-1200"</code> down at 1200</li>
  </ul>
</li>

<a name=weekly></a>
<li>weekly - switch off or set the weekly timer of a Fernotron device<br>
   Format: like daily (HHMMHHMM) but seven times. Starts at Monday. A '+' can be used to copy the previous day.<br>
   <ul>
     <li><code>set &lt;name&gt; weeky off</code> disables weekly-timer</li>
     <li><code>set &lt;name&gt; weekly "0700-++++0900-+"</code>  up by weekly-timer at Mon-Fri=0700, Sat-Sun=0900</li>
     <li><code>set &lt;name&gt; weekly "0600-0530-+++1130-0800-"</code> up at Mon=0600, Tue-Fri=0530, Sat=1130, Sun=0800</li>
   </ul>
</li>

<a name=astro></a>
<li>astro - switch on/off or set the astro (civil dusk) timer of a Fernotron device<br>
    The shutter goes down at civil dusk or some minutes before or after if you provide a -/+ minute offset.<br>
    <ul>
      <li><code>set &lt;name&gt; astro off</code> disables astro-timer</li>
      <li><code>set &lt;name&gt; astro on</code> down by astro-timer at civil dusk</li>
      <li><code>set &lt;name&gt; astro "-10"</code> down at 10 minutes before civil dusk</li>
      <li><code>set &lt;name&gt; astro 10</code> down at 10 minutes after civil dusk</li>
    </ul>
</li>

  <a name=xxx_pair></a>
  <li>xxx_pair - Lets MCU pair the next received sender to this shutter (Paired senders will influence the shutter position)</li>

  <a name=xxx_unpair></a>
  <li>xxx_unpair - Lets MCU unpair the next received Sender to this shutter</li>
</ul>


<h4>GUI und speech control</h4>
<ul>
<li>Alexa<br>
<code>attr &lt;name&gt;  genericDeviceType blind</code><br>
<code>attr &lt;name&gt;  alexaName Schlafraum Rollo</code><br>
</li>
<li>buttons and sliders in FHEMWEB<br>
<code>attr &lt;name&gt; webCmd up:stop:down:sun-down:pct</code><br>
</li>
<li>Home-Bridge<br>
<code>attr &lt;name&gt; room Homekit</code><br>
<code>attr &lt;name&gt; genericDeviceType blind</code><br>
<code>attr &lt;name&gt; webCmd down:stop:up</code><br>
<code>attr &lt;name&gt; userReadings position { ReadingsVal($NAME,"state",0) }</code><br>
</li>
</ul>

=end html


=begin html_DE

<a name="Tronferno"></a>

<h3>Tronferno</h3>

<i>Tronferno</i> ist ein logisches FHEM-Modul zum steuern von Rollladen Motoren und Steckdosen und empfangen von Sendern und Sensoren über das Fernotron-Funkprotokoll mithilfe eines Mikrocontrollers. Es verwendet das physische FHEM-Modul TronfernoMCU um mit der <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a> Mikrocontroller Firmware zu kommunizieren.

<h4>Define</h4>

<p>
  <code>
    define  &lt;name&gt; Tronferno [a=ID] [g=N] [m=N] [input[=(plain|sun|central)]] [scan]<br>
  </code>

<p>
<ul>
  <li>a=ID : Geräte ID. Default ist die ID der 2411 (gespeichert in der MCU). Nur verwenden, wenn eine abweichende ID benutzt werden soll.<br>
             Sechsstellige Hexadezimale-Zahl nach dem Muster: 10xxxx=Handsender, 20xxxx=Sonnensensor, 80xxxx=Zentrale, 90xxxx=Motor.</li>
  <li>g=N : Gruppen-Nummer (1-7)  oder  0/weglassen für alle Gruppen</li>
  <li>m=N : Empfänger-Nummer (1-7) oder  0/weglassen für alle Empfänger der Gruppe</li>
  <li>scan : Definiert ein Gerät welches alle eingehenden Fernotron-Nachrichten empfängt. Wird automatisch angelegt als "Tronferno_Scan"</li>
  <li>input: Definiert Geräte welches eingehende Fernotron-Nachrichten empfängt die für den Empfänger a/g/m bestimmt sind<br>
             Die SenderTypen plain, sun oder central brauchen nicht angegeben werden, da  sie sich bereits aus der ID ergeben<br>
 <li>Hinweis: Die Optionen a/g/m haben den Default-Wert 0. Es ist das selbe ob man sie ganz weglässt oder explizit 0 als Wert benutzt (a=0 g=0 m=0).</li>
</ul>


<p>Ein Tronferno Gerät kann entweder einen einzelnen Empfänger oder eine Gruppe von Empfängern gleichzeitig adressieren.
<p>Empfangene Nachrichten von Controllern/Sensoren werden durch Eingabe Geräte verarbeitet. Das (automatisch erzeugte) Default-Eingabegerät (Tronferno_Scan) empfängt alle Nachrichten, für die noch kein eigenes Eingabe Geräte definiert wurde.
<p> Eingabegeräte werden durch Verwenden des Parameters 'input' in der Definition erzeugt.


<h5>Beispiele für Geräte zum Senden</h5>
<ul>
<li><code>define tfmcu TronfernoMCU /dev/ttyUSB0</code> (Definiere zuerst das I/O-Gerät das die Tronferno Geräte benötigen)</li>
<li><code>define roll21 Tronferno g=2 m=1</code> (Rollladen 1 in Gruppe 2)</li>
<li><code>define roll10 Tronferno g=1</code> (Rollladen-Gruppe 1)</li>
<li><code>define roll00 Tronferno</code> (Alle Rollladen-Gruppen)</li>
<li><code>define plain_101234 Tronferno a=101234</code> (Simulierter Handsender 101234</li>
<li><code>define motor_0abcd Tronferno a=90abcd</code> (Sendet direkt an Motor 0abcd. Die Ziffer 9 dem Motorcode voranstellen!)</li>
<li><code></code> </li>
</ul>
<h5>Beispiele für Geräte zum Empfang von Sendern</h5>
<ul>
<li><code>define myFernoSwitch Tronferno a=10abcd input</code> (Handsender als Schalter für Hoch/Runter/Stopp)</li>
<li><code>define myFernoSun Tronferno a=20abcd input</code>  (Sonnensensor als on/off Schalter  (on: Sonnenschein, off: kein Sonnenschein))</li>
<li><code> myFernoSwitch2 Tronferno g=2 m=3 input </code> (Programmierzentrale als Schalter für Hoch/Runter/Stopp)</li>
<li><code>define n_toggleHUEDevice3 notify myFernoSwitch:stop set HUEDevice3 toggle</code> (Schalte Hue-Lampe um wenn Stopp gedrückt wird)</li>
<li><code>define n_toggleHUEDevice3 notify Tronferno_Scan:plain:1089ab:stop set HUEDevice3 toggle</code> (...wie oben, aber mit dem allgemeinem Input Gerät "scan")</li>
<li><code></code> </li>
</ul>



<h5>Drei verschiedene Methoden der Adressierung</h5>

<ol>
  <li> Die IDs vorhandener Sende-Geräte einscannen und dann benutzen.
    Beispiel: Die ID der 2411 benutzen um dann über Gruppen und Empfängernummern die Rollläden anzusprechen.</li>

  <li> Ausgedachte Handsender IDs mit Motoren zu koppeln.
    Beispiel: Rollladen 1 mit 100001, Rollladen 2 mit 100002, ...</li>

  <li> Empfänger IDs: Funkmotoren haben 5 stellige "Funk-Codes" aufgedruckt, eigentlich gedacht zur Inbetriebnahme.
    Es muss eine 9 davorgestellt werden um die ID zu erhalten.</li>
</ol>

<h5>Drei Arten der Gruppenbildung</h5>

<ol>
  <li>Gruppen und Empfänger entsprechen der 2411. Gruppenbildung durch die 0 als Joker.  (g=1 m=0 oder g=0 m=1) </li>

  <li> Wie bei realen Handsendern. Beispiel: Ein (virtueller) Handsender wird bei allen Motoren einer Etage angemeldet.</li>

  <li> nicht möglich</li>
</ol>

<h5>Drei Beispiele</h5>
<ol>
  <li>
    <code>define myShutterGroup1 Tronferno g=1 m=0</code><br>
    <code>define myShutter11 Tronferno g=1 m=1</code><br>
    <code>define myShutter12 Tronferno g=1 m=2</code><br>
    ...
    <code>define myShutterGroup2 Tronferno g=2 m=0</code><br>
    <code>define myShutter21 Tronferno g=2 m=1</code><br>
    <code>define myShutter22 Tronferno g=2 m=2</code><br>
      </li>

  <li>
    <code>define myShutter1 Tronferno a=100001</code><br>
    <code>define myShutter2 Tronferno a=100002</code><br>
    Nun aktiviere Set-Modus am Fernotron Empfänger und sende Stopp vom neu definierten Geräte um es zu koppeln.
 ...</li>

<li><code>define myShutter__0d123 Tronferno a=90d123</code></li>
</ol>


<a name="Tronfernoattr"></a>
<h4>Attribute</h4>
<ul>
  <li><a name="repeats">repeats N</a><br>
        Wiederhohlen einer Nachricht beim Senden zum Verbessern der Chancen das sie ankommt (default ist 2 Wiederhohlungen).
  </li>
  <li><a name="pctInverse">pctInverse 1|0</a><br>
        Invertiert die Position-Prozente Normal: Auf=100%, ZU=0%. Invertiert: Auf=0%, Zu=100%<br>
  </li>
</ul>

<a name=Tronfernoset></a>
<h4>Set</h4>
<ul>
  <a name=up></a>
  <li>up - Öffne Rollladen</li>

  <a name=down></a>
  <li>down - Schließe Rollladen</li>

  <a name=stop></a>
  <li>stop - Stoppe den Rollladen</li>

  <a name=set></a>
  <li>set  - Aktiviere Koppel Modus am Fernotron Empfänger (SET)</li>

  <a name=sun-down></a>
  <li>sun-down - Bewege Rollladen zur SonnenSensor-Position (wenn Sonnenautomatik aktiv ist und der Rollladen zur Zeit weiter geöffnet ist als die Sonnenposition)</li>

  <a name=sun-up></a>
  <li>sun-up - Kehrt aus der Sonnenposition zurück in die Offen-Position</li>

  <a name=sun-inst></a>
  <li>sun-inst - Speichere aktuelle Position als neue Sonnenposition</li>

  <a name=position></a>
  <li>position - Bewege den Rollladen zur angegebenen Position in Prozent. (100% ist offen. Sprachsteuerung: 1% ist stop, 2% ist sun-down)</li>

  <a name=pct></a>
  <li>pct - Bewege den Rollladen zur angegebenen Position in Prozent. (100% ist offen. Sprachsteuerung: 1% ist stop, 2% ist sun-down)</li>


  <a name=sun-auto></a>
  <li>sun-auto - Schalte Sonnenautomatik des Empfängers ein oder aus</li>

  <a name=manual></a>
  <li>manual - Schalte Manuell ein oder aus<br>
     Der Manuelle-Modus verhindert alles automatischen Rollladen Bewegungen durch interne Timer oder gekoppelte Sensoren<br>
  <ul>
   <li><code>set &lt;name&gt; manual on</code></li>
   <li><code>set &lt;name&gt; manual off</code></li>
  </ul>

    <p><small>Klugde: Der Manuelle Modus wird erreicht durch ersetzten der Programme des Empfängers. Um wieder in den Automatik-Modus zu wechseln müssen alle Timer neu programmiert werden (mit den in der MCU zwischengespeicherten Daten). Die Original 2411 macht dies auch so.</small>
</li>

  <a name=random></a>
  <li>random - Schalte Zufalls-Timer des Empfänger ein oder aus</li>

<a name=daily></a>
<li>daily - Programmiere Tages-Timer des Empfängers<br>
   Format: HHMMHHMM für auf/zu Timer. Benutze  '-' statt HHMM zum deaktivieren des auf oder zu Timers.<br>
   <ul>
    <li><code>set &lt;name&gt; daily off</code> deaktiviert Tagestimer</li>
    <li><code>set &lt;name&gt; daily "0700-"</code> täglich um 7:00 Uhr öffnen</li>
    <li><code>set &lt;name&gt; daily "-1200"</code> täglich um 12:00 Uhr schließen</li>
  </ul>
</li>

<a name=weekly></a>
<li>weekly - Programmiere Wochentimer des Empfängers<br>
   Format: Wie Tagestimer (HHMMHHMM) aber 7 mal hintereinander. Von Montag bis Sonntag. Ein '+' kopiert den Timer vom Vortag.<br>
   <ul>
     <li><code>set &lt;name&gt; weekly off</code> deaktiviert Wochentimer</li>
     <li><code>set &lt;name&gt; weekly "0700-++++0900-+"</code>  Mo-Fr um 07:00 Uhr öffnen, Sa-So um 09:00 Uhr öffnen</li>
     <li><code>set &lt;name&gt; weekly "0600-0530-+++1130-0800-"</code>Öffnen am Mo um 6:00 Uhr, Di-Fr um 05:30, Sa um 11:30 und So um 08:00 Uhr</li>
   </ul>
</li>

<a name=astro></a>
<li>astro - Programmiere Astro-Timer (Dämmerung) des Fernotron-Empfängers<br>
    Der Rollladen schließt zur zivilen Dämmerung +/- dem angegebenen Minuten-Offset.<br>
    <ul>
      <li><code>set &lt;name&gt; astro off</code> deaktiviert Astro-Timer</li>
      <li><code>set &lt;name&gt; astro on</code> schließt zur zivilen Dämmerung</li>
      <li><code>set &lt;name&gt; astro "-10"</code> schließt 10 Minuten vor der zivilen Dämmerung</li>
      <li><code>set &lt;name&gt; astro 10</code> schließt 10 Minuten nach der zivilen Dämmerung</li>
    </ul>
</li>

  <a name=xxx_pair></a>
  <li>xxx_pair - Binde den Sender der als nächstes sendet an diesen Empfänger. Dies dient dazu, die Position des Motors zu ermitteln, in dem der Mikrocontroller alle Befehle von gekoppelten Sendern mithört. Man sollte also nur Sender hier binden die auch real diesen Empfänger steuern (also mit ihm real gekoppelt sind).

  <a name=xxx_unpair></a>
  <li>xxx_unpair - Lösche die Bindung des Senders der als nächstes sendet an diesen Empfänger.</li>
</ul>


<h4>GUI und Sprachsteuerung</h4>
<ul>
<li>Alexa<br>
<code>attr &lt;name&gt;  genericDeviceType blind</code><br>
<code>attr &lt;name&gt;  alexaName Schlafraum Rollo</code><br>
</li>
<li>Buttons und Schieber in FHEMWEB<br>
<code>attr &lt;name&gt; webCmd up:stop:down:sun-down:pct</code><br>
</li>
<li>Home-Bridge<br>
<code>attr &lt;name&gt; room Homekit</code><br>
<code>attr &lt;name&gt; genericDeviceType blind</code><br>
<code>attr &lt;name&gt; webCmd down:stop:up</code><br>
<code>attr &lt;name&gt; userReadings position { ReadingsVal($NAME,"state",0) }</code><br>
</li>
</ul>

=end html_DE

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Tronferno.pm 2>&1 | grep -v 'Undefined subroutine'"
# eval: (my-buffer-local-set-key (kbd "C-c C-c") (lambda () (interactive) (shell-command "cd ../../.. && ./build.sh")))
# eval: (my-buffer-local-set-key (kbd "C-c c") 'compile)
# eval: (my-buffer-local-set-key (kbd "C-c p") (lambda () (interactive) (shell-command "perlcritic  ./10_Tronferno.pm")))
# End:

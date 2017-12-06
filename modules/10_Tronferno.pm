#############################################
## *experimental* FHEM module Tronferno
#  FHEM module to control Fernotron devices via Tronferno-MCU ESP8266 hardware
#
#  written by Bert Winkelmann <tf.zwiebert@online.de>
#
#
# - copy or softink this file to /opt/fhem/FHEM/10_Tronferno.pm
# - do 'reload 10_Tronferno'
#
#  device arguments
#      a - 6 digit Fernotron hex ID or 0 (default: 0)
#      g - group number: 0..7 (default: 0)
#      m - member number: 0..7 (default: 0)
#
#     Example: define roll12 g=1 m=2
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
        my $u = 'wrong syntax: define <name> Fernotron a=ID [g=N] [m=N]';

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
            Tronferno_transmit($name, $req);
            main::readingsSingleUpdate($hash, 'state', $cmd, 0);
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
    }
}

1;

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Tronferno.pm"
# End:

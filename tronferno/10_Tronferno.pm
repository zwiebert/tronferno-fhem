## *experimental* FHEM module Tronferno-MCU
# Author: Bert Winkelmann
#
#  FHEM module to control Fernotron devices via Tronferno-MCU ESP8266 hardware
#
# - copy or softink this file to /opt/fhem/FHEM/10_Tronferno.pm
# - submit command 'rereadcfg' to fhem  (maybe try 'reload 10_Tronferno' too)
#
#
# Bugs:
#  - this needs the latest firmware of tronferno-mcu (workaround: keep another TCP client connected at the same time. or change TCP code to keep connection open for a while)
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

        my $socket = 0;    #IO::Socket::INET->new(Proto => 'tcp', PeerPort => 7777, PeerAddr => AttrVal($name, 'mcuaddr', $def_mcuaddr),

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

    sub Tronferno_build_cmd($$$) {
        my ($name, $cmd, $c) = @_;
        my $g = main::AttrVal($name, 'groupNumber',  0);
        my $m = main::AttrVal($name, 'memberNumber', 0);
        return "$cmd g=$g m=$m c=$c;";
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

        if (exists $map_tcmd->{$cmd}) {
            my $req = Tronferno_build_cmd($name, 'send', $map_tcmd->{$cmd});
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

        $hash->{AttrList} = 'mcuaddr groupNumber memberNumber controllerId';
        $hash->{SetFn}    = "Tronferno::Tronferno_Set";
    }
}

1;

# Local Variables:
# compile-command: "perl -w ./10_Tronferno.pm"
# End:

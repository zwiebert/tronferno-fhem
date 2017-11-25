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

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Tronferno.pm"
# End:

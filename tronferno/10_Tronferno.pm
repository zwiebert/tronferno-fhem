## *experimental* FHEM modules Tronferno and Fernotron
# (they exist both in a single file for now for easier development)
#
#  1) FHEM module to control Fernotron devices via SIGNALduino hardware
#
# - rename and copy or softlink this file to /opt/fhem/FHEM/10_Fernotron.pm
# - add "Fernotron" to /opt/fhem/FHEM/SIGNALduino.pm liket this:
#---------------8<-------------------------
# Supported Clients per default
#  my $clientsSIGNALduino = ":IT:"
#                           ."Fernotron:"
#                           ."CUL_TCM97001:"
#--------------->8-------------------------
# - submit command 'rereadcfg' to fhem  (maybe try 'reload 10_Fernotron' too)
#
# 2) FHEM module to control Fernotron devices via Tronferno-MCU ESP8266 hardware
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
use IO::Select;

package main {

    # initialize as Tronferno if the file is named 10_Tronferno.pm
    sub Tronferno_Initialize($) {
        my ($hash) = @_;

        $hash->{DefFn} = 'Tronferno::Tronferno_Define';

        $hash->{AttrList} = 'mcuaddr groupNumber memberNumber controllerId';
        $hash->{SetFn}    = "Tronferno::Tronferno_Set";
    }

    # initialize as Fernotron if the file is named 10_Fernotron.pm
    sub Fernotron_Initialize($) {
        my ($hash) = @_;

        $hash->{DefFn} = 'Fernotron::Fernotron_Define';

        $hash->{AttrList} = 'groupNumber memberNumber controllerId';
        $hash->{SetFn}    = "Fernotron::Fernotron_Set";
    }

}

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

    sub Tronferno_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;

        return "\"set $name\" needs at least one argument" unless (defined($cmd));

        if ($cmd eq 'on' or $cmd eq 'up') {
            my $req = Tronferno_build_cmd($name, 'send', 'up');
            Tronferno_transmit($name, $req);
        }
        elsif ($cmd eq 'off' or $cmd eq 'down') {
            my $req = Tronferno_build_cmd($name, 'send', 'down');
            Tronferno_transmit($name, $req);
        }
        elsif ($cmd eq 'stop') {
            my $req = Tronferno_build_cmd($name, 'send', 'stop');
            Tronferno_transmit($name, $req);
        }
        elsif ($cmd eq 'timer') {
        }
        elsif ($cmd eq 'config') {
        }
        elsif ($cmd eq 'send') {
        }
        else {
            return "unknown argument $cmd choose one of up down stop";
        }

        return undef;
    }

}

########
# experimental code. its  not really part of Tronferno
#
package Fernotron {

  our $p_string = "SR;;R=1;;P0=400;;P1=-400;;P2=-3200;;P3=-800;;P4=800;;";
  my $def_cu = '801234';

    sub Fernotron_Define($$) {
        my ($hash, $def) = @_;
        my $name = $hash->{NAME};

        print("call define\n");
        main::AssignIoPort($hash);

    }

    sub Fernotron_transmit($$$) {
        my ($hash, $command, $c) = @_;
        my $name = $hash->{NAME};
        my $args = {
            command => $command,
            a       => hex(main::AttrVal($name, 'controllerId', $def_cu)),
            g       => main::AttrVal($name, 'groupNumber', 0),
            m       => main::AttrVal($name, 'memberNumber', 0),
            c       => $c,
        };
        my $fsb = args2cmd($args);
        if ($fsb != -1) {
	     print "$name: send messasge: " . fsb2string($fsb) . "\n";
            my $tx_data = cmd2dString($fsb);     # print "debug: $p_string$tx_data\n";
            my $msg     = "$p_string$tx_data";
            $msg =~ s/;;/;/g;
            main::IOWrite($hash, 'raw', $msg);
        }
        else { print "no fsb\n"; }
    }

    sub Fernotron_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;
        return "\"set $name\" needs at least one argument" unless (defined($cmd));

        main::AssignIoPort($hash);               # if undef $hash->{IODev};
        my $io = $hash->{IODev} or return '"no io device"';

        if ($cmd eq 'on' or $cmd eq 'up') {
            Fernotron_transmit($hash, 'send', 'up');
        }
        elsif ($cmd eq 'off' or $cmd eq 'down') {
            Fernotron_transmit($hash, 'send', 'up');
        }
        elsif ($cmd eq 'stop') {
            Fernotron_transmit($hash, 'send', 'stop');
        }
        elsif ($cmd eq 'timer') {
        }
        elsif ($cmd eq 'config') {
        }
        elsif ($cmd eq 'send') {
        }
        else {
            return "unknown argument $cmd choose one of up down stop";
        }

        return undef;
    }

    #  experimental code to generate and parse SIGNALduino strings for Fernotron
    #
    #  - extract central unit ID from once received Sd string
    #  - send any command to any group and member paired with that central unit

    my $debug = 0;

###############################################
## timings

    # PRE_STP_DT1_ON, #P0  +2 * 200us =  +400us
    # PRE_DT0_OFF,    #P1  -2 * 200us =  -400us
    # STP_OFF,        #P2 -16 * 200us = -3200us
    # DT1_OFF,        #P3  -4 * 200us =  -800us
    # DT0_ON,         #P4  +4 * 200us =  +800us

    my %rf_timings = (
        'P0.min' => 350,
        'P0.max' => 450,
        'P1.min' => -450,
        'P1.max' => -350,
        'P2.min' => -3500,
        'P2.max' => -2500,
        'P3.min' => -900,
        'P3.max' => -700,
        'P4.min' => 700,
        'P4.max' => 900,
    );

    #                   1 2 3 4 5 6 7
    my $d_pre_string = "01010101010101";    # preamble
    my $d_stp_string = "02";                # stop comes before each preamble and before each word
    my $d_dt0_string = "41";                # data bit 0 (/..long..\short)
    my $d_dt1_string = "03";                # data bit 1 (/short\..long..)

## global configuration
    my %C = (
        'centralUnitID' => 0x8012ab,

    );

## we store all 5 bytes, which is wasteful as the first 3 bits equals the hash-key.  simplifies the code a bit
    my %fsbs;

    sub dbprint($) {
        if ($debug) {
            my ($s) = @_;
            print $s;
        }

    }

##########################################
## convert a single byte to a data string
##########################################
    #
    #  "t if VAL contains an even number of 1 bits"
    sub is_bits_even($) {
        my ($val) = @_;

        $val ^= $val >> 4;
        $val ^= $val >> 2;
        $val ^= $val >> 1;
        $val &= 0x01;
        return ($val == 0);
    }
    #
    sub fer_get_word_parity ($$) {
        my ($data_byte, $pos) = @_;
        my $is_even = is_bits_even($data_byte);
        return (($pos & 1)) ? ($is_even ? 3 : 1) : ($is_even ? 0 : 2);
    }
    #
    sub byte2word ($$) {
        my ($data_byte, $pos) = @_;
        return ($data_byte | (fer_get_word_parity($data_byte, $pos) << 8));
    }
    #
    sub word2dString($) {
        my ($w) = @_;
        my $r = "";
        for (my $i = 0; $i < 10; ++$i) {
            $r .= (0 == (($w >> $i) & 1) ? $d_dt0_string : $d_dt1_string);
        }
        return $r;
    }
    #
    # turn one databyte into a string of: two 10-bit words and two stop bits
    sub byte2dString($) {
        my ($b) = @_;
        return $d_stp_string . word2dString(byte2word($b, 0)) . $d_stp_string . word2dString(byte2word($b, 1));
    }
### end ###

###############################################
### convert a byte commmand to a data string
    #
## calc checksum to @array,
    sub calc_checksum($$) {
        my ($cmd, $cs) = @_;
        foreach my $b (@$cmd) {
            $cs += $b;
        }
        return (0xff & $cs);
    }
    #
    sub cmd2dString($) {
        my ($fsb) = @_;
        my $r = "D=$d_stp_string$d_pre_string";
        foreach my $b (@$fsb, calc_checksum($fsb, 0)) {
            $r .= byte2dString($b);
        }
        return $r . ';;';
    }
### end ###

    my ($fer_dat_ADDR_2, $fer_dat_ADDR_1, $fer_dat_ADDR_0,    ## sender or receiver address
        $fer_dat_TGL_and_MEMB,                                # key-press counter + some ID of the sender (like Member number, Type of sender, ...)
        $fer_dat_GRP_and_CMD                                  # Group-ID of sender + the command code (0...0xF)
    ) = qw(0 1 2 3 4);

    # values of low nibble in data[fer_dat_GRP_and_CMD].
###/ Command Codes
    my ($fer_cmd_None,
        $fer_cmd_1,
        $fer_cmd_2,
        $fer_cmd_STOP,
        $fer_cmd_UP,
        $fer_cmd_DOWN,
        $fer_cmd_SunDOWN,
        $fer_cmd_SunUP,
        $fer_cmd_SunINST,
        $fer_cmd_EndPosUP,
        $fer_cmd_endPosDOWN,
        $fer_cmd_0xb,
        $fer_cmd_0xc,
        $fer_cmd_SET,
        $fer_cmd_0xe,
        $fer_cmd_Program    # Sun-Test (dat_MEMB=1), Time send (dat_Memb=0), Data send (dat_MEMB=member)
    ) = qw (0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15);

    # values of high nibble in data[$fer_dat_GRP_and_CMD].
###/ Sender IDs
    my ($fer_grp_Broadcast,
        $fer_grp_G1,
        $fer_grp_G2,
        $fer_grp_G3,
        $fer_grp_G4,
        $fer_grp_G5,
        $fer_grp_G6,
        $fer_grp_G7
## FIXME: only 3 bits used so far. Is the highest bit used for anything? */

    ) = qw (0 1 2 3 4 5 6 7);

    # values of low nibble in data[$fer_dat_TGL_and_MEMB].
###/ Sender IDs
    my ($fer_memb_Broadcast,    # RTC data, ...
        $fer_memb_SUN,          # sent by SunSensor
        $fer_memb_SINGLE,       # sent by hand sender
        $fer_memb_P3,
        $fer_memb_P4,
        $fer_memb_P5,
        $fer_memb_P6,
        $fer_memb_RecAddress,    # $fer_dat_ADDR contains address of the receiver (set function via motor code)
        $fer_memb_M1,            #8
        $fer_memb_M2,
        $fer_memb_M3,
        $fer_memb_M4,
        $fer_memb_M5,
        $fer_memb_M6,
        $fer_memb_M7,
    ) = qw (0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15);

##############################################
###
    #
    sub fsb_getByDevID($) {
        my ($devID) = @_;
        if (!exists($fsbs{$devID})) {
            $fsbs{$devID} = [ (($devID >> 16) & 0xff), (($devID >> 8) & 0xff), ($devID & 0xff), 0x00, 0x00 ];
        }

        return $fsbs{$devID};
    }

    sub fer_tglNibble_ctUp($$) {
        my ($toggle_nibble, $step) = @_;
        my $result = 0xff & ($toggle_nibble + $step);
        if ($result < $toggle_nibble) {
            ++$result;
        }

        return ($result > 15) ? 1 : $result;
    }

    sub FSB_MODEL_IS_CENTRAL($) {
        my ($fsb) = @_;
        return ($$fsb[0] & 0xf0) == 0x80;
    }

    sub FSB_MODEL_IS_RECEIVER($) {
        my ($fsb) = @_;
        return ($$fsb[0] & 0xf0) == 0x90;
    }

    sub FSB_MODEL_IS_SUNSENS($) {
        my ($fsb) = @_;
        return ($$fsb[0] & 0xf0) == 0x20;
    }

    sub FSB_MODEL_IS_STANDARD($) {
        my ($fsb) = @_;
        return ($$fsb[0] & 0xf0) == 0x10;
    }

    sub FSB_GET_DEVID($) {
        my ($fsb) = @_;
        return $$fsb[$fer_dat_ADDR_2] << 16 | $$fsb[$fer_dat_ADDR_1] << 8 | $$fsb[$fer_dat_ADDR_0];
    }

    sub FSB_GET_CMD($) {
        my ($fsb) = @_;
        return ($$fsb[$fer_dat_GRP_and_CMD] & 0x0f);
    }

    sub FSB_GET_MEMB($) {
        my ($fsb) = @_;
        return ($$fsb[$fer_dat_TGL_and_MEMB] & 0x0f);
    }

    sub FSB_PUT_CMD($$) {
        my ($fsb, $cmd) = @_;
        $$fsb[$fer_dat_GRP_and_CMD] = ($$fsb[$fer_dat_GRP_and_CMD] & 0xf0) | ($cmd & 0x0f);
    }

    sub FSB_PUT_MEMB($$) {
        my ($fsb, $val) = @_;
        $$fsb[$fer_dat_TGL_and_MEMB] = ($$fsb[$fer_dat_TGL_and_MEMB] & 0xf0) | ($val & 0x0f);
    }

    sub FSB_GET_TGL($) {
        my ($fsb) = @_;
        return 0x0f & ($$fsb[$fer_dat_TGL_and_MEMB] >> 4);
    }

    sub FSB_PUT_GRP($$) {
        my ($fsb, $val) = @_;
        $$fsb[$fer_dat_GRP_and_CMD] = (($val << 4) & 0xf0) | ($$fsb[$fer_dat_GRP_and_CMD] & 0x0f);
    }

    sub FSB_GET_GRP($) {
        my ($fsb) = @_;
        return 0x0f & ($$fsb[$fer_dat_GRP_and_CMD] >> 4);
    }

    sub FSB_PUT_TGL($$) {
        my ($fsb, $val) = @_;
        $$fsb[$fer_dat_TGL_and_MEMB] = (($val << 4) & 0xf0) | ($$fsb[$fer_dat_TGL_and_MEMB] & 0x0f);
    }
    #
    #
    sub fer_update_tglNibble($$) {
        my ($fsb, $repeats) = @_;

        my $step = 0;

        if (!FSB_MODEL_IS_CENTRAL($fsb)) {
            $step = 1;
        }
        elsif ($repeats > 0) {
            $step = (FSB_GET_CMD($fsb) == $fer_cmd_STOP ? 1 : 0);
        }
        else {
            $step = 1;
        }

        if ($step > 0) {
            my $tgl = fer_tglNibble_ctUp(FSB_GET_TGL($fsb), $step);
            FSB_PUT_TGL($fsb, $tgl);
        }
    }
    #
    #
    #

    my $tglct = {};

    sub fsb_doToggle($) {
        my ($fsb) = @_;

        my $tgl = 0xf;

        if (exists($tglct->{ FSB_GET_DEVID($fsb) })) {
            $tgl = $tglct->{ FSB_GET_DEVID($fsb) };
        }

        FSB_PUT_TGL($fsb, $tgl);
        fer_update_tglNibble($fsb, 0);
        $tgl = FSB_GET_TGL($fsb);

        $tglct->{ FSB_GET_DEVID($fsb) } = $tgl;
    }
    #
    #
    sub fsb2string($) {
        my ($fsb) = @_;
        return sprintf "0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x", $$fsb[0], $$fsb[1], $$fsb[2], $$fsb[3], $$fsb[4];

    }
    #
    #
### end ###

#########################################################
### sniff device ID from string received via SIGNALduino
    #
## translate the substring between 'D=' and ';' to our own send timings and return the result;
    #
    sub rx_get_data($) {
        my ($s) = @_;

        #"MU;P0=395;P1=-401;P2=-3206;P3=798;P4=-804;
        if ($s
            =~ /(P0=(?<P0>-?\d+);)?(P1=(?<P1>-?\d+);)?(P1=(?<P1>-?\d+);)?(P2=(?<P2>-?\d+);)?(P3=(?<P3>-?\d+);)?(P4=(?<P4>-?\d+);)?(P5=(?<P5>-?\d+);)?(P6=(?<P6>-?\d+);)?(P7=(?<P7>-?\d+);)?D=(?<data>\d+)/
            )
        {
            my $tr_in  = "";
            my $tr_out = "";
            my $data   = $+{data};

            for (my $i = 0; $i <= 7; ++$i) {    # P0 ... P7 in input
                if (exists $+{"P$i"}) {
                    my $n = $+{"P$i"};
                    dbprint "P$i=$n\n";
                    for (my $k = 0; $k <= 4; ++$k) {    # P0 .. P4 in output
                        if ($rf_timings{"P$k.min"} <= $n && $n <= $rf_timings{"P$k.max"}) {
                            $tr_in  .= $i;
                            $tr_out .= $k;
                            dbprint "$i -> $k\n";
                        }
                    }
                }
            }

            dbprint "$data\n";
            eval "\$data =~ tr/$tr_in/$tr_out/";
            dbprint "$data\n";

            return $data;
        }

        return "";
    }
    #
    #
## return position of first stop bit (next bit starts first data word)
    sub find_stop($) {
        my ($s) = @_;
        return index($s, $d_stp_string);
    }

    #
    #
    #
## extract devID
    sub rx_sd2sd_word($$) {
        my ($sd, $word_idx) = @_;
        my $word = substr($sd, ($word_idx * 22) + 2, 20);
        return $word;
    }

    sub rx_sd2byte($$) {
        my ($word0, $word1) = @_;
        dbprint "word0: $word0\n";
        dbprint "word1: $word1\n";

        my $bit0 = $d_dt0_string;
        my $bit1 = $d_dt1_string;

        if (!(substr($word0, 0, 16) eq substr($word1, 0, 16))) {
            return -1;    # error
        }
        elsif (0 && !(substr($word0, 18, 2) eq $bit1 && substr($word1, 18, 2) eq $bit0)) {
            return -2;    # error
        }
        else {
            my $b = 0;
            for (my $k = 0; $k < 8; ++$k) {
                my $bit = substr($word0, $k * 2, 2);

                #dbprint "$bit\n";
                if ($bit eq $bit0) {

                    # nothing
                }
                elsif ($bit eq $bit1) {
                    $b |= (0x1 << $k);
                }
                else {
                    dbprint "error\n";
                    return -3;
                }

                # dbprint "0: $bit0, 1: $bit1, ok\n";
            }
            return $b;
        }

        return -1;
    }

    sub rx_sd2bytes ($) {
        my ($sendData) = @_;
        my $rx_data    = rx_get_data($sendData);
        my $stop_idx   = find_stop($rx_data);

        if ($stop_idx > 0) {
            $rx_data = substr($rx_data, $stop_idx);

            my @bytes;
            my $word_count = int(length($rx_data) / 22);

            dbprint("word_count=$word_count\n");

            for (my $i = 0; $i < $word_count - 1; $i += 2) {
                my $word0 = rx_sd2sd_word($rx_data, $i);
                my $word1 = rx_sd2sd_word($rx_data, $i + 1);

                my $b = rx_sd2byte($word0, $word1);
                if ($b >= 0) {
                    $bytes[ $i / 2 ] = $b;
                }
                else {
                    return 0;
                }
            }

            if ($debug) {
                print "extracted bytes: ";
                foreach my $b (@bytes) {
                    printf "0x%02x, ", $b;
                }
                print "\n";
            }
            return @bytes;

        }
        return 0;

    }

    sub rx_get_devID($) {
        my ($bytes) = @_;
        return $$bytes[$fer_dat_ADDR_2] << 16 | $$bytes[$fer_dat_ADDR_1] << 8 | $$bytes[$fer_dat_ADDR_0];
    }

    sub rx_get_ferCmd($) {
        my ($bytes) = @_;
        return ($$bytes[$fer_dat_GRP_and_CMD] & 0x0f);
    }

    sub rx_get_ferGrp($) {
        my ($bytes) = @_;
        return ($$bytes[$fer_dat_GRP_and_CMD] & 0xf0) >> 4;
    }

    sub rx_get_ferMemb($) {
        my ($bytes) = @_;
        return ($$bytes[$fer_dat_TGL_and_MEMB] & 0x0f);
    }

    sub rx_get_ferTgl($) {
        my ($bytes) = @_;
        return ($$bytes[$fer_dat_TGL_and_MEMB] & 0xf0) >> 4;
    }

    #
### end ###

###########################################################################
### send commands to fhem
    #
    #
    my %map_fcmd = (
        "up"       => $fer_cmd_UP,
        "down"     => $fer_cmd_DOWN,
        "stop"     => $fer_cmd_STOP,
        "set"      => $fer_cmd_SET,
        "sun-down" => $fer_cmd_SunDOWN,
        "sun-inst" => $fer_cmd_SunINST,
    );

    sub cmd2sdCMD($) {
        my ($fsb) = @_;
        return "set sduino raw " . $p_string . cmd2dString($fsb);
    }
    #
    #
    sub args2cmd($) {
        my ($args) = @_;

        my $fsb;

        if (exists($$args{'a'})) {
            my $val = $$args{'a'};
            $fsb = fsb_getByDevID($val);
        }
        else {
            $fsb = fsb_getByDevID($C{'centralUnitID'});    # default
        }

        if (exists($$args{'c'})) {
            my $val = $$args{'c'};
            if (exists($map_fcmd{$val})) {
                FSB_PUT_CMD($fsb, $map_fcmd{$val});
            }
            else {
                warn "error: unknown command '$val'\n";
                return -1;
            }
        }

        if (exists($$args{'g'})) {
            my $val = $$args{'g'};
            if (0 <= $val && $val <= 7) {
                FSB_PUT_GRP($fsb, $fer_grp_Broadcast + $val);
            }
            else {
                warn "error: invalid group '$val'\n";
                return -1;
            }
        }
        else {
            FSB_PUT_GRP($fsb, $fer_grp_Broadcast);    # default
        }

        if (exists($$args{'m'})) {
            my $val = $$args{'m'};
            if ($val == 0) {
                FSB_PUT_MEMB($fsb, $fer_memb_Broadcast);
            }
            elsif (1 <= $val && $val <= 7) {
                FSB_PUT_MEMB($fsb, $fer_memb_M1 + $val - 1);
            }
            else {
                warn "error: invalid member '$val'\n";
                return -1;
            }
        }
        elsif (FSB_MODEL_IS_RECEIVER($fsb)) {
            FSB_PUT_MEMB($fsb, $fer_memb_RecAddress);
        }
        elsif (FSB_MODEL_IS_SUNSENS($fsb)) {
            FSB_PUT_MEMB($fsb, $fer_memb_SUN);
        }
        elsif (FSB_MODEL_IS_STANDARD($fsb)) {
            FSB_PUT_MEMB($fsb, $fer_memb_SINGLE);
        }
        else {
            FSB_PUT_MEMB($fsb, $fer_memb_Broadcast);    # default
        }

        fsb_doToggle($fsb);
        return $fsb;
    }

}

1;

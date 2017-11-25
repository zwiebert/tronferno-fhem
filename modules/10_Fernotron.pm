######################################
## *experimental* FHEM module Fernotron
## FHEM module to control Fernotron devices via SIGNALduino hardware
## Author: Bert Winkelmann <tf.zwiebert@online.de>
##
## - copy or softlink this file to /opt/fhem/FHEM/10_Fernotron.pm
##
## - add "Fernotron" as client to SIGNALduino:
##          copy old list form Internals.Clients
##          insert 'Fernotron:' right before the last entry SIGNALduino_un:
##         attr sduino Clients (paste the list here)
##   example:
##         attr sduino Clients   :FS10:CUL_FHTTK:Siro:FHT:FS20:Fernotron:SIGNALduino_un:
##
##

use strict;

use 5.14.0;

package FernotronDrv {

    my $def_cu = '801234';

##  experimental code to generate and parse SIGNALduino strings for Fernotron
##
##  - extract central unit ID from once received Sd string
##  - send any command to any group and member paired with that central unit

    my $debug = 0;

################################################
### timings

## PRE_STP_DT1_ON, #P0  +2 * 200us =  +400us
## PRE_DT0_OFF,    #P1  -2 * 200us =  -400us
## STP_OFF,        #P2 -16 * 200us = -3200us
## DT1_OFF,        #P3  -4 * 200us =  -800us
## DT0_ON,         #P4  +4 * 200us =  +800us

    my $rf_timings = {
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
    };

    my $p_string = 'SR;R=1;P0=400;P1=-400;P2=-3200;P3=-800;P4=800;';

##                   1 2 3 4 5 6 7
    my $d_pre_string = '01010101010101';    # preamble
    my $d_stp_string = '02';                # stop comes before each preamble and before each word
    my $d_dt0_string = '41';                # data bit 0 (/..long..\short)
    my $d_dt1_string = '03';                # data bit 1 (/short\..long..)

### global configuration
    my $C = {
        'centralUnitID' => 0x8012ab,        # FIXME:-bw/23-Nov-17
    };

### we store all 5 bytes, which is wasteful as the first 3 bits equals the hash-key.  simplifies the code a bit
    my $fsbs = {};

    sub dbprint($) {
        if ($debug) {
            my ($s) = @_;
            print $s;
        }

    }

###########################################
### convert a single byte to a data string
###########################################
##
##  "t if VAL contains an even number of 1 bits"
    sub is_bits_even($) {
        my ($val) = @_;

        $val ^= $val >> 4;
        $val ^= $val >> 2;
        $val ^= $val >> 1;
        $val &= 0x01;
        return ($val == 0);
    }
##
    sub fer_get_word_parity ($$) {
        my ($data_byte, $pos) = @_;
        my $is_even = is_bits_even($data_byte);
        return (($pos & 1)) ? ($is_even ? 3 : 1) : ($is_even ? 0 : 2);
    }
##
    sub byte2word ($$) {
        my ($data_byte, $pos) = @_;
        return ($data_byte | (fer_get_word_parity($data_byte, $pos) << 8));
    }
##
    sub word2dString($) {
        my ($w) = @_;
        my $r = '';
        for (my $i = 0; $i < 10; ++$i) {
            $r .= (0 == (($w >> $i) & 1) ? $d_dt0_string : $d_dt1_string);
        }
        return $r;
    }
##
## turn one databyte into a string of: two 10-bit words and two stop bits
    sub byte2dString($) {
        my ($b) = @_;
        return $d_stp_string . word2dString(byte2word($b, 0)) . $d_stp_string . word2dString(byte2word($b, 1));
    }
#### end ###

################################################
#### convert a byte commmand to a data string
##
### calc checksum to @array,
    sub calc_checksum($$) {
        my ($cmd, $cs) = @_;
        foreach my $b (@$cmd) {
            $cs += $b;
        }
        return (0xff & $cs);
    }
##
    sub cmd2dString($) {
        my ($fsb) = @_;
        my $r = "D=$d_stp_string$d_pre_string";
        foreach my $b (@$fsb, calc_checksum($fsb, 0)) {
            $r .= byte2dString($b);
        }
        return $r . ';';
    }

    sub cmd2sdString($) {
        my ($fsb) = @_;
        my $r = "$p_string;D=$d_stp_string$d_pre_string";
        foreach my $b (@$fsb, calc_checksum($fsb, 0)) {
            $r .= byte2dString($b);
        }
        return $r . ';';
    }

#### end ###

    my ($fer_dat_ADDR_2, $fer_dat_ADDR_1, $fer_dat_ADDR_0,    ## sender or receiver address
        $fer_dat_TGL_and_MEMB,                                # key-press counter + some ID of the sender (like Member number, Type of sender, ...)
        $fer_dat_GRP_and_CMD                                  # Group-ID of sender + the command code (0...0xF)
    ) = qw(0 1 2 3 4);

## values of low nibble in data[fer_dat_GRP_and_CMD].
####/ Command Codes
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

## values of high nibble in data[$fer_dat_GRP_and_CMD].
####/ Sender IDs
    my ($fer_grp_Broadcast,
        $fer_grp_G1,
        $fer_grp_G2,
        $fer_grp_G3,
        $fer_grp_G4,
        $fer_grp_G5,
        $fer_grp_G6,
        $fer_grp_G7
### FIXME: only 3 bits used so far. Is the highest bit used for anything? */

    ) = qw (0 1 2 3 4 5 6 7);

## values of low nibble in data[$fer_dat_TGL_and_MEMB].
####/ Sender IDs
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

###############################################
####
##
    sub fsb_getByDevID($) {
        my ($devID) = @_;
        if (!exists($fsbs->{$devID})) {
            $fsbs->{$devID} = [ (($devID >> 16) & 0xff), (($devID >> 8) & 0xff), ($devID & 0xff), 0x00, 0x00 ];
        }

        return $fsbs->{$devID};
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
##
##
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
##
##
##

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
##
##
    sub fsb2string($) {
        my ($fsb) = @_;
        return sprintf "0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x", $$fsb[0], $$fsb[1], $$fsb[2], $$fsb[3], $$fsb[4];

    }
##
##
#### end ###

##########################################################
#### sniff device ID from string received via SIGNALduino
##
### translate the substring between 'D=' and ';' to our own send timings and return the result;
##
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
                        if ($rf_timings->{"P$k.min"} <= $n && $n <= $rf_timings->{"P$k.max"}) {
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
##
##
### return position of first stop bit (next bit starts first data word)
    sub find_stop($) {
        my ($s) = @_;
        return index($s, $d_stp_string);
    }

##
##
##
### extract devID
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

##
#### end ###

############################################################################
#### send commands to fhem
##
##
    my $map_fcmd = {
        "up"       => $fer_cmd_UP,
        "down"     => $fer_cmd_DOWN,
        "stop"     => $fer_cmd_STOP,
        "set"      => $fer_cmd_SET,
        "sun-down" => $fer_cmd_SunDOWN,
        "sun-inst" => $fer_cmd_SunINST,
		    };

    sub get_commandlist() { return keys(%$map_fcmd); }
    sub is_command_valid($) { my ($command) = @_;  return exists $map_fcmd->{$command}; }

    sub cmd2sdCMD($) {
        my ($fsb) = @_;
        return "set sduino raw " . $p_string . cmd2dString($fsb);
    }
##
##
    sub args2cmd($) {
        my ($args) = @_;

        my $fsb;

        if (exists($$args{'a'})) {
            my $val = $$args{'a'};
            $fsb = fsb_getByDevID($val);
        }
        else {
            $fsb = fsb_getByDevID($C->{'centralUnitID'});    # default
        }

        if (exists($$args{'c'})) {
            my $val = $$args{'c'};
            if (exists($map_fcmd->{$val})) {
                FSB_PUT_CMD($fsb, $map_fcmd->{$val});
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

package Fernotron {
################### FHEM ######################################
    sub Fernotron_Define($$) {
        my ($hash, $def) = @_;
        my $name = $hash->{NAME};

        my @a = split("[ \t][ \t]*", $def);
        my ($a, $g, $m) = (undef, 0, 0);
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

        if ($a == undef) {
            return "$name: missing argument 'a'";
        }

        #FIXME-bw/24-Nov-17: validate options
        $hash->{helper}{ferid_a} = $a;
        $hash->{helper}{ferid_g} = $g;
        $hash->{helper}{ferid_m} = $m;

        main::AssignIoPort($hash);

        return undef;
    }

    sub Fernotron_transmit($$$) {
        my ($hash, $command, $c) = @_;
        my $name = $hash->{NAME};
        my $args = {
            command => $command,
            a       => $hash->{helper}{ferid_a},
            g       => $hash->{helper}{ferid_g},
            m       => $hash->{helper}{ferid_m},
            c       => $c,
        };
        my $fsb = FernotronDrv::args2cmd($args);
        if ($fsb != -1) {
            print "$name: send messasge: " . fsb2string($fsb) . "\n";
            my $msg = FernotronDrv::cmd2sdString($fsb);    # print "debug: $p_string$tx_data\n";
            main::IOWrite($hash, 'raw', $msg);
        }
        else { print "no fsb\n"; }
    }

    sub Fernotron_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;
        return "\"set $name\" needs at least one argument" unless (defined($cmd));

        main::AssignIoPort($hash);           # if undef $hash->{IODev};
        my $io = $hash->{IODev} or return '"no io device"';

        if ($cmd eq '?') {
            my $res = "unknown argument $cmd choose one of ";
            foreach my $key (FernotronDrv::get_commandlist()) {
                $res .= " $key:noArg";
            }
            return $res;
        }

        if (FernotronDrv::is_command_valid($cmd)) {
            Fernotron_transmit($hash, 'send', $cmd);
        }
        else {
            return "unknown argument $cmd choose one of " . join(' ', FernotronDrv::get_commandlist());
        }
        return undef;
    }

}

package main {

    sub Fernotron_Initialize($) {
        my ($hash) = @_;

        $hash->{DefFn} = 'Fernotron::Fernotron_Define';
        $hash->{SetFn} = "Fernotron::Fernotron_Set";
    }

}

1;

=pod
=item device
=item summary controls shutters via Fernotron protocol
=item summary_DE steuert Rolläden über Fernotron Protokoll

=begin html

<a name="Fernotron"></a>

 <h3>Fernotron</h3>

     <i>Fernotron</i> is a logic module to control shutters using Fernotron protocol. It generates commands wich are then send via <i>SIGNALduino</i> as raw message. <i>Fernotron</i> could also 
turn back received raw messages into commands.  But Fernotron protocol is unidirectional, so there is not much to receive.


<h4>Basics</h4>

Each device has is using an uniq ID number. A receiver remembers the ID of a controller. That way they are linked together. Each receiver can 'member one central controller unit (incl the group and member numbers), one sun sensor and a few plain controllers.

h4>Defining Devices</h4>

Each device may control a single shutter, but could also control an entire group.  This depends on the ID and the group and member numbers.

<p><code>
    define <my_shutter> Fernotron a=ID [g=GN] [m=MN]<br>
</code>			
		
  <p>  ID : the device ID. A six digit hexadecimal number. 10xxxx=plain controller, 20xxxx=sun sensor, 80xxxx=central controller unit, 90xxxx=receiver<br>
    GN : group number (1-7) or 0 (default) for all groups<br>
    MN : member number  (1-7) or  0 (default) for all group members<br>

			
<p>'g' or  'n' are only useful combined with an ID of the central controller type. 


<h4>Different Kinds of Adressing</h4>

<ol>
<li> Scanning physical controllers and use their IDs. Example: Using the  ID of a  2411 controller to access shutters via group and member numbers.</li>

<li> Make up IDs and pair them with shutters. Example: Pair shutter 1 with ID 100001, shutter  2 with 100002, ...</li>

<li> Receiver IDs: RF controlled shutters may have a 5 digit code printed on or on a small cable sticker. Prefix a 9 with it and you get an ID.</li>
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
<li><code>define rollo42 Fernotron a=80808 g=4 m=2</code></li>
</ul></li>

  <li><ul>
<li><code>define rollo1 Fernotron a=100001 </code></li>
<li>enable set mode on the receiver</li>
<li>press stop for rollo1</li>
</ul></li>

  <li><ul>
<li><code>define rollo_0d123 Fernotron a=90d123</code></li>
</ul></li>
</ol>
=end html


=begin html_DE

<a name="Fernotron"></a>

 <h3>Fernotron</h3>

     <i>Fernotron</i> ist ein logisches Modul zur Steuerung von Fernotron Rolläden.  Die erzeugten Kommandos werden über <i>SIGNALduino</i> als Raw gesendet. <i>Fernotron</i> kann außerdem empfangene Raw Nachrichten wieder in Kommandos umwandeln, was aber bei einem unidirektionalem Protokoll nicht sehr viel Nutzen bringt. 


<h4>Grundlagen</h4>

Jedes Gerät eine ID-Nummer ab Werk fest einprogrammiert. Empfänger und Sender werden gekoppelt, indem sich der Empfänger die ID des Senders merkt. Jeder Empfänger kann sich je eine ID einer Zentraleinheit (inklusive Gruppe und Empfängernummer), eines Sonnensensors und mehrerer Handsender merken.


<h4>Gerät definieren</h4>

Ein Gerät kann einen einzige Rolladen aber  auch eine ganze Gruppe ansprechen.  Dies wird durch die verwendete ID und Gruppen und Empfängernummer bestimmt.

<p><code>
    define <MeinRolladen> Fernotron a=ID [g=GN] [m=MN]<br>
</code>
			
		
<p>    ID : Die Geräte ID. Eine  sechstellige hexadezimale Zahl.  10xxxx=Handsender, 20xxxx=Sonnensensor, 80xxxx=Zentraleinheit, 90xxxx=Empfänger<br>
    GN : Gruppennummer (1-7) oder 0 (default) für alle Gruppen<br>
    MN : Empfängernummer (1-) oder 0 (default) für alle Empfänger<br>
			
<p>'g' und 'n' sind nur sinnvoll, wenn als ID eine Zentraleinheit angegeben wurde 


<h4>Verschiedene Methoden der Adressierung</h4>

<ol>
<li> Die IDs vorhandener Sende-Geräte einscannen und dann benutzen. Beispiel: Die ID der 2411 benutzen um dann über Gruppen und Empfängernummern die Rolläden anzusprechen.</li>

<li> Ausgedachte IDs mit Motoren zu koppeln.  Beispiel: Rolladen Nr 1 mit 100001, Nr 2 mit 100002, ...</li>

<li> Empfänger IDs: Funkmotoren haben 5 stellige "Funk-Codes" aufgedruckt, eigentlich gedacht zur Inbetriebnahme. Es muss eine 9 davorgestellt werden um die ID zu erhalten.</li>
</ol>

<h4>Gruppenbildung</h4>

<ol>
<li>Gruppen und Empfäger entsprechen der 2411. Gruppenbildung durch die 0 als Joker.  (g=1 m=0 oder g=0 m=1) </li>

<li> Wie bei realen Handsendern. Beispiel: Ein (virtueller) Handsender wird bei allen Motoren einer Etage angemeldet.</li>

<li> nicht möglich</li>
</ol>


<h4>Kommandos</h4>

<ul>
<li>up - öffnen</li>
<li>down - schließen</li>
<li>stop - anhalten</li>
<li>set  - Setzfunktion aktivieren</li>
<li>sun-down - Herunterfahren bis Sonnenposition (nur bei aktiverter Sonnenautomatik)</li>
<li>sun-inst - aktuelle Position als Sonnenposition speichern</li>
</ul>

<h4>Beispiele</h4>
<ol>
  <li><ul>
<li>scanne die ID der 2411 mit fhemft.pl (FIXME)</li>
<li><code>define rollo42 Fernotron a=80abcd g=4 m=2</code></li>
</ul></li>

  <li><ul>
<li><code>define rollo1 Fernotron a=100001 </code></li>
<li>aktivere Set-Modus des gewünschten Motors</li>
<li><code>set rollo1 stop</code></li>
</ul></li>

  <li><ul>
<li><code>define rollo_0d123 Fernotron a=90d123</code></li>
</ul></li>
</ol>

=end html_DE

=cut

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Fernotron.pm"
# End:

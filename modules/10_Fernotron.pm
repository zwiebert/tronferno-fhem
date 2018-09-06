######################################
## *experimental* FHEM module Fernotron
## FHEM module to control Fernotron devices via SIGNALduino hardware
## Author: Bert Winkelmann <tf.zwiebert@online.de>
##
## - copy or softlink this file to /opt/fhem/FHEM/10_Fernotron.pm
##
## - patch SIGNALduino
##    sudo patch /opt/fhem/FHEM/00_SIGNALduino.pm  ./signalduino.diff
##

use strict;

use 5.14.0;


package Fernotron::Drv {

    my $def_cu = '801234';

################################################
### timings

## PRE_STP_DT1_ON, #P0  +2 * 200us =  +400us
## PRE_DT0_OFF,    #P1  -2 * 200us =  -400us
## STP_OFF,        #P2 -16 * 200us = -3200us
## DT1_OFF,        #P3  -4 * 200us =  -800us
## DT0_ON,         #P4  +4 * 200us =  +800us

    my $fmt_string = 'SR;R=%d;%sD=%s%s%s;';    # repeats, p_string, d_stp_string, d_pre_string, data

    my $p_string = 'P0=400;P1=-400;P2=-3200;P3=-800;P4=800;';

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

    #                    1 2 3 4 5 6 7
    my $d_pre_string = '01010101010101';    # preamble
    my $d_stp_string = '02';                # stop comes before each preamble and before each word
    my $d_dt0_string = '41';                # data bit 0 (/..long..\short)
    my $d_dt1_string = '03';                # data bit 1 (/short\..long..)

    # global configuration
    my $C = {
        'centralUnitID' => 0x8012ab,        # FIXME:-bw/23-Nov-17
    };

    # the latest command for each target device is stored as array of 5 bytes
    # example: 0x8012ab => [0x80, 0x12, 0xab, 0x12, 0x34]
    # use: to implement rolling counter
    my $fsbs = {};

    sub dbprint($) {
        main::Log3(undef, 5, "Fernotron: $_[0]");    # global verbose level used
    }

########################################################
### convert a single byte to a string of two 10bit words
########################################################
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
    sub byte2dString {
        my $res = "";
        foreach my $b (@_) {
            $res .= $d_stp_string . word2dString(byte2word($b, 0)) . $d_stp_string . word2dString(byte2word($b, 1));
        }
        return $res;
    }
#### end ###

################################################
#### convert a byte commmand to a data string
##
##
    # calc checksum to @array,
    sub calc_checksum($$) {
        my ($cmd, $cs) = @_;
        foreach my $b (@$cmd) {
            $cs += $b;
        }
        return (0xff & $cs);
    }

    # convert 5-byte message into SIGNALduino raw message
    sub cmd2sdString($$) {
        my ($fsb, $repeats) = @_;
        return sprintf($fmt_string, $repeats + 1, $p_string, $d_stp_string, $d_pre_string, byte2dString(@$fsb, calc_checksum($fsb, 0)));

        # return $p_string . "D=$d_stp_string$d_pre_string" . byte2dString(@$fsb, calc_checksum($fsb, 0)) . ';';
    }

#### end ###

### some constants
##
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
        } elsif ($repeats > 0) {
            $step = (FSB_GET_CMD($fsb) == $fer_cmd_STOP ? 1 : 0);
        } else {
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

############################################################
#### decode command from SIGNALduino's dispatched DMSG
##
##

    # checksum may be truncated by older SIGNALduino versions, so verify if ID and MEMB match
    sub fsb_verify_by_id($) {
        my ($fsb) = @_;
        my $m = FSB_GET_MEMB($fsb);

        return ($m == $fer_memb_Broadcast || ($fer_memb_M1 <= $m && $m <= $fer_memb_M7)) if FSB_MODEL_IS_CENTRAL($fsb);
        return ($m == $fer_memb_SUN)        if FSB_MODEL_IS_SUNSENS($fsb);
        return ($m == $fer_memb_SINGLE)     if FSB_MODEL_IS_STANDARD($fsb);
        return ($m == $fer_memb_RecAddress) if FSB_MODEL_IS_RECEIVER($fsb);

        return 0;
    }

    # convert byte string to bit string (no longer needed for dev-33)
    sub fer_byteHex2bitMsg($) {
        my ($byteHex) = @_;
        my $bitMsg = '';
        for my $b (split(//, $byteHex)) {
            $bitMsg .= sprintf("%04b", hex($b));
        }
        return $bitMsg;
    }

    # convert dmsg to just bits (by simply removing the F (floating) characters
    sub fer_dev33dmsg2bitMsg($) {
	my ($dmsg) = @_;
	$dmsg =~ s/F//g;
	return $dmsg;
    }

    # convert 10bit string to 10bit word
    sub fer_bin2word($) {
        return unpack("N", pack("B32", substr("0" x 32 . reverse(shift), -32)));
    }

    # split long bit string to array of 10bit strings. disregard trailing bits.
    sub fer_bitMsg_split($) {
        my @bitArr = unpack('(A10)*', shift);
        $#bitArr -= 1 if length($bitArr[$#bitArr]) < 10;
        return \@bitArr;
    }

    # convert  array of 10bit strings to array of 10bit words
    sub fer_bitMsg2words($) {
        my ($bitArr) = @_;
        my @wordArr = ();

        foreach my $ws (@$bitArr) {
            push(@wordArr, fer_bin2word($ws));
        }
        return \@wordArr;
    }

    # convert array of 10bit words into array of 8bit bytes
    sub fer_words2bytes($) {
        my ($words) = @_;
        my @bytes = ();

        for (my $i = 0; $i < scalar(@$words); $i += 2) {
            my $w0 = $$words[$i];
            my $w1 = $$words[ $i + 1 ];
            my $p0 = defined($w0) && fer_get_word_parity($w0, 0);
            my $p1 = defined($w1) && fer_get_word_parity($w1, 1);

            if ($p0 ne 0) {
                push(@bytes, $w0 & 0xff);

            } elsif ($p1 ne 0) {
                push(@bytes, $w1 & 0xff);
            } else {
                return \@bytes;
            }
        }
        return \@bytes;
    }

    # convert decoded message from SIGNALduino dispatch to Fernotron byte message
    sub fer_sdDmsg2Bytes($) {
	my ($dmsg) = @_;
	
	my $bit_msg =  (length($dmsg) < 100) ? fer_byteHex2bitMsg($dmsg) : fer_dev33dmsg2bitMsg($dmsg);
        return fer_words2bytes(fer_bitMsg2words(fer_bitMsg_split($bit_msg)));
    }
##
##
##### end ####


############################################################################
#### convert a/g/m into Fernotron byte message
##
##
    my $map_fcmd = {
        "up"       => $fer_cmd_UP,
        "down"     => $fer_cmd_DOWN,
        "stop"     => $fer_cmd_STOP,
        "set"      => $fer_cmd_SET,
        "sun-down" => $fer_cmd_SunDOWN,
        "sun-up"   => $fer_cmd_SunUP,
        "sun-inst" => $fer_cmd_SunINST,
    };

    my $last_error = "";
    sub get_last_error() { return $last_error; }

    sub get_commandlist() { return keys(%$map_fcmd); }
    sub is_command_valid($) { my ($command) = @_; dbprint($command); return exists $map_fcmd->{$command}; }

    sub get_command_name_by_number($) {
        my ($cmd) = @_;
        my @res = grep { $map_fcmd->{$_} eq $cmd } keys(%$map_fcmd);
        return $#res >= 0 ? $res[0] : "";
    }

##
##
    # convert args into 5-Byte message (checksum will be added by caller)
    sub args2cmd($) {
        my ($args) = @_;

        my $fsb;

        if (exists($$args{'a'})) {
            my $val = $$args{'a'};
            $fsb = fsb_getByDevID($val);
        } else {
            $fsb = fsb_getByDevID($C->{'centralUnitID'});    # default
        }

        if (exists($$args{'c'})) {
            my $val = $$args{'c'};
            if (exists($map_fcmd->{$val})) {
                FSB_PUT_CMD($fsb, $map_fcmd->{$val});
            } else {
                $last_error = "error: unknown command '$val'\n";
                return -1;
            }
        }

        if (exists($$args{'g'})) {
            my $val = $$args{'g'};
            if (0 <= $val && $val <= 7) {
                FSB_PUT_GRP($fsb, $fer_grp_Broadcast + $val);
            } else {
                $last_error = "error: invalid group '$val'\n";
                return -1;
            }
        } else {
            FSB_PUT_GRP($fsb, $fer_grp_Broadcast);    # default
        }

        if (FSB_MODEL_IS_CENTRAL($fsb)) {
            my $val = 0;
            $val = $$args{'m'} if exists $$args{'m'};
            if ($val == 0) {
                FSB_PUT_MEMB($fsb, $fer_memb_Broadcast);
            } elsif (1 <= $val && $val <= 7) {
                FSB_PUT_MEMB($fsb, $fer_memb_M1 + $val - 1);
            } else {
                $last_error = "error: invalid member '$val'\n";
                return -1;
            }
        } elsif (FSB_MODEL_IS_RECEIVER($fsb)) {
            FSB_PUT_MEMB($fsb, $fer_memb_RecAddress);
        } elsif (FSB_MODEL_IS_SUNSENS($fsb)) {
            FSB_PUT_MEMB($fsb, $fer_memb_SUN);
        } elsif (FSB_MODEL_IS_STANDARD($fsb)) {
            FSB_PUT_MEMB($fsb, $fer_memb_SINGLE);
        } else {
            FSB_PUT_MEMB($fsb, $fer_memb_Broadcast);    # default
        }

        fsb_doToggle($fsb);
        return $fsb;
    }
}
 	

package Fernotron {
#old: dmsg: P82#01406481232C4B294652C4712
#dev-33: dmsg: P82#F0000000101F0000000110F1001001001F1001001010F1011101001F1011101010F1001111001F1001111010F1100010001F1100010010F010000110
    sub Fernotron_Parse {
        my ($io_hash, $message) = @_;

        my ($proto, $dmsg) = split('#', $message);
        my $address = 'Fernotron';
        my $fsb     = Fernotron::Drv::fer_sdDmsg2Bytes($dmsg);

	
        return undef if (ref($fsb) ne 'ARRAY' || scalar(@$fsb) < 5);
        return undef unless Fernotron::Drv::fsb_verify_by_id($fsb);

        my $msg = sprintf("%02x, %02x, %02x, %02x, %02x", @$fsb);
        main::Log3($io_hash, 3, "Fernotron: message received: $msg");

        if (my $hash = $main::modules{Fernotron}{defptr}{$address}) {

            # Nachricht für $hash verarbeiten
            $hash->{received_Bytes} = $msg;
            $hash->{received_HR}
                = sprintf("a=%02x%02x%02x, c=%s", $$fsb[0], $$fsb[1], $$fsb[2], Fernotron::Drv::get_command_name_by_number(Fernotron::Drv::FSB_GET_CMD($fsb)));

            # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.
            return $hash->{NAME};
        }

        return undef;
    }


    sub Fernotron_Define($$) {
        my ($hash, $def) = @_;
        my @a       = split("[ \t][ \t]*", $def);
        my $name    = $a[0];
        my $address = $a[1];

        my ($a, $g, $m) = (0, 0, 0);
        my $u    = 'wrong syntax: define <name> Fernotron a=ID [g=N] [m=N]';
        my $scan = 0;

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
            } elsif ($key eq 'scan') {
                $scan = 1;
                $main::modules{Fernotron}{defptr}{$address} = $hash;
            } else {
                return "$name: unknown argument $o in define";    #FIXME add usage text
            }
        }

        if ($scan eq 0) {
            main::Log3($name, 3, "a=$a g=$g m=$m\n");
            return "missing argument a" if ($a == 0);
            $hash->{helper}{ferid_a} = $a;
            $hash->{helper}{ferid_g} = $g;
            $hash->{helper}{ferid_m} = $m;
        }
        main::AssignIoPort($hash);

        return undef;
    }

    sub Fernotron_transmit($$$) {
        my ($hash, $command, $c) = @_;
        my $name = $hash->{NAME};
        my $io   = $hash->{IODev};

        return 'error: IO device not open' unless (exists($io->{NAME}) and main::ReadingsVal($io->{NAME}, 'state', '') eq 'opened');

        my $args = {
            command => $command,
            a       => $hash->{helper}{ferid_a},
            g       => $hash->{helper}{ferid_g},
            m       => $hash->{helper}{ferid_m},
            c       => $c,
            r       => int(main::AttrVal($name, 'repeats', '1')),
        };
        my $fsb = Fernotron::Drv::args2cmd($args);
        if ($fsb != -1) {
            main::Log3($name, 1, "$name: send: " . Fernotron::Drv::fsb2string($fsb));
            my $msg = Fernotron::Drv::cmd2sdString($fsb, $args->{r});
            main::Log3($name, 3, "$name: raw: $msg");
            main::IOWrite($hash, 'raw', $msg);
        } else {
            return Fernotron::Drv::get_last_error();
        }
        return undef;

    }

    sub Fernotron_Set($$@) {
        my ($hash, $name, $cmd, @args) = @_;
        return "\"set $name\" needs at least one argument" unless (defined($cmd));
        my $u = "unknown argument $cmd choose one of ";

        if ($main::modules{Fernotron}{defptr}{'Fernotron'} eq $hash) {    ## receiver
            return $u;                                                    # nothing to set for receiver

        }

        my $io = $hash->{IODev} or return '"no io device"';

        if ($cmd eq '?') {
            foreach my $key (Fernotron::Drv::get_commandlist()) {
                $u .= " $key:noArg";
            }
            return $u;
        }

        if (Fernotron::Drv::is_command_valid($cmd)) {
            my $res = Fernotron_transmit($hash, 'send', $cmd);
            main::readingsSingleUpdate($hash, 'state', $cmd, 0) if ($res eq undef);
            return $res unless ($res eq undef);
        } else {
            return "unknown argument $cmd choose one of " . join(' ', Fernotron::Drv::get_commandlist());
        }

        return undef;
    }

    sub Fernotron_Attr(@) {
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

    sub Fernotron_Initialize($) {
        my ($hash) = @_;
        $hash->{Match}    = "^P82#.+";
        $hash->{AttrList} = 'repeats:0,1,2,3,4,5';

        $hash->{DefFn}   = 'Fernotron::Fernotron_Define';
        $hash->{SetFn}   = "Fernotron::Fernotron_Set";
        $hash->{ParseFn} = "Fernotron::Fernotron_Parse";
        $hash->{AttrFn}  = "Fernotron::Fernotron_Attr";
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

<i>Fernotron</i> is a logic module to control shutters using Fernotron protocol. 
It generates commands wich are then send via <i>SIGNALduino</i>. <i>Fernotron</i> can also receive messages sent by other Fernotron controllers. The Fernotron shutters communicate unidirectional, so they don't sent any feedback information, like if they are currently open or close.



<h4>Pairing</h4>

Each controller has an uniq ID number. To pair a shutter to one or more controller(s), the shutter just remembers the ID of each controller.

Each receiver can rmember one central controller unit (incl the group and member numbers), one sun sensor and some plain up/stop/down switches.

Shutter motors have also an ID number printed on.  If you have no easy access to the pyhsical Set-Button of the shutter motor, that ID can be used to initiate pairing/unpairing or adjust rotation direction and end-positions. 
 


<h4>Defining Devices</h4>

Each device may control a single shutter, but could also control an entire group.
This depends on the ID and the group and member numbers.

<p>
				    
  <code>
    define <my_shutter> Fernotron a=ID [g=GN] [m=MN]<br>
  </code>			
		
<p> 
  ID : the device ID. A six digit hexadecimal number. 10xxxx=plain controller, 20xxxx=sun sensor, 80xxxx=central controller unit, 90xxxx=receiver<br>
  GN : group number (1-7) or 0 (default) for all groups<br>
  MN : member number  (1-7) or  0 (default) for all group members<br>

<p>
  'g' or  'n' are only useful combined with an ID of the central controller type. 

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


<h4>Commands</h4>

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
      <li>first scan the ID of the 2411: <code>define scanFerno Fernotron scan</code>.  Hold down the stop button of your 2411 some time. Now open the scanFerno on the FHEM web-interface.  The ID is found under Internals:received_HR</li>
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

<i>Fernotron</i> ist ein logisches Modul zur Steuerung von Fernotron Rolläden.
Die erzeugten Kommandos werden über <i>SIGNALduino</i> gesendet.
<i>Fernotron</i> kann außerdem Nachrichten empfangen die von anderen Fernotron-Kontrollern  gesendet werden. Die Rolläden kommunizieren unidirektional. Sie senden also leider keine Feedback Information wie offen/geschlossen.


<h4>Kopplung</h4>

Jeder Kontroller eine ID-Nummer ab Werk fest einprogrammiert.
Empfänger und Sender werden gekoppelt, indem sich der Empfänger die ID eines bzw. mehrerer Sender merkt.
Jeder Empfänger kann sich je eine ID einer Zentraleinheit (inklusive Gruppe und Empfängernummer), eines Sonnensensors und mehrerer Handsender merken.

Rolladen-Motore haben ebenfalls eine ID Nummer aufgedruckt.  Wenn kein Zugang zum physischen Setz-Taster des Motors besteht, kann diese ID benutzt werden um den Koppelvorgang einzuleiten oder Einstellung der Drehrichtung und Endpunkte vorzunehmen.


<h4>Gerät definieren</h4>

Ein Gerät kann einen einzige Rolladen aber  auch eine ganze Gruppe ansprechen.
Dies wird durch die verwendete ID und Gruppen und Empfängernummer bestimmt.

<p>
  <code>
    define <MeinRolladen> Fernotron a=ID [g=GN] [m=MN]<br>
  </code>
			
		
<p>  
  ID : Die Geräte ID. Eine  sechstellige hexadezimale Zahl.  10xxxx=Handsender, 20xxxx=Sonnensensor, 80xxxx=Zentraleinheit, 90xxxx=Empfänger<br>
  GN : Gruppennummer (1-7) oder 0 (default) für alle Gruppen<br>
  MN : Empfängernummer (1-) oder 0 (default) für alle Empfänger<br>
			
<p>
  'g' und 'n' sind nur sinnvoll, wenn als ID eine Zentraleinheit angegeben wurde 


<h4>Verschiedene Methoden der Adressierung</h4>

<ol>
  <li> Die IDs vorhandener Sende-Geräte (oder einfach nur die ID der Zentrale 2411) einscannen und dann benutzen.
    Beispiel: Die ID der 2411 benutzen um dann über Gruppen und Empfängernummern die Rolläden anzusprechen.</li>

  <li> Ausgedachte Handsender IDs mit Motoren zu koppeln.
    Beispiel: Rolladen Nr 1 mit 100001, Nr 2 mit 100002, ...</li>

  <li> Empfänger IDs: Funkmotoren haben 5 stellige "Funk-Codes" aufgedruckt, eigentlich gedacht zur Inbetriebnahme.
    Es muss eine 9 davorgestellt werden um die ID zu erhalten.</li>
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
      <li>scanne die ID der 2411: <code>define scanFerno Fernotron scan</code>. Den Stop Taster der 2411 einige Sekunden drücken. Das scanFerno Gerät über die FHEM-Webseite öffnen. DIe ID der 2411 steht nun  unter Internals:received_HR.</li>
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

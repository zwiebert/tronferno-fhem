################################################################################
## *experimental* FHEM module for Fernotron devices
##
##  - file: /opt/fhem/FHEM/10_Fernotron.pm
##  - needs IODev SIGNALduino v3.3.3
##  - to send commands to Fernotron devices
##  - to recveive commands from Fernotron controllers
##
## Fernotron is a legacy unidirectional 434MHz protocol for shutters and lights
################################################################################
## Author: Bert Winkelmann <tf.zwiebert@online.de>
## Project: https://github.com/zwiebert/tronferno-fhem
################################################################################

package Fernotron::fhem;
use strict;
use warnings;
use v5.20;
use feature qw(signatures);
no warnings qw(experimental::signatures);

package main;
use subs qw(AssignIoPort AttrVal IOWrite Log3 ReadingsVal readingsSingleUpdate);

package Fernotron::Protocol;
################################################################################
###

# for sendMsg()
my $d_float_string = 'D';  # or 'F'
my $d_pause_string = $d_float_string . 'PPPPPPP';
my $fmt_dmsg_string = 'P82#%s%s#R%d';  # d_pause_string, data, repeats

# the latest command for each target device is stored as array of 5 bytes
# example: 0x8012ab => [0x80, 0x12, 0xab, 0x12, 0x34]
# use: to implement rolling counter
my $fsbs = {};

sub dbprint($) {
    #main::Log3(undef, 0, "Fernotron: $_[0]");    # verbose level of IODev may be used here
}

################################################################################
### convert a single byte to a string of two 10bit words
################################################################################
##
##  "t if VAL contains an even number of 1 bits"
sub is_bits_even($val) {

    $val ^= $val >> 4;
    $val ^= $val >> 2;
    $val ^= $val >> 1;
    $val &= 0x01;
    return ($val == 0);
}
##
sub fer_get_word_parity($data_byte, $pos) {
    my $is_even = is_bits_even($data_byte);
    return (($pos & 1)) ? ($is_even ? 3 : 1) : ($is_even ? 0 : 2);
}
## create 10bit word from 8bit byte (pos: 0 or 1)
sub fer_word_from_byte($data_byte, $pos) {
    return ($data_byte | (fer_get_word_parity($data_byte, $pos) << 8));
}
##
sub fer_bits_from_word($w) {
    my $r = '';
    for (my $i = 0; $i < 10; ++$i) {
        $r .= (0 == (($w >> $i) & 1) ? '0' : '1');
    }
    return $r;
}

##
## turn databytes into bit string with two 10bit words for each byte and one stop bit before each word
##
sub fer_dmsg_from_msgBytes(@msgBytes) {
    my $res = "";
    foreach my $b (@msgBytes) {
        $res .= $d_float_string . fer_bits_from_word(fer_word_from_byte($b, 0)) . $d_float_string . fer_bits_from_word(fer_word_from_byte($b, 1));
    }
    return $res;
}
#### end ###

################################################
#### convert a byte commmand to a data string
##
##
# calc checksum for @array,
sub fer_checkSum_from_msgBytes($cmd, $cs) {
    foreach my $b (@$cmd) {
        $cs += $b;
    }
    return (0xff & $cs);
}

# convert 5-byte message into SIGNALduino message like DMSG
sub fer_outDmsg_from_byteMsg($fsb, $repeats) {
    return sprintf($fmt_dmsg_string,
                   $d_pause_string,
                   fer_dmsg_from_msgBytes(@$fsb, fer_checkSum_from_msgBytes($fsb, 0)),
                   $repeats + 1);
}

#### end ###

### some constants
##
use constant {
    fer_dat_ADDR_2 => 0,
    fer_dat_ADDR_1 => 1,
    fer_dat_ADDR_0 => 2,         ## sender or receiver address
    fer_dat_TGL_and_MEMB => 3,   # key-press counter + some ID of the sender (like Member number, Type of sender, ...)
    fer_dat_GRP_and_CMD => 4     # Group-ID of sender + the command code (0...0xF)
};

## values of low nibble in data[fer_dat_GRP_and_CMD].
####/ Command Codes
use constant {
    fer_cmd_None => 0,
    fer_cmd_1 => 1,
    fer_cmd_2 => 2,
    fer_cmd_STOP => 3,
    fer_cmd_UP => 4,
    fer_cmd_DOWN => 5,
    fer_cmd_SunDOWN => 6,
    fer_cmd_SunUP => 7,
    fer_cmd_SunINST => 8,
    fer_cmd_EndPosUP => 9,
    fer_cmd_endPosDOWN => 10,
    fer_cmd_0xb => 11,
    fer_cmd_0xc => 12,
    fer_cmd_SET => 13,
    fer_cmd_0xe => 14,
    fer_cmd_Program => 15    # Sun-Test (dat_MEMB=1), Time send (dat_Memb=0), Data send (dat_MEMB=member)
};

## values of high nibble in data[$fer_dat_GRP_and_CMD].
####/ Sender IDs
use constant {
    fer_grp_Broadcast => 0,
    fer_grp_G1 => 1,
    fer_grp_G2 => 2,
    fer_grp_G3 => 3,
    fer_grp_G4 => 4,
    fer_grp_G5 => 5,
    fer_grp_G6 => 6,
    fer_grp_G7 => 7
        ### FIXME: only 3 bits used so far. Is the highest bit used for anything? */
};

## values of low nibble in data[fer_dat_TGL_and_MEMB].
####/ Sender IDs
use constant {
    fer_memb_Broadcast => 0,    # RTC data, ...
    fer_memb_SUN => 1,          # sent by SunSensor
    fer_memb_SINGLE => 2,       # sent by hand sender
    fer_memb_P3 => 3,
    fer_memb_P4 => 4,
    fer_memb_P5 => 5,
    fer_memb_P6 => 6,
    fer_memb_RecAddress => 7,    # fer_dat_ADDR contains address of the receiver (set function via motor code)
    fer_memb_M1 => 8,            #8
    fer_memb_M2 => 9,
    fer_memb_M3 => 10,
    fer_memb_M4 => 11,
    fer_memb_M5 => 12,
    fer_memb_M6 => 13,
    fer_memb_M7 => 14,
};

###############################################
####
##
sub fsb_getByDevID($devID) {
    if (!exists($fsbs->{$devID})) {
        $fsbs->{$devID} = [ (($devID >> 16) & 0xff), (($devID >> 8) & 0xff), ($devID & 0xff), 0x00, 0x00 ];
    }

    return $fsbs->{$devID};
}

sub fer_tglNibble_ctUp($toggle_nibble, $step) {
    my $result = 0xff & ($toggle_nibble + $step);
    if ($result < $toggle_nibble) {
        ++$result;
    }

    return ($result > 15) ? 1 : $result;
}

my $FDT_MASK = 0xff; # 0xf0 or 0xff (more strict)

sub FSB_MODEL_IS_INVALID($) { # assumes that low nibble is zero in any device  (not sure if this is true)
    my ($fsb) = @_;
    return ($$fsb[0] & 0x0f) != 0;
}


sub FSB_MODEL_IS_CENTRAL($fsb) {
    return ($$fsb[0] & $FDT_MASK) == 0x80;
}

sub FSB_MODEL_IS_RECEIVER($fsb) {
    return ($$fsb[0] & $FDT_MASK) == 0x90;
}

sub FSB_MODEL_IS_SUNSENS($fsb) {
    return ($$fsb[0] & $FDT_MASK) == 0x20;
}

sub FSB_MODEL_IS_STANDARD($fsb) {
    return ($$fsb[0] & $FDT_MASK) == 0x10;
}

sub FSB_GET_DEVID($fsb) {
    return $$fsb[fer_dat_ADDR_2] << 16 | $$fsb[fer_dat_ADDR_1] << 8 | $$fsb[fer_dat_ADDR_0];
}

sub FSB_GET_CMD($fsb) {
    return ($$fsb[fer_dat_GRP_and_CMD] & 0x0f);
}

sub FSB_GET_MEMB($fsb) {
    return ($$fsb[fer_dat_TGL_and_MEMB] & 0x0f);
}

sub FSB_PUT_CMD($fsb, $cmd) {
    $$fsb[fer_dat_GRP_and_CMD] = ($$fsb[fer_dat_GRP_and_CMD] & 0xf0) | ($cmd & 0x0f);
}

sub FSB_PUT_MEMB($fsb, $val) {
    $$fsb[fer_dat_TGL_and_MEMB] = ($$fsb[fer_dat_TGL_and_MEMB] & 0xf0) | ($val & 0x0f);
}

sub FSB_GET_TGL($fsb) {
    return 0x0f & ($$fsb[fer_dat_TGL_and_MEMB] >> 4);
}

sub FSB_PUT_GRP($fsb, $val) {
    $$fsb[fer_dat_GRP_and_CMD] = (($val << 4) & 0xf0) | ($$fsb[fer_dat_GRP_and_CMD] & 0x0f);
}

sub FSB_GET_GRP($fsb) {
    return 0x0f & ($$fsb[fer_dat_GRP_and_CMD] >> 4);
}

sub FSB_PUT_TGL($fsb, $val) {
    $$fsb[fer_dat_TGL_and_MEMB] = (($val << 4) & 0xf0) | ($$fsb[fer_dat_TGL_and_MEMB] & 0x0f);
}
##
##
sub fer_update_tglNibble($fsb, $repeats) {

    my $step = 0;

    if (!FSB_MODEL_IS_CENTRAL($fsb)) {
        $step = 1;
    } elsif ($repeats > 0) {
        $step = (FSB_GET_CMD($fsb) == fer_cmd_STOP ? 1 : 0);
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

sub fsb_doToggle($fsb) {

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
sub fer_stringify_fsb($fsb) {
    return sprintf '0x%02x, 0x%02x, 0x%02x, 0x%02x, 0x%02x', @$fsb;

}
##
##
#### end ###

############################################################
#### decode command from SIGNALduino's dispatched DMSG
##
##

# checksum may be truncated by older SIGNALduino versions, so verify if ID and MEMB match
sub fer_consistency_of_fsb($fsb) {
    my $have_checksum = (scalar(@$fsb) == 6);

    return (($$fsb[0] + $$fsb[1] + $$fsb[2] + $$fsb[3] + $$fsb[4]) & 0xFF) eq $$fsb[5] if ($have_checksum);

    my $m = FSB_GET_MEMB($fsb);

    return ($m == fer_memb_Broadcast || (fer_memb_M1 <= $m && $m <= fer_memb_M7)) if FSB_MODEL_IS_CENTRAL($fsb);
    return ($m == fer_memb_SUN)        if FSB_MODEL_IS_SUNSENS($fsb);
    return ($m == fer_memb_SINGLE)     if FSB_MODEL_IS_STANDARD($fsb);
    return ($m == fer_memb_RecAddress) if FSB_MODEL_IS_RECEIVER($fsb);

    return 0;
}

# convert dmsg to array of 10bit strings. disregard trailing bits.
sub fer_msgBits_from_dmsg($dmsg) {
    my @bitArr = split('F', $dmsg);

    # if dmsg starts with 'F', as it should, remove the empty string at index 0
    shift(@bitArr) if (length($bitArr[0]) == 0);

    return \@bitArr;
}

# convert 10bit string to 10bit word
sub fer_word_from_wordBits($) {
    return unpack('N', pack('B32', substr('0' x 32 . reverse(shift), -32)));
}

# split long bit string to array of 10bit strings. disregard trailing bits.
sub fer_bitMsg_split($) {
    my @bitArr = unpack('(A10)*', shift);
    $#bitArr -= 1 if length($bitArr[-1]) < 10;
    return \@bitArr;
}

# convert  array of 10bit strings to array of 10bit words
sub fer_msgWords_from_msgBits($bitArr) {
    my @wordArr = ();

    foreach my $ws (@$bitArr) {
        if (length($ws) == 10) {
            push(@wordArr, fer_word_from_wordBits($ws));
        } else {
            push (@wordArr, -1);
        }
    }
    return \@wordArr;
}

# convert array of 10bit words into array of 8bit bytes
sub fer_msgBytes_from_msgWords($words) {
    my @bytes1 = ();
    my @bytes2 = ();
    my @idx2 = ();

    for (my $i = 0; $i < scalar(@$words); $i += 2) {
        my $w0 = $$words[$i];
        my $w1 = $$words[ $i + 1 ];
        my $p0 = defined($w0) && ($w0 ne -1) && fer_get_word_parity($w0, 0);
        my $p1 = defined($w1) && ($w1 ne -1) && fer_get_word_parity($w1, 1);

        if ($p0 && $p1 && ($w0&0xff) != ($w1&0xff)) {
            push(@bytes1, $w0 & 0xff);
            push(@bytes2, $w1 & 0xff);
            push(@idx2, $i);
        } elsif ($p0) {
            push(@bytes1, $w0 & 0xff);
            push(@bytes2, undef);
        } elsif ($p1) {
            push(@bytes1, $w1 & 0xff);
            push(@bytes2, undef);
        } else {
            return \@bytes1;
        }
    }
    return \@bytes1 if (scalar(@bytes1) < 6); # no checksum availabe

    my @fsb = @bytes1;

    return \@fsb if ((($fsb[0] + $fsb[1] + $fsb[2] + $fsb[3] + $fsb[4]) & 0xFF) eq $fsb[5]);

    ### if a word is incorrect but has correct parity try to find out the correct one by checksum
    ### not sure how likely this will succeed. never saw it happen

    for (my $j=0; $j < (1 << scalar(@idx2)); ++$j) {
        for (my $i=0; $i < scalar(@idx2); ++$i) {
            my $k = $idx2[$i];
            if (($j & (1<<$k)) && $bytes2[$k]) {
                $fsb[$k] = $bytes2[$k];
            }
        }
        return \@fsb if ((($fsb[0] + $fsb[1] + $fsb[2] + $fsb[3] + $fsb[4]) & 0xFF) eq $fsb[5]);
        @fsb = @bytes1;
    }

    return undef;
}

# convert decoded message from SIGNALduino dispatch to Fernotron byte message
sub fer_msgBytes_from_dmsg($dmsg) {
    dbprint('new bit string dmsg');
    return fer_msgBytes_from_msgWords(fer_msgWords_from_msgBits(fer_msgBits_from_dmsg($dmsg)));
}
##
##
##### end ####


############################################################################
#### convert a/g/m into Fernotron byte message
##
##
my $map_fcmd = {
    'up'       => fer_cmd_UP,
        'down'     => fer_cmd_DOWN,
        'stop'     => fer_cmd_STOP,
        'set'      => fer_cmd_SET,
        'sun-down' => fer_cmd_SunDOWN,
        'sun-up'   => fer_cmd_SunUP,
        'sun-inst' => fer_cmd_SunINST,
};

my $last_error = '';
sub get_last_error() { return $last_error; }

sub fer_cmdNumbers() { return keys(%$map_fcmd); }
sub fer_isValid_cmdName($) { my ($command) = @_; dbprint($command); return exists $map_fcmd->{$command}; }

sub fer_cmdName_from_cmdNumber($cmd) {
    my @res = grep { $map_fcmd->{$_} eq $cmd } keys(%$map_fcmd);
    return $#res >= 0 ? $res[0] : '';
}

##
##
# convert args into 5-Byte message (checksum will be added by caller)
sub fer_msgBytes_from_args($args) {

    my $fsb;

    if (exists($$args{'a'})) {
        my $val = $$args{'a'};
        $fsb = fsb_getByDevID($val);
    } else {
        $last_error = 'error: missing parameter "a"';
        return -1;
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
            FSB_PUT_GRP($fsb, fer_grp_Broadcast + $val);
        } else {
            $last_error = "error: invalid group '$val'\n";
            return -1;
        }
    } else {
        FSB_PUT_GRP($fsb, fer_grp_Broadcast);    # default
    }

    if (FSB_MODEL_IS_CENTRAL($fsb)) {
        my $val = 0;
        $val = $$args{'m'} if exists $$args{'m'};
        if ($val == 0) {
            FSB_PUT_MEMB($fsb, fer_memb_Broadcast);
        } elsif (1 <= $val && $val <= 7) {
            FSB_PUT_MEMB($fsb, fer_memb_M1 + $val - 1);
        } else {
            $last_error = "error: invalid member '$val'\n";
            return -1;
        }
    } elsif (FSB_MODEL_IS_RECEIVER($fsb)) {
        FSB_PUT_MEMB($fsb, fer_memb_RecAddress);
    } elsif (FSB_MODEL_IS_SUNSENS($fsb)) {
        FSB_PUT_MEMB($fsb, fer_memb_SUN);
    } elsif (FSB_MODEL_IS_STANDARD($fsb)) {
        FSB_PUT_MEMB($fsb, fer_memb_SINGLE);
    } else {
        FSB_PUT_MEMB($fsb, fer_memb_Broadcast);    # default
    }

    fsb_doToggle($fsb);
    return $fsb;
}

package Fernotron::fhem;

use constant MODNAME => 'Fernotron';
# names for different kind of fernotron devices
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

sub makeInputKeyByFsb($fsb) {
    my $key =  sprintf('%02x%02x%02x', @$fsb);
    if (Fernotron::Protocol::FSB_MODEL_IS_CENTRAL($fsb)) {
        my $m =  Fernotron::Protocol::FSB_GET_MEMB($fsb);
        if ($m > 0) {
            $m -= 7;
        }
        my $g = Fernotron::Protocol::FSB_GET_GRP($fsb);
        $key .= "-$g-$m";
    }
    return $key;
}

# returns input device hash for this fsb, or default input device, or undef if none exists
sub ff_inputDevice_findBy_fsb($fsb) {
    my $key = makeInputKeyByFsb($fsb);
    my $hash = $main::modules{+MODNAME}{defptr}{$key};
    $hash =  $main::modules{+MODNAME}{defptr}{+DEF_INPUT_DEVICE} unless defined($hash);
    return $hash; # may be undef if no input device exists
}

# update Reading of default input device, if there was no matching input device
sub defaultInputMakeReading($fsb, $hash) {

    ### convert message to human readable parts
    my $kind = Fernotron::Protocol::FSB_MODEL_IS_CENTRAL($fsb) ? FDT_CENTRAL
        : Fernotron::Protocol::FSB_MODEL_IS_RECEIVER($fsb) ? FDT_RECV
        : Fernotron::Protocol::FSB_MODEL_IS_SUNSENS($fsb) ? FDT_SUN
        : Fernotron::Protocol::FSB_MODEL_IS_STANDARD($fsb) ? FDT_PLAIN
        : undef;

    return undef unless $kind;

    my $ad = sprintf('%02x%02x%02x', @$fsb);
    my $g = 0;
    my $m = 0;
    my $gm = '';
    if (Fernotron::Protocol::FSB_MODEL_IS_CENTRAL($fsb)) {
        $m =  Fernotron::Protocol::FSB_GET_MEMB($fsb);
        if ($m > 0) {
            $m -= 7;
        }
        $g = Fernotron::Protocol::FSB_GET_GRP($fsb);
        $gm = " g=$g m=$m";
    }

    my $c = Fernotron::Protocol::fer_cmdName_from_cmdNumber(Fernotron::Protocol::FSB_GET_CMD($fsb));

    ### combine parts and update reading
    my $human_readable = "$kind a=$ad$gm c=$c";
    my $state = "$kind:$ad" . ($kind eq FDT_CENTRAL ? "-$g-$m" : '')  . ":$c";
    $state =~ tr/ /:/; # don't want spaces in reading
    my $do_trigger =  !($kind eq FDT_RECV || $kind eq 'unknown'); # unknown and receiver should not trigger events

    $hash->{received_HR} = $human_readable;
    main::readingsSingleUpdate($hash, 'state',  $state, $do_trigger);
    return 1;
}

# update Reading of matching input device
sub inputMakeReading($fsb, $hash) {
    
    return defaultInputMakeReading($fsb, $hash) if ($hash->{helper}{ferInputType} eq 'scan');

    my $inputType = $hash->{helper}{ferInputType};
    my $c = Fernotron::Protocol::fer_cmdName_from_cmdNumber(Fernotron::Protocol::FSB_GET_CMD($fsb));
    return undef unless defined($c);

    my $do_trigger = 1;

    my $state = undef;

    if ($inputType eq FDT_SUN) {
        $state = $c eq 'sun-down' ? 'on'
            : $c eq 'sun-up' ? 'off' : undef;
    } elsif ($inputType eq FDT_PLAIN) {
        $state = $c;
    } elsif ($inputType eq FDT_CENTRAL) {
        $state = $c;
    }

    return undef unless defined ($state);

    main::readingsSingleUpdate($hash, 'state',  $state, $do_trigger);
    return 1;
}

# create return value for _Parse for autocreate a new in or out device
sub ff_autocreateName_by_fsb($fsb, $is_input) {

    ### convert message to human readable parts
    my $kind = Fernotron::Protocol::FSB_MODEL_IS_CENTRAL($fsb) ? FDT_CENTRAL
        : Fernotron::Protocol::FSB_MODEL_IS_RECEIVER($fsb) ? FDT_RECV
        : Fernotron::Protocol::FSB_MODEL_IS_SUNSENS($fsb) ? FDT_SUN
        : Fernotron::Protocol::FSB_MODEL_IS_STANDARD($fsb) ? FDT_PLAIN
        : undef;

    return undef unless $kind;

    my $ad = sprintf('%02x%02x%02x', @$fsb);
    my $g = 0;
    my $m = 0;
    if (Fernotron::Protocol::FSB_MODEL_IS_CENTRAL($fsb)) {
        $m =  Fernotron::Protocol::FSB_GET_MEMB($fsb);
        if ($m > 0) {
            $m -= 7;
        }
        $g = Fernotron::Protocol::FSB_GET_GRP($fsb);
    }

    my $c = Fernotron::Protocol::fer_cmdName_from_cmdNumber(Fernotron::Protocol::FSB_GET_CMD($fsb));

    my $name = "UNDEFINED Fernotron";
    $name .= "_${kind}" if ($is_input);
    $name .= "_$ad";
    $name .= "_${g}_$m" if ($kind eq FDT_CENTRAL);
    $name .= " Fernotron a=$ad";
    $name .= " g=$g m=$m" if ($kind eq FDT_CENTRAL);
    $name .= " input=$kind" if ($is_input);
    return $name;
}


#dev-33: dmsg: P82#F0000000101F0000000110F1001001001F1001001010F1011101001F1011101010F1001111001F1001111010F1100010001F1100010010F010000110
sub X_Parse {
    my ($io_hash, $message) = @_;
    my $result = undef;

    my ($proto, $dmsg) = split('#', $message);

    my $fsb     = Fernotron::Protocol::fer_msgBytes_from_dmsg($dmsg) or return undef;
    
    my $hash = ff_inputDevice_findBy_fsb($fsb);
    my $default =  $main::modules{+MODNAME}{defptr}{+DEF_INPUT_DEVICE};

    if ($hash and $hash == $default) {
        my $attrCreate = main::AttrVal($hash->{NAME}, ATTR_AUTOCREATE_NAME, ATTR_AUTOCREATE_DEFAULT);
        $hash->{debug} = $attrCreate;
        if ($attrCreate ne ATTR_AUTOCREATE_DEFAULT) {
            my $is_input = $attrCreate eq ATTR_AUTOCREATE_IN;
            return ff_autocreateName_by_fsb($fsb, $is_input); # autocreate specific input device or return undef
        }
    }

    return 'UNDEFINED Fernotron_Scan Fernotron scan' unless ($default || $hash); # autocreate default input device


    my $byteCount = scalar(@$fsb);
    $hash->{received_ByteCount} = "$byteCount";
    $hash->{received_ID} = ($byteCount >= 3) ? sprintf('a=%02x%02x%02x', @$fsb) : undef;
    $hash->{received_CheckSum} = ($byteCount == 6) ? sprintf('%02x', $$fsb[5]) : undef;
    return $result if ($byteCount < 5);

    my $fsb_valid =  Fernotron::Protocol::fer_consistency_of_fsb($fsb);
    $hash->{received_IsValid} = $fsb_valid ? 'yes' : 'no';
    return $result unless $fsb_valid;

    my $msgString = Fernotron::Protocol::fer_stringify_fsb($fsb);
    $hash->{received_Bytes} = $msgString;
    main::Log3($io_hash, 3, "Fernotron: message received: $msgString");


    inputMakeReading($fsb, $hash) or return undef;


    return $hash->{NAME}; # message was handled by this device
}

sub ff_fdType_from_ferId($ad) {
    my $msb = sprintf('%x', ($ad >> 16));
    my $fdt = $msb2fdt->{"$msb"};
    return $fdt;
}

sub X_Define($hash, $def) {
    my @args       = split("[ \t][ \t]*", $def);
    my $name    = $args[0];
    my $address = $args[1];

    my ($ad, $g, $m) = (0, 0, 0);
    my $u    = 'wrong syntax: define <name> Fernotron a=ID [g=N] [m=N] [scan] [input=(sun|plain|central)]';
    my $scan = 0;
    my $is_input = 0;
    my $fdt = '';

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
        } elsif ($key eq 'scan') {
            $scan = 1;

            $main::modules{+MODNAME}{defptr}{+DEF_INPUT_DEVICE} = $hash;
            $hash->{helper}{inputKey} = DEF_INPUT_DEVICE;

            $hash->{helper}{ferInputType} = 'scan';

        } elsif ($key eq 'input') {
            $fdt = $value;
            $is_input = 1;
        } else {
            return "$name: unknown argument $o in define";    #FIXME add usage text
        }
    }

    if ($is_input) {
        my $value = $fdt;
        $fdt = ff_fdType_from_ferId($ad) unless $fdt;

        return "$name: invalid input type: $value in define. Choose one of: sun, plain, central" unless (defined($fdt) && ("$fdt" eq FDT_SUN || "$fdt" eq FDT_PLAIN || "$fdt" eq FDT_CENTRAL));
        $hash->{helper}{ferInputType} = $fdt;
        my $key =  sprintf('%6x', $ad);
        $key .= "-$g-$m" if ("$fdt" eq FDT_CENTRAL);
        $main::modules{+MODNAME}{defptr}{$key} = $hash;
        $hash->{helper}{inputKey} = $key;
        $hash->{fernotron_type} = $fdt;
    }

    if (not $scan) {
        main::Log3($name, 3, "Fernotron ($name): a=$ad g=$g m=$m\n");
        return 'missing argument a' if ($ad == 0);
        $hash->{helper}{ferid_a} = $ad;
        $hash->{helper}{ferid_g} = $g;
        $hash->{helper}{ferid_m} = $m;
    }
    main::AssignIoPort($hash);

    return undef;
}

sub X_Undef($hash, $name) {

    # remove deleted input devices from defptr
    my $key = $hash->{helper}{inputKey};
    delete $main::modules{+MODNAME}{defptr}{$key} if (defined($key));

    return undef;
}

sub transmit($hash, $command, $c) {
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
    my $fsb = Fernotron::Protocol::fer_msgBytes_from_args($args);
    if ($fsb != -1) {
        main::Log3($name, 1, "$name: send: " . Fernotron::Protocol::fer_stringify_fsb($fsb));
        my $msg = Fernotron::Protocol::fer_outDmsg_from_byteMsg($fsb, $args->{r});
        main::Log3($name, 3, "$name: sendMsg: $msg");
        main::IOWrite($hash, 'sendMsg', $msg);
    } else {
        return Fernotron::Protocol::get_last_error();
    }
    return undef;

}

my $cmd2pos = { up => 100, down => 0, 'sun-down' => 50  };

sub X_Set($hash, $name, $cmd = undef, @args) {
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
        foreach my $key (Fernotron::Protocol::fer_cmdNumbers()) {
            $u .= " $key:noArg";
        }
        return $u .  ' position:slider,0,50,100';
    }

    my $io = $hash->{IODev} or return 'error: no io device';


    if (Fernotron::Protocol::fer_isValid_cmdName($cmd)) {
        my $res = transmit($hash, 'send', $cmd);
        unless ($res) {
            my $pos = $$cmd2pos{$cmd};

            main::readingsSingleUpdate($hash, 'state', $pos, 0) if (defined($pos));
        }
        return $res if ($res);
    } elsif ($cmd eq 'position') {
        return "\"set $name $cmd\" needs one argument" unless (defined($args[0]));
        my $percent = $args[0];
        my $c = 'up';
        if ($percent eq '0') {
            $c = 'down';
        } elsif ($percent eq '50') {
            $c = 'sun-down';
        } elsif ($percent eq '99') {
            $c = 'stop';
        }

        my $res = transmit($hash, 'send', $c);
        return $res if ($res);
    } else {
        return "unknown argument $cmd choose one of " . join(' ', Fernotron::Protocol::fer_cmdNumbers(), 'position');
    }

    return undef;
}

sub X_Attr($cmd, $name, $attrName, $attrValue) {

    # $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
    # $name - Gerätename
    # $attrName/$attrValue sind Attribut-Name und Attribut-Wert

    if ($cmd eq 'set') {
        if ($attrName eq 'repeats') {
            my $r = int($attrValue);
            return "invalid argument '$attrValue'. Expected: 0..5" unless (0 <= $r and $r <= 5);
        } elsif ($attrName eq ATTR_AUTOCREATE_NAME) {
            my $val = $attrValue;
            return "invalid argument '$attrValue'. Expected: in out default" unless ($val eq ATTR_AUTOCREATE_IN || $val eq ATTR_AUTOCREATE_OUT || $val eq ATTR_AUTOCREATE_DEFAULT);
        }
    }
    return undef;
}

package main;

sub Fernotron_Initialize($hash) {
    $hash->{Match}    = '^P82#.+';
    $hash->{AttrList} = 'IODev repeats:0,1,2,3,4,5 create:default,out,in';

    $hash->{DefFn}   = 'Fernotron::fhem::X_Define';
    $hash->{UndefFn} = 'Fernotron::fhem::X_Undef';
    $hash->{SetFn}   = 'Fernotron::fhem::X_Set';
    $hash->{ParseFn} = 'Fernotron::fhem::X_Parse';
    $hash->{AttrFn}  = 'Fernotron::fhem::X_Attr';

    #$hash->{AutoCreate} = {'Fernotron_Scan'  => {noAutocreatedFilelog => 1} };
}


1;


=pod
=encoding utf-8
=item device
=item summary controls shutters via Fernotron protocol
=item summary_DE steuert Rolläden über Fernotron Protokoll
=begin html

<a name="Fernotron"></a>
<h3>Fernotron</h3>

<i>Fernotron</i> is a logic FHEM module to 1) control shutters and power plugs using Fernotron protocol and 2) utilize Fernotron controllers and sensors as general switches in FHEM.

<ul>
<li>Required I/O device: <i>SIGNALduino</i></li>
<li>Protocol limitations: It's uni-directional. No information of the receivers status is available. So it's not best suited for automation without user attention.</li>
<li>Pairing: Senders have 6 digit Hex-Numbers as ID.  To pair, the receiver learns IDs of its paired Senders.</li>
<li>Sending directly: Motors have also an ID wich can be used to address messages to it without pairing.</li>
<li>



<h4>Defining Devices</h4>

<h5>1. FHEM devices to control Fernotron devices</h5>

Each output device may control a single shutter, or a group of shutters depending on the parameters given in the define statement.

<p>
  <code>
    define  &lt;name&gt; Fernotron a=ID [g=GN] [m=MN]<br>
  </code>

<p>
  ID : the device ID. A six digit hexadecimal number. 10xxxx=plain controller, 20xxxx=sun sensor, 80xxxx=central controller unit, 90xxxx=receiver<br>
  GN : group number (1-7) or 0 (default) for all groups<br>
  MN : member number  (1-7) or  0 (default) for all group members<br>

<p>
  'g' or  'n' are only useful combined with an ID of the central controller type.


<h5>2. FHEM Devices controlled by Fernotron senders</h5>

<p>  Incoming data is handled by input devices. There is one default input device, who handles all messages not matchin a defined input device. The default input device will be auto-created.

<p> Input devices are defined just like output devices, but with the parameter 'input' given in the define.

<p>
  <code>
    define  &lt;name&gt; Fernotron a=ID [g=GN] [m=MN] input[=(plain|sun|central)]<br>
  </code>
<p>
The input type (like plain) can be ommitted. Its already determined by the ID (e.g. each ID starting with 10 is a plain controller).
<ul>
 <li>defining a plain controller as switch for up/down/stop<br>
      <code>define myFernoSwitch Fernotron a=10abcd input</code></li>
<li>defining a sun sensor as on/off switch (on: sunshine, off: no sunshine)<br>
     <code>define myFernoSun Fernotron a=20abcd input </code></li>
<li>defining a switch for up/down/stop controlled by a Fernotron central unit<br>
     <code>define myFernoSwitch2 Fernotron a=80abcd g=2 m=3 input</code></li>
<li>define a notify device to toggle our light device HUEDevice3<br>
      <code>define myFernoSwitch2 Fernotron a=80abcd g=2 m=3 input</code></li>
 <li>define a notify device to toggle our light device HUEDevice3<br>
     <code>define n_toggleHUEDevice3 notify myFernoSwitch:stop set HUEDevice3 toggle</code></li>
<li>Its possible to use the default input device with your notify device, if you don't want to define specific input devices. This works only if you really had no input device defined for that Fernotron ID<br>
     <code>define n_toggleHUEDevice3 notify Fernotron_Scan:plain:10abcd:stop set HUEDevice3 toggle</code></li>
</ul>


<h4>Adressing and Pairing in Detail</h4>

<h5>Three different methods to make messsages find their target Fernotron receiver</h5>
<ol>
  <li>Use IDs of existing Controllers you own. Scan IDs of physical Fernotron controllers you own and copy their IDs in our FHEM output devices.  Use default input device Fernotron_Scan to scan the ID first. Then use the ID to define your device. Here we have scanned the ID of our 2411 central resulting to 801234. Now define devices by using it
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

<a name="Fernotronattr"></a>
<h6>Attributes</h6>
<ul>
  <li><a name="repeats">repeats N</a><br>
        repeat sent messages N additional times to increase the chance of successfull delivery (default: 1 repeat)
  </li>

  <li><a name="create">create (default|in|out)</a><br>
       This attribute has only effect on the Fernotron default input device Fernotron_Scan or whatever you named it (default name used to be scanFerno).
       It enables auto-creating devices for input, output or none expect the default input device itself.
       Hit the STOP button on a Fernotron controller to add it as a device to FHEM.
       You may rename the created devices using rename command.
  </li>
</ul>


<a name=Fernotronset></a>
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

</ul>


<h4>Examples</h4>

<h5>Adressing and Pairing in Detail</h5>
<ol>
  <li>
    <code>define myShutterGroup1 Fernotron a=801234 g=1 m=0</code><br>
    <code>define myShutter11 Fernotron a=801234 g=1 m=1</code><br>
    <code>define myShutter12 Fernotron a=801234 g=1 m=2</code><br>
    ...
    <code>define myShutterGroup2 Fernotron a=801234 g=2 m=0</code><br>
    <code>define myShutter21 Fernotron a=801234 g=2 m=1</code><br>
    <code>define myShutter22 Fernotron a=801234 g=2 m=2</code><br>
      </li>

  <li>
    <code>define myShutter1 Fernotron a=100001</code><br>
    <code>define myShutter2 Fernotron a=100002</code><br>
    Now activate Set-mode on the Fernotron receiver and send a STOP by the newly defined device you wish to pair with it.
 ...</li>

<li><code>define myShutter__0d123 Fernotron a=90d123</code></li>
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

=begin html_DE

<a name="Fernotron"></a>
<h3>Fernotron</h3>

<i>Fernotron</i> ist ein logisches Modul zur Steuerung von Fernotron Rolläden und Funk-Steckdosen/Lampen
Die erzeugten Kommandos werden über <i>SIGNALduino</i> gesendet.
<i>Fernotron</i> kann außerdem Nachrichten empfangen die von anderen Fernotron-Kontrollern  gesendet werden. Die Rolläden kommunizieren unidirektional. Sie senden also leider keine Feedback Information wie offen/geschlossen.


<h4>Kopplung</h4>

Jeder Kontroller hat eine ID-Nummer ab Werk fest einprogrammiert.

Empfänger und Sender werden gekoppelt, indem sich der Empfänger die ID eines bzw. mehrerer Sender merkt (diese lernt).
Jeder Empfänger kann sich je eine ID einer Zentraleinheit (inklusive Gruppe und Empfängernummer), eines Sonnensensors und mehrerer Handsender merken.

Rolladen-Motore haben ebenfalls eine ID Nummer aufgedruckt.  Wenn kein Zugang zum physischen Setz-Taster des Motors besteht, kann diese ID benutzt werden um den Koppelvorgang einzuleiten oder Einstellung der Drehrichtung und Endpunkte vorzunehmen.


<h4>Gerät definieren</h4>

<h5>Ausgabe Geräte</h5>

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
  'g' und 'n' sind nur sinnvoll, wenn als ID eine Zentraleinheit angegeben wurde.


<h5>Eingabe Geräte</h5>

<p>Empfangene Nachrichten von Controllern/Sensoren werden durch Eingabe Geräte verarbeitet. Es gibt ein Default-Eingabegerät, welches alle Nachrichten verarbeitet, für die kein eigenes Eingabe Geräte definiert wurde. Das Default-Eingabegerät wird automatisch angelegt.

<p> Eingabegeräte werden wie Ausgebegeräte definiert plus dem Parameter 'input' in der Definition:

<p>
  <code>
    define  &lt;name&gt; Fernotron a=ID [g=GN] [m=MN] input[=(plain|sun|central)]<br>
  </code>
<p>
Der Input-Typ (z.B. plain für Handsender) kann weggelassen werden. Er wird dann bestimmt durch die ID (z.B. jede ID beginnend mit 10 gehört zu Typ plain)
<p>
  <code>
    define myFernoSwitch Fernotron a=10abcd input           # ein Handsender als Schalter für up/down/stop<br>
    define myFernoSun Fernotron a=20abcd input              # ein Sonnensensor als on/off Schalter  (on: Sonnenschein, off: kein Sonnenschein)
    define myFernoSwitch2 Fernotron a=80abcd g=2 m=3 input  # defines a switch for up/down/stop controlled by a Fernotron central unit<br>
  </code>

<p>Nun lassen sich die üblichen notify-Geräte oder DOIF-Geräte nutzen um Events zu verarbeiten:

<p> Beispiel: Ein Notify um Lampe HUEDevice3 zu toggeln wenn STOP auf Handsender myFernoSwitch gedrückt wird:
  <code>
    define n_toggleHUEDevice3 notify myFernoSwitch:stop set HUEDevice3 toggle
  </code>

<p> Wenn kein spezifisches Eingabegerät definiert werden soll, kann man das Default-Eingabegerät nutzen:
<p> Beispiel wie oben, nur mit dem Default-Eingabegerät
  <code>
    define n_toggleHUEDevice3 notify Fernotron_Scan:plain:1089ab:stop set HUEDevice3 toggle
  </code>

<h4>Verschiedene Methoden der Adressierung</h4>

<ol>
  <li> Die IDs vorhandener Sende-Geräte einscannen und dann benutzen.
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
  <li>sun-down - Anfahren der Sonnenposition (nur bei aktiverter Sonnenautomatik und wenn Laden oberhalb dieser Position steht)</li>
  <li>sun-up - Wenn in Sonnenposition, dann fährt diese Kommando den Laden komplett hoch.</li>
  <li>sun-inst - aktuelle Position als Sonnenposition speichern</li>
  <li>position - fahre zu position 0 (down), 50 (sun-down), 100 (up), 99 (stop). (für alexa)</li>
</ul>

<h4>Beispiele</h4>

<h5>Addressierung und Pairing</h5>
<ol>
  <li><ul>
      <li>Die ID der 2411 befindet sich auf einem Aufkleber im Batteriefach (sechstellige ID in der Form 80xxxx.</li>
      <li>Ohne ID-Aufkleber: scanne die ID der 2411: Den Stop Taster der 2411 einige Sekunden drücken. Im automatisch erzeugten Default-Eingabegerät "Fernotron_Scan" steht die ID unter Internals:received_HR.</li>
      <li><code>define myShutter_42 Fernotron a=80abcd g=4 m=2</code></li>
  </ul></li>

  <li><ul>
      <li><code>define myShutter_1 Fernotron a=100001 </code></li>
      <li>aktivere Set-Modus des gewünschten Motors</li>
      <li><code>set myShutter_1 stop</code></li>
  </ul></li>

  <li><ul>
      <li><code>define myShutter__0d123 Fernotron a=90d123</code></li>
  </ul></li>
</ol>

<h5>weitere Beispiele</h5>
<ul>
<li>Attribute für alexa setzen:<br>
<code>attr myShutter_42 genericDeviceType blind</code><br>
<code>attr myShutter_42 alexaName Schlafzimmer Rollo</code><br>
</li>
<li>GUI buttons<br>
<code>attr myShutter_42 webCmd down:stop:up</code><br>
</li>
</ul>

=end html_DE

=cut

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./10_Fernotron.pm 2>&1 | grep -v 'Undefined subroutine'"
# eval: (my-buffer-local-set-key (kbd "C-c C-c") (lambda () (interactive) (shell-command "cd ../../.. && ./build.sh")))
# eval: (my-buffer-local-set-key (kbd "C-c c") 'compile)
# eval: (my-buffer-local-set-key (kbd "C-c p") (lambda () (interactive) (shell-command "perlcritic  ./10_Fernotron.pm")))
# End:

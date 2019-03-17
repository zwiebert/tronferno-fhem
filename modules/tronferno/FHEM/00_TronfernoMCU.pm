################################################################################
## *experimental* FHEM I/O device module for Tronferno-MCU hardware
##
##
##  - file: /opt/fhem/FHEM/00_TronfernoMCU.pm
################################################################################
## Author: Bert Winkelmann <tf.zwiebert@online.de>
## Project: https://github.com/zwiebert/tronferno-fhem
## Related Hardware-Project: https://github.com/zwiebert/tronferno-mcu
################################################################################


require DevIo;
#require HttpUtils;
require File::Path;
require File::Basename;

use strict;
use warnings;
use 5.14.0;

package TronfernoMCU;
# protos to avoid module-reloading errors if signature has changed
# (because it was annoying to have the subs in the right order for this)
sub devio_open_device($);
sub devio_close_device($);
sub devio_get_serial_device_name($);
sub mcu_read_all_config($);
sub mcu_read_config($$);
sub mcu_config($$$);
sub mcu_download_firmware($);
sub cb_fw_get_next_file($$$);
sub fw_get_next_file($);
sub fw_get_and_write_flash($$;$$);
sub fw_get($$;$);
sub fw_mk_list_file($$);
sub file_slurp($$);
sub file_read_last_line($);
sub log_get_success($);
sub sys_cmd_get_success($);
sub cb_async_system_cmd($);
sub run_system_cmd($$$$$$);
sub fw_write_flash($$);
sub fw_erase_flash($$);

sub X_Define($$);
sub X_Undef($$);
sub X_Ready($);
sub X_Read($$);
sub X_Set($$@);
sub X_Init($);
sub X_Callback($);
sub X_Write ($$);

my $def_mcuaddr = 'fernotron.fritz.box.';
my $mcu_port = 7777;
my $mcu_baud = 115200;

my $mcfg_prefix = 'mcu-config.';
my $mco = {
    MCFG_CU => 'cu',
    MCFG_RTC => 'rtc',
    MCFG_BAUD => 'baud',
    MCFG_WLAN_SSID => 'wlan-ssid',
    MCFG_WLAN_PASSWD => 'wlan-password',
    MCFG_LONGITUDE => 'longitude',
    MCFG_LATITUDE => 'latitude',
    MCFG_TZ => 'tz',
    MCFG_VERBOSE => 'verbose',
    MCFG_RESTART => 'restart',
    MCFG_MQTT_PASSWORD => 'mqtt-password',
    MCFG_MQTT_USER => 'mqtt-user',
    MCFG_MQTT_URL => 'mqtt-url',
    MCFG_MQTT_ENABLE => 'mqtt-enable',
};

my $mcof = {};
my $mcor = {};
my $usage = '';

while(my($k, $v) = each %$mco) {
    my $vp = $mcfg_prefix.$v;
    $mcof->{$vp} = $v;
    $mcor->{$v} = $vp;
    if ($k eq 'MCFG_VERBOSE') {
        $usage .= " $vp:0,1,2,3,4,5";
    } elsif ($k eq 'MCFG_RESTART') {
        $usage .= " $vp:1";
    } elsif ($k eq 'MCFG_MQTT_ENABLE') {
        $usage .= " $vp:0,1";       
    } else {
        $usage .= " $vp";
    }
}

sub devio_open_device($) {
    my ($hash) = @_;
    my $dn = $hash->{DeviceName} // 'undef'; 
    # open connection with custom init and error callback function (non-blocking connection establishment)
    main::Log3 ($hash->{NAME}, 5, "tronferno-mcu devio_open_device() for ($dn)");
    return main::DevIo_OpenDev($hash, 0, "TronfernoMCU::X_Init", "TronfernoMCU::X_Callback"); 
}

sub devio_close_device($) {
    my ($hash) = @_;
    my $dn = $hash->{DeviceName} // 'undef'; 
    # close connection if maybe open (on definition modify)
    main::Log3 ($hash->{NAME}, 5, "tronferno-mcu devio_close_device() for ($dn)"); 
    return main::DevIo_CloseDev($hash); # if(main::DevIo_IsOpen($hash));  
}

sub devio_get_serial_device_name($) {
    my ($hash) = @_;
    my $devname = $hash->{DeviceName} // '';
    return undef unless index($devname, '@') > 0;
    my ($dev, $baud) = split('@', $devname);
    return $dev;
}

# called when a new definition is created (by hand or from configuration read on FHEM startup)
sub X_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);

    my $name = $a[0];
    
    # $a[1] is always equals the module name "MY_MODULE"
    
    # first argument is the hostname or IP address of the device (e.g. "192.168.1.120")
    my $dev = $a[2];
    
    $dev = $def_mcuaddr unless($dev); # FIXME: remove this line

    return "no device given" unless($dev);

    #append default baudrate / portnumber
    if (index($dev, '/') != -1) {
        #serial device
        $dev .= '@' . "$mcu_baud" if (index($dev, '@') < 0);
    } else {
        #TCP/IP connection
        $dev .= ":$mcu_port" if(index($dev, ':') < 0);
    }
    
    # first close connection if maybe open (on definition modify)
    devio_close_device($hash);
    # now change old device name to new one
    $hash->{DeviceName} = $dev;
    # open connection with custom init and error callback function (non-blocking connection establishment)
    devio_open_device($hash);
    
    return undef;
}

# called when definition is undefined 
# (config reload, shutdown or delete of definition)
sub X_Undef($$)
{
    my ($hash, $name) = @_;
    main::Log3 ($hash->{NAME}, 5, "tronferno-mcu X_Undef()"); 
    # close the connection 
    devio_close_device($hash);
    
    return undef;
}

# called repeatedly if device disappeared
sub X_Ready($)
{
    my ($hash) = @_;

    main::Log3 ($hash->{NAME}, 5, "tronferno-mcu X_Ready()"); 
    # try to reopen the connection in case the connection is lost
    return devio_open_device($hash);
}

# called when data was received
sub X_Read($$)
{
    # if DevIo_Expect() returns something we call this function with an additional argument
    my ($hash, $data) = @_;
    my $name = $hash->{NAME};

    # read the available data (or don't if called from X_Set)
    $data = main::DevIo_SimpleRead($hash) unless (defined($data));
    # stop processing if no data is available (device disconnected)
    return if(!defined($data));

    my $buf = $hash->{PARTIAL} . $data;
    
    main::Log3 ($name, 5, "TronfernoMCU ($name) - received data: >>>$data<<<");
    
    my $remain = '';
    foreach my $line (split(/^/m, $buf)) {
        if (index($line, "\n") < 0) {
            $remain = $line;
            last;
        }

        $line =~ tr/\r\n//d;

        main::Log3 ($name, 4, "TronfernoMCU ($name) - received line: >>>>>$line<<<<<");

        if ($line =~ /^(U:position:\s*.+);$/) {
            my $msg =  "TFMCU#$1";
            main::Log3 ($name, 4, "$name: dispatch: $msg"); 
            main::Dispatch($hash, $msg);

        } elsif ($line =~ /^([Cc]:.*);$/) {
            my $msg =  "TFMCU#$1";
            main::Log3 ($name, 4, "$name: dispatch: $msg"); 
            main::Dispatch($hash, $msg);

        } elsif ($line =~ /^tf:.* timer: (.*);$/) {
            my $msg = "TFMCU#timer $1";
            main::Log3 ($name, 4, "$name: dispatch: $msg"); 
            main::Dispatch($hash, $msg);

        } elsif ($line =~ /^tf:.* config: (.*);$/) {
            for my $kv (split (' ', $1)) {
                my ($k, $v) = split('=', $kv);
                $k = $mcor->{$k};
                $hash->{$k} = $v if $k;
            }

        } elsif ($line =~ /^tf:.* mcu: (.*);$/) {
            for my $kv (split (' ', $1)) {
                my ($k, $v) = split('=', $kv);
                $hash->{"mcu-$k"} = $v;
           }
        } elsif ($line =~ /\s+wifistation:\s+got\s+ip:\s*([0-9.]*).*/) { #ESP32
            main::readingsSingleUpdate($hash, 'mcu.ip4-address', $1, 1);
        }
    }

    $hash->{PARTIAL} = $remain;
}

sub mcu_read_all_config($) {
    my ($hash) = @_;
    main::DevIo_SimpleWrite($hash, "config all=?;", 2);
}

sub mcu_read_config($$) {
    my ($hash, @args) = @_;
    my $msg = "";
    for my $o (@args) {
        $msg .= "$o=?";
    }
    main::DevIo_SimpleWrite($hash, "config $msg;", 2);
}

sub mcu_config($$$) {
    my ($hash, $opt, $arg) = @_;
    my $msg =  "$opt=$arg";
    $msg .=  " $opt=?" unless ($arg eq '?' || $opt eq 'wlan-password');
    $msg .= ' restart=1' if 0 == index($opt, 'wlan-'); # do restart after changing any wlan option

    main::DevIo_SimpleWrite($hash, "config $msg;", 2);
}

sub mcu_download_firmware($) {
    my ($hash) = @_;
}

my $firmware;
{
    my $fw = {};
    $firmware = $fw;
    
    {
        my $fwe = {};
        $fw->{'xxx.mcu-firmware.esp32'} = $fwe;

        $fwe->{args} = ':upgrade,download,write-flash,xxx.erase-flash,download-beta-version';
        # FIXME: file list should better be fetched from server
        $fwe->{files} = ['firmware/esp32/tronferno-mcu.bin',
                         'firmware/esp32/bootloader.bin',
                         'firmware/esp32/partitions.bin',
                         'tools/esptool.py',
                         'flash_esp32.sh'];
        $fwe->{tgtdir} = '/tmp/TronfernoMCU/';
        $fwe->{uri} = 'https://raw.githubusercontent.com/zwiebert/tronferno-mcu-bin/master/';
        $fwe->{uri_beta} = 'https://raw.githubusercontent.com/zwiebert/tronferno-mcu-bin/beta/';
        $fwe->{write_flash_cmd} = '/bin/sh flash_esp32.sh %s';
        $fwe->{erase_flash_cmd} = 'python tools/esptool.py --port %s --chip esp32 erase_flash';
    }

    {
        my $fwe8 = {};
        $fw->{'xxx.mcu-firmware.esp8266'} = $fwe8;


        $fwe8->{args} = ':upgrade,download,write-flash,xxx.erase-flash,download-beta-version';
        # FIXME: file list should better be fetched from server
        $fwe8->{files} = ['firmware/esp8266/blank.bin',
                          'firmware/esp8266/eagle.flash.bin',
                          'firmware/esp8266/eagle.irom0text.bin',
                          'firmware/esp8266/esp_init_data_default_v08.bin',
                          'tools/esptool.py',
                          'flash_esp8266.sh'];
        $fwe8->{tgtdir} = '/tmp/TronfernoMCU/';
        $fwe8->{uri} = 'https://raw.githubusercontent.com/zwiebert/tronferno-mcu-bin/master/';
        $fwe8->{uri_beta} = 'https://raw.githubusercontent.com/zwiebert/tronferno-mcu-bin/beta/';
        $fwe8->{write_flash_cmd} = '/bin/sh flash_esp8266.sh %s';
        $fwe8->{erase_flash_cmd} = 'python tools/esptool.py --port %s --chip esp8266 erase_flash';
    }
}

# append to X_Set() usage text
while(my($k, $v) = each %$firmware) {
    $usage .= " $k".$v->{args};
}

sub cb_fw_get_next_file($$$) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $fwg =  $hash->{helper}{fw_get};
    
    if (!$err && open (my $fh, '>', $fwg->{dst_file})) {
        # save file
        binmode($fh);
        print $fh $data;
        close ($fh);
        fw_get_next_file($hash);
    } else {
        # error
        main::readingsSingleUpdate($hash, $fwg->{id}, 'error', 1);
    }
}

sub fw_get_next_file($) {
    my ($hash) = @_;
    my $fwg =  $hash->{helper}{fw_get};
    my $count = $fwg->{file_count};
    my $files = $fwg->{files};

    my $idx = $fwg->{file_idx}++;

    unless ($idx < $count) {
        main::readingsSingleUpdate($hash, $fwg->{id}, 'done', 1);
        if ($fwg->{write_func}) {
            &{$fwg->{write_func}}(@{$fwg->{write_args}});
        }
        return;
    }

    my $file = $$files[$idx];
    my $param = $fwg->{http_param};
    my $base_dir =  $fwg->{dst_base}; 
    
    # create destination directory
    my $dst_dir = $base_dir . File::Basename::dirname($file); # compose dir path
    File::Path::make_path($dst_dir, {mode => 0755}); # create dir

   
    $fwg->{dst_file} = "$base_dir$file";
    $param->{url} = $fwg->{uri} . $file;

    main::HttpUtils_NonblockingGet($param);
}



sub fw_get_and_write_flash($$;$$) {
    my($hash, $fw, $write_flash, $uri) = @_;
    $uri = $fw->{uri} unless $uri;
    my $dst_base =  $fw->{tgtdir};

    my $fwg = {};
    $hash->{helper}{fw_get} = $fwg;

    $fwg->{file_idx} = 0;
    $fwg->{file_count} = scalar(@{$fw->{files}});
    $fwg->{files} = $fw->{files};
    $fwg->{uri} = $uri;
    $fwg->{dst_base} = $dst_base;
    $fwg->{id} = 'fw_get';

    if ($write_flash) {
        $fwg->{write_func} = \&fw_write_flash;
        $fwg->{write_args} = [$hash, $fw];
    }
    
    $fwg->{http_param} = {
        timeout    => 5, 
        hash       => $hash,
        method     => "GET",
        header     => "User-Agent: TeleHeater/2.2.3\r\nAccept: application/octet-stream",
        callback   => \&cb_fw_get_next_file,
    };

    main::readingsSingleUpdate($hash, $fwg->{id}, 'run', 1);
    fw_get_next_file($hash);
}

sub fw_get($$;$) {
    return fw_get_and_write_flash(shift, shift, undef, shift);
}
=pod

## wget related code disabled

sub fw_mk_list_file($$) {
    my($hash, $fw) = @_;
    my $tgtdir =  $fw->{tgtdir};
    my $fname = $tgtdir.'files.txt';
    File::Path::make_path($tgtdir, {mode => 0755}); # create dir
    my $of;
    if (open ($of,'>',$fname)) {
        print $of join ("\n", @{$fw->{files}});
        close ($of);
    }
}

my $wget_log = 'wget.txt';

sub fw_get($$) {
    my($hash, $fw) = @_;
    my $uri = $fw->{uri};
    my $tgtdir =  $fw->{tgtdir};
    my $log = "$tgtdir$wget_log";
    my $sc = "wget --no-verbose --base=$uri -i files.txt -x -nH --cut-dirs 3 --preserve-permissions"; #FIXME: literal

    fw_mk_list_file($hash, $fw);
    run_system_cmd($hash, $tgtdir, $log, $sc, 'fw_get', 0);
}

=cut


my $write_flash_log = 'write_flash.txt';
my $erase_flash_log = 'erase_flash.txt';
my $tag_status = 'status_';
my $tag_succ = $tag_status.'0';
my $done_file = 'done.txt';
my $cmd_status = "echo $tag_status\$? | tee $done_file";

sub file_slurp($$) {
    my ($filename, $dst) = @_;

    $$dst = do {
    local $/;
    open my $fh, $filename or return undef;
    <$fh>
    };
    return 1;
}

sub file_read_last_line($) {
    my $last_line = '';
    if (open (my $f, '<', shift)) {
        $last_line = $_ while <$f>; 
        close($f);
    }
    chomp($last_line);
    return $last_line;
}
sub log_get_success($) {
    my $status = file_read_last_line(shift);
    return 1 if $status eq $tag_succ;
    return 0 if index($status, $tag_status) == 0;
    return undef; # no status line. command still running?
}
sub sys_cmd_get_success($) {
    my ($hash) = @_;
    return log_get_success($hash->{helper}{sys_cmd}{status_file});
}

sub cb_async_system_cmd($) {
    my ($hash) = @_;
    my $start_time = $hash->{helper}{sys_cmd}{start_time};
    my $id = $hash->{helper}{sys_cmd}{id};
    my $timeout = 45; #FIXME: literal
    my $cl = $hash->{helper}{sys_cmd}{cl};
    my $logstr = "";
 

    if (-e $hash->{helper}{sys_cmd}{status_file}) {
        my $failed = !sys_cmd_get_success($hash);
        my $result = $failed ? 'error' : 'done';
    
        main::readingsSingleUpdate($hash, $id, "$result", 1);
        file_slurp($hash->{helper}{sys_cmd}{log}, \$logstr) if $failed;
        
        if ($id  eq 'fw_get') {
            main::asyncOutput($cl, "firmware download command failed:\n\n" . $logstr) if ($cl && $failed);
        } elsif ($id eq 'fw_write_flash') {
            main::asyncOutput($cl, "write-flash command failed:\n\n" . $logstr) if ($cl && $failed);
            devio_open_device($hash);
        } elsif ($id  eq 'fw_erase_flash') {
            main::asyncOutput($cl, "erase-flash command failed:\n\n" . $logstr) if ($cl && $failed);
            devio_open_device($hash);
        }
    } elsif ($start_time + $timeout < main::gettimeofday()) {
        main::readingsSingleUpdate($hash, $id, 'timeout', 1);
    } else {
        main::InternalTimer(main::gettimeofday() + 4, 'TronfernoMCU::cb_async_system_cmd', $hash);
        return; # return here to not reach cleanup code at bottom
    }

    # all done. clean up data
    $hash->{helper}{sys_cmd} = undef;
}
sub run_system_cmd($$$$$$) {
    my ($hash, $tgtdir, $log, $sc, $id, $close_device) = @_;
    my $status_file = "$tgtdir$done_file"; 
    my $command = "(cd $tgtdir && $sc; $cmd_status) 1>$log 2>&1 &";

    devio_close_device($hash) if $close_device;
    unlink($status_file);
    system($command);

    $hash->{helper}{sys_cmd} = {};
    $hash->{helper}{sys_cmd}{id} = $id;
    $hash->{helper}{sys_cmd}{dir} = $tgtdir;
    $hash->{helper}{sys_cmd}{status_file} = $status_file;
    $hash->{helper}{sys_cmd}{start_time} = main::gettimeofday();
    $hash->{helper}{sys_cmd}{cl} = $hash->{CL};
    $hash->{helper}{sys_cmd}{log} = $log;

    main::readingsSingleUpdate($hash, $id, 'run', 1);
    main::InternalTimer(main::gettimeofday() + 4, 'TronfernoMCU::cb_async_system_cmd', $hash);
    $hash->{"shell-command-$id"} = $command;
}


sub fw_write_flash($$) {
    my($hash, $fw) = @_;
    my $tgtdir =  $fw->{tgtdir};
    my $log = "$tgtdir$write_flash_log";
    my $ser_dev = devio_get_serial_device_name($hash);
    my $id = 'fw_write_flash';
    my $client_hash = $hash->{CL};
    
    unless ($ser_dev) {
        main::asyncOutput($client_hash, "write_flash failed: MCU needs do be connected via a serial device)")
            if ($client_hash && $client_hash->{canAsyncOutput});
        main::readingsSingleUpdate($hash, $id, 'error', 1);
        return "no serial device";
    }

    unless ($fw->{write_flash_cmd}) {
        main::readingsSingleUpdate($hash, $id, 'error', 1);
        return "internal_error: no system command"  ;
    }
    
    my $sc = sprintf($fw->{write_flash_cmd}, $ser_dev);
    run_system_cmd($hash, $tgtdir, $log, $sc, $id, 1);

    return undef;
}

sub fw_erase_flash($$) {
    my($hash, $fw) = @_;
    my $tgtdir =  $fw->{tgtdir};
    my $log = "$tgtdir$erase_flash_log";
    my $ser_dev = devio_get_serial_device_name($hash);
    return unless $ser_dev;
    return unless $fw->{erase_flash_cmd};
    
    my $sc = sprintf($fw->{erase_flash_cmd}, $ser_dev);
    run_system_cmd($hash, $tgtdir, $log, $sc, 'fw_erase_flash', 1);
}

# called if set command is executed
sub X_Set($$@) {
    my ($hash, $name, $cmd, @args) = @_;
    my ($a1, $a2, $a3, $a4) = @args;

    return "\"set $name\" needs at least one argument" unless (defined($cmd));

    my $u = "unknown argument $cmd choose one of ";
    $u .= $usage;
    
    if ($cmd eq '?') {
        return $u;
    } elsif($mcof->{$cmd}) {
        mcu_config($hash, $mcof->{$cmd}, $a1) if defined($a1); 
    } elsif($firmware->{$cmd}) {
        if ($a1 eq 'download') {
            fw_get($hash, $firmware->{$cmd});
        } elsif ($a1 eq 'download-beta-version') {
            fw_get($hash, $firmware->{$cmd}, $firmware->{$cmd}{uri_beta});
        } elsif ($a1 eq 'upgrade') {
            fw_get_and_write_flash($hash, $firmware->{$cmd}, 1);
        } elsif ($a1 eq 'write-flash') {
            fw_write_flash($hash, $firmware->{$cmd});
        } elsif ($a1 eq 'xxx.erase-flash') {
            fw_erase_flash($hash, $firmware->{$cmd});
        }
    } elsif($cmd eq 'xxx.mcu-firmware.esp8266') {
    } elsif($cmd eq 'xxx.mcu-firmware.atmega328') {
    } elsif($cmd eq "statusRequest") {
        #main::DevIo_SimpleWrite($hash, "get_status\r\n", 2);
    } elsif($cmd eq "on") {
        #main::DevIo_SimpleWrite($hash, "on\r\n", 2);
    } elsif($cmd eq "off") {
        #main::DevIo_SimpleWrite($hash, "off\r\n", 2);
    } else {
        return $u;
    }
    
    return undef;
}

# will be executed upon shuccessful connection establishment (see main::DevIo_OpenDev())
sub X_Init($)
{
    my ($hash) = @_;
    # get shutter positions and firmware version
    main::DevIo_SimpleWrite($hash, "send p=?;mcu version=full;config all=?;", 2);
    # get mcu config
   # mcu_read_all_config($hash);
    return undef; 
}

sub X_Callback($)
{
    my ($hash, $error) = @_;
    my $name = $hash->{NAME};

    # create a log emtry with the error message
    main::Log3 ($name, 5, "TronfernoMCU ($name) - error while connecting: $error") if ($error);
    
    return undef; 
}

sub X_Write ($$)
{
    my ( $hash, $addr, $msg) = @_;
    my $name = $hash->{NAME};

    main::Log3 ($name, 5, "TronfernoMCU ($name) _Write(): $addr: $msg");
    main::DevIo_SimpleWrite($hash, $msg, 2, 1);
    return undef;
}



package main;

sub TronfernoMCU_Initialize($) {
    my ($hash) = @_;

    $hash->{SetFn}   = 'TronfernoMCU::X_Set';
    $hash->{DefFn}   = 'TronfernoMCU::X_Define';
    $hash->{ReadFn}  = 'TronfernoMCU::X_Read';
    $hash->{ReadyFn} = 'TronfernoMCU::X_Ready';
    $hash->{WriteFn} = 'TronfernoMCU::X_Write';
    $hash->{UndefFn} = 'TronfernoMCU::X_Undef';

    $hash->{Clients} = 'Tronferno';
    $hash->{MatchList} = { '1:Tronferno' => '^TFMCU#.+' };
}


1;

=pod
=item device
=item summary I/O device which communicates with Tronferno-MCU
=item summary_DE E/A Gerät welches mit Tronferno-MCU kommuniziert

=begin html

<a name="TronfernoMCU"></a>
<h3>TronfernoMCU</h3>


<p><i>TronfernoMCU</i> is a physical Device for the purpose of 1) controlling Fernotron devices or 2) utilizing Fernotron controllers into FHEM.
<ul>
 <li>Provides the IODev requiered by Tronferno logical devices</li>
 <li>Requiered MCU/RF-hardware: <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a></li>
 <li>Can flash the MCU (ESP32 or ESP8266) using the respective SET command. (if conected to FHEM by USB)</i>
 <li>Can configure the MCU using SET commands</li>
 <li>Can connect to MCU by 1) USB or 2) WLAN.</li>
</ul> 

<p>
<a name="TronfernoMCUset"></a>
<h4>SET</h4>
<ul>

  <a name="mcu-config.baud"></a>
  <li>mcu-config.baud<br>
    Baud rate of MCU's serial interface</li>

  <a name="mcu-config.cu"></a>
  <li>mcu-config.cu<br>
   Central-Unit ID used by the MCU (six digit hex number)</li>


  <a name="mcu-config.latitude"></a>
  <li>mcu-config.latitude<br>
   geographical coordinates are used to calculate civil dusk for astro-timer (decimal degree, e.g. 52.5)</li>

  <a name="mcu-config.longitude"></a>
  <li>mcu-config.longitude<br>
   geographical coordinates are used to calculate civil dusk for astro-timer (decimal degree, e.g. 13,4)</li>

  <a name="mcu-config.restart"></a>
  <li>mcu-config.restart<br>
    Retart the MCU.</li>

  <a name="mcu-config.rtc"></a>
  <li>mcu-config.rtc<br>
    Set MCU's internal real time clock by ISO date/time string (e.g. 1999-12-31T23:59:00). If possible, the MCU will use NTP instead.</li>

  <a name="mcu-config.rtc"></a>
  <li>mcu-config.rtc<br>
    Set MCU's internal real time clock by ISO date/time string (e.g. 1999-12-31T23:59:00). If possible, the MCU will use NTP instead.</li>

  <a name="mcu-config.tz"></a>
  <li>mcu-config.tz<br>
    Time-zone in POSIX (TZ) format</li>

  <a name="mcu-config.rtc"></a>
  <li>mcu-config.rtc<br>
    </li>

  <a name="mcu-config.verbose"></a>
  <li>mcu-config.verbose<br>
    Verbosity level of MCU's diagnose output (0 .. 5)</li>

  <a name="mcu-config.wlan-password"></a>
  <li>mcu-config.wlan-passord<br>
    Password used by MCU to connect to WLAN/WiFi<br>
    Note: MCU will be restarted after setting this option </li>

  <a name="mcu-config.wlan-ssid"></a>
  <li>mcu-config.wlan-ssid<br>
    WLAN/WiFi SSID to connect to<br>
    Note: MCU will be restarted after setting this option</li>

  <a name="xxx.mcu-firmware.esp32"></a>
  <li>xxx.mcu-firmware.esp32<br>

   Fetch and write latest MCU firmware from tronferno-mcu-bin github repository.
    <ul>
     <li>download<br>
         Downloads firmware and flash-tool from github.<br>
         Files can be found at /tmp/TronfernoMCU<br>
         Status is shown in reading fw_get (run,done,error,timeout).</li>
     <li>write-flash<br>
         Writes downloaded firmware to serial port used in definition of this device.<br>
         Required Tools: python, pyserial; <code>apt install python  python-serial</code><br>
         Expected MCU: Plain ESP32 with 4MB flash. Edit the flash_esp32.sh command for different hardware.<br>
         Status is shown in reading fw_write_flash (run,done,error,timeout). Shell output may be displayed at error.</li>
     <li>upgrade<br>
        Combines download and write-flash for convinience.
         </li>
     <li>xxx.erase-flash<br>
          Optional Step before write-flash: Use downloaded tool to delete the MCU's flash memory content. All saved data in MCU will be lost.<br>
         Required Tools: python, pyserial; <code>apt install python  python-serial</code><br>
         Status is shown in reading fw_erase_flash (run,done,error,timeout). Shell output may be displayed at error.</li>
     <li>download-beta-version<br>
         Downloads beta-firmware and flash-tool from github.<br>
         Files can be found at /tmp/TronfernoMCU<br>
         Status is shown in reading fw_get (run,done,error,timeout).</li>
    </ul>
  </li>

  <a name="xxx.mcu-firmware.esp8266"></a>
  <li>xxx.mcu-firmware.esp8266<br>
   Fetch and write latest MCU firmware from tronferno-mcu-bin github repository.
    <ul>
     <li>download<br>
         Downloads firmware and flash-tool from github.<br>
         Files can be found at /tmp/TronfernoMCU<br>
         Status is shown in reading fw_get (run,done,error,timeout).</li>
     <li>write-flash<br>
         Writes downloaded firmware to serial port used in definition of this device.<br>
         Required Tools: python, pyserial; <code>apt install python  python-serial</code><br>
         Expected MCU: Plain ESP8266 with 4MB flash. Edit the flash_esp32.sh command for different hardware.<br>
         Status is shown in reading fw_write_flash (run,done,error,timeout). Shell output may be displayed at error.</li>
     <li>upgrade<br>
        Combines download and write-flash for convinience.
     <li>xxx.erase-flash<br>
          Optional Step before write-flash: Use downloaded tool to delete the MCU's flash memory content. All saved data in MCU will be lost.<br>
         Required Tools: python, pyserial; <code>apt install python  python-serial</code><br>
         Status is shown in reading fw_erase_flash (run,done,error,timeout). Shell output may be displayed at error.</li>
     <li>download-beta-version<br>
         Downloads beta-firmware and flash-tool from github.<br>
         Files can be found at /tmp/TronfernoMCU<br>
         Status is shown in reading fw_get (run,done,error,timeout).</li>
    </ul>
  </li>


</ul>

<br>     Examples:
<br>
<br> 1) MCU module is connected via TCP/IP
<br>
<br>    define tfmcu TronfernoMCU  192.168.1.123
<br>    define shutter_11 Tronferno g=1 m=1
<br>    define shutter_12 Tronferno g=1 m=2
<br>     ..
<br>    define shutter_77 Tronferno g=7 m=7
<br>
<br> 2) MCU module is connected via USB port /dev/ttyUSB1
<br>
<br>    define tfmcu TronfernoMCU /dev/ttyUSB1
<br>    define shutter_11 Tronferno g=1 m=1
<br>    define shutter_12 Tronferno g=1 m=2
<br>     ..
<br>    define shutter_77 Tronferno g=7 m=7
<br>
<br>  ### Make sure the I/O device tfmcu is defined before any shutter_xx device ###
<br>  ### Otherwise the shutter_xx devices can't find their I/O device (because its not defined yet) ###

<p>

=end html

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./00_TronfernoMCU.pm"
# eval: (my-buffer-local-set-key (kbd "C-c C-c") (lambda () (interactive) (shell-command "cd ../../.. && ./build.sh")))
# End:


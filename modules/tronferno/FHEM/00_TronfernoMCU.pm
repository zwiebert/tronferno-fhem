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

use strict;
use warnings;
use 5.14.0;

package main;

sub DevIo_CloseDev($@);
sub DevIo_IsOpen($);
sub DevIo_OpenDev($$$;$);
sub DevIo_SimpleRead($);
sub DevIo_SimpleWrite($$$;$);
sub Dispatch($$;$$);
sub HttpUtils_NonblockingGet($);
sub InternalTimer($$$;$);
sub Log3($$$);
sub asyncOutput($$);
sub gettimeofday();
sub readingsSingleUpdate($$$$);
sub readingsSingleUpdate($$$$);


sub TronfernoMCU_Initialize($);

package TronfernoMCU;

require DevIo;
require HttpUtils;
require File::Path;
require File::Basename;

sub File::Path::make_path;


# protos to avoid module-reloading errors if signature has changed
# (because it was annoying to have the subs in the right order for this)

sub X_Define($$);
sub X_Read($$);
sub X_Ready($);
sub X_Set($$@);
sub X_Undef($$);
sub X_Write ($$);
sub cb_async_system_cmd($);
sub devio_close_device($);
sub devio_get_serial_device_name($);
sub devio_openDev_failed_cb($);
sub devio_openDev_succeeded_cb($);
sub devio_open_device($);
sub file_read_last_line($);
sub file_slurp($$);
sub fw_erase_flash($$);
sub fw_get($$;$);
sub fw_get_and_write_flash($$;$$);
sub fw_get_next_file($);
sub fw_get_next_file_cb($$$);
sub fw_mk_list_file($$);
sub fw_write_flash($$);
sub log_get_success($);
sub mcu_config($$$);
sub mcu_download_firmware($);
sub mcu_read_all_config($);
sub mcu_read_config($$);
sub run_system_cmd($$$$$$);
sub sys_cmd_get_success($);
sub sys_cmd_rm_log_internals($);
sub wdcon_cure_lag($);
sub wdcon_get_next_msgid($);
sub wdcon_test_check_reply_line($$);
sub wdcon_test_init($$);
sub wdcon_test_timer_cb($);
sub wdcon_test_transmit($);

my $def_mcuaddr = 'fernotron.fritz.box.';
my $mcu_port = 7777;
my $mcu_baud = 115200;
my $FW_WRT_ID = 'fw_write_flash';
my $FW_ERA_ID = 'fw_erase_flash';

my $mcfg_prefix = 'mcc.';
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
    MCFG_HTTP_PASSWORD => 'http-password',
    MCFG_HTTP_USER => 'http-user',
    MCFG_HTTP_ENABLE => 'http-enable',
    MCFG_NETWORK => 'network',
    MCFG_ALL => 'all',
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
    } elsif ($k =~ /_ENABLE$/) {
        $usage .= " $vp:0,1";
    } elsif ($k eq 'MCFG_NETWORK') {
        $usage .= " $vp:none,ap,wlan,lan";
    } elsif ($k eq 'MCFG_ALL') {
        $usage .= " $vp:?";
    } else {
        $usage .= " $vp";
    }
}

## connection watchdog ##
sub wdcon_cure_lag($) {
    my ($hash) = @_;
    my $wdcon = $hash->{helper}{wdcon};
    #TODO: do restart with lagging USB
    main::Log3 ($hash->{NAME}, 1, "MCU connection lag. Try to restart MCU");
    main::DevIo_SimpleWrite($hash, "config restart=1;", 2);
    main::DevIo_SimpleWrite($hash, "config restart=1;", 2);
    main::DevIo_SimpleWrite($hash, "config restart=1;", 2);
    $wdcon->{state} = 'lag_cured';
}
sub wdcon_get_next_msgid($) {
    my ($hash) = @_;
    my $wdcon = $hash->{helper}{wdcon};
    ++$wdcon->{msgid};
    $wdcon->{msgid} %= 256;
    return $wdcon->{msgid};
}
sub wdcon_test_transmit($) {
    my ($hash) = @_;
    my $wdcon = $hash->{helper}{wdcon};

    my $tod = main::gettimeofday();
    $wdcon->{tod} = $tod;
    my $msgid = wdcon_get_next_msgid($hash);
    $wdcon->{expected} = 'warning@'.$msgid.':unknown-option: unknown';
    main::DevIo_SimpleWrite($hash, "cmd unknown=0 mid=$msgid;", 2);
    $wdcon->{state} = 'sent';
}
sub wdcon_test_check_reply_line($$) {
    my ($hash, $line) = @_;
    my $wdcon = $hash->{helper}{wdcon};
    my $expected =  $wdcon->{expected};
    if ($expected) {
        #print "expected: <$expected>\n";
        #print "received: <$line>\n";
        if ($expected eq $line) {
            $wdcon->{state} = 'received';
            $wdcon->{expected} = '';
            $wdcon->{fail_count} = 0;
        }
    }
}
sub wdcon_test_timer_cb($) {
    my ($hash) = @_;
    if(main::DevIo_IsOpen($hash)) {
        my $wdcon = $hash->{helper}{wdcon};
        my $long_interval = $wdcon->{interval};
        my $short_interval = 3;
        my $reconnect_interval = 20;
        my $state = $wdcon->{state};

        if ($state eq 'none') {
            wdcon_test_transmit($hash);
        } elsif ($state eq 'sent') {
            if (++$wdcon->{fail_count} > $wdcon->{max_fail_count}) {
                wdcon_cure_lag($hash);
            } else {
                wdcon_test_transmit($hash);
            }
        } elsif ($state eq 'received') {
            $wdcon->{state} = 'none';
            goto DONE;
        } elsif ($state eq 'lag_cured') {
            goto DONE;
        } elsif ($state eq 'xxxx') {
            devio_close_device($hash);
            $wdcon->{state} = 'reconnect';
            goto RECONNECT;
        } elsif ($state eq 'reconnect') {
            devio_open_device($hash);
            return;
        } elsif ($state eq 'xxx') {
        }

        main::InternalTimer( main::gettimeofday() + $short_interval, 'TronfernoMCU::wdcon_test_timer_cb', $hash);
        return;
      DONE:
        $wdcon->{fail_count} = 0;
        main::InternalTimer( main::gettimeofday() + $long_interval, 'TronfernoMCU::wdcon_test_timer_cb', $hash);
        return;
      RECONNECT:
        main::InternalTimer( main::gettimeofday() + $reconnect_interval, 'TronfernoMCU::wdcon_test_timer_cb', $hash);
        return;
    }
}
sub wdcon_test_init($$) {
    my ($hash, $interval) = @_;
    $hash->{helper}{wdcon} = { interval => $interval, fail_count => 0, time_for_reply => 3, max_fail_count => 3, msgid => 0, state => 'none' };
    wdcon_test_timer_cb($hash);
}

## DevIO ##
sub devio_open_device($) {
    my ($hash) = @_;
    my $dn = $hash->{DeviceName} // 'undef';
    # open connection with custom init and error callback function (non-blocking connection establishment)
    main::Log3 ($hash->{NAME}, 5, "tronferno-mcu devio_open_device() for ($dn)");
    return main::DevIo_OpenDev($hash, 0, "TronfernoMCU::devio_openDev_succeeded_cb", "TronfernoMCU::devio_openDev_failed_cb");
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

sub devio_openDev_succeeded_cb($)
{
    my ($hash) = @_;
    main::DevIo_SimpleWrite($hash, "send p=?;mcu version=full;config all=?;", 2);
    wdcon_test_init($hash, 60 * 5); # XXX
    return undef;
}

sub devio_openDev_failed_cb($)
{
    my ($hash, $error) = @_;
    my $name = $hash->{NAME};

    main::Log3 ($name, 5, "TronfernoMCU ($name) - error while connecting: $error") if ($error);

    return undef;
}

# called when a new definition is created (by hand or from configuration read on FHEM startup)
sub X_Define($$)
{
    my ($hash, $def) = @_;
    my @args = split("[ \t]+", $def);

    my $name = $args[0];

    # $args[1] is always equals the module name "MY_MODULE"

    # first argument is the hostname or IP address of the device (e.g. "192.168.1.120")
    my $dev = $args[2];

    $dev = $def_mcuaddr unless($dev); # FIXME: remove this line

    return "no device given" unless($dev);

    #append default baudrate / portnumber
    if (index($dev, '/') != -1) {
        #serial device
        $hash->{helper}{connection_type} = 'usb';
        $dev .= '@' . "$mcu_baud" if (index($dev, '@') < 0);
    } else {
        #TCP/IP connection
        $hash->{helper}{connection_type} = 'tcp';
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

    #main::Log3 ($name, 5, "TronfernoMCU ($name) - received data: >>>$data<<<");

    my $remain = '';
    foreach my $line (split(/^/m, $buf)) {
        if (index($line, "\n") < 0) {
            $remain = $line;
            last;
        }

        $line =~ tr/\r\n//d;

        wdcon_test_check_reply_line($hash, $line);

        main::Log3 ($name, 4, "TronfernoMCU ($name) - received line: <$line>");

        if ($line =~ /^([AU]:position:\s*.+);$/) {
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
        } elsif ($line =~ /^tf:.* ipaddr:\s*([0-9.]*);$/) {
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
    $msg .= ' restart=1' if 0 == index($opt, 'wlan-') || ($opt == 'network'); # do restart after changing any network option

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
        $fw->{'mcu-firmware.esp32'} = $fwe;

        $fwe->{args} = ':upgrade,download,write-flash,xxx.erase-flash,upgrade-beta-version,download-beta-version';
        # FIXME: file list should better be fetched from server
        $fwe->{files} = ['firmware/esp32/tronferno-mcu.bin',
                         'firmware/esp32/bootloader.bin',
                         'firmware/esp32/partitions.bin',
                         'firmware/esp32/ota_data_initial.bin',
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
        $fw->{'mcu-firmware.esp8266'} = $fwe8;


        $fwe8->{args} = ':upgrade,download,write-flash,xxx.erase-flash,upgrade-beta-version,download-beta-version';
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

sub fw_get_next_file_cb($$$) {
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
        callback   => \&fw_get_next_file_cb,
    };

    main::readingsSingleUpdate($hash, $fwg->{id}, 'run', 1);
    fw_get_next_file($hash);
}

sub fw_get($$;$) {
    my ($hash, $fw, $uri) = @_;
    return fw_get_and_write_flash($hash, $fw, undef, $uri);
}

my $write_flash_log = 'write_flash.txt';
my $erase_flash_log = 'erase_flash.txt';
my $tag_status = 'status_';
my $tag_succ = $tag_status.'0';
my $done_file = 'done.txt';
my $cmd_status = "echo $tag_status\$? | tee $done_file";

sub file_slurp($$) {
    my ($filename, $dst) = @_;
    open(my $fh, '<', $filename) or return 0;
    $$dst = do { local $/;  <$fh> };
    close($fh);
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

sub sys_cmd_rm_log_internals($) {
    my ($hash) = @_;
    delete ($hash->{"$FW_WRT_ID.log"});
    delete ($hash->{"$FW_ERA_ID.log"});
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
        $hash->{"$id.log"} = substr($logstr, 0, 300) if $failed;

        if ($id  eq 'fw_get') {
            main::asyncOutput($cl, "firmware download command failed:\n\n" . $logstr) if ($cl && $failed);
        } elsif ($id eq $FW_WRT_ID) {
            main::asyncOutput($cl, "write-flash command failed:\n\n" . $logstr) if ($cl && $failed);
            devio_open_device($hash);
        } elsif ($id  eq $FW_ERA_ID) {
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
    my $id = $FW_WRT_ID;
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
    run_system_cmd($hash, $tgtdir, $log, $sc, $FW_ERA_ID, 1);
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
        sys_cmd_rm_log_internals($hash);
        if ($a1 eq 'download') {
            fw_get($hash, $firmware->{$cmd});
        } elsif ($a1 eq 'download-beta-version') {
            fw_get($hash, $firmware->{$cmd}, $firmware->{$cmd}{uri_beta});
        } elsif ($a1 eq 'upgrade') {
            fw_get_and_write_flash($hash, $firmware->{$cmd}, 1);
        } elsif ($a1 eq 'upgrade-beta-version') {
            fw_get_and_write_flash($hash, $firmware->{$cmd}, 1, $firmware->{$cmd}{uri_beta});
        } elsif ($a1 eq 'write-flash') {
            fw_write_flash($hash, $firmware->{$cmd});
        } elsif ($a1 eq 'xxx.erase-flash') {
            fw_erase_flash($hash, $firmware->{$cmd});
        }
    } elsif($cmd eq 'mcu-firmware.esp8266') {
    } elsif($cmd eq 'mcu-firmware.atmega328') {
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
=encoding utf-8
=item device
=item summary I/O device which communicates with Tronferno-MCU
=item summary_DE E/A Gerät welches mit Tronferno-MCU kommuniziert

=begin html

<a name="TronfernoMCU"></a>
<h3>TronfernoMCU</h3>

<p><i>TronfernoMCU</i> is a physical Device to connect Tronferno-MCU hardware..
<ul>
 <li>Provides the IODev requiered by Tronferno logical devices</li>
 <li>Requiered MCU/RF-hardware: <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a></li>
 <li>Can flash the MCU (ESP32 or ESP8266) using the respective Set command. (if conected to FHEM by USB)</i>
 <li>Can configure the MCU using Set commands</li>
</ul>


<h4>Define</h4>

<p>
<code>define &lt;name&gt; TronfernoMCU (USB_PORT|IP4_ADDRESS)</code>

<ul>
<li><code> &lt;name&gt;</code> the suggested name is "tfmcu"</li>
<li><code>USB_PORT</code> if MCU is connected to FHEM server by USB</li>
<li><code>IP4_ADDRES</code> if MCU is connected to FHEM server by network</li>
</ul>

<p>Make sure this device is defined before any Tronferno devices. At FHEM startup it needs to be created first, or any Fernotron devices defined prior will fail to be created</p>

<p> Multiple devices can be defined if you have multiple MCU units connected. Then the IODev of a Tronferno device has to be set to the name of the correct TronfernoMCU device it is supposed to use</p>

<h5>Examples</h5>
<ul>
<li><code>define tfmcu TronfernoMCU /dev/ttyUSB1</code> (connect device by USB cable)</li>
<li><code>define tfmcu TronfernoMCU 192.168.1.123</code> (connect device by IP network)</li>
</ul>

<a name="TronfernoMCUset"></a>
<h4>Set</h4>
<ul>

  <a name="mcc.all"></a>
  <li>mcc.all<br>
    Get all configuration data from MCU<br>
    <code>set tfmcu mcc.all ?</code><br></li>

  <a name="mcc.baud"></a>
  <li>mcc.baud<br>
    Baud rate of MCU's serial interface</li>

  <a name="mcc.cu"></a>
  <li>mcc.cu<br>
   Central-Unit ID used by the MCU (six digit hex number)</li>


  <a name="mcc.latitude"></a>
  <li>mcc.latitude<br>
   geographical coordinates are used to calculate civil dusk for astro-timer (decimal degree, e.g. 52.5)</li>

  <a name="mcc.longitude"></a>
  <li>mcc.longitude<br>
   geographical coordinates are used to calculate civil dusk for astro-timer (decimal degree, e.g. 13.4)</li>

  <a name="mcc.restart"></a>
  <li>mcc.restart<br>
    Retart the MCU.</li>

  <a name="mcc.rtc"></a>
  <li>mcc.rtc<br>
    Set MCU's internal real time clock by ISO date/time string (e.g. 1999-12-31T23:59:00). If possible, the MCU will use NTP instead.</li>

  <a name="mcc.tz"></a>
  <li>mcc.tz<br>
    Time-zone in POSIX (TZ) format</li>

  <a name="mcc.verbose"></a>
  <li>mcc.verbose<br>
    Verbosity level of MCU's diagnose output (0 .. 5)</li>

  <a name="mcc.network"></a>
  <li>mcc.network<br>
    Network to connect: none, ap, wlan, lan<br>
<ul>
     <li>none: no networking</li>
     <li>ap: create WLAN accesspoint</li>
     <li>wlan: connect to existing WLAN</li>
     <li>lan: connect to Router via Ethernet</li>
     <li>Note: MCU will be restarted after setting this option</li>
</ul></li>

  <a name="mcc.wlan-password"></a>
  <li>mcc.wlan-passord<br>
    Password used by MCU to connect to WLAN/WiFi<br>
    Note: MCU will be restarted after setting this option </li>

  <a name="mcc.wlan-ssid"></a>
  <li>mcc.wlan-ssid<br>
    WLAN/WiFi SSID to connect to<br>
    Note: MCU will be restarted after setting this option</li>

  <a name="mcc.mqtt-enable"></a>
  <li>mcc.mqtt-enable - enables/disables builtin MQTT client<br>
    <code>set tfmcu mcc.mqtt-enable 1</code><br>
    <code>set tfmcu mcc.mqtt-enable 0</code><br>
<br>
    <code>attr MQTT2_tronferno42 setList cli tfmcu/cli $EVENT</code><br>
    <code>set MQTT2_tronferno42 cli send g=4 m=2 c=down</code><br>
<br>
    </li>

  <a name="mcc.mqtt-url"></a>
  <li>mcc.mqtt-url - URL of MQTT server to connect<br>
    <code>set tfmcu mcc.mqtt-url "mqtt://192.168.1.42:7777"</code>
    </li>

  <a name="mcc.mqtt-user"></a>
  <li>mcc.mqtt-user - User name for MQTT server connection<br>
    <code>set tfmcu mcc.mqtt-user myUserName</code>
    </li>

  <a name="mcc.mqtt-password"></a>
  <li>mcc.mqtt-password - Password for MQTT server connection<br>
    <code>set tfmcu mcc.mqtt-password myPassword</code>
    </li>

  <a name="mcc.http-enable"></a>
  <li>mcc.http-enable - enables/disables builtin webserver<br>
    <code>set tfmcu mcc.http-enable 1</code><br>
    <code>set tfmcu mcc.http-enable 0</code><br>
<br>
    <small>Note: ESP32 only</small><br>
    </li>

  <a name="mcc.http-user"></a>
  <li>mcc.http-user - set optional webserver login user name<br>
    <code>set tfmcu mcc.http-user myUserName</code>
    </li>

  <a name="mcc.http-password"></a>
  <li>mcc.http-password - set optional webserver login password<br>
    <code>set tfmcu mcc.http-password myPassword</code>
    </li>

  <a name="mcu-firmware.esp32"></a>
  <li>mcu-firmware.esp32<br>

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
         Status is shown in reading fw_write_flash (run,done,error,timeout). Shell output may be displayed at error in Internals.</li>
     <li>upgrade<br>
        Combines download and write-flash for convinience.
         </li>
     <li>xxx.erase-flash<br>
          Optional Step before write-flash: Use downloaded tool to delete the MCU's flash memory content. All saved data in MCU will be lost.<br>
         Required Tools: python, pyserial; <code>apt install python  python-serial</code><br>
         Status is shown in reading fw_erase_flash (run,done,error,timeout). Shell output may be displayed at error in Internals.</li>
     <li>download-beta-version<br>
         Downloads beta-firmware and flash-tool from github.<br>
         Files can be found at /tmp/TronfernoMCU<br>
         Status is shown in reading fw_get (run,done,error,timeout).</li>
    </ul>
  </li>

  <a name="mcu-firmware.esp8266"></a>
  <li>mcu-firmware.esp8266<br>
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
         Status is shown in reading fw_write_flash (run,done,error,timeout). Shell output may be displayed at error in Internals.</li>
     <li>upgrade<br>
        Combines download and write-flash for convinience.
     <li>xxx.erase-flash<br>
          Optional Step before write-flash: Use downloaded tool to delete the MCU's flash memory content. All saved data in MCU will be lost.<br>
         Required Tools: python, pyserial; <code>apt install python  python-serial</code><br>
         Status is shown in reading fw_erase_flash (run,done,error,timeout). Shell output may be displayed at error in Internals.</li>
     <li>download-beta-version<br>
         Downloads beta-firmware and flash-tool from github.<br>
         Files can be found at /tmp/TronfernoMCU<br>
         Status is shown in reading fw_get (run,done,error,timeout).</li>
    </ul>
  </li>


</ul>

=end html

=begin html_DE

<a name="TronfernoMCU"></a>
<h3>TronfernoMCU</h3>


<p><i>TronfernoMCU</i> ist ein physisches FHEM Gerät zum steuern von Fernotron-Empfängern und Empfang von Fernotron Sendern.
<ul>
 <li>Erzeugt das IODev benötigt von den logischen Tronferno FHEM Geräten</li>
 <li>MCU/RF-hardware/firmware: <a href="https://github.com/zwiebert/tronferno-mcu">tronferno-mcu</a></li>
 <li>Kann die Firmware flashen für den Mikrocontroller (ESP32 oder ESP8266) mit den jeweiligen SET Kommandos. (wenn über USB verbunden mit FHEM Server)</i>
 <li>Kann Mikrocontroller konfigurieren mit SET Kommandos</li>
 <li>Kann sich über Netzwerk oder USB mit dem Mikrocontroller verbinden.</li>
</ul>

<h4>Define</h4>

<p>
<code>define &lt;name&gt; TronfernoMCU (USB_PORT|IP4_ADDRESS)</code>

<ul>
<li><code> &lt;name&gt;</code> empfohlener Name: "tfmcu"</li>
<li><code>USB_PORT</code> Wenn MCU verbunden mit FHEM über USB</li>
<li><code>IP4_ADDRES</code> Wenn MCU verbunden mit FHEM über Netzwerk</li>
</ul>

<p>Dieses Gerät muss vor allen Tronferno Geräten definiert werden die es benutzen. Beim FHEM Server Start muss es vorher erzeugt werden. Alle vorher erzeugten Tronferno Geräte können nicht angelegt werden.</p>

<p>Mehrere Geräte können definiert werden wenn mehrere MCs vorhanden sind. Dann den IODev der Tronferno Geräte auf den Namen des TronfernoMCU Gerätes setzen, welches verwendet werden soll.</p>

<h5>Beispiele</h5>
<ul>
<li><code>define tfmcu TronfernoMCU /dev/ttyUSB1</code> (verbinde mit MC über USB)</li>
<li><code>define tfmcu TronfernoMCU 192.168.1.123</code> (verbinde mit MC über IP Netzwerk)</li>
</ul>

<a name="TronfernoMCUset"></a>
<h4>Set</h4>
<ul>

  <a name="mcc.all"></a>
  <li>mcc.all<br>
    Lese die komplette Konfiguration aus dem Miktrocontroller aus<br>
    <code>set tfmcu mcc.all ?</code><br></li>

  <a name="mcc.cu"></a>
  <li>mcc.cu<br>
   Programmierzentralen-ID (sechsstellige Hex Nummer im Batteriefach der 2411 Zentrale)</li>

  <a name="mcc.latitude"></a>
  <li>mcc.latitude<br>
   Breitengrad zum Berechnen der Dämmerung (Dezimal-Grad. z.B. 52.5)</li>

  <a name="mcc.longitude"></a>
  <li>mcc.longitude<br>
   Längengrad zum Berechnen der Dämmerung (Dezimal-Grad. z.B. 13.4)</li>

  <a name="mcc.restart"></a>
  <li>mcc.restart<br>
    Neustart des Controllers.</li>

  <a name="mcc.rtc"></a>
  <li>mcc.rtc<br>
    Setzen der Uhrzeit des Controllers mittels ISO Datum/Zeit (z.B. 2018-12-31T23:59:00), falls kein NTP möglich ist.</li>

  <a name="mcc.tz"></a>
  <li>mcc.tz<br>
    Zeit-Zone im POSIX (TZ) Format</li>

  <a name="mcc.verbose"></a>
  <li>mcc.verbose<br>
    Umfang der Diagnose Ausgaben des Controllers (0 .. 5)</li>

  <a name="mcc.network"></a>
  <li>mcc.network<br>
    Netzwerk zum Verbinden des Controllers: none, ap, wlan, lan<br>
<ul>
     <li>none: Kein Netzwerk</li>
     <li>ap:  Wlan Zugangspunkt erzeugen (für Erstkonfiguration)</li>
     <li>wlan: Verbinde mit vorhandenem WLAN</li>
     <li>lan: Verbinde mit Router über Ethernet</li>
     <li>Hinweis: MC wird neugestartet nach setzen einer dieser Optionen</li>
</ul></li>
  <a name="mcc.wlan-password"></a>
  <li>mcc.wlan-password<br>
    Passwort zum Verbinden mit bestehendem WLAN Netz<br>
   Hinweis: MC wird neugestartet nach setzen dieser Option</li>


  <a name="mcc.wlan-ssid"></a>
  <li>mcc.wlan-ssid<br>
    SSID es bestehenden WLAN Netzes<br>
    Hinweis: MC wird neugestartet nach setzen dieser Option</li>


  <a name="mcc.mqtt-enable"></a>
  <li>mcc.mqtt-enable - aktiviere MQTT Klient des MCs<br>
    <code>set tfmcu mcc.mqtt-enable 1</code><br>
    <code>set tfmcu mcc.mqtt-enable 0</code><br>
<br>
    <code>attr MQTT2_tronferno42 setList cli tfmcu/cli $EVENT</code><br>
    <code>set MQTT2_tronferno42 cli send g=4 m=2 c=down</code><br>
<br>
    <small>Hinweis: ESP32 und ESP8266</small><br>
    </li>

  <a name="mcc.mqtt-url"></a>
  <li>mcc.mqtt-url - URL des MQTT Brokers/Servers<br>
    <code>set tfmcu mcc.mqtt-url "mqtt://192.168.1.42:7777"</code>
    </li>

  <a name="mcc.mqtt-user"></a>
  <li>mcc.mqtt-user - Username für Login beim MQTT Server/Broker<br>
    <code>set tfmcu mcc.mqtt-user myUserName</code>
    </li>

  <a name="mcc.mqtt-password"></a>
  <li>mcc.mqtt-password - Passwort für Login beim MQTT Server/Broker<br>
    <code>set tfmcu mcc.mqtt-password myPassword</code>
    </li>

  <a name="mcc.http-enable"></a>
  <li>mcc.http-enable - aktiviert den Webserver des MCs (Browseroberfläche)<br>
    <code>set tfmcu mcc.http-enable 1</code><br>
    <code>set tfmcu mcc.http-enable 0</code><br>
<br>
    <small>Hinweis: Nur ESP32</small><br>
    </li>

  <a name="mcc.http-user"></a>
  <li>mcc.http-user - Optionaler Webserver Benutzername zur Authentifizierung<br>
    <code>set tfmcu mcc.http-user myUserName</code>
    </li>

  <a name="mcc.http-password"></a>
  <li>mcc.http-password -  Optionales Webserver Benutzerpasswort zur Authentifizierung<br>
    <code>set tfmcu mcc.http-password myPassword</code>
    </li>

  <a name="mcu-firmware.esp32"></a>
  <li>mcu-firmware.esp32<br>
   Download der letzten MC firmware von GitHub(tronferno-mcu-bin) und Flashen
    <ul>
     <li>download<br>
         Download Firmware und Flash-Programm.<br>
         Dateien werden kopiert nach /tmp/TronfernoMCU<br>
         Status ist sichtbar im Reading fw_get (run,done,error,timeout).</li>
     <li>write-flash<br>
         Flasht die Firmware über den USB Port definiert in diesem Gerät.<br>
         Benötigt: python, pyserial; <code>apt install python  python-serial</code><br>
         MCU: ESP32/4MB/WLAN angeschlossen über USB.<br>
         Status ist sichtbar im Reading fw_write_flash (run,done,error,timeout).</li>
     <li>upgrade<br>
        Kombiniert download und flashen in einem Schritt.
         </li>
     <li>xxx.erase-flash<br>
          Optional: Löschen des FLASH-ROM. Alle gespeicherten Daten auf dem MC gehen verloren!</br>
         Benötigt: python, pyserial; <code>apt install python  python-serial</code><br>
         Status ist sichtbar im Reading fw_erase_flash (run,done,error,timeout).</li>
     <li>download-beta-version<br>
         Download der letzten beta-firmware und Flash Programm.<br>
         Dateien werden kopiert nach /tmp/TronfernoMCU<br>
         Status ist sichtbar im Reading fw_get (run,done,error,timeout).</li>
    </ul>
  </li>

  <a name="mcu-firmware.esp8266"></a>
  <li>mcu-firmware.esp8266<br>
  Download der letzten MC firmware von GitHub(tronferno-mcu-bin) und Flashen
    <ul>
     <li>download<br>
         Download Firmware und Flash-Programm.<br>
         Dateien werden kopiert nach /tmp/TronfernoMCU<br>
         Status ist sichtbar im Reading fw_get (run,done,error,timeout).</li>
     <li>write-flash<br>
         Flasht die Firmware über den USB Port definiert in diesem Gerät.<br>
         Benötigt: python, pyserial; <code>apt install python  python-serial</code><br>
         MCU: ESP8266/4MB/WLAN angeschlossen über USB.<br>
         Status ist sichtbar im Reading fw_write_flash (run,done,error,timeout).</li>
     <li>upgrade<br>
        Kombiniert download und flashen in einem Schritt.
         </li>
     <li>xxx.erase-flash<br>
          Optional: Löschen des FLASH-ROM. Alles gespeicherten Daten auf dem MC gehen verloren!</br>
         Benötigt: python, pyserial; <code>apt install python  python-serial</code><br>
         Status ist sichtbar im Reading fw_erase_flash (run,done,error,timeout).</li>
     <li>download-beta-version<br>
         Download der letzten beta-firmware und Flash Programm.<br>
         Dateien werden kopiert nach /tmp/TronfernoMCU<br>
         Status ist sichtbar im Reading fw_get (run,done,error,timeout).</li>
    </ul>
  </li>


</ul>

=end html_DE

# Local Variables:
# compile-command: "perl -cw -MO=Lint ./00_TronfernoMCU.pm 2>&1 | grep -v 'Undefined subroutine'"
# eval: (my-buffer-local-set-key (kbd "C-c C-c") (lambda () (interactive) (shell-command "cd ../../.. && ./build.sh")))
# eval: (my-buffer-local-set-key (kbd "C-c c") 'compile)
# eval: (my-buffer-local-set-key (kbd "C-c p") (lambda () (interactive) (shell-command "perlcritic  ./00_TronfernoMCU.pm")))
# End:

# tronferno-fhem
experimental code for Fernotron and FHEM

## What it currently does

### FHEM experimental module

* modules for both SIGNALduino and Tronferno-MCU

* configuration in FHEM

in  fhem.cfg it looks like this:

```
...
define ftroll22 Fernotron                       shutter 2/2 pm for SIGNALduino
attr ftroll22 controllerId 0x80abcd             scan your ID(s) with the fhemft.pl script
attr ftroll22 groupNumber 2                     group number
attr ftroll22 memberNumber 2                    member number
attr ftroll22 webCmd down:stop:up
define ftroll21 Fernotron                       shutter 2/1
attr ftroll21 controllerId 0x80abcd
attr ftroll21 groupNumber 2
attr ftroll21 memberNumber 1
attr ftroll21 webCmd down:stop:up
...
define roll22 Tronferno                         shutter 2/2  for Fernotron-MCU
attr roll22 groupNumber 2
attr roll22 mcuaddr 192.168.1.61               IP4 address of tronferno-mcu hardware
attr roll22 memberNumber 2
attr roll22 webCmd down:stop:up
define roll25 Tronferno                         shutter 2/5
attr roll25 groupNumber 2
attr roll25 mcuaddr 192.168.1.61
attr roll25 memberNumber 5
attr roll25 webCmd down:stop:up
```


### Sending and receiving vie SIGNALduino using a perl script (fhemft.pl)

* works from command line and runs fhem.pl directly with the message passed by command line
* can scan the FHEM/SIGNALduino logfile for Fernotron commands
* can send Fernotron commands using the ID obtained by scanning or the IDs written on the motor/cable sticker.  Please prefix a motor-ID with Digit 9. So 0abcd written on a motor label becomes 90abcd.


#### Usage
```
Usage:  fhemft.pl command [options ...]

commands: --scan, --send, --help

  --send            build and send a Fernotron command-message via FHEM
   -a=ID            ferntron ID (hex number), e.g. the ID of the 2411 main controller unit
   -g=N             group number 1 ... 7,  or 0 for send to all groups
   -m=N             member number 1 ... 7.  or 0 for send to all members
   -c=string        command string: up, down, stop, sun-down, sun-inst, set

   -n=string        name of SIGNALduino in FHEM (default: sduino)

  --scan            scan the current FHEM logfile for received Fernotron commands
    -f FILE         use this fhem log file insted of default
    -v=N            set verbose level of SIGNALduino. Must be at least level 4 to make it work.
```


#### Examples
```
   ./fhemft.pl --send -a=80abcd -g=1 -c=up  -n=sduino      # opens all shutters of group 1
   ./fhemft.pl --send -a=90abcd --send -c=close            # closes motor 0abcd
   ./fhemft.pl --scan -n=sduino -v=4                       # after that press stop button on controller
```


```

$ ./fhemft.pl --scan -v=4
/opt/fhem/fhem.pl localhost:7072  'attr sduino verbose 4'
id=80abcd, tgl=11, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=12, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=13, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=14, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=15, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=1, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=2, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=3, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=4, memb=1, grp=3, cmd=3,  
id=80abcd, tgl=5, memb=1, grp=3, cmd=3,  
error
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=7, memb=1, grp=3, cmd=5,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
id=80abcd, tgl=9, memb=1, grp=3, cmd=4,  
^C
```

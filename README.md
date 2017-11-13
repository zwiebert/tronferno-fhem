# tronferno-fhem
experimental code for Fernotron and FHEM

## What it currently does


### Sending and receiving vie SIGNALduino

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

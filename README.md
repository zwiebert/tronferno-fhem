# tronferno-fhem
experimental code for Fernotron and FHEM

## What it currently does

### Experimental FHEM modules  (10_Tronferno.pm and 10_Fernotron.pm)

* Fhem module Fernotron  works with SIGNALduino.  Module Tronferno works with Tronferno-MUC hardware

* how to install: see comments at top of the module files

* How to configure in FHEM:

From web-interface or telnet add a device for each shutter and configure the attributes.


```
...
define ftroll22 Fernotron a=80abcd g=2 m=2      #shutter group-2 member-2 for SIGNALduino
attr ftroll22 webCmd down:stop:up
define ftroll21 Fernotron  a=80abcd g=2 m=1     #shutter 2/1
attr ftroll21 webCmd down:stop:up
...
define tfmcu TronfernoMCU 192.168.1.61          # IO device for TCP/IP or ...
define tfmcu TronfernoMCU /dev/ttyUSB1          # ... IO devie for USB port

define roll22 Tronferno g=2 m=2                 #shutter 2/2  for Tronferno-MCU
attr roll22 webCmd down:stop:up
define roll25 Tronferno g=2 m=5                 #shutter 2/5
attr roll25 webCmd down:stop:up
```


## Recent Changes

* TronfernoMCU can now be flashed on ESP32. It's at the moment more stable via TCP/IP than ESP8266.
* Tronferno can read back status from MCU module
* Tronferno comes now with DevIO module 00_TronfernoMCU.pm. So the MCU can now be attached via USB port.

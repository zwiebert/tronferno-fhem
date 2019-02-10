<p align="center">
  <span>English</span> |
  <a href="README-de.md">Deutsch</a>
</p>

# tronferno-fhem
experimental code for Fernotron and FHEM

## What it currently does

### Experimental FHEM modules  (10_Tronferno.pm and 10_Fernotron.pm)

* Fhem module Fernotron  works with SIGNALduino.  Module Tronferno works with TronfernoMCU hardware device

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


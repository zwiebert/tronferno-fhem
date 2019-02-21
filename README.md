#<p align="center">
  <span>English</span> |
  <a href="README-de.md">Deutsch</a>
</p>

# tronferno-fhem

Using Fernotron devices with FHEM

## General


This project contains two different FHEM modules for the purpose of controlling and utilizing physical Fernotron devices via radio frequency. Fernotron devices are shutters, plugs and  controllers, sensors for input. 

1. FHEM module Fernotron controls Fernotron devices and utilizes Sensors and Switches for usage with FHEM.  It requires SIGNALduino as underlying IODev and RF transceiver hardware. The installation is described below. After that, please refer to the [English module help text](doc/sduino_fernotron.pod).

2. FHEM  Module Tronferno controls Fernotron devices. It has its own I/O device module TronfernoMCU. It requires the [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu) RF transceiver hardware. Installation is described below. Please refer to  [English module help text](doc/tronferno.pod) for usage information after that.


## Installation

Installation and update of the modules and documentation is done by FHEM's update command:

### Fernotron module for SIGNALduino
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/control.txt
```

At first install please add protocol number 82 to attribute whitelist_IDs of SIGNALduino device (sduino).

### Tronferno module for tronferno-mcu hardware
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/control.txt
```


## Usage Examples for Fernotron FHEM module

Please read the [English module help text](doc/sduino_fernotron.pod) for more information.

A SIGNALduino needs do be defined first. Fernotron requires is as I/O Device to connect to physical Fernotron devices via RF.

* Define devices to control shutters

```
...
define ftroll22 Fernotron a=80abcd g=2 m=2      # define device to control shutter 2 of  group 2
attr ftroll22 webCmd down:stop:up               # control buttons for web-interface
attr ftroll22 genericDeviceType blind           # ... needed by alexa module
attr ftroll22 alexaName SomeName                 # ... needed by alexa module
...
```

### Usage Examples for Tronferno/TronfernoMCU FHEM modules

Please read the [English module help text](doc/tronferno.pod) for more information.

* First, define IO device and chose if it connects to the hardware via USB or TCP/IP. 
```
...
define tfmcu TronfernoMCU 192.168.1.61          # IODev for TCP/IP or ...
define tfmcu TronfernoMCU /dev/ttyUSB1          # ... for USB
```


* Define devices to control shutters

```
...
define roll22 Tronferno g=2 m=2                 # define device to control shutter 2 of  group 2
attr roll22 webCmd down:stop:up                 # control buttons for web-interface
attr roll22 genericDeviceType blind             # ... needed by alexa module
attr roll22 alexaName SomeName                   # ... needed by alexa module
...
```

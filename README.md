<p align="center">
  <span>English</span> |
  <a href="README-de.md">Deutsch</a>
</p>

# tronferno-fhem

Use Fernotron devices with FHEM Server

## General

It contains two different FHEM modules, useful to owners of Fernotron shutters and controllers.

* One module to control Fernotron Receivers (like shutter motors) and to integrate Fernotron controllers (manual and sun sensors) into FHEM. It requires SIGNALduino hardware connected to your FHEM server.

* The other module is intended for users of  [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu) hardware.

## Installation

Installation and update of the modules and documentaion is done by FHEM's update command:

### Fernotron module for SIGNALduino-dev
```
     update https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/control.txt
```


### Fernotron module for SIGNALduino-stable
```
     update https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino-stable/control.txt
```

Additionally you may need to apply the diff from directory modules/sduino-stable to FHEM/00_SIGNALduino.pm using patch command. Or set  IODev-attribute of each Fernotron device to sduino. But this only allows transmitting. No receiving possible without doing the patching.

### Tronferno module for tronferno-mcu hardware
```
     update https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/control.txt
```


## Usage

### Fernotron for SIGNALduino

* If SIGNALduino is already in use, all you need to do is install this module and define your devices. The input device scanFerno will be auto-created if Fernotron transmissios are received.

Using Notify or DOIF you can integrate Fernotron controllers and sun-sensors into FHEM. The device 'scanFerno' handles all the input itself.

Example - notify to toggle a lamp when pressig STOP on Fernotron-Controllers with ID 1023dc

```
   define n_myFerLamp notify scanFerno:plain:1023dc:stop set myLamp toggle
```
 
* More info in the module's commandref

Example - define devices to control shutters

```
...
define ftroll22 Fernotron a=80abcd g=2 m=2      # define device to control shutter 2 of  group 2
attr ftroll22 webCmd down:stop:up               # control buttons for web-interface
attr ftroll22 genericDeviceType blind           # ... needed by alexa module
attr ftroll22 alexaName DerName                 # ... needed by alexa module
...
```

### Tronferno for tronferno-mcu

* If you have tronferno-mcu hardware in use, you can control it with FHEM using this module. Available are simple commands like up/down/stop. You have to define a single I/O device TronfernoMCU first. Then you can define Tronferno devices - one for each shutter.

Example - define devices
```
...
define tfmcu TronfernoMCU 192.168.1.61          # IODev for TCP/IP or ...
define tfmcu TronfernoMCU /dev/ttyUSB1          # ... for USB
...
define roll22 Tronferno g=2 m=2                 # define device to control shutter 2 of  group 2
attr roll22 webCmd down:stop:up                 # control buttons for web-interface
attr roll22 genericDeviceType blind             # ... needed by alexa module
attr roll22 alexaName DerName                   # ... needed by alexa module
...
```

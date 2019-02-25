<p align="center">
  <span>English</span> |
  <a href="README-de.md">Deutsch</a>
</p>

# tronferno-fhem

Using Fernotron devices with FHEM

## General


This project contains two different FHEM modules for the purpose of controlling and utilizing physical Fernotron devices via radio frequency. Fernotron devices are shutters, plugs and  controllers, sensors for input. 


### 1. FHEM module Fernotron

 * It controls Fernotron devices and utilizes Sensors and Switches for usage with FHEM.
 * It requires SIGNALduino as underlying IODev and RF transceiver hardware.
 * Please refer to the [module help text](doc/sduino_fernotron.pod).

### Installation and Update

 The module and commandref are installed by FHEM's update command:


```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/control.txt
```

To be able to receive Fernotron commands you need to:

 * add protocol number 82 to attribute whitelist_IDs of SIGNALduino device (sduino). To do this go to menu 'Display protocollist' available at the SIGNALduino device page at FHEMWEB. (note: if you add protocol numbers to that attribute, all other protocol numbers become disabled)

 * configure two SIGNALduino hardware options:
```
get sduino raw CEO
get sduino raw CDR
```






### 2. FHEM  Module Tronferno

 * It controls Fernotron devices.
 * It has its own I/O device module TronfernoMCU.
 * It requires the [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu) RF transceiver hardware.
 * Please refer to  [TronfernoMCU I/O  module help text](doc/tronferno_mcu.pod) and [Tronferno module help text](doc/tronferno.pod) for usage information after that.

### Installation and Update

 The modules and commandref are installed by FHEM's update command:

```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/control.txt
```



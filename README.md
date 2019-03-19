<p align="center">
  <span>English</span> |
  <a href="README-de.md">Deutsch</a>
</p>

# tronferno-fhem

Using Fernotron devices with FHEM

### General


This project contains two different FHEM modules for the purpose of controlling and utilizing physical Fernotron devices via radio frequency. Fernotron devices are shutters, plugs and  controllers, sensors for input. 


### 1. FHEM module Fernotron

 * controls Fernotron devices
 * makes Fernotron sensors and switches available in FHEM.
 * requires SIGNALduino as underlying IODev and RF transceiver hardware.
 * Read [module help text](doc/sduino_fernotron.pod).
 
#### Installation and Update

 The module and commandref are installed and updated by FHEM's update command:


```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/controls_fernotron.txt
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
 * Please refer to  [TronfernoMCU I/O  module help text](doc/tronferno_mcu.pod) and [Tronferno module help text](doc/tronferno.pod) for usage information.

#### Installation and Update

 The modules and commandref are installed and updated by FHEM's update command:

```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/controls_tronferno.txt
```


### 3. MQTT

* needs no specific Module in FHEM
* the ESP32-Hardware [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu) can be controlled by its command line interface via MQTT.

After you configured the connection data to the FHEM MQTT2_SERVER you cand define a shutter device in FHEM like this:


```
define mshutter23 MQTT2_DEVICE

attr mshutter23 setList up:noArg tfmcu/cli send g=2 m=3 c=up\
stop:noArg tfmcu/cli send g=2 m=3 c=stop\
down:noArg tfmcu/cli send g=2 m=3 c=down

attr mshutter23 webCmd down:stop:up
```

Explanation:
  * stop:noArg - the name of the generated Set command (noArg gets rid of the useles textinput field on FHEMWEB)
  * tfmcu/cli  - the MQTT Topic to where the CLI command will be sent
  * send g=2 m=3 c=down  - the CLI command to close the shutter number 3 of group 2
  

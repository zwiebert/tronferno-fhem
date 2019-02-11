<p align="center">
   <a href="README.md">English</a> |
    <span>Deutsch</span>
</p>

# tronferno-fhem

Fernotron mit FHEM Server steuern

## Verwendung

Zwei verschiedene FHEM Module nützlich für Besitzer von Fernotron Rollläden.

* Ein Modul zur Benutzung mit FHEM um Fernotron Empfäger-Geräte (Rollläden) anzusteuern. Das Modul funktioniert mit SIGNALduino Hardware am FHEM

* Ein FHEM-Modulpaar für Benutzer der Hardware [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu).


### FHEM Modul 10_Fernotron.pm für SIGNALduino

* Wenn bereits der SIGNALduino in Verwendung ist, reicht alleine die Installation dieses Moduls um Fernotron Geräte steuern zu können. Das ist beschränkt auf die normalen Kommandos wie Auf/Zu.
 Dieses Module kann dann durch FHEM Module wie ROLLO, alexa, AutomaticShuttersControl (ACS) angesteuert werden zur Erweiterung des Funktionsumfangs.
 
* Weitere Infos in [doc/Modul_Bedienung.md](doc/Modul_Bedienung.md) und im Modul selber

Aus dem FHEM Web-Interface herause die Geräte definieren:

```
...
define ftroll22 Fernotron a=80abcd g=2 m=2      #shutter group-2 member-2 for SIGNALduino
attr ftroll22 webCmd down:stop:up               # 

attr ftroll22 genericDeviceType blind           # ... nötig wenn Alexa benutzt werden soll
attr ftroll22 alexaName XXX

define ftroll21 Fernotron  a=80abcd g=2 m=1     #shutter 2/1
...etc..
```



### FHEM Module 10_Tronferno.pm und 00_TronfernoMCU.pm für tronferno-mcu

* Wird der tronferno-mcu Hardware betrieben, kann dieser über FHEM gesteuert werden.  Verfügbar sind nur dei einfachen Kommandos. Es werden die Positionsdaten aus der MCU durch das Modul angezeigt

* Fhem module Fernotron  works with SIGNALduino.  Module Tronferno works with TronfernoMCU hardware device

* Installations Hinweise befinden sich in der Datei

* how to install: see comments at top of the module files

* How to configure in FHEM:


From web-interface or telnet add a device for each shutter and configure the attributes.


```
...
define tfmcu TronfernoMCU 192.168.1.61          # IO device for TCP/IP or ...
define tfmcu TronfernoMCU /dev/ttyUSB1          # ... IO devie for USB port

define roll22 Tronferno g=2 m=2                 #shutter 2/2  for Tronferno-MCU
attr roll22 webCmd down:stop:up

attr roll22 genericDeviceType blind            # ... nötig wenn Alexa benutzt werden soll
attr roll22 alexaName XXX


define roll25 Tronferno g=2 m=5                 #shutter 2/5
attr roll25 webCmd down:stop:up
...etc...
```



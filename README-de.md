﻿<p align="center">
   <a href="README.md">English</a> |
    <span>Deutsch</span>
</p>

# tronferno-fhem

Fernotron Geräte mit FHEM Server verwenden

## Allgemeines

Zwei verschiedene FHEM Module für Besitzer von Fernotron Rollläden oder Fernotron Sendern.

* Ein FHEM-Modul welches SIGNALduino verwendet um Fernotron Empfäger-Geräte (meistens Rollläden) anzusteuern und Fernotron-Taster und Sonnensensoren zur allgemeinen Steuerung in FHEM notify oder DOIF zu nutzen.

* Ein FHEM-Modul für die Benutzer der Hardware [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu).

## Installation

Die Installation oder Aktualisierung der Module und Dokumentation wird durch den update Befehl von FHEM wie folgt durchgeführt:

### Fernotron Modul für SIGNALduino-dev
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/control.txt
```

Bei der ersten Installation ist es nötig die Protokollnummer 82 zum Attribut whitelist_IDs des SIGNALduino Gerätes (sduino) hinzuzufügen um das Empfangen freizuschalten. Dazu das Gerät sduino im Web-Interface öffnen und im Information Menu den Link 'Display protocollist' öffnen. Oder besser vorher den aktuellen Hilfetext für das Attribute whitelist_IDs lesen.

Alternativ
```
attr sduino development 1
```


### Fernotron Modul für SIGNALduino-stable
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino-stable/control.txt
```

Hier sollte noch das diff aus dem Verzeichnis modules/sduino-stable benutzt werden um FHEM/00_SIGNALduino.pm zu patchen. Alternativ das IODev-Attribut jedes Fernotron Gerätes auf sduino setzen. Allerdings ist dann nur Senden möglich, kein Empfangen. 

### Tronferno Module für tronferno-mcu Hardware
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/control.txt
```


## Verwendung

### Fernotron für SIGNALduino


#### Geräte zum Steuern von Rolläden (Output)

* Wenn bereits der SIGNALduino in Verwendung ist, reicht alleine die Installation dieses Moduls um Fernotron Geräte steuern zu können. Das ist beschränkt auf die normalen Kommandos wie Auf/Zu.
 Fernotron Geräte können durch FHEM Module wie ROLLO, alexa, AutomaticShuttersControl (ACS) angesteuert werden zur Erweiterung des Funktionsumfangs.
 
#### Geräte zum Empfangen von Fernotron Sendern und Sensoren für allgemeine Steuerungsaufgaben (Input)
 
* Default Input Gerät: Es wird ein Gerät scanFerno automatich angelegt was alle  Nachrichten übernimmt für deren Absender kein eigenes Input-Gerät definiert wurde. Damit könne IDs gescannt werden die benötigt werden zum Definieren von Input-Geräten und u.U. auch Output-Geräten.

* Input-Geräte können für Handsender (plain) und Sonnensensor (sun) angelegt werden.
```
   define FernoHandsender_1 Fernotron a=1023dc input=plain    # dieses gerät empfängt Nachrichen vom Handsender. Das Reading state ist: up, down, stop.
                                                              
   define FernoSonnenSensor_1 Fernotron a=2023dc input=sun    # dieses gerät empfängt Nachrichen vom Sonnensensor.  Das Reading state ist: on, off. (on=Sonne)
``` 

Beispiel - Notify um Lampe zu toggeln über STOP Taster eines Fernotron-Handsenders

```
   define n_myFerLamp notify scanFerno:plain:1023dc:stop set myLamp toggle
```
 
* Weitere Infos in [doc/Modul_Bedienung.md](doc/Modul_Bedienung.md) und im CommandRef des Fernotron-Moduls

Beispiel- Geräte zur Rollladensteuerung anlegen:

```
...
define ftroll22 Fernotron a=80abcd g=2 m=2      # Gerät zur Steuerung Rolladen Gruppe 2 Empfänger 2 
attr ftroll22 webCmd down:stop:up               # Bedienknöpfe für Weboberfläche 
attr ftroll22 genericDeviceType blind           # ... nur für alexa Modul nötig
attr ftroll22 alexaName DerName                 # ... nur für alexa Modul nötig
...
```

### Tronferno für tronferno-mcu

* Wird der tronferno-mcu Hardware betrieben, kann dieser über FHEM gesteuert werden.  Verfügbar sind nur die einfachen Kommandos. Es werden die Positionsdaten aus der MCU durch das Modul angezeigt.  Es muss ein E/A-Gerät TronfernoMCU definiert werden siehe unten und beliebig viele Rolladen-Geräte Tronferno.

Beispiel - Geräte anlegen. 
```
...
define tfmcu TronfernoMCU 192.168.1.61          # Entweder ein E/A-Gerät für Datenverkehr über TCP/IP ...
define tfmcu TronfernoMCU /dev/ttyUSB1          # ... oder ein E/A-Gerät für Datenverkehr über USB
...
define roll22 Tronferno g=2 m=2                 # Gerät zur Steuerung Rolladen Gruppe 2 Empfänger 2
attr roll22 webCmd down:stop:up                 # Bedienknöpfe für Weboberfläche 
attr roll22 genericDeviceType blind             # ... nur für alexa Modul nötig
attr roll22 alexaName DerName                   # ... nur für alexa Modul nötig
...
```


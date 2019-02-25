<p align="center">
   <a href="README.md">English</a> |
    <span>Deutsch</span>
</p>

# tronferno-fhem

Module zum Einbinden von Fernotron Geräten in FHEM Server

## Allgemeines

Dieses Repository enthält zwei verschiedene FHEM Module um Fernotron Geräte via Funk zu steuern und/oder als Eingabegeräte zu nutzen. Fernotron Geräte sind u.a. Rohrmotoren bzw. Steuerrelais für diese, Funk-Steckdosen sowie sendende Geräte wie Handsender und Sonnensensoren.


1.  Ein FHEM-Modul "Fernotron" zum steuern von Fernotron Empfänger und zum Einbinden von Fernotron-Sendern in FHEM zur allgemeinen Verwendung. Es benötigt SIGNALduino als I/O-Gerät und Radio-Hardware. Die Installation ist im folgenden Abschnitt beschrieben. Die weitere Nutzung in der  [deutschen Moduldokumentation](doc/sduino_fernotron_de.pod). 

2.  FHEM-Modul "Tronferno" zum Steuern von Fernotron Empfängern über die Hardware [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu).
Installation ist unten beschrieben. Die weitere Nutzung in der [englische Moduldokumentation](doc/tronferno.pod).


## Installation

Die Installation oder Aktualisierung der Module und Dokumentation wird durch den update Befehl von FHEM wie folgt durchgeführt:

### Fernotron Modul für SIGNALduino
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/control.txt
```
#### Konfiguration von SIGNALduino zum Empfang von Fernotron Nachrichten
Das reine Senden funktioniert ohne jede Konfiguration. Aber bei der ersten Installation ist es nötig die Protokollnummer 82 zum Attribut whitelist_IDs des SIGNALduino Gerätes (sduino) hinzuzufügen um das Empfangen freizuschalten. Dazu das Gerät sduino in FHEMWEB öffnen und im Information-Menü den Link 'Display protocollist' öffnen. Dazu auch den aktuellen Hilfetext für das Attribut whitelist_IDs lesen.

Die SIGNALduino-Hardware müsste zum Empfang entsprechend konfiguiert werden durch:
```
get sduino raw CEO
get sduino raw CDR
```
(Config_Enable_Overflow und Config_Disable_Reduction ?)

SIGNALduino Konfiguration ist beschrieben in [Nachricht im FHEM-Forum](https://forum.fhem.de/index.php/topic,82379.msg744554.html#msg744554)

### Tronferno Module für tronferno-mcu Hardware
```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/control.txt
```

## Beispiele Tronferno für tronferno-mcu

Siehe auch die [englische Moduldokumentation](doc/tronferno.pod) für mehr Infos.



* Als erstes muss das I/O Gerät definiert werden. Es kann entweder per USB oder TCP/IP mit der Hardware verbunden werden:
```
...
define tfmcu TronfernoMCU 192.168.1.61          # Entweder ein E/A-Gerät für Datenverkehr über TCP/IP ...
define tfmcu TronfernoMCU /dev/ttyUSB1          # ... oder ein E/A-Gerät für Datenverkehr über USB
```

* Gerät definieren zum Steuern eines Rolladens

```
...
define roll22 Tronferno g=2 m=2                 # Gerät zur Steuerung Rolladen Gruppe 2 Empfänger 2
attr roll22 webCmd down:stop:up                 # Bedienknöpfe für Weboberfläche 
attr roll22 genericDeviceType blind             # ... nur für alexa Modul nötig
attr roll22 alexaName EinName                   # ... nur für alexa Modul nötig
...
```

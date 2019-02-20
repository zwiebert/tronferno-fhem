<p align="center">
   <a href="README.md">English</a> |
    <span>Deutsch</span>
</p>

# tronferno-fhem

Module zum Einbinden von Fernotron Geräten in FHEM Server

## Allgemeines

Dieses Repository enthält zwei verschiedene FHEM module um Fernotron Geräte zu via Funk zu steuern und/oder als Eingabe zu nutzen. Fernotron Geräte sind Rohrmotoren bzw. Steuerrelais für diese, Steckdosen sowie sendende Geräte wie Handsender und Sonnensensoren.


1.  Ein FHEM-Modul "Fernotron" zum steuern von Fernotron Empfänger und zum Einbinden von Fernotron-Sendern in FHEM zur allgemeinen Verwendung. Es benötigt SIGNALduino als I/O-Gerät und Radio-Hardware. Die Installation ist im folgenden Abschnitt beschrieben. Die weitere Nutzung in der  [deutschen Moduldokumentation](doc/sduino_fernotron_de.pod). 

2.  FHEM-Modul "Tronferno" zum Steuern von Fernotron Empfängern über die Hardware [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu).
Installation ist unten beschrieben. Die weitere Nutzung in der [englische Moduldokumentation](doc/tronferno.pod).


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

## Beispiele für Fernotron für SIGNALduino

Weitere Infos in der [Moduldokumentation](doc/sduino_fernotron_de.pod) und auch in [doc/Modul_Bedienung.md (teilweise veraltet)](doc/Modul_Bedienung.md).

Ein SIGNALduino Gerät muss bereits definiert sein.


* Gerät zur Rollladensteuerung anlegen:

```
...
define ftroll22 Fernotron a=80abcd g=2 m=2      # Gerät zur Steuerung Rolladen Gruppe 2 Empfänger 2 
attr ftroll22 webCmd down:stop:up               # Bedienknöpfe für Weboberfläche 
attr ftroll22 genericDeviceType blind           # ... nur für alexa Modul nötig
attr ftroll22 alexaName DerName                 # ... nur für alexa Modul nötig
...
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
attr roll22 alexaName DerName                   # ... nur für alexa Modul nötig
...
```

<p align="center">
   <a href="README.md">English</a> |
    <span>Deutsch</span>
</p>

# tronferno-fhem

Module zum Einbinden von Fernotron Geräten in FHEM Server

## Allgemeines

Dieses Repository enthält zwei verschiedene FHEM Module um Fernotron Geräte via Funk zu steuern und/oder als Eingabegeräte zu nutzen. Fernotron Geräte sind u.a. Rohrmotoren bzw. Steuerrelais für diese, Funk-Steckdosen sowie sendende Geräte wie Handsender und Sonnensensoren.


### 1.  FHEM-Modul "Fernotron"

 * zum steuern von Fernotron Empfänger
 * zum Einbinden von Fernotron-Sendern in FHEM zur allgemeinen Verwendung.
 * Es benötigt SIGNALduino als I/O-Gerät und Radio-Hardware.
 * Beschreibung ind  [deutschen Moduldokumentation](doc/sduino_fernotron_de.pod). 

#### Installation und Aktualisierung

 * die Module und commandref werden durch FHEMs update Kommando installiert und aktualisiert

```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/sduino/control.txt
```

 * (wenn erforderlich: einmalig alle vorher manuell manuell installierten Versionen in einer shell löschen oder deren Besitzer ändern mit 'sudo chown fhem.dialout /opt/fhem/10_Fernotron.pm').


#### Konfiguration von SIGNALduino zum Empfang von Fernotron Nachrichten
Das reine Senden funktioniert ohne jede Konfiguration. Aber bei der ersten Installation ist es nötig die Protokollnummer 82 zum Attribut whitelist_IDs des SIGNALduino Gerätes (sduino) hinzuzufügen um das Empfangen freizuschalten. Dazu das Gerät sduino in FHEMWEB öffnen und im Information-Menü den Link 'Display protocollist' öffnen. Dazu auch den aktuellen Hilfetext für das Attribut whitelist_IDs lesen.

Die SIGNALduino-Hardware müsste zum Empfang entsprechend konfiguiert werden durch:
```
get sduino raw CEO
get sduino raw CDR
```
(Config_Enable_Overflow und Config_Disable_Reduction ?)

SIGNALduino Konfiguration ist beschrieben in [Nachricht im FHEM-Forum](https://forum.fhem.de/index.php/topic,82379.msg744554.html#msg744554)



#### 2.  FHEM-Modul "Tronferno" zum Steuern von Fernotron Empfängern über die Hardware [Tronferno-MCU](https://github.com/zwiebert/tronferno-mcu).
Installation ist unten beschrieben. Die weitere Nutzung in [englische TronfernoMCU I/O Moduldokumentation](doc/tronferno_mcu.pod) und  [englische Tronferno Moduldokumentation](doc/tronferno.pod).

#### Installation und Aktualisierung

 Die Module und commandref werden durch FHEMs update Kommando installiert und aktualisiert

```
     update all https://raw.githubusercontent.com/zwiebert/tronferno-fhem/master/modules/tronferno/control.txt
```


FHEM Modul Fernotron - Benutzung
================================


Grundlagen
----------

Jedes Gerät eine ID-Nummer ab Werk fest einprogrammiert. Empfänger und Sender werden gekoppelt, indem sich der Empfänger die ID des Senders merkt. Jeder Empfänger kann sich je eine ID einer Zentraleinheit (inklusive Gruppe und Empfängernummer), eines Sonnensensors und mehrerer Handsender merken.


Gerät definieren
----------------

Ein Gerät kann einen einzige Rolladen aber  auch eine ganze Gruppe ansprechen.  Dies wird durch die verwendete ID und Gruppen und Empfängernummer bestimmt.


Attribute
---------

* controllerID - sechstellige hexadezimale Zahl.  10xxxx=Handsender, 20xxxx=Sonnensensor, 80xxxx=Zentraleinheit, 90xxxx=Empfänger
* groupNumber  - Gruppennummer einer Zentralheinheit: Zahl wischen 0 und 7.  0 steht für alle Gruppen.
* memberNumber - Empfängernummer in einer Gruppe: 0-7. 0 für alle Empfänger.


Verschiedene Methoden der Adressierung
--------------------------------------

1) Die IDs vorhandener Sende-Geräte einscannen und dann benutzen. Beispiel: Die ID der 2411 benutzen um dann über Gruppen und Empfängernummern die Rolläden anzusprechen.

2) Ausgedachte IDs mit Motoren zu koppeln.  Beispiel: Rolladen Nr 1 mit 100001, Nr 2 mit 100002, ...

3) Empfänger IDs: Funkmotoren haben 5 stellige "Funk-Codes" aufgedruckt, eigentlich gedacht zur Inbetriebnahme. Es muss eine 9 davorgestellt werden um die ID zu erhalten.


Gruppenbildung:

zu 1) Gruppen und Empfäger entsprechen der 2411. Gruppenbildung durch die 0 als Joker.  (g=1 m=0 oder g=0 m=1) 

zu 2) Wie bei realen Handsendern. Beispiel: Ein (virtueller) Handsender wird bei allen Motoren einer Etage angemeldet.

zu 3) nicht möglich


Kommandos
---------

* up - öffnen
* down - schließen
* stop - anhalten
* set  - Setzfunktion aktivieren
* sun-down - Herunterfahren bis Sonnenposition (nur bei aktiverter Sonnenautomatik)
* sun-inst - aktuelle Position als Sonnenposition speichern


Beispiele
---------

### nach Methode 1)

* ID der vorhandenen 2411 scannen:

           Shell-Kommando: perl fhemft.pl --scan -n=sduino -v=4 
             -- jetzt den STOP Knopf der 2411 festhalten ---
           Shell-Ausgabe: id=80abcd,  ....  (ID notieren)

* Eingaben im FHEM Webinterface 

          Kommando-Feld: define Rolladen_11 Fernotron    (Enter)
          attr Feld: controllerId: 80abcd    (Enter)
		  attr Feld: groupNumber: 1   (Enter)
		  attr Feld: memberNumber: 1  (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
          ...
		  
          Kommando-Feld: define Rolladen_42 Fernotron    (Enter)
          attr Feld: controllerId: 80abcd    (Enter)
		  attr Feld: groupNumber: 4   (Enter)
		  attr Feld: memberNumber: 2  (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  ...
		  
          Kommando-Feld: define Rolladen_Alle Fernotron    (Enter)
          attr Feld: controllerId: 80abcd    (Enter)
		  attr Feld: groupNumber: 0   (Enter)
		  attr Feld: memberNumber: 0  (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  

### nach Methode 2)

* Eingaben im FHEM Webinterface 

          Kommando-Feld: define Rolladen_Bad  Fernotron    (Enter)
          attr Feld: controllerId: 100001    (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config

          Rolladen im Bad in den Setzmodus versetzen (Set-Knopf oder 2411 Set-Funktion)
		  
		  stop anklicken zum koppeln (Motor quittiert durch anlaufen)
		  
		  up oder down anklicken. Motor sollte reagieren.
		  
		  Kommando-Feld: define Rolladen_Kueche  Fernotron    (Enter)
          attr Feld: controllerId: 100002    (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  ...
		  
		  
		  
### nach Methode 3)

          Motorcode herausfinden. Steht auf Kabel-Sticker und direkt auf dem Motor (wenn ausgebaut).
		  Beispiel: Code 0D1234 aufgedruckt

* Eingaben im FHEM Webinterface 

          Kommando-Feld: define Rolladen_Bad  Fernotron    (Enter)
          attr Feld: controllerId: 90D1234    (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  Motor reagiert nun auf down/stop/up/set 
		  

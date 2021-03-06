FHEM Modul Fernotron - Benutzung
================================

!! Eine aktuellere Dokumentation befindet sich in der automatisch erzeugten Datei [doc/sduino_fernotron_de](sduino_fernotron_de.pod) !!

Grundlagen
----------

Original-Fernotron-Geräte habe eine ID-Nummer ab Werk fest einprogrammiert. Empfänger und Sender werden gekoppelt, indem sich der Empfänger die ID des Senders merkt (bzw. diese "lernt"). Jeder Empfänger kann sich je eine ID einer Zentraleinheit (inklusive Gruppe und Empfängernummer), eines Sonnensensors und mehrerer Handsender merken.

Gerät definieren
----------------

Ein Gerät kann einen einzige Rolladen aber  auch eine ganze Gruppe ansprechen.  Dies wird durch die verwendete ID und Gruppen und Empfängernummer bestimmt.

            define <MeinRolladen> Fernotron a=ID [g=GN] [m=MN]
			
		
			ID : Die Geräte ID. Eine  sechstellige hexadezimale Zahl.  10xxxx=Handsender, 20xxxx=Sonnensensor, 80xxxx=Zentraleinheit, 90xxxx=Empfänger
			GN : Gruppennummer (1-7) oder 0 (default) für alle Gruppen
			MN : Empfängernummer (1-) oder 0 (default) für alle Empfänger
			
'g' und 'm' sind nur sinnvoll, wenn als ID eine Zentraleinheit angegeben wurde 


Verschiedene Methoden der Adressierung
--------------------------------------

1) Virtuelle Controller mit IDs vorhandener Sende-Geräte. Bietet sich an um die Zentrale (2411) zu simulieren und die vorhandenen Gruppen und Empfängernummern zu nutzen. Es muss nur die ID der Zentrale eingescannt oder vom Etikett im Batteriefach abgelesen werden.  Scannen mit (define scanFerno Fernotron scan) und dann unter Internals.receive_HR die ID (a=xxxxxx) ablesen. (Scannen ist unzuverlässig, da das SIGNALduino das Checksum-Byte meistens nicht mit empfängt. Also mehrfach probieren)

2) Virtuelle Controller anlegen. Die ID denkt man sich selber aus. Bietet sich an um virtuelle einfach Handsender (2431) zu erzeugen (ID: 10xxxx) um diese dann mit je einem Motoren zu koppeln. Ist wohl die technisch sauberste Lösung. Man hat dann keine virtuellen Doubles vorhandener Geräte, sondern Geräte die einem zugekauftem Controller entsprechen.

3) Messages direkt an den Empfäger addressieren. Funkmotoren haben 5 stellige "Funk-Codes" aufgedruckt. Es muss eine 9 davorgestellt werden um die ID zu erhalten. Eine Zweckentfremdung dieser IDs, die eigentlich für die Inbetriebnahme gedacht sind.


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
* sun-down - Herunterfahren bis Sonnenposition (nur bei aktivierter Sonnenautomatik)
* sun-up - fährt wieder hoch nach sun-down
* sun-inst - aktuelle Position als Sonnenposition speichern


Attribute
---------
* repeats 0..5 - Wiederhohltes Senden des Kommandos für sicheren Empfang. 0 sendet nur 1 mal. 1 sendet doppelt, etc. (Default: 1)



Beispiele
---------

### nach Methode 1)

* ID der vorhandenen 2411 scannen:

           define scanFerno Fernotron scan
             -- STOP Knopf der 2411 festhalten ---
		   ID erscheint nach Browser refresh beim Gerät scanFerno unter Internals.receive_HR 

* Eingaben im FHEM Webinterface 
 
          Kommando-Feld: define Rolladen_11 Fernotron a=80abcd g=1 m=1  (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
          ...
		  
          Kommando-Feld: define Rolladen_42 Fernotron a=80abcd g=4 m=2  (Enter)
  		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  ...
		  
          Kommando-Feld: define Rolladen_Alle Fernotron  a=80abcd  (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  

### nach Methode 2)

* Eingaben im FHEM Webinterface 

          Kommando-Feld: define Rolladen_Bad a=100001 Fernotron    (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config

          Rolladen im Bad in den Setzmodus versetzen (Set-Knopf oder 2411 Set-Funktion)
		  
		  stop anklicken zum koppeln (Motor quittiert durch anlaufen)
		  
		  up oder down anklicken. Motor sollte reagieren.
		  
		  Kommando-Feld: define Rolladen_Kueche  Fernotron a=100002   (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  ...
		  
		  
		  
### nach Methode 3)

          Motorcode herausfinden. Steht auf Kabel-Sticker und direkt auf dem Motor (wenn ausgebaut).
		  Beispiel: Code 0D123 aufgedruckt

* Eingaben im FHEM Webinterface 

          Kommando-Feld: define Rolladen_Bad  Fernotron a=90D123   (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  Motor reagiert nun auf down/stop/up/set 
		  

FHEM Modul Fernotron - Benutzung
================================


Modul installieren
------------------

* Das Modul 10_Fernotron.pm muss in den FEM Modul-Ordner (/opt/fhem/FHEM/) kopiert werden.

* Ein Gerät vom Typ SIGNALduino muss definiert sein und natürlich die SIGNALduino Hardware angeschlossen sein.

* Fernotron zur Liste der Klienten des SIGNALduino Geräts hinzufügen. Angenommen das Gerät heißt 'sduino'. Das Gerät im Webinterface öffnen und den Wert unter Internals.Clients kopieren.

  Unter attr.Clients eingeben:  :Fernotron   und dahinter den kopierten Wert pasten.  Das sieht dann in etwa so aus:

             :Fernotron:IT:CUL_TCM97001:SD_RSL:OREGON:CUL_TX:SD_AS:Hideki:SD_WS07:SD_WS09: :SD_WS:RFXX10REC:Dooya:SOMFY:SD_UT:SD_WS_Maverick:FLAMINGO:CUL_WS:Revolt: :FS10:CUL_FHTTK:Siro:FHT:FS20:SIGNALduino_un:
			 
nun attr drücken oder Enter Taste.


* Alternativ kann man das ganze als Kommando zu fhem.cfg hinzufügen (dort direkt unter "define sduino"):

             attr sduino Clients :Fernotron:IT:CUL_TCM97001:SD_RSL:OREGON:CUL_TX:SD_AS:Hideki:SD_WS07:SD_WS09: :SD_WS:RFXX10REC:Dooya:SOMFY:SD_UT:SD_WS_Maverick:FLAMINGO:CUL_WS:Revolt: :FS10:CUL_FHTTK:Siro:FHT:FS20:SIGNALduino_un:
			 
			 
Hinterher den Befehl rereadcfg ausführen.



Grundlagen
----------

Jedes Gerät hat eine ID-Nummer ab Werk fest einprogrammiert. Empfänger und Sender werden gekoppelt, indem sich der Empfänger die ID des Senders merkt. Jeder Empfänger kann sich je eine ID einer Zentraleinheit (inklusive Gruppe und Empfängernummer), eines Sonnensensors und mehrerer Handsender merken.

Gerät definieren
----------------

Ein Gerät kann einen einzige Rolladen aber  auch eine ganze Gruppe ansprechen.  Dies wird durch die verwendete ID und Gruppen und Empfängernummer bestimmt.

            define <MeinRolladen> Fernotron a=ID [g=GN] [m=MN]
			
		
			ID : Die Geräte ID. Eine  sechstellige hexadezimale Zahl.  10xxxx=Handsender, 20xxxx=Sonnensensor, 80xxxx=Zentraleinheit, 90xxxx=Empfänger
			GN : Gruppennummer (1-7) oder 0 (default) für alle Gruppen
			MN : Empfängernummer (1-) oder 0 (default) für alle Empfänger
			
'g' und 'n' sind nur sinnvoll, wenn als ID eine Zentraleinheit angegeben wurde 


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
		  Beispiel: Code 0D1234 aufgedruckt

* Eingaben im FHEM Webinterface 

          Kommando-Feld: define Rolladen_Bad  Fernotron a=90D1234   (Enter)
		  attr Feld: webCmd: down:stop:up  (Enter)
		  Save config
		  
		  Motor reagiert nun auf down/stop/up/set 
		  

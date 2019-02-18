#!/bin/sh

(cd modules/sduino && perl ../../mk_ctrl_fernotron.pl > control.txt)
(cd modules/sduino-stable && perl ../../mk_ctrl_fernotron.pl > control.txt)
(cd modules/tronferno && perl ../../mk_ctrl_tronferno.pl > control.txt)

    

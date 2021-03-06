#!/bin/sh

(cd modules/sduino && perl ../../mk_ctrl_fernotron.pl > controls_fernotron.txt)
(cd modules/tronferno && perl ../../mk_ctrl_tronferno.pl > controls_tronferno.txt)


false || (
debug=-nopoderrors

(echo "=begin html" && sed '/^=begin html$/,/^=end html$/!d;//d' < modules/sduino/FHEM/10_Fernotron.pm && echo "=end html") | pod2html $debug > doc/sduino_fernotron_pod.html
(echo "=begin html" && sed '/^=begin html_DE$/,/^=end html_DE$/!d;//d' < modules/sduino/FHEM/10_Fernotron.pm && echo "=end html") | pod2html $debug > doc/sduino_fernotron_pod_de.html
(echo "=begin html" && sed '/^=begin html$/,/^=end html$/!d;//d' < modules/tronferno/FHEM/10_Tronferno.pm && echo "=end html") | pod2html $debug > doc/tronferno_pod.html
(echo "=begin html" && sed '/^=begin html_DE$/,/^=end html_DE$/!d;//d' < modules/tronferno/FHEM/10_Tronferno.pm && echo "=end html") | pod2html $debug > doc/tronferno_pod_de.html
(echo "=begin html" && sed '/^=begin html$/,/^=end html$/!d;//d' < modules/tronferno/FHEM/00_TronfernoMCU.pm && echo "=end html") | pod2html $debug > doc/tronferno_mcu_pod.html
(echo "=begin html" && sed '/^=begin html_DE$/,/^=end html_DE$/!d;//d' < modules/tronferno/FHEM/00_TronfernoMCU.pm && echo "=end html") | pod2html $debug > doc/tronferno_mcu_pod_de.html
)


(echo "=begin html" && sed '/^=begin html$/,/^=end html$/!d;//d' < modules/sduino/FHEM/10_Fernotron.pm && echo "=end html") > doc/sduino_fernotron.pod
(echo "=encoding UTF-8\n" && echo "=begin html" && sed '/^=begin html_DE$/,/^=end html_DE$/!d;//d' < modules/sduino/FHEM/10_Fernotron.pm && echo "=end html") > doc/sduino_fernotron_de.pod
(echo "=begin html" && sed '/^=begin html$/,/^=end html$/!d;//d' < modules/tronferno/FHEM/10_Tronferno.pm && echo "=end html") > doc/tronferno.pod
(echo "=encoding UTF-8\n" && echo "=begin html" && sed '/^=begin html_DE$/,/^=end html_DE$/!d;//d' < modules/tronferno/FHEM/10_Tronferno.pm && echo "=end html") > doc/tronferno_de.pod
(echo "=begin html" && sed '/^=begin html$/,/^=end html$/!d;//d' < modules/tronferno/FHEM/00_TronfernoMCU.pm && echo "=end html") > doc/tronferno_mcu.pod
(echo "=encoding UTF-8\n" && echo "=begin html" && sed '/^=begin html_DE$/,/^=end html_DE$/!d;//d' < modules/tronferno/FHEM/00_TronfernoMCU.pm && echo "=end html") > doc/tronferno_mcu_de.pod

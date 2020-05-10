.PHONY: 00_TronfernoMCU.compile 10_Tronferno.compile 10_Fernotron.compile
00_TronfernoMCU.compile: modules/tronferno/FHEM/00_TronfernoMCU.compile
10_Tronferno.compile: modules/tronferno/FHEM/10_Tronferno.compile
10_Fernotron.compile: modules/sduino/FHEM/10_Fernotron.compile

.PHONY: 00_TronfernoMCU.critic 10_Tronferno.critic 10_Fernotron.critic
00_TronfernoMCU.critic: modules/tronferno/FHEM/00_TronfernoMCU.critic
10_Tronferno.critic: modules/tronferno/FHEM/10_Tronferno.critic
10_Fernotron.critic: modules/sduino/FHEM/10_Fernotron.critic

.PHONY: controls

%.compile: %.pm
	perl -cw -MO=Lint $< 2>&1 | grep -v 'Undefined subroutine'
 
%.critic: %.pm
	perlcritic --verbose 7 $<

.PHONY: controls verify push not_dirty
controls:
	./build.sh
verify: ./build.sh 00_TronfernoMCU.compile 10_Tronferno.compile 10_Fernotron.compile
not_dirty:
	git update-index --refresh && git diff-index --quiet HEAD --
push: verify not_dirty
	git push


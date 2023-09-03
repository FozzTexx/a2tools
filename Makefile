SUBDIRS = src 

stp_disk_PROGS = src/a2recv/a2recv.bin \
				src/a2send/a2send.bin \
				src/stp/stp.bin
telnet_disk_PROGS = src/a2recv/a2recv.bin \
				src/a2send/a2send.bin \
				src/telnet/telnet.bin

homectrl_disk_PROGS = src/a2recv/a2recv.bin \
				src/homecontrol-client/homectrl.bin \
				src/homecontrol-client/grphview.bin \

mastodon_disk_PROGS = src/mastodon/mastodon.bin \
				src/mastodon/mastocli.bin \
				src/mastodon/mastowrite.bin \
				src/mastodon/mastoconf.bin

CLEANDISK = disks/basic-empty.dsk

.PHONY: all clean

all clean upload:
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir -f Makefile $@ || exit; \
	done

stp.dsk: $(stp_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ STP
	java -jar bin/ac.jar -p $@ STP.SYSTEM SYS < bin/loader.system; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

stpperso.dsk: $(stp_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ STP
	java -jar bin/ac.jar -p $@ STP.SYSTEM SYS < bin/loader.system; \
	java -jar bin/ac.jar -p $@ STPSTARTURL TXT < src/stp/STPSTARTURL; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

telnet.dsk: $(telnet_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ TELNET
	java -jar bin/ac.jar -p $@ TELNET.SYSTEM SYS < bin/loader.system; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

homectrl.dsk: $(homectrl_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ HOMECONTROL
	java -jar bin/ac.jar -p $@ HOMECTRL.SYSTEM SYS < bin/loader.system; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

homectrlperso.dsk: $(homectrl_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ HOMECONTROL
	java -jar bin/ac.jar -p $@ HOMECTRL.SYSTEM SYS < bin/loader.system; \
	java -jar bin/ac.jar -p $@ SRVURL TXT < src/homecontrol-client/SRVURL; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

mastoperso.dsk: $(mastodon_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ MASTODON
	java -jar bin/ac.jar -p $@ MASTODON.SYSTEM SYS < bin/loader.system; \
	java -jar bin/ac.jar -p $@ mastsettings TXT < src/mastodon/mastsettings; \
	java -jar bin/ac.jar -p $@ clisettings TXT < src/mastodon/clisettings; \
	java -jar bin/ac.jar -d $@ BASIC; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

mastodon.dsk: $(mastodon_disk_PROGS)
	cp $(CLEANDISK) $@; \
	java -jar bin/ac.jar -n $@ MASTODON
	java -jar bin/ac.jar -p $@ MASTODON.SYSTEM SYS < bin/loader.system; \
	java -jar bin/ac.jar -d $@ BASIC; \
	for prog in $^; do \
		java -jar bin/ac.jar -as $@ $$(basename $$prog | sed "s/\.bin$///") < $$prog; \
	done
	cp $@ ~/Documents/ADTPro-2.1.0/disks/; \
	cp $@ dist/; \

dist: clean all stp.dsk telnet.dsk homectrl.dsk mastodon.dsk mastoperso.dsk homectrlperso.dsk stpperso.dsk

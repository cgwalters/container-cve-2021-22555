all: 50-worker-more-restricted-seccomp.mc.yaml exploit-cve-2021-22555

exploit-cve-2021-22555: exploit.c
	gcc -m32 -Wall -o $@ $<

%.mc.yaml: %.bu.yaml
	butane --files-dir . < $< > $@.tmp && mv $@.tmp $@
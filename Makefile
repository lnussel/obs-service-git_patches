prefix=/usr
servicedir=$(prefix)/lib/obs/service

all:

install:
	mkdir -p $(DESTDIR)$(servicedir)
	install -m 755 git_patches $(DESTDIR)$(servicedir)
	install -m 644 git_patches.service $(DESTDIR)$(servicedir)
	install -m 755 update_git.sh $(DESTDIR)$(servicedir)

.PHONY: all install

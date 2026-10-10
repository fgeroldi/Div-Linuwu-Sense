obj-m := src/linuwu_sense.o

KVER  ?= $(shell uname -r)
KDIR  := /lib/modules/$(KVER)/build
PWD   := $(shell pwd)

MDIR  := /lib/modules/$(KVER)/kernel/drivers/platform/x86
MODNAME := linuwu_sense
REAL_USER := $(shell echo $${SUDO_USER:-$$(whoami)})
VERSION ?= 1.0
RELEASE ?= 2
RPMBUILD_DIR ?= $(PWD)/rpmbuild

MODNAME_HYPHEN := $(subst _,-,$(MODNAME))
DEB_BUILD_DIR ?= $(PWD)/debbuild
DEB_PKG_NAME  ?= $(MODNAME_HYPHEN)-dkms
DEB_VERSION   ?= $(VERSION)-$(RELEASE)
DEB_ARCH      ?= all
DEB_FILE      ?= $(DEB_BUILD_DIR)/$(DEB_PKG_NAME)_$(DEB_VERSION)_$(DEB_ARCH).deb

.PHONY: all clean clean-rpm clean-deb tarball srpm akmod kmod deb install uninstall install-akmod install-deb

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	@rm -f src/$(MODNAME).ko

clean-rpm:
	rm -rf $(RPMBUILD_DIR) *.tar.gz *.rpm

clean-deb:
	rm -rf $(DEB_BUILD_DIR) *.deb

tarball:
	@mkdir -p $(RPMBUILD_DIR)/SOURCES
	@rm -rf $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)
	@mkdir -p $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)/src
	@cp -a Makefile Kbuild LICENSE README.md dkms.conf linuwu_sense.service $(MODNAME).spec $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)/
	@cp -a $(MODNAME)-tmpfiles.conf $(MODNAME)-modules-load.conf $(MODNAME)-modprobe-blacklist.conf $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)/
	@cp -a src/linuwu_sense.c $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)/src/
	@tar -czf $(RPMBUILD_DIR)/SOURCES/$(MODNAME)-$(VERSION).tar.gz -C $(RPMBUILD_DIR) $(MODNAME)-$(VERSION)
	@rm -rf $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)
	@cp -a $(MODNAME)-tmpfiles.conf $(MODNAME)-modules-load.conf $(MODNAME)-modprobe-blacklist.conf $(RPMBUILD_DIR)/SOURCES/

srpm: tarball
	@mkdir -p $(RPMBUILD_DIR)/{SPECS,SRPMS,RPMS,BUILD,BUILDROOT,tmp}
	@echo "%_topdir $(RPMBUILD_DIR)" > $(PWD)/.rpmmacros
	@echo "%_tmppath $(RPMBUILD_DIR)/tmp" >> $(PWD)/.rpmmacros
	@cp -a $(MODNAME).spec $(RPMBUILD_DIR)/SPECS/
	HOME=$(PWD) rpmbuild --define "buildforkernels akmod" -bs $(RPMBUILD_DIR)/SPECS/$(MODNAME).spec
	@echo "SRPM created at $(RPMBUILD_DIR)/SRPMS/"

akmod: srpm
	HOME=$(PWD) rpmbuild --define "buildforkernels akmod" -ba $(RPMBUILD_DIR)/SPECS/$(MODNAME).spec
	@echo "Akmod and Common RPMs created at $(RPMBUILD_DIR)/RPMS/"

kmod: srpm
	HOME=$(PWD) rpmbuild --define "kernels $(KVER)" -ba $(RPMBUILD_DIR)/SPECS/$(MODNAME).spec
	@echo "Kmod RPM for $(KVER) created at $(RPMBUILD_DIR)/RPMS/"

install-akmod: akmod
	@echo "Installing akmod package..."
	sudo dnf install -y --allowerasing $(RPMBUILD_DIR)/RPMS/noarch/$(MODNAME)-common-*.rpm $(RPMBUILD_DIR)/RPMS/x86_64/akmod-$(MODNAME)-*.rpm || \
	sudo dnf reinstall -y $(RPMBUILD_DIR)/RPMS/noarch/$(MODNAME)-common-*.rpm $(RPMBUILD_DIR)/RPMS/x86_64/akmod-$(MODNAME)-*.rpm
	@echo "Building module with akmods..."
	sudo akmods --force
	@echo "Reloading module..."
	sudo modprobe -r $(MODNAME) 2>/dev/null || true
	sudo modprobe $(MODNAME)

deb: clean-deb
	@echo "Creating Debian package layout in $(DEB_BUILD_DIR)..."
	@mkdir -p $(DEB_BUILD_DIR)/pkg/DEBIAN
	@mkdir -p $(DEB_BUILD_DIR)/pkg/usr/src/$(MODNAME_HYPHEN)-$(VERSION)/src
	@mkdir -p $(DEB_BUILD_DIR)/pkg/usr/lib/tmpfiles.d
	@mkdir -p $(DEB_BUILD_DIR)/pkg/etc/modules-load.d
	@mkdir -p $(DEB_BUILD_DIR)/pkg/etc/modprobe.d
	@mkdir -p $(DEB_BUILD_DIR)/pkg/usr/lib/systemd/system
	@mkdir -p $(DEB_BUILD_DIR)/pkg/usr/share/doc/$(DEB_PKG_NAME)
	@cp -a src/linuwu_sense.c $(DEB_BUILD_DIR)/pkg/usr/src/$(MODNAME_HYPHEN)-$(VERSION)/src/
	@cp -a Kbuild $(DEB_BUILD_DIR)/pkg/usr/src/$(MODNAME_HYPHEN)-$(VERSION)/
	@printf "obj-m := src/$(MODNAME).o\n\nKVER ?= \$$(shell uname -r)\nKDIR ?= /lib/modules/\$$(KVER)/build\nPWD  ?= \$$(shell pwd)\n\nall:\n\t\$$(MAKE) -C \$$(KDIR) M=\$$(PWD) modules\n\nclean:\n\t\$$(MAKE) -C \$$(KDIR) M=\$$(PWD) clean\n\t@rm -f src/$(MODNAME).ko\n" > $(DEB_BUILD_DIR)/pkg/usr/src/$(MODNAME_HYPHEN)-$(VERSION)/Makefile
	@sed 's/^PACKAGE_VERSION=.*/PACKAGE_VERSION="$(VERSION)"/' dkms.conf > $(DEB_BUILD_DIR)/pkg/usr/src/$(MODNAME_HYPHEN)-$(VERSION)/dkms.conf
	@cp -a $(MODNAME)-tmpfiles.conf $(DEB_BUILD_DIR)/pkg/usr/lib/tmpfiles.d/$(MODNAME).conf
	@cp -a $(MODNAME)-modules-load.conf $(DEB_BUILD_DIR)/pkg/etc/modules-load.d/$(MODNAME).conf
	@cp -a $(MODNAME)-modprobe-blacklist.conf $(DEB_BUILD_DIR)/pkg/etc/modprobe.d/$(MODNAME)-blacklist.conf
	@cp -a $(MODNAME).service $(DEB_BUILD_DIR)/pkg/usr/lib/systemd/system/$(MODNAME).service
	@cp -a README.md $(DEB_BUILD_DIR)/pkg/usr/share/doc/$(DEB_PKG_NAME)/
	@cp -a LICENSE $(DEB_BUILD_DIR)/pkg/usr/share/doc/$(DEB_PKG_NAME)/copyright
	@gzip -9 -n -c debian/changelog > $(DEB_BUILD_DIR)/pkg/usr/share/doc/$(DEB_PKG_NAME)/changelog.Debian.gz
	@cp -a debian/$(DEB_PKG_NAME).postinst $(DEB_BUILD_DIR)/pkg/DEBIAN/postinst
	@cp -a debian/$(DEB_PKG_NAME).prerm $(DEB_BUILD_DIR)/pkg/DEBIAN/prerm
	@cp -a debian/$(DEB_PKG_NAME).postrm $(DEB_BUILD_DIR)/pkg/DEBIAN/postrm
	@find $(DEB_BUILD_DIR)/pkg -type d -exec chmod 755 {} +
	@find $(DEB_BUILD_DIR)/pkg -type f -exec chmod 644 {} +
	@chmod 755 $(DEB_BUILD_DIR)/pkg/DEBIAN/postinst $(DEB_BUILD_DIR)/pkg/DEBIAN/prerm $(DEB_BUILD_DIR)/pkg/DEBIAN/postrm
	@printf "Package: $(DEB_PKG_NAME)\nVersion: $(DEB_VERSION)\nSection: kernel\nPriority: optional\nArchitecture: $(DEB_ARCH)\nDepends: dkms (>= 2.1.0.0), udev\nRecommends: linux-headers-generic | linux-headers\nProvides: $(MODNAME), $(MODNAME_HYPHEN), $(MODNAME)-dkms\nMaintainer: Felipe Geroldi <142124821+fgeroldi@users.noreply.github.com>\nHomepage: https://github.com/fgeroldi/Div-Linuwu-Sense\nDescription: Acer RGB Keyboard Backlight and Turbo Mode kernel module (DKMS)\n Unofficial Linux Kernel Module for Acer Gaming RGB Keyboard Backlight\n and Turbo Mode (Acer Predator / Nitro).\n .\n This package provides the source code for the $(MODNAME) kernel module\n configured to be built automatically with DKMS on kernel updates.\n" > $(DEB_BUILD_DIR)/pkg/DEBIAN/control
	@printf "/etc/modules-load.d/$(MODNAME).conf\n/etc/modprobe.d/$(MODNAME)-blacklist.conf\n" > $(DEB_BUILD_DIR)/pkg/DEBIAN/conffiles
	@chmod 644 $(DEB_BUILD_DIR)/pkg/DEBIAN/control $(DEB_BUILD_DIR)/pkg/DEBIAN/conffiles
	@echo "Building Debian package with dpkg-deb..."
	dpkg-deb --root-owner-group --build $(DEB_BUILD_DIR)/pkg $(DEB_FILE)
	@echo "Debian package created at $(DEB_FILE)"

install-deb: deb
	@echo "Installing deb package..."
	sudo apt install -y $(DEB_FILE) || sudo dpkg -i $(DEB_FILE)

uninstall:
	@sudo rm -f /etc/modules-load.d/$(MODNAME).conf
	@sudo rm -f /etc/modprobe.d/blacklist-acer_wmi.conf
	@sudo systemctl stop linuwu_sense.service
	@sudo systemctl disable linuwu_sense.service
	@sudo rm -f /etc/systemd/system/linuwu_sense.service
	@sudo systemctl daemon-reload
	@sudo rmmod $(MODNAME) 2>/dev/null || true
	@sudo modprobe acer_wmi
	@echo "Removing current user from linuwu_sense group if exists..."
	@if getent group linuwu_sense >/dev/null; then \
		sudo gpasswd -d $(REAL_USER) linuwu_sense || true; \
		sudo groupdel linuwu_sense || true; \
	else \
		echo "Group linuwu_sense does not exist."; \
	fi
	@sudo rm -f /etc/tmpfiles.d/$(MODNAME).conf
	@sudo rm -f $(MDIR)/$(MODNAME).ko
	@sudo depmod -a
	@echo "Uninstalled $(MODNAME) and cleaned up related configuration."

install: all
	@sudo rmmod acer_wmi 2>/dev/null || true
	@echo "blacklist acer_wmi" | sudo tee /etc/modprobe.d/blacklist-acer_wmi.conf > /dev/null
	sudo install -d $(MDIR)
	sudo install -m 644 src/$(MODNAME).ko $(MDIR)
	sudo depmod -a
	@echo "$(MODNAME)" | sudo tee /etc/modules-load.d/$(MODNAME).conf > /dev/null
	sudo modprobe $(MODNAME)
	@sudo cp linuwu_sense.service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable linuwu_sense.service
	@sudo systemctl start linuwu_sense.service
	@echo "Setting up group and permissions..."
	@echo "Detected user: $(REAL_USER)"
	@if ! getent group linuwu_sense >/dev/null; then \
		sudo groupadd linuwu_sense; \
	fi; 
	sudo usermod -aG linuwu_sense $(REAL_USER)
	@echo "Setting permissions via tmpfiles..."
	@model_path=$$(ls /sys/module/$(MODNAME)/drivers/platform:acer-wmi/acer-wmi/ | grep -E 'predator_sense|nitro_sense' || true); \
	if [ -n "$$model_path" ]; then \
		echo "Detected model directory: $$model_path"; \
		conf_file="/etc/tmpfiles.d/$(MODNAME).conf"; \
		[ -f $$conf_file ] || sudo touch $$conf_file; \
		if echo "$$model_path" | grep -q "nitro_sense"; then \
			supported_fields="fan_speed battery_limiter battery_calibration usb_charging"; \
		else \
			supported_fields="backlight_timeout battery_calibration battery_limiter boot_animation_sound fan_speed lcd_override usb_charging"; \
		fi; \
		for f in $$supported_fields; do \
			entry="f /sys/module/$(MODNAME)/drivers/platform:acer-wmi/acer-wmi/$$model_path/$$f 0660 root $(MODNAME)"; \
			grep -qxF "$$entry" $$conf_file || echo "$$entry" | sudo tee -a $$conf_file > /dev/null; \
		done; \
		kb_base="/sys/module/$(MODNAME)/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb"; \
		if [ -d "$$kb_base" ]; then \
			for z in four_zone_mode per_zone_mode; do \
				entry="f $$kb_base/$$z 0660 root $(MODNAME)"; \
				grep -qxF "$$entry" $$conf_file || echo "$$entry" | sudo tee -a $$conf_file > /dev/null; \
			done; \
		fi; \
		sudo systemd-tmpfiles --create $$conf_file; \
	else \
		echo "Warning: Could not detect predator_sense or nitro_sense in sysfs."; \
	fi
	@echo "Module $(MODNAME) installed and configured to load at boot."

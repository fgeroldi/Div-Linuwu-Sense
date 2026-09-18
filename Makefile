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

.PHONY: all clean clean-rpm tarball srpm akmod kmod install uninstall install-akmod

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	@rm -f src/$(MODNAME).ko

clean-rpm:
	rm -rf $(RPMBUILD_DIR) *.tar.gz *.rpm

tarball:
	@mkdir -p $(RPMBUILD_DIR)/SOURCES
	@rm -rf $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)
	@mkdir -p $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)/src
	@cp -a Makefile LICENSE README.md linuwu_sense.service $(MODNAME).spec $(RPMBUILD_DIR)/$(MODNAME)-$(VERSION)/
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

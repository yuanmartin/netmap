# To build external modules, you must have a prebuilt kernel available
# that contains the configuration and header files used in the build.
# go in the kernel directory and do a
#       make oldconfig; make scripts; make prepare
# or    make defconfig; make scripts; make prepare
#

MODNAME:=netmap
SUBSYS:=generic monitor pipe vale
SRCDIR:=/home/wangbojing/share/netmap/LINUX
BUILDDIR:=/home/wangbojing/share/netmap

# The following commands are needed to build the modules as out-of-tree,
# in fact the kernel sources path must be specified.

# Additional compile flags (e.g. header location)
EXTRA_CFLAGS := -I$(BUILDDIR) -I$(SRCDIR) -I$(SRCDIR)/../sys -I$(SRCDIR)/../sys/dev -DCONFIG_NETMAP
EXTRA_CFLAGS += -Wno-unused-but-set-variable
EXTRA_CFLAGS += $(foreach s,$(SUBSYS),-DCONFIG_NETMAP_$(shell echo $s|tr a-z- A-Z_))


# We use KSRC for the kernel configuration and sources.
# If the sources are elsewhere, then use SRC to point to them.
KSRC = /lib/modules/4.4.16/build
SRC  = /lib/modules/4.4.16/build
KOPTS = 
MODPATH = 
LIN_VER = 40410
MOD_LIST := CONFIG_VIRTIO_NET=m CONFIG_FORCEDETH=m CONFIG_VETH=m CONFIG_E1000=m 
PATCHES = 
S_DRIVERS = i40e ixgbevf ixgbe igb e1000e e1000 veth.c forcedeth.c virtio_net.c
E_DRIVERS = i40e ixgbevf ixgbe igb e1000e
DRVSUFFIX = 

ifeq (,$(DRVSUFFIX))
else
EXTRA_CFLAGS += -DNETMAP_DRIVER_SUFFIX=$(DRVSUFFIX)
endif

# actual drivers after copy and patch
DRIVERS = $(shell [ -n "$(S_DRIVERS)" ] && ls -dAp $(S_DRIVERS) 2> /dev/null)
# external drivers after copy and patch
DRIVERS_EXT = $(shell [ -n "$(E_DRIVERS)" ] && ls -dAp $(E_DRIVERS) 2> /dev/null)

COMMON_OPTS=-C $(KSRC) M=$(BUILDDIR) EXTRA_CFLAGS='$(EXTRA_CFLAGS)' $(KOPTS) modules

define common_driver
get-$(1):
	$($(1)@fetch)
	$($(1)@src)
	$(foreach p,$($(1)@patch),patch --posix --quiet --force -p1 < $(p);)
	$(if $($(1)@build),,$(if $(filter-out %.c,$(1)),mv $(1)/Makefile $(1)/orig.mak || mv $(1)/Kbuild $(1)/orig.mak; cp drv-subdir.mak $(1)/Makefile,))
	touch get-$(1)
distclean-$(1):
	-$($(1)@distclean)
	rm -rf $(1) get-$(1)
endef

define external_driver
build-$(1): get-$(1) netmap.ko
	if [ -d $(1) ] && [ -e Module.symvers ]; then cp Module.symvers $(1); fi
	+$($(1)@build)
clean-$(1):
	-$($(1)@clean)
install-$(1): install-netmap
	$($(1)@install)
endef

.PHONY: $(foreach d,$(E_DRIVERS),build-$(d) clean-$(1) install-$(1)) netmap.ko


all: $(S_DRIVERS:%=get-%) netmap.ko $(E_DRIVERS:%=build-%) apps

netmap.ko:
	$(MAKE) $(COMMON_OPTS) CONFIG_NETMAP=m $(MOD_LIST) O_DRIVERS="$(patsubst %.c,%.o,$(filter-out $(DRIVERS_EXT),$(DRIVERS)))" NETMAP_DRIVER_SUFFIX=$(DRVSUFFIX)

-include default-config.mak
-include config.mak
-include drivers.mak

$(foreach d,$(S_DRIVERS),$(eval $(call common_driver,$(d))))
$(foreach d,$(E_DRIVERS),$(eval $(call external_driver,$(d))))

.PHONY: install install-netmap install-apps install-headers install-docs
install: install-netmap $(E_DRIVERS:%=install-%) install-apps install-headers install-docs

install-netmap:
	$(MAKE) -C $(KSRC) M=$(BUILDDIR) CONFIG_NETMAP=m $(MOD_LIST) \
		O_DRIVERS="$(DRIVERS:%.c=%.o)" \
		$(KOPTS) \
		NETMAP_DRIVER_SUFFIX=$(DRVSUFFIX) \
		$(if $(MODPATH),INSTALL_MOD_PATH=$(MODPATH)) \
		modules_install

clean: $(E_DRIVERS:%=clean-%) clean-apps
	-@ $(MAKE) -C $(KSRC) M=$(BUILDDIR) clean 2> /dev/null

APPS_LIST=vale-ctl nmreplay tlem lb bridge pkt-gen
APPS_CC=cc
APPS_LD=ld
PREFIX=/usr/local
DESTDIR?=

APPS_BUILD=$(APPS_LIST:%=build-app-%)
APPS_INSTALL=$(APPS_LIST:%=install-app-%)

apps: $(APPS_BUILD)
install-apps: $(APPS_INSTALL)
clean-apps: $(APPS_LIST:%=clean-app-%)

.PHONY: apps $(APPS_BUILD) install-apps $(APPS_INSTALL)
define apps_actions
build-app-$(1):
	+$(MAKE) -C build-apps/$(1) SRCDIR=$(SRCDIR)/.. CC="$(APPS_CC)" LD="$(APPS_LD)"

install-app-$(1):
	$(MAKE) -C build-apps/$(1) install SRCDIR=$(SRCDIR)/.. DESTDIR="$(abspath $(DESTDIR))" PREFIX="$(PREFIX)"

clean-app-$(1):
	$(MAKE) -C build-apps/$(1) clean SRCDIR=$(SRCDIR)/..
endef
$(foreach a,$(APPS_LIST),$(eval $(call apps_actions,$(a))))

+%:
	@echo $($*)

INCLUDE_PREFIX := $(if $(filter-out /,$(PREFIX)),$(PREFIX),/usr)

install-headers:
	install -m 0644 -D $(SRCDIR)/../sys/net/netmap.h $(DESTDIR)/$(INCLUDE_PREFIX)/include/net/netmap.h
	install -m 0644 -D $(SRCDIR)/../sys/net/netmap_user.h $(DESTDIR)/$(INCLUDE_PREFIX)/include/net/netmap_user.h
	install -m 0644 -D $(SRCDIR)/../sys/net/netmap_virt.h $(DESTDIR)/$(INCLUDE_PREFIX)/include/net/netmap_virt.h

MAN_PREFIX := $(INCLUDE_PREFIX)

install-docs:
	install -D -m 644 $(SRCDIR)/../share/man/man4/netmap.4 $(DESTDIR)/$(MAN_PREFIX)/share/man/man4/netmap.4

distclean: clean $(S_DRIVERS:%=distclean-%)
	rm -f config.status config.log netmap_linux_config.h \
		patches drivers.mak Kbuild netmap.mak default-config.mak
	rm -rf netmap-tmpdir
	rm -f *.orig *.rej
	if [ -L GNUmakefile ]; then rm GNUmakefile; fi
	if [ -L drv-subdir.mak ]; then rm drv-subdir.mak; fi
	if [ -L read-vars.mak ]; then rm read-vars.mak; fi
	rm -rf build-apps
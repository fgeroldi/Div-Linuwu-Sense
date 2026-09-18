%{!?buildforkernels:%global buildforkernels akmod}
%global debug_package %{nil}

Name:           linuwu_sense
Version:        1.0
Release:        2%{?dist}
Summary:        Acer RGB Keyboard Backlight and Turbo Mode kernel module

License:        GPLv3
URL:            https://github.com/0x7375646F/Linuwu-Sense
Source0:        %{name}-%{version}.tar.gz
Source1:        %{name}-tmpfiles.conf
Source2:        %{name}-modules-load.conf
Source3:        %{name}-modprobe-blacklist.conf

BuildRequires:  kmodtool
BuildRequires:  systemd-rpm-macros

# Needed for building kmod
%global AkmodsBuildRequires %{_bindir}/kmodtool, elfutils-libelf-devel, gcc
BuildRequires:  %{AkmodsBuildRequires}

# Standard kernel-devel build requirement for local building
%{!?kernels:BuildRequires: gcc, elfutils-libelf-devel, kernel-devel}

# kmodtool macro expansion
%{expand:%(kmodtool --target %{_target_cpu} %{?repo:--repo %{repo}} --kmodname %{name} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null) }

%description
Unofficial Linux Kernel Module for Acer Gaming RGB Keyboard Backlight and Turbo Mode
(Acer Predator / Nitro).

%package -n %{name}-common
Summary:        Common files for %{name}
BuildArch:      noarch
Provides:       %{name}-kmod-common = %{version}
Requires:       systemd

%description -n %{name}-common
This package contains common files for %{name}, such as the systemd service,
tmpfiles configuration, modules-load configuration, and modprobe blacklist.

%prep
# Error out if there was something wrong with kmodtool
%{?kmodtool_check}

# Print kmodtool output for debugging purposes
kmodtool --target %{_target_cpu} %{?repo:--repo %{repo}} --kmodname %{name} %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null

%setup -q -c -T
tar -xzf %{SOURCE0}
mv %{name}-%{version} %{name}-%{version}-src

# Copy source directory for each kernel version to build
for kernel_version in %{?kernel_versions} ; do
    cp -a %{name}-%{version}-src _kmod_build_${kernel_version%%___*}
done

%build
for kernel_version in %{?kernel_versions}; do
    pushd _kmod_build_${kernel_version%%___*}
    make %{?_smp_mflags} -C ${kernel_version##*___} M=`pwd` modules
    popd
done

%install
rm -rf %{buildroot}

# Install kernel modules
for kernel_version in %{?kernel_versions}; do
    pushd _kmod_build_${kernel_version%%___*}
    mkdir -p %{buildroot}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}
    install -m 0755 src/*.ko %{buildroot}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}
    chmod 0755 %{buildroot}%{kmodinstdir_prefix}${kernel_version%%___*}%{kmodinstdir_postfix}/*.ko
    popd
done

%{?akmod_install}

# Install userland / common configuration files
install -D -m 0644 %{SOURCE1} %{buildroot}%{_tmpfilesdir}/%{name}.conf
install -D -m 0644 %{SOURCE2} %{buildroot}%{_modulesloaddir}/%{name}.conf
install -D -m 0644 %{SOURCE3} %{buildroot}%{_modprobedir}/%{name}-blacklist.conf
install -D -m 0644 %{name}-%{version}-src/linuwu_sense.service %{buildroot}%{_unitdir}/%{name}.service

%pre -n %{name}-common
getent group linuwu_sense >/dev/null || groupadd -r linuwu_sense

%post -n %{name}-common
%systemd_post %{name}.service
%tmpfiles_create_package %{name} %{SOURCE1}

%preun -n %{name}-common
%systemd_preun %{name}.service

%postun -n %{name}-common
%systemd_postun_with_restart %{name}.service

%files -n %{name}-common
%license %{name}-%{version}-src/LICENSE
%doc %{name}-%{version}-src/README.md
%{_tmpfilesdir}/%{name}.conf
%{_modulesloaddir}/%{name}.conf
%{_modprobedir}/%{name}-blacklist.conf
%{_unitdir}/%{name}.service

%changelog
* Fri Sep 18 2026 Felipe Geroldi <142124821+fgeroldi@users.noreply.github.com> - 1.0-2
- Fix compatibility with kernel 7.2+ and add ANV16-41 quirk

* Fri Sep 18 2026 Felipe Geroldi <142124821+fgeroldi@users.noreply.github.com> - 1.0-1
- Akmod packaging for linuwu_sense with kernel 7.2+ compatibility

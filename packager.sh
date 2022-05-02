#!/usr/bin/bash

# This scripts creates and build a simple RPM package
#
# Prerequisites:
#  - rpm-build, make and gcc (as it's a c file) packages must be installed
#

# Ref. http://aerostitch.github.io/linux_and_unix/RedHat/build_sample_rpm.html

# Holds the name of the root directory containing the necessary structure to
# build RPM packages.
RPM_ROOT_DIR=~/rpm_factory

PKG_NAME=dummy_package
PKG_TAR=/tmp/${PKG_NAME}.tar.gz
BINARY_FILE=hello_world
# Recreate the root directory and its structure if necessary
mkdir -p ${RPM_ROOT_DIR}/{SOURCES,BUILD,RPMS,SPECS,SRPMS,tmp}
pushd  $RPM_ROOT_DIR
cp ${PKG_TAR} ${RPM_ROOT_DIR}/SOURCES/

# Creating a basic spec file
cat << __EOF__ > ${RPM_ROOT_DIR}/SPECS/${PKG_NAME}.spec
Summary: This package is a sample for quickly build dummy RPM package.
Name: $PKG_NAME
Version: 1.0
Release: 0
License: GPL
Packager: $USER
Group: Development/Tools
Source: %{name}.tar.gz
BuildRequires: coreutils
BuildRoot: ${RPM_ROOT_DIR}/tmp/%{name}-%{version}

%description
%{summary}

%prep
%setup -n ${PKG_NAME}

%build
make $BINARY_FILE

%install
mkdir -p "%{buildroot}/opt/${PKG_NAME}"
cp $BINARY_FILE "%{buildroot}/opt/${PKG_NAME}/"

%files
/opt/${PKG_NAME}/hello_world

%clean
%if "%{clean}" != ""
  rm -rf %{_topdir}/BUILD/%{name}
  [ $(basename %{buildroot}) == "%{name}-%{version}-%{release}.%{_target_cpu}" ] && rm -rf %{buildroot}
%endif

%post
chmod 755 -R /opt/${PKG_NAME}
__EOF__

rpmbuild -v -bb --define "_topdir ${RPM_ROOT_DIR}" SPECS/${PKG_NAME}.spec
popd



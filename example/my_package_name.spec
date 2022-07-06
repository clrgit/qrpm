
Name: my_package_name
Summary: This is a summary of the package
Version: 1.2.3
Release: 4
License: GPL
Packager: clr
Requires: ruby
Requires: httpd
Requires: postgresql13
Source: %{name}.tar.gz
BuildRoot: /tmp/d20220502-22446-8neiew/tmp/%{name}-%{version}

%description
Optional longer description of the package

%prep
%setup -n my_package_name

%build
my_configure; my_make

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/sbin %{buildroot}/usr/share/my_package_name %{buildroot}/var/lib
cp bin/a_file %{buildroot}/usr/bin/a_file
cp bin/another_file %{buildroot}/usr/bin/another_file
cp bin/a_file %{buildroot}/usr/bin/an_alias
cp share/some_data %{buildroot}/usr/share/my_package_name/some_data
cp share/some_other_data %{buildroot}/var/lib/some_other_data
touch %{buildroot}/usr/sbin/a_file

%files
/usr/bin/a_file
/usr/bin/another_file
/usr/bin/an_alias
/usr/share/my_package_name/some_data
/var/lib/some_other_data
%ghost /usr/sbin/a_file

%clean
%if "%{clean}" != ""
  rm -rf %{_topdir}/BUILD/%{name}
  [ $(basename %{buildroot}) == "%{name}-%{version}-%{release}.%{_target_cpu}" ] && rm -rf %{buildroot}
%endif

%post

ln -sf /bin/a_file /usr/sbin/a_file


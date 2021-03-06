#! /bin/bash

# PERL: https://www.perl.org/get.html
# SSL:  https://www.openssl.org/source/
# ZLIB: https://www.zlib.net/
: ${PERL_VERSION:=5.32.1}
: ${OPENSSL_VERSION:=1.1.1i}
: ${ZLIB_VERSION:=1.2.11}

: ${BUILDER_NAME="Guillaume Bougard (teclib)"}
: ${BUILDER_MAIL="gbougard_at_teclib.com"}

set -e

export LC_ALL=C LANG=C
export MACOSX_DEPLOYMENT_TARGET=10.10

# Check platform we are running on
ARCH=$(uname -m)
case "$(uname -s) $ARCH" in
    Darwin*x86_64)
        echo "GLPI-Agent MacOSX Packaging for $ARCH..."
        ;;
    Darwin*)
        echo "$ARCH support is missing, please report an issue" >&2
        exit 2
        ;;
    *)
        echo "This script can only be run under MacOSX system" >&2
        exit 1
        ;;
esac

ROOT="${0%/*}"
cd "$ROOT"
ROOT="`pwd`"

BUILD_PREFIX="/Applications/GLPI-Agent.app"

# We uses munkipkg script to simplify the process
# Thanks to https://github.com/munki/munki-pkg project
if [ ! -e munkipkg ]; then
    echo "Downloading munkipkg script..."
    curl -so munkipkg https://raw.githubusercontent.com/munki/munki-pkg/main/munkipkg
    if [ ! -e munkipkg ]; then
        echo "Failed to download munkipkg script" >&2
        exit 3
    fi
    chmod +x munkipkg
fi

# Needed folder
while [ -n "$1" ]
do
    case "$1" in
        clean)
            rm -rf build
            ;;
    esac
    shift
done
[ -d build ] || mkdir build
[ -d payload ] || mkdir payload

# Perl build configuration
[ -e ~/.curlrc ] && egrep -q '^insecure' ~/.curlrc || echo insecure >>~/.curlrc
OPENSSL_CONFIG_OPTS="zlib --with-zlib-include='$ROOT/build/zlib' --with-zlib-lib='$ROOT/build/zlib/zlib.a'"
CPANM_OPTS="--build-args=\"OTHERLDFLAGS='-Wl,-search_paths_first'\""
SHASUM="$( which shasum 2>/dev/null )"

build_static_zlib () {
    cd "$ROOT"
    echo ======== Build zlib $ZLIB_VERSION
    ARCHIVE="zlib-$ZLIB_VERSION.tar.gz"
    ZLIB_URL="http://www.zlib.net/$ARCHIVE"
    [ -e "$ARCHIVE" ] || curl -so "$ARCHIVE" "$ZLIB_URL"
    [ -d "zlib-$ZLIB_VERSION" ] || tar xzf "$ARCHIVE"
    [ -d "$ROOT/build/zlib" ] || mkdir -p "$ROOT/build/zlib"
    cd "$ROOT/build/zlib"
    [ -e Makefile ] || CFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" ../../zlib-$ZLIB_VERSION/configure --static \
        --libdir="$PWD" --includedir="$PWD"
    make libz.a
}

build_perl () {
    cd "$ROOT"
    echo ======== Build perl $PERL_VERSION
    PERL_ARCHIVE="perl-$PERL_VERSION.tar.gz"
    PERL_URL="https://www.cpan.org/src/5.0/$PERL_ARCHIVE"
    [ -e "$PERL_ARCHIVE" ] || curl -so "$PERL_ARCHIVE" "$PERL_URL"

    # Eventually verify archive
    if [ -n "$SHASUM" ]; then
        [ -e "$PERL_ARCHIVE.sha1" ] || curl -so "$PERL_ARCHIVE.sha1.txt" "$PERL_URL.sha1.txt"
        read SHA1 x <<<$( $SHASUM $PERL_ARCHIVE )
        if [ "$SHA1" == "$(cat $PERL_ARCHIVE.sha1.txt)" ]; then
            echo "Perl $PERL_VERSION ready for building..."
        else
            echo "Can't build perl $PERL_VERSION, source archive sha1 digest mismatch"
            exit 1
        fi
    fi

    PATCHPERL_URL="https://raw.githubusercontent.com/gugod/patchperl-packing/master/patchperl"
    [ -e patchperl ] || curl -so patchperl  "$PATCHPERL_URL"
    cd build
    [ -d "perl-$PERL_VERSION" ] || tar xzf "../$PERL_ARCHIVE"
    cd "perl-$PERL_VERSION"
    if [ ! -e patchperl ]; then
        cp -a ../../patchperl .
        chmod +x patchperl
        chmod -R +w .
        ./patchperl
    fi
    if [ ! -e Makefile ]; then
        rm -f config.sh Policy.sh
        ./Configure -de -Dprefix=$BUILD_PREFIX -Duserelocatableinc -DNDEBUG    \
            -Dman1dir=none -Dman3dir=none -Dusethreads -UDEBUGGING             \
            -Dusemultiplicity -Duse64bitint -Duse64bitall                      \
            -Aeval:privlib=.../../lib -Aeval:scriptdir=.../../bin              \
            -Aeval:vendorprefix=.../.. -Aeval:vendorlib=.../../agent           \
            -Dcf_by="$BUILDER_NAME" -Dcf_email="$BUILDER_MAIL" -Dperladmin="$BUILDER_MAIL"
    fi
    make -j4
    make install.perl DESTDIR="$ROOT/build"
}

# 1. Zlib is needed at least later to build openssl
build_static_zlib

# 2. build perl
build_perl

cd "$ROOT"

# 3. Include new perl in script PATH
echo "Using perl $PERL_VERSION..."
export PATH="$ROOT/build$BUILD_PREFIX/bin:$PATH"

echo ========
perl --version
echo ========

# 4. Download and Build OpenSSL
if [ ! -d "build/openssl-$OPENSSL_VERSION" ]; then
    echo ======== Build openssl $OPENSSL_VERSION
    ARCHIVE="openssl-$OPENSSL_VERSION.tar.gz"
    OPENSSL_URL="https://www.openssl.org/source/$ARCHIVE"
    [ -e "$ARCHIVE" ] || curl -so "$ARCHIVE" "$OPENSSL_URL"

    # Eventually verify archive
    if [ -n "$SHASUM" ; then
        [ -e "$ARCHIVE.sha1" ] || curl -so "$ARCHIVE.sha1" "$OPENSSL_URL.sha1"
        read SHA1 x <<<$( $SHASUM $ARCHIVE )
        if [ "$SHA1" == "$(cat $ARCHIVE.sha1)" ]; then
            echo "OpenSSL $OPENSSL_VERSION ready for building..."
        else
            echo "Can't build OpenSSL $OPENSSL_VERSION, source archive sha1 digest mismatch"
            exit 1
        fi
    fi

    # Uncompress OpenSSL
    if [ ! -d "openssl-$OPENSSL_VERSION" ]; then
        rm -rf "openssl-$OPENSSL_VERSION"
        tar xzf $ARCHIVE
    fi

    [ -e "$ROOT/zlib-$ZLIB_VERSION/zlib.h" ] \
        && cp -f "$ROOT/zlib-$ZLIB_VERSION/zlib.h" "$ROOT/zlib-$ZLIB_VERSION/zconf.h" "$ROOT/openssl-$OPENSSL_VERSION/include"

    # Build OpenSSL under dedicated folder. This is only possible starting with OpenSSL v1.1.0
    [ -d build/openssl ] || mkdir -p build/openssl
    cd build/openssl

    CFLAGS="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" ../../openssl-$OPENSSL_VERSION/config no-autoerrinit no-shared \
        --prefix="/openssl" $OPENSSL_CONFIG_OPTS
    make

    # Only install static lib from build folder
    make install_sw DESTDIR="$ROOT/build/openssl-$OPENSSL_VERSION"

    # Copy libz.a if previously built to lately be included in Net::SSLeay building
    [ -e "$ROOT/build/zlib/libz.a" ] && \
        cp -f "$ROOT/build/zlib/libz.a" "$ROOT/build/openssl-$OPENSSL_VERSION/openssl/lib"
    [ -e "$ROOT/zlib-$ZLIB_VERSION/zlib.h" ] \
        && cp -f "$ROOT/zlib-$ZLIB_VERSION/zlib.h" "$ROOT/zlib-$ZLIB_VERSION/zconf.h" "$ROOT/build/openssl-$OPENSSL_VERSION/openssl/include"
fi

export OPENSSL_PREFIX="$ROOT/build/openssl-$OPENSSL_VERSION/openssl"

# 5. Install cpanm
cd "$ROOT"
echo "Install cpanminus"
if [ ! -e "build$BUILD_PREFIX/bin/cpanm" ]; then
    CPANM_URL="https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm"
    curl -so build$BUILD_PREFIX/bin/cpanm "$CPANM_URL"
    chmod +x build$BUILD_PREFIX/bin/cpanm
fi

# 6. Still install modules needing compilation
while read modules
do
    [ -z "${modules%%#*}" ] && continue
    echo ======== Install $modules
    cpanm --notest -v --no-man-pages $CPANM_OPTS $modules
done <<MODULES
Module::Install
Sub::Identify Params::Validate HTML::Parser Compress::Zlib Digest::SHA
Net::SSLeay
MODULES

# Try the library
echo ======== SSL check
perl -e 'use Net::SSLeay; print Net::SSLeay::SSLeay_version(0)," (", sprintf("0x%x",Net::SSLeay::SSLeay()),") installed with perl $^V\n";'
echo ========

# Prepare glpi-agent sources
cd ../..
rm -rf build MANIFEST MANIFEST.bak *.tar.gz
[ -e Makefile ] && make clean
perl Makefile.PL

# Install required agent modules
cpanm --notest -v --installdeps --no-man-pages $CPANM_OPTS .

echo '===== Installing more perl module deps ====='
cpanm --notest -v --no-man-pages  $CPANM_OPTS LWP::Protocol::https             \
    HTTP::Daemon Proc::Daemon Archive::Extract File::Copy::Recursive JSON::PP  \
    URI::Escape Net::Ping Parallel::ForkManager Net::SNMP Net::NBName DateTime \
    Thread::Queue Parse::EDID YAML::Tiny UUID::Tiny Data::UUID
# Crypt::DES Crypt::Rijndael are commented as Crypt::DES fails to build on MacOSX
# Net::Write::Layer2 depends on Net::PCAP but it fails on MacOSX

rm -rf "$ROOT/payload${BUILD_PREFIX%%/*}"
mkdir -p "$ROOT/payload$BUILD_PREFIX"

echo ======== Clean installation
rsync -a --exclude=.packlist --exclude='*.pod' --exclude=.meta --delete --force \
    "$ROOT/build$BUILD_PREFIX/lib/" "$ROOT/payload$BUILD_PREFIX/lib/"
rm -rf "$ROOT/payload$BUILD_PREFIX/lib/pods"
mkdir "$ROOT/payload$BUILD_PREFIX/bin"
cp -a "$ROOT/build$BUILD_PREFIX/bin/perl" "$ROOT/payload$BUILD_PREFIX/bin/perl"

# Finalize sources
if [ -n "$GITHUB_REF" -a -z "${GITHUB_REF%refs/tags/*}" ]; then
    VERSION="${GITHUB_REF#refs/tags/}"
else
    read Version equals VERSION <<<$( egrep "^VERSION = " Makefile | head -1 )
fi

if [ -z "${VERSION#*-dev}" -a -n "$GITHUB_SHA" ]; then
    VERSION="${VERSION%-dev}-git${GITHUB_SHA:0:8}"
fi

COMMENTS="Built by Teclib on $HOSTNAME: $(LANG=C date)"

echo "Preparing sources..."
perl Makefile.PL PREFIX="$BUILD_PREFIX" DATADIR="$BUILD_PREFIX/share"   \
    SYSCONFDIR="$BUILD_PREFIX/etc" LOCALSTATEDIR="$BUILD_PREFIX/var"    \
    INSTALLSITELIB="$BUILD_PREFIX/agent" PERLPREFIX="$BUILD_PREFIX/bin" \
    COMMENTS="$COMMENTS" VERSION="$VERSION"

# Fix shebang
rm -rf inc/ExtUtils
mkdir inc/ExtUtils

cat >inc/ExtUtils/MY.pm <<-EXTUTILS_MY
	package ExtUtils::MY;
	
	use strict;
	require ExtUtils::MM;
	
	our @ISA = qw(ExtUtils::MM);
	
	{
	    package MY;
	    our @ISA = qw(ExtUtils::MY);
	}
	
	sub _fixin_replace_shebang {
	    return '#!$BUILD_PREFIX/bin/perl';
	}
	
	sub DESTROY {}
EXTUTILS_MY

make

echo "Make done."

echo "Installing to payload..."
make install DESTDIR="$ROOT/payload"
echo "Installed."

cd "$ROOT"

# Create conf.d and fix default conf
[ -d "payload$BUILD_PREFIX/etc/conf.d" ] || mkdir -p "payload$BUILD_PREFIX/etc/conf.d"
AGENT_CFG="payload$BUILD_PREFIX/etc/agent.cfg"
sed -i .1.bak -Ee "s/^scan-homedirs *=.*/scan-homedirs = 1/" $AGENT_CFG
sed -i .2.bak -Ee "s/^scan-profiles *=.*/scan-profiles = 1/" $AGENT_CFG
sed -i .3.bak -Ee "s/^httpd-trust *=.*/httpd-trust = 127.0.0.1/" $AGENT_CFG
sed -i .4.bak -Ee "s/^logger *=.*/logger = File/" $AGENT_CFG
sed -i .5.bak -Ee "s/^#?logfile *=.*/logfile = \/var\/log\/glpi-agent.log/" $AGENT_CFG
sed -i .6.bak -Ee "s/^#?logfile-maxsize *=.*/logfile-maxsize = 10/" $AGENT_CFG
sed -i .7.bak -Ee "s/^#?include \"conf\.d\/\"/include \"conf.d\"/" $AGENT_CFG
rm -f $AGENT_CFG*.bak

echo "Create build-info.plist..."
cat >build-info.plist <<-BUILD_INFO
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>distribution_style</key>
		<false/>
		<key>identifier</key>
		<string>org.glpi-project.glpi-agent</string>
		<key>install_location</key>
		<string>/</string>
		<key>name</key>
		<string>GLPI-Agent-${VERSION}_$ARCH.pkg</string>
		<key>ownership</key>
		<string>recommended</string>
		<key>postinstall_action</key>
		<string>none</string>
		<key>preserve_xattr</key>
		<false/>
		<key>suppress_bundle_relocation</key>
		<true/>
		<key>version</key>
		<string>$VERSION</string>
	</dict>
	</plist>
BUILD_INFO

cat >product-requirements.plist <<-REQUIREMENTS
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	    <key>os</key>
	    <array>
	        <string>10.10</string>
	    </array>
	    <key>arch</key>
	    <array>
	        <string>$ARCH</string>
	    </array>
	</dict>
	</plist>
REQUIREMENTS

echo "Build package"
./munkipkg .

PKG="GLPI-Agent-${VERSION}_$ARCH.pkg"
DMG="GLPI-Agent-${VERSION}_$ARCH.dmg"

echo "Prepare distribution installer..."
cat >Distribution.xml <<-CUSTOM
	<?xml version="1.0" encoding="utf-8" standalone="no"?>
	<installer-gui-script minSpecVersion="2">
	    <title>GLPI-Agent $VERSION</title>
	    <pkg-ref id="org.glpi-project.glpi-agent" version="$VERSION" onConclusion="none">$PKG</pkg-ref>
	    <license file="License.txt" mime-type="text/plain" />
	    <background file="background.png" uti="public.png" alignment="bottomleft"/>
	    <background-darkAqua file="background.png" uti="public.png" alignment="bottomleft"/>
	    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
	    <options customize="never" require-scripts="false" hostArchitectures="$ARCH"/>
	    <choices-outline>
	        <line choice="default">
	            <line choice="org.glpi-project.glpi-agent"/>
	        </line>
	    </choices-outline>
	    <choice id="default"/>
	    <choice id="org.glpi-project.glpi-agent" visible="false">
	        <pkg-ref id="org.glpi-project.glpi-agent"/>
	    </choice>
	    <os-version min="10.10" />
	</installer-gui-script>
CUSTOM
productbuild --product product-requirements.plist --distribution Distribution.xml \
    --package-path "build" --resources "Resources" "build/Dist-$PKG"
mv -vf "build/Dist-$PKG" "build/$PKG"

if [ -e "build/$PKG" ]; then
    rm -f "build/$DMG"
    echo "Create DMG"
    hdiutil create -fs "HFS+" -srcfolder "build/$PKG" "build/$DMG"
fi

ls -l build/*.pkg build/*.dmg

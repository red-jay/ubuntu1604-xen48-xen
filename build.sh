#!/usr/bin/env bash

set -eux
set -o pipefail

GPG_PASSFILE=(/dev/shm/pass.*)

# configure debsign for PPA submission
printf 'DEBSIGN_PROGRAM="gpg --no-use-agent --no-tty --trusted-key 0x7D1110294E694719 --passphrase-file %s"\nDEBSIGN_KEYID=%s\n' "${GPG_PASSFILE[0]}" "0x7D1110294E694719" > "${HOME}/.devscripts"
export DEBFULLNAME="RJ Bergeron"
export DEBEMAIL="hewt1ojkif@gmail.com"

# well we should have chdist & madison, but if not install them.
{ type rmadison && type chdist ; } || { apt-get -qq -y update && apt-get -qq -y install devscripts ; }

# get our upstream version
upstream_version=$(rmadison xen -u qa -s stretch-security 2>/dev/null|cut -d'|' -f2|sort -V|tail -n1)
upstream_version=${upstream_version# }
upstream_version=${upstream_version% }

# create a distribution to run apt tools against without interfering with the real system
[ -e "${HOME}/.chdist/xenial" ] || chdist create xenial
sed 's/'"$(lsb_release -cs)"'/xenial/g' > "${HOME}/.chdist/xenial/etc/apt/sources.list" < /etc/apt/sources.list

# add our PPA for package checking
cp notarrjay_ubuntu_stretch_xen-on-xenial.gpg "${HOME}/.chdist/xenial/etc/apt/trusted.gpg.d/"
echo "deb http://ppa.launchpad.net/notarrjay/stretch-xen-on-xenial/ubuntu xenial main" >> "${HOME}/.chdist/xenial/etc/apt/sources.list"

# get packagelists for that so we can compare builds
chdist apt-get xenial -qq update

# cool now use the apt tools via chdist to get our already-built package version
downstream_version=$(chdist apt-cache xenial show xen-hypervisor-4.8-amd64 | grep Version | cut -d: -f2 | sort -V | tail -n1)
downstream_version=${downstream_version# }
downstream_version=${downstream_version% }

# exit with success if we already have a matching upstream
# FORCE_BUILD is here so we can easily make this never match ;)
case "${FORCE_BUILD+x}${downstream_version}" in
  "${upstream_version}"*) exit 0 ;;
  *) : ;;
esac

# grab everything for a local patch
xen_dsc="http://security.debian.org/debian-security/pool/updates/main/x/xen/xen_${upstream_version}.dsc"
lv="${xen_dsc##*/}"
dv=${lv##*-}
dv=${dv%.dsc}
ov=${lv%-$dv*}
upath=${xen_dsc%$lv}

# lv=xen_4.8.3+xsa262+shim4.10.0+comet3-1+deb9u7.dsc
# dv=1+deb9u7.dsc
# dv=1+deb9u7
# ov=xen_4.8.3+xsa262+shim4.10.0+comet3

curl -LO "${xen_dsc}"
curl -LO "${upath}${ov}.orig.tar.gz"
curl -LO "${upath}${ov}-${dv}.debian.tar.xz"
curl -LO "${upath}${ov}.orig-shim.tar.gz"

cat "${lv}"

# validate this isn't crap
mkdir -p "${HOME}/.gnupg"
apt-get -qq update && apt-get -qq -y install debian-keyring
dscverify "${lv}"

# extract it
dpkg-source -x "${lv}"

# patch it
( cd "${ov/_/-}" && patch -p1 < ../ovmf-rules.patch )

# repack it
dpkg-source -b "${ov/_/-}/"

# ship to PPA
type backportpackage || { apt-get -qq -y update && apt-get -qq -y install ubuntu-dev-tools ; }
backportpackage -d xenial -u ppa:notarrjay/stretch-xen-on-xenial -y "${lv}" -S '~ppa2'

#!/bin/bash

#Function description：

#1 download openwrt source

#2 set up openwrt config

#3 download tool, toolchain and packages

#4 compile tool and toolchain

NUM_CPU=$(nproc)
OPENWRT_GIT_REPO=https://git.openwrt.org/openwrt/openwrt.git
OPENWRT_GIT_BRANCH=master

openwrt_prepare() {
	local CONFIG=$1
	local TMPBUILDDIR=$1
	local tries=5
	
	cd "$TMPBUILDDIR"

	#1 download openwrt source
	openwrt_download
	
	#2 set up openwrt config
	# otherwise OpenWrt will generate new release keys every build
	openwrt_create_signing_keys

	# update feeds
	# TODO: drop another workaround: temporarily disable building all packages
	#./scripts/feeds update
	#./scripts/feeds install -a

	# configure openwrt because otherwise it wont download everything
	openwrt_config "$CONFIG"
	
	#3 download tool, toolchain and packages
	while ! make tools/tar/compile download -j "$NUM_CPU" IGNORE_ERRORS=ym BUILD_LOG=1 ; do
		tries=$((tries - 1))
		if [ $tries -eq 0 ] ; then
			echo "================================================================================"
			echo "$(date -u) - Failed to download sources"
			echo "================================================================================"
			exit 1
		fi
	done
	
	#4 compile tool and toolchain
	openwrt_build_toolchain
	
	#5 make a backup
	echo -e "\nsave current openwrt state\n"
	popd
	rsync -a source/ source_backup/
	
	#6 calculate and show script run time
	calculate_build_duration
	print_out_duration
}

openwrt_download() {
	
	# checkout the repo
	echo "================================================================================"
	echo "$(date -u) - Cloning git repository from $OPENWRT_GIT_REPO $OPENWRT_GIT_BRANCH. "
	echo "================================================================================"
	# git clone -b "$OPENWRT_GIT_BRANCH" "$OPENWRT_GIT_REPO" source
	pushd source
	
	# get lastest commit 
        # git pull

	echo "================================================================================"
	echo "$(date -u) - received git version $(git log -1 --pretty=oneline)"
	echo "================================================================================"
}

openwrt_create_signing_keys() {
	echo "============================================================================="
	cat <<- EOF
# OpenWrt signs the release with a signing key, but generate the signing key if not
# present. To have a reproducible release we need to take care of signing keys.
# OpenWrt will also put the key-build.pub into the resulting image (pkg: base-files)!
# At the end of the build it will use the key-build to sign the Packages repo list.
# Use a workaround this problem:
# key-build.pub contains the pubkey of OpenWrt buildbot
# key-build     contains our build key
# Meaning only signed files will be different but not the images.
# Packages.sig is unreproducible.
# here is our random signing key
# chosen by fair dice roll.
# guaranteed to be random.
# private key
EOF
	echo -e 'untrusted comment: Local build key\nRWRCSwAAAAB12EzgExgKPrR4LMduadFAw1Z8teYQAbg/EgKaN9SUNrgteVb81/bjFcvfnKF7jS1WU8cDdT2VjWE4Cp4cxoxJNrZoBnlXI+ISUeHMbUaFmOzzBR7B9u/LhX3KAmLsrPc=' | tee key-build
	echo "\n# public key"
	echo -e 'untrusted comment: Local build key\nRWQ/EgKaN9SUNja2aAZ5VyPiElHhzG1GhZjs8wUewfbvy4V9ygJi7Kz3' | tee key-build.pub

	echo "# override the pubkey with 'OpenWrt usign key for unattended build jobs' to have the same base-files pkg and images"
	echo -e 'untrusted comment: OpenWrt usign key for unattended build jobs\nRWS1BD5w+adc3j2Hqg9+b66CvLR7NlHbsj7wjNVj0XGt/othDgIAOJS+' | tee key-build.pub
	echo "============================================================================="
}

openwrt_config() {
	local CONFIG=$1
	echo -e "\nstart make menuconfig\n"
	#linux中>表示覆盖原文件内容，>>表示追加内容。
	printf "CONFIG_TARGET_$CONFIG=y\n" > .config
	printf "CONFIG_ALL=y\n" >> .config
	printf "CONFIG_AUTOREMOVE=y\n" >> .config
	printf "CONFIG_BUILDBOT=y\n" >> .config
	printf "CONFIG_CLEAN_IPKG=y\n" >> .config
	printf "CONFIG_TARGET_ROOTFS_TARGZ=y\n" >> .config
	printf 'CONFIG_KERNEL_BUILD_USER="openwrt"\n' >> .config
	printf 'CONFIG_KERNEL_BUILD_DOMAIN="buildhost"\n' >> .config

	# WORKAROUND: the OpenWrt build system has a bug with iw when using CONFIG_ALL=y and selecting iw as dependency (over target dependencies).
	printf 'CONFIG_PACKAGE_iw=y\n' >> .config
	make defconfig
}



openwrt_build_toolchain() {

	echo "============================================================================="
	echo "$(LC_ALL=en_US.UTF-8 date -u) - Building the toolchain."
	echo "============================================================================="

	OPTIONS=('-j' "$NUM_CPU" 'IGNORE_ERRORS=n m y' 'BUILD_LOG=1')

	ionice -c 3 make "${OPTIONS[@]}" tools/install
	ionice -c 3 make "${OPTIONS[@]}" toolchain/install
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

print_out_duration() {
	if [ -z "$DURATION" ]; then
		return
	fi
	local HOUR=$(echo "$DURATION/3600"|bc)
	local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date -u) - total duration: ${HOUR}h ${MIN}m ${SEC}s." 
}


if [ $# != 1 ] ; then 
echo "USAGE: $0 TARGET" 
echo " e.g.: $0 ar71xx/brcm47xx/kirkwood/lantiq/mediatek/omap/ramips/sunxi/tegra/x86" 
exit 1; 
fi


START=$(date +'%s')
TARGET=$1

#ROOTDIR=$PWD

mkdir -p "$TARGET"

openwrt_prepare $TARGET



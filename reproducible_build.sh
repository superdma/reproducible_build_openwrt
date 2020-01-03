#!/bin/bash

NUM_CPU=$(nproc)
OPENWRT_GIT_REPO=https://git.openwrt.org/openwrt/openwrt.git
OPENWRT_GIT_BRANCH=master

export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1

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

openwrt_download() {
	local CONFIG=$1
	local TMPBUILDDIR=$1
	local tries=5
	
	cd "$TMPBUILDDIR"

	# checkout the repo
	echo "================================================================================"
	echo "$(date -u) - Cloning git repository from $OPENWRT_GIT_REPO $OPENWRT_GIT_BRANCH. "
	echo "================================================================================"
	git clone -b "$OPENWRT_GIT_BRANCH" "$OPENWRT_GIT_REPO" source
	pushd source
	
	# get lastest commit 
       	# git pull
	
	echo "================================================================================"
	echo "$(date -u) - received git version $(git log -1 --pretty=oneline)"
	echo "================================================================================"

	# otherwise OpenWrt will generate new release keys every build
	openwrt_create_signing_keys

	# update feeds
	# TODO: drop another workaround: temporarily disable building all packages
	#./scripts/feeds update
	#./scripts/feeds install -a

	# configure openwrt because otherwise it wont download everything
	openwrt_config "$CONFIG"
	while ! make tools/tar/compile download -j "$NUM_CPU" IGNORE_ERRORS=ym BUILD_LOG=1 ; do
		tries=$((tries - 1))
		if [ $tries -eq 0 ] ; then
			echo "================================================================================"
			echo "$(date -u) - Failed to download sources"
			echo "================================================================================"
			exit 1
		fi
	done
	
	echo -e "\nsave current openwrt state\n"
	popd
	rsync -av source/ source_backup/
}

openwrt_build_toolchain() {

	echo "============================================================================="
	echo "$(date -u) - Building the toolchain."
	echo "============================================================================="

	OPTIONS=('-j' "$NUM_CPU" 'IGNORE_ERRORS=n m y' 'BUILD_LOG=1')

	ionice -c 3 $MAKE "${OPTIONS[@]}" tools/install
	ionice -c 3 $MAKE "${OPTIONS[@]}" toolchain/install
}

# RUN - b1 or b2. b1 means first run, b2 second
# TARGET - a target including subtarget. E.g. ar71xx_generic
openwrt_compile() {
	local RUN=$1
	local TARGET=$2

	OPTIONS=('-j' "$NUM_CPU" 'IGNORE_ERRORS=n m y' 'BUILD_LOG=1')

	# make $RUN more human readable
	[ "$RUN" = "b1" ] && RUN="first" 
	[ "$RUN" = "b2" ] && RUN="second"
        
	OPENWRT_VERSION=$(git rev-parse --short HEAD)
	echo "============================================================================="
	echo "$(date -u) - Building OpenWrt ${OPENWRT_VERSION} ($TARGET) - $RUN build run."
	echo "============================================================================="

	ionice -c 3 $MAKE "${OPTIONS[@]}"
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


openwrt_apply_variations() {
	local RUN=$1

	if [ "$RUN" = "b1" ] ; then
		export TZ="/usr/share/zoneinfo/Etc/GMT+12"
		#export FAKETIME="+0d"
		export MAKE=make
	else
		export TZ="/usr/share/zoneinfo/Etc/GMT-14"
		export FAKETIME="-378d"
		export LANG="fr_CH.UTF-8"
		export LC_ALL="fr_CH.UTF-8"
		export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
		export CAPTURE_ENVIRONMENT="I capture the environment"
		# use allmost all cores for second build
		export NEW_NUM_CPU=$(echo "$NUM_CPU-1" | bc)
		export MAKE=make
	fi
}


openwrt_build() {
	local RUN=$1
	local TARGET=$2
	
	pushd source
	# set tz, date, core, ..
	openwrt_apply_variations "$RUN"

	openwrt_build_toolchain 
	# build images and packages
	openwrt_compile "$RUN" "$TARGET"

	popd
	if [ "$RUN" = "b1" ] ; then
		mv source source1
		mv source_backup source
	else
		mv source source2
	fi
}

openwrt_recover_variations() {
	export TZ="CST-8"
	export FAKETIME="+0d"
	export LANG="en_HK.UTF-8"
	unset LC_ALL
	export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:"
}

openwrt_strip_and_save_result() {
	cd "$ROOTDIR"
	echo -e "\nsave images and packages to b1\n"
	source ./strip.sh $TARGET "source1" "b1"
	
	cd "$ROOTDIR"
	echo -e "\nsave images and packages to b2\n"
	source ./strip.sh $TARGET "source2" "b2"
}

calculate_reproducible_result() {
	cd "$ROOTDIR"
	echo -e "\nthe percentage of reproducible images and packages:\n"
	source ./rebuild.sh $TARGET
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


DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
TARGET=$1
ROOTDIR=$PWD

mkdir -p "$TARGET"
cd "$TARGET"

openwrt_download $TARGET

openwrt_build "b1" "$TARGET"

openwrt_build "b2" "$TARGET"

openwrt_recover_variations

openwrt_strip_and_save_result

calculate_reproducible_result

calculate_build_duration

print_out_duration



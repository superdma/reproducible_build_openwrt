
#!/bin/bash

#Function description：

#1 twice run openwrt build

#2 strip images and packages, then save them 

#3 diffoscope images and packages, generate difference json file

#4 show result

NUM_CPU=$(nproc)

openwrt_build() {
	local RUN=$1
	local TARGET=$2
	
	pushd source
	# set tz, date, core, ..
	openwrt_apply_variations "$RUN"
	
	# build images and packages
	openwrt_compile "$RUN" "$TARGET"
	
	popd
	
	if [ "$RUN" = "b1" ] ; then
		mv source source1
		#mkdir source 
		#disorderfs source_backup/ source/
		mv source_backup source
	else
		echo -e " if openwrt do disorderfs, source can't mv to source2"
		mv source source2
	fi
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
	echo "$(LC_ALL=en_US.UTF-8 date -u) - Building OpenWrt ${OPENWRT_VERSION} ($TARGET) - $RUN build run."
	echo "============================================================================="

	ionice -c 3 $MAKE "${OPTIONS[@]}"
}

openwrt_apply_variations() {
	local RUN=$1
	export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1
	
	if [ "$RUN" = "b1" ] ; then
		export TZ="/usr/share/zoneinfo/Etc/GMT+12"
		#export FAKETIME="+0d"
		export MAKE=make
	else
		export TZ="/usr/share/zoneinfo/Etc/GMT-14"
		#export FAKETIME="-378d"
		export LANG="fr_CH.UTF-8"
		export LC_ALL="fr_CH.UTF-8"
		export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
		export CAPTURE_ENVIRONMENT="I capture the environment"
		# use allmost all cores for second build
		export NUM_CPU=$(echo "$NUM_CPU-0" | bc)
		export MAKE=make
	fi
}

openwrt_recover_variations() {
	export TZ="CST-8"
	export FAKETIME="+0d"
	export LANG="en_US.UTF-8"
	unset LC_ALL
	export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:"
}

openwrt_strip_and_save_result() {
	cd "$ROOTDIR"
	echo -e "\nsave images and packages to b1\n"
	source ./reproducible_openwrt_strip_and_save.sh $TARGET "source1" "b1"
	
	cd "$ROOTDIR"
	echo -e "\nsave images and packages to b2\n"
	source ./reproducible_openwrt_strip_and_save.sh $TARGET "source2" "b2"
	
	#when openwrt build by disorderfs, uncomment 
	#source ./reproducible_openwrt_strip_and_save.sh $TARGET "source" "b2"
}

calculate_reproducible_result() {
	cd "$ROOTDIR"
	echo -e "\nthe percentage of reproducible images and packages:\n"
	source ./reproducible_openwrt_diffoscope.sh $TARGET
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
ROOTDIR=$PWD

cd "$TARGET"

openwrt_build "b1" "$TARGET"

openwrt_build "b2" "$TARGET"

openwrt_recover_variations

openwrt_strip_and_save_result

calculate_reproducible_result

calculate_build_duration

print_out_duration

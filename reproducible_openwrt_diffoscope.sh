#!/bin/bash

# diffoscope memory limit in kilobytes
DIFFOSCOPE="Diffoscope $(diffoscope --version 2>&1)"
DIFFOSCOPE_VIRT_LIMIT=$((10*1024*1024))
TIMEOUT="30m"
DEBUG=false


get_filesize() {
		local BYTESIZE="$(du -h -b $1 | cut -f1)"
		# numbers below 16384K are understood and more meaningful than 16M...
		if [ $BYTESIZE -gt 16777216 ] ; then
			SIZE="$(echo $BYTESIZE/1048576|bc)M"
		elif [ $BYTESIZE -gt 1024 ] ; then
			SIZE="$(echo $BYTESIZE/1024|bc)K"
		else
			SIZE="$BYTESIZE bytes"
		fi
}

call_diffoscope() {
	echo "$1 $2"
	mkdir -p $TMPDIR/$1/$(dirname $2)
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	local msg=""
	set +e
	# remember to also modify the retry diffoscope call 15 lines below
	( ulimit -v "$DIFFOSCOPE_VIRT_LIMIT"
	  timeout "$TIMEOUT" \
		diffoscope \
			--html $TMPDIR/$1/$2.html \
			$TMPDIR/b1/$1/$2 \
			$TMPDIR/b2/$1/$2 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	LOG_RESULT=$(grep '^E: 15binfmt: update-binfmts: unable to open' $TMPLOG || true)
	if [ ! -z "$LOG_RESULT" ] ; then
		rm -f $TMPLOG $TMPDIR/$1/$2.html
		echo "$(date -u) - diffoscope not available, will sleep 2min and retry."
		sleep 2m
		# remember to also modify the retry diffoscope call 15 lines above
		( ulimit -v "$DIFFOSCOPE_VIRT_LIMIT"
		  timeout "$TIMEOUT" \
			diffoscope \
				--html $TMPDIR/$1/$2.html \
				$TMPDIR/b1/$1/$2 \
				$TMPDIR/b2/$1/$2 2>&1 \
			) 2>&1 >> $TMPLOG
		RESULT=$?
	fi
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG # print dbd output
	rm -f $TMPLOG
	case $RESULT in
		0)	echo "$(date -u) - $1/$2 is reproducible, yay!"
			;;
		1)
			echo "$(date -u) - $DIFFOSCOPE found issues, please investigate $1/$2"
			;;
		2)
			msg="$(date -u) - $DIFFOSCOPE had trouble comparing the two builds. Please investigate $1/$2"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				msg="$(date -u) - $DIFFOSCOPE produced no output for $1/$2 and was killed after running into timeout after ${TIMEOUT}..."
			else
				msg="$DIFFOSCOPE was killed after running into timeout after $TIMEOUT, but there is still $TMPDIR/$1/$2.html"
			fi
			;;
		*)
			# Process killed by signal exits with 128+${signal number}.
			# 31 = SIGSYS = maximum signal number in signal(7)
			if (( $RESULT > 128 )) && (( $RESULT <= 128+31 )); then
				RESULT="$RESULT (SIG$(kill -l $(($RESULT - 128))))"
			fi
			msg="$(date -u) - Something weird happened, $DIFFOSCOPE on $1/$2 exited with $RESULT and I don't know how to handle it."
			;;
	esac
	if [ ! -z "$msg" ] ; then
		echo $msg | tee -a $TMPDIR/$1/$2.html
	fi
}


#PACKAGE_DIR=$2
#PACKAGE_NAME=$3
#call_diffoscope "$PACKAGE_DIR" "$PACKAGE_NAME"

remove -rf openwrt package images
VERSION=$1
RESULTSDIR="$ROOTDIR/$1"
TMPDIR="$RESULTSDIR"

mkdir -p "$RESULTSDIR/images"
mkdir -p "$RESULTSDIR/packages"


# run diffoscope on the images
GOOD_IMAGES=0
ALL_IMAGES=0
SIZE=""
cd "$RESULTSDIR/b1/targets"
tree .

# call_diffoscope requires TMPDIR

# iterate over all images (merge b1 and b2 images into one list)
# call diffoscope on the images
for target in * ; do
	cd "$target"
	for subtarget in * ; do
		cd "$subtarget"

		# search images in both paths to find non-existing ones
		IMGS1=$(find -- * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
		pushd "$RESULTSDIR/b2/targets/$target/$subtarget"
		IMGS2=$(find -- * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
		popd

		for image in $(printf "%s\n%s" "$IMGS1" "$IMGS2" | sort -u ) ; do
			let ALL_IMAGES+=1
			if [ ! -f "$RESULTSDIR/b1/targets/$target/$subtarget/$image" ] || [ ! -f "$RESULTSDIR/b2/targets/$target/$subtarget/$image" ] ; then
				continue
			fi

			if [ "$(sha256sum "$RESULTSDIR/b1/targets/$target/$subtarget/$image" "$RESULTSDIR/b2/targets/$target/$subtarget/$image" \
				| cut -f 1 -d ' ' | uniq -c  | wc -l)" != "1" ] ; then
				call_diffoscope "targets/$target/$subtarget" "$image"
			else
				echo "$(date -u) - targets/$target/$subtarget/$image is reproducible!"
			fi
			#get_filesize "$image"
			if [ -f "$RESULTSDIR/targets/$target/$subtarget/$image.html" ] ; then
				mv "$RESULTSDIR/targets/$target/$subtarget/$image.html" "$RESULTSDIR/images"
			else
				#SHASUM=$(sha256sum "$image" |cut -d " " -f1)
				let GOOD_IMAGES+=1
				rm -f "$RESULTSDIR/targets/$target/$subtarget/$image.html" # cleanup from previous (unreproducible) tests - if needed
			fi
		done
		cd ..
	done
	cd ..
done


# run diffoscope on the packages
GOOD_PACKAGES=0
ALL_PACKAGES=0
cd "$RESULTSDIR/b1"
tree .
for i in * ; do
	if [ ! -d "$i" ] ; then
		continue
	fi

	cd "$i"

	# search packages in both paths to find non-existing ones
	PKGS1=$(find -- * -type f -name "*.ipk" | sort -u )
	pushd "$RESULTSDIR/b2/$i"
	PKGS2=$(find -- * -type f -name "*.ipk" | sort -u )
	popd

	for j in $(printf "%s\n%s" "$PKGS1" "$PKGS2" | sort -u ) ; do
		let ALL_PACKAGES+=1
		if [ ! -f "$RESULTSDIR/b1/$i/$j" ] || [ ! -f "$RESULTSDIR/b2/$i/$j" ] ; then
			continue
		fi
		if [ "$(sha256sum "$RESULTSDIR/b1/$i/$j" "$RESULTSDIR/b2/$i/$j" | cut -f 1 -d ' ' | uniq -c  | wc -l)" != "1" ] ; then
			call_diffoscope "$i" "$j"
		else
			echo "$(date -u) - $i/$j is reproducible!"
		fi
		if [ -f "$RESULTSDIR/$i/$j.html" ] ; then
			mv "$RESULTSDIR/$i/$j.html" "$RESULTSDIR/packages/"
		else
			#SHASUM=$(sha256sum "$j" |cut -d " " -f1)
			let GOOD_PACKAGES+=1
			rm -f "$RESULTSDIR/$i/$j.html" # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
done

if [ $ALL_IMAGES -ne 0 ] ; then
	GOOD_PERCENT_IMAGES=$(echo "scale=1 ; ($GOOD_IMAGES*100/$ALL_IMAGES)" | bc )
else
	GOOD_PERCENT_IMAGES=0
fi

if [ $ALL_PACKAGES -ne 0 ] ; then
	GOOD_PERCENT_PACKAGES=$(echo "scale=1 ; ($GOOD_PACKAGES*100/$ALL_PACKAGES)" | bc )
else
	GOOD_PERCENT_PACKAGES=0
fi

cd "$TMPDIR"
#touch result.txt 

echo "=============================================================================" | tee -a result.txt
echo "$(date) - OpenWrt ${OPENWRT_VERSION} ($TARGET) - Reproducible Result" | tee -a result.txt
echo "=============================================================================" | tee -a result.txt
echo "ALL_IMAGES is $ALL_IMAGES, GOOD_IMAGES is $GOOD_IMAGES" | tee -a result.txt
echo "ALL_PACKAGES is $ALL_PACKAGES, GOOD_PACKAGES is $GOOD_PACKAGES" | tee -a result.txt
echo "$GOOD_PERCENT_IMAGES% images and $GOOD_PERCENT_PACKAGES% packages is reproducible in current test framework." |tee -a result.txt


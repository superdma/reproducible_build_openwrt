#!/bin/bash


openwrt_strip_metadata_signature() {
	local openwrttop=$1

	cd "$openwrttop"
	find bin/targets/ -type f | \
		grep -E -v '(\.ipk|sha256sums|config.seed|kernel-debug.tar.bz2|manifest|Packages.gz|Packages|Packages.sig)$' | \
		while read -r line ; do
			./staging_dir/host/bin/fwtool -s /dev/null -t "$line" || true
	done
}

#RUN b1 = source, b2 = source1/source
save_openwrt_results() {
	local RUN=$1

	# first save all images and target specific packages #FIXME: include feeds.buildinfo and version.buildinfo
	pushd bin/targets
	for target in * ; do
		pushd "$target" || continue
		for subtarget in * ; do
			pushd "$subtarget" || continue

			# save firmware images
			mkdir -p "$TMPDIR/$RUN/targets/$target/$subtarget/"
			for image in $(find * -name "*.bin" -o -name "*.squashfs") ; do
				cp -p "$image" "$TMPDIR/$RUN/targets/$target/$subtarget/"
			done

			# save subtarget specific packages
			if [ -d packages ] ; then
				pushd packages
				for package in $(find * -name "*.ipk" -o -name "Package*") ; do
					mkdir -p $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package) || ( echo $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package) ; continue )
					cp -p $package $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package)/
				done
				popd
			fi
			popd
		done
		popd
	done
	popd

	# save all generic packages
	# arch is like mips_34kc_dsp
	pushd bin/packages/
	for arch in * ; do
		pushd "$arch" || continue
		for feed in * ; do
			pushd "$feed" || continue
			for package in $(find * -name "*.ipk" -o -name "Package*") ; do
				mkdir -p "$TMPDIR/$RUN/packages/$arch/$feed/$(dirname "$package")"
				cp -p "$package" "$TMPDIR/$RUN/packages/$arch/$feed/$(dirname "$package")/"
			done
			popd
		done
		popd
	done
	popd
}
VERSION=$1
BUILDTIMES=$3
TMPDIR="$ROOTDIR/$1"

BUILDDIR="$TMPDIR/$2"
openwrt_strip_metadata_signature $BUILDDIR

cd $BUILDDIR
save_openwrt_results $BUILDTIMES


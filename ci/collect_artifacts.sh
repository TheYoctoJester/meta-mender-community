#!/bin/sh


if [ -z ${BUILDDIR+x} ]; then
	echo "BUILDDIR is unset, exiting";
	exit 1;
fi
if [ -z ${ARTIFACT_PATH+x} ]; then
	echo "ARTIFACT_PATH is unset, exiting";
	exit 1;
fi

echo "using BUILDDIR: $BUILDDIR"
echo "using ARTIFACT_PATH: $ARTIFACT_PATH"

mkdir -p $ARTIFACT_PATH

IMAGE_SUBPATH="build/tmp/deploy/images"

for build in $(ls $BUILDDIR); do
	echo "found build: $build"

	if [ ! -d "$BUILDDIR/$build/$IMAGE_SUBPATH" ]; then
		echo "no artifacts found"
		continue
	fi

	for board in $(ls $BUILDDIR/$build/$IMAGE_SUBPATH); do
		echo ".. found board $board"
		mkdir -p $ARTIFACT_PATH/$build
		echo "$board" > $ARTIFACT_PATH/$build/board.txt
		cp -fR $BUILDDIR/$build/$IMAGE_SUBPATH/$board $ARTIFACT_PATH/$build/images
		cp -fR $BUILDDIR/$build/build/conf $ARTIFACT_PATH/$build

		if [ -d "$BUILDDIR/$build/build/tmp/buildstats" ]; then
			cp -fR $BUILDDIR/$build/build/tmp/buildstats $ARTIFACT_PATH/$build
		fi
	done
done

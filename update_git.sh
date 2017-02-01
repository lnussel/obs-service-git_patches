#!/bin/bash
#
# Instead of a quilt workflow, we use a git tree that contains
# all the commits on top of a stable tarball.
#
# When updating this package, just either update the git tree
# below (use rebase!) or change the tree path and use your own
#
# That way we can easily rebase against the next stable release
# when it comes.

set -e

GIT_TREE=git://github.com/openSUSE/qemu.git
GIT_LOCAL_TREE=~/git/qemu-opensuse
GIT_BRANCH=opensuse-2.8
GIT_UPSTREAM_TAG=v2.8.0
GIT_DIR=/dev/shm/qemu-factory-git-dir
CMP_DIR=/dev/shm/qemu-factory-cmp-dir

rm -rf $GIT_DIR
rm -rf $CMP_DIR

if [ -d "$GIT_LOCAL_TREE" ]; then
    echo "Processing $GIT_BRANCH branch of local git tree, using tag:" \
         "$GIT_UPSTREAM_TAG"
    if ! (cd $GIT_LOCAL_TREE && git show-branch $GIT_BRANCH &>/dev/null); then
        echo "Error: Branch $GIT_BRANCH not found - please create a remote" \
             "tracking branch of origin/$GIT_BRANCH"
        exit
    fi
    git clone -ls $GIT_LOCAL_TREE $GIT_DIR -b $GIT_BRANCH
    if ! (cd $GIT_LOCAL_TREE && git remote show upstream &>/dev/null); then
        echo "Remote for upstream git tree not found. Next time add remote" \
             "named upstream for git://git.qemu.org/qemu.git and update"
        (cd $GIT_DIR && git remote add upstream git://git.qemu-project.org/qemu.git)
        (cd $GIT_DIR && git remote update)
   fi
else
    echo "Processing $GIT_BRANCH branch of remote git tree, using tag:" \
         "$GIT_UPSTREAM_TAG"
    echo "(For much fast processing, consider establishing a local git tree" \
         "at $GIT_LOCAL_TREE)"
    git clone $GIT_TREE $GIT_DIR -b $GIT_BRANCH
    (cd $GIT_DIR && git remote add upstream git://git.qemu-project.org/qemu.git)
    (cd $GIT_DIR && git remote update)
fi
(cd $GIT_DIR && git format-patch -N $GIT_UPSTREAM_TAG --suffix= -o $CMP_DIR >/dev/null)
QEMU_VERSION=`cat $GIT_DIR/VERSION`
echo "QEMU version: $QEMU_VERSION"

rm -rf $GIT_DIR

(
    CHANGED_COUNT=0
    UNCHANGED_COUNT=0
    DELETED_COUNT=0
    ADDED_COUNT=0

    shopt -s nullglob

# Process patches to eliminate useless differences: limit file names to 40 chars
# before extension and remove git signature. ('30' below gets us past dir prefix)
    for i in $CMP_DIR/*; do
        # format-patch may append a signature, which per default contains the git version
        # wipe everything starting from the signature tag
        sed '/^-- $/Q' $i > $CMP_DIR/${i:30:40}.patch
        rm $i
    done

    for i in 0???-*.patch; do
        if [ -e $CMP_DIR/$i ]; then
            if cmp -s $CMP_DIR/$i $i; then
                rm $CMP_DIR/$i
                let UNCHANGED_COUNT+=1
            else
                mv $CMP_DIR/$i .
                let CHANGED_COUNT+=1
            fi
        else
            osc rm --force $i
            let DELETED_COUNT+=1
            echo "  ${i##*/}" >> qemu.changes.deleted
        fi
    done

    for i in $CMP_DIR/*; do
        mv $i .
        osc add ${i##*/}
        let ADDED_COUNT+=1
        echo "  ${i##*/}" >> qemu.changes.added
    done

    for package in qemu qemu-linux-user; do
        while IFS= read -r line; do
            if [ "$line" = "PATCH_FILES" ]; then
                for i in 0???-*.patch; do
                    NUM=${i%%-*}
                    echo -e "Patch$NUM:      $i"
                done
            elif [ "$line" = "PATCH_EXEC" ]; then
                for i in 0???-*.patch; do
                    NUM=${i%%-*}
                    echo "%patch$NUM -p1"
                done
            elif [ "$line" = "QEMU_VERSION" ]; then
                echo "Version:        $QEMU_VERSION"
            elif [[ "$line" =~ ^Source: ]]; then
                QEMU_TARBALL=qemu-`echo "$line" | cut -d '-' -f 2-`
                VERSION_FILE=${QEMU_TARBALL%.tar.bz2}/roms/seabios/.version
                SEABIOS_VERSION=`tar jxfO "$QEMU_TARBALL" "$VERSION_FILE"`
                SEABIOS_VERSION=`echo $SEABIOS_VERSION | cut -d '-' -f 2`
                echo "$line"
            elif [ "$line" = "SEABIOS_VERSION" ]; then
                echo "Version:        $SEABIOS_VERSION"
            else
                echo "$line"
            fi
        done < $package.spec.in > $package.spec

        # Factory requires all deleted and added patches to be mentioned
        if [ -e qemu.changes.deleted ] || [ -e qemu.changes.added ]; then
            echo "Patch queue updated from ${GIT_TREE} ${GIT_BRANCH}" > $package.changes.proposed
        fi
        if [ -e qemu.changes.deleted ]; then
            echo "* Patches dropped:" >> $package.changes.proposed
            cat qemu.changes.deleted  >> $package.changes.proposed
        fi
        if [ -e qemu.changes.added ]; then
            echo "* Patches added:" >> $package.changes.proposed
            cat qemu.changes.added  >> $package.changes.proposed
        fi
        if [ -e $package.changes.proposed ]; then
            osc vc --file=$package.changes.proposed $package
            rm -f $package.changes.proposed
        fi
    done
    if [ -e qemu.changes.deleted ]; then
        rm -f qemu.changes.deleted
    fi
    if [ -e qemu.changes.added ]; then
        rm -f qemu.changes.added
    fi
    echo "git patch summary"
    echo "  unchanged: $UNCHANGED_COUNT"
    echo "    changed: $CHANGED_COUNT"
    echo "    deleted: $DELETED_COUNT"
    echo "      added: $ADDED_COUNT"
)

rm -rf $CMP_DIR

sed -e 's|^\(Name:.*qemu\)|\1-testsuite|' < qemu.spec > qemu-testsuite.spec
osc service localrun format_spec_file

/bin/sh pre_checkin.sh -q

echo "Please remember to run pre_checkin.sh after modifying qemu.changes."

#!/bin/bash -e
# Copyright (c) 2011-2017 SUSE LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

. update_git.cfg

cleanup()
{
    [ -z "$GIT_DIR" ] || rm -rf "$GIT_DIR"
    [ -z "$CMP_DIR" ] || rm -rf "$GIT_DIR"
}

trap cleanup EXIT

GIT_DIR=`mktemp -d --tmpdir update_git.XXXXXXXXXX`
CMP_DIR=`mktemp -d --tmpdir update_git.XXXXXXXXXX`

rm -f .update_git.*

: ${GIT_LOCAL_TREE:=${XDG_CACHE_HOME:-~/.cache}/update_git/${GIT_TREE##*/}}


echo "Processing $GIT_BRANCH branch of remote git tree, using tag:" \
     "$GIT_UPSTREAM_TAG"

if ! [ -d "$GIT_LOCAL_TREE" ]; then
    echo "Initializing cache at $GIT_LOCAL_TREE"

    git clone --bare $GIT_TREE $GIT_LOCAL_TREE
fi
echo "Updating cache ache $GIT_LOCAL_TREE"
(cd $GIT_LOCAL_TREE && git remote update)

echo "Processing $GIT_BRANCH branch of local git tree, using tag:" \
     "$GIT_UPSTREAM_TAG"
git clone -ls $GIT_LOCAL_TREE $GIT_DIR -b $GIT_BRANCH

(cd $GIT_DIR && git format-patch -N $GIT_UPSTREAM_TAG --suffix=.tmp -o $CMP_DIR >/dev/null)

CHANGED_COUNT=0
UNCHANGED_COUNT=0
DELETED_COUNT=0
ADDED_COUNT=0

shopt -s nullglob

patches=()
for i in $CMP_DIR/*.tmp; do
    basename="${i##*/}"
    newname=${basename%.tmp}
    newname=${newname%.diff} # remove .diff suffix it exist
    # limit file names to 40 chars before extension
    newname=${newname:0:40}.diff
    # remove git signature and commit hash to make content
    # independent of git version
    head -n -3 "$i" | tail -n +2 | sed -e '/^index .......\.\........ [0-9]\+/d' > "$CMP_DIR/$newname"
    rm "$i"
    localname=${newname#*-}
    patches+=("$localname")
    if [ -e "$localname" ]; then
	if cmp -s "$CMP_DIR/$newname" "$localname"; then
	    rm "$CMP_DIR/$newname"
	    let UNCHANGED_COUNT+=1
	else
	    mv "$CMP_DIR/$newname" "$localname"
	    let CHANGED_COUNT+=1
	fi
    else
	mv "$CMP_DIR/$newname" "$localname"
	let ADDED_COUNT+=1
	echo "  $localname" >> .update_git.changes.added
	osc add "$localname"
    fi
done

# delete dropped patches
for patch in *.diff; do
    keep=
    for i in "${patches[@]}"; do
	if [ "$i" = "$patch" ]; then
	    keep=1
	    break
	fi
    done
    if [ -z "$keep" ]; then
	osc rm --force $patch
	let DELETED_COUNT+=1
	echo "  $patch" >> .update_git.changes.deleted
    fi
done

for package in "${PACKAGES[@]}"; do
    skip=
    while IFS= read -r line; do
	if [ "$line" = "# PATCHLIST END" ]; then
	    skip=
	    i=0
	    for patch in "${patches[@]}"; do
		printf "Patch%02d:        %s\n" "$i" "$patch"
		let i+=1
	    done
	fi
	if [ -z "$skip" ]; then
	    echo "$line"
	fi
	if [ "$line" = "# PATCHLIST BEGIN" ]; then
	    skip=1
	fi
    done < $package.spec > $package.spec.new
    mv $package.spec.new $package.spec

    if [ -e .update_git.changes.deleted ]; then
	echo "* Patches dropped:" >> $package.changes.proposed
	cat .update_git.changes.deleted  >> $package.changes.proposed
    fi
    if [ -e .update_git.changes.added ]; then
	echo "* Patches added:" >> $package.changes.proposed
	cat .update_git.changes.added  >> $package.changes.proposed
    fi
    if [ -e $package.changes.proposed ]; then
	osc vc --file=$package.changes.proposed $package
	rm -f $package.changes.proposed
    fi
done
rm -f .update_git.*
echo "git patch summary"
echo "  unchanged: $UNCHANGED_COUNT"
echo "    changed: $CHANGED_COUNT"
echo "    deleted: $DELETED_COUNT"
echo "      added: $ADDED_COUNT"

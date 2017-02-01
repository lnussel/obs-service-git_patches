#!/bin/bash -e
#
# based on qemu's update_git.sh this program updates the patches
# applied on top of a tarball based on commmits in git
#
# how to use:
# quilt setup rpmlint.spec
# cp rpmlint-$RPMLINTVERSION/series .
# mkdir ~/git; cd ~/git
# git clone git://git.code.sf.net/p/rpmlint/code rpmlint-code
# git checkout -b opensuse-$RPMLINTVERSION v$RPMLINTVERSION
# git quiltimport --patches /where/rpmlint/checkout/is
# ... add/remove/rebase patches
# ... to rebase to a new version create branch and modify versions below
# when done run update_git.sh

GIT_TREE=https://github.com/lnussel/rpmlint-code.git
GIT_LOCAL_TREE=~/git/rpmlint-code
GIT_BRANCH=opensuse-1.8
GIT_UPSTREAM_TAG=rpmlint-1.8

cleanup()
{
    [ -z "$GIT_DIR" ] || rm -rf "$GIT_DIR"
    [ -z "$CMP_DIR" ] || rm -rf "$GIT_DIR"
}

trap cleanup EXIT

GIT_DIR=`mktemp -d --tmpdir update_git.XXXXXXXXXX`
CMP_DIR=`mktemp -d --tmpdir update_git.XXXXXXXXXX`

rm -f .update_git.*

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
             "named upstream for $GIT_TREE and update"
        (cd $GIT_DIR && git remote add upstream "$GIT_TREE")
        (cd $GIT_DIR && git remote update)
   fi
else
    echo "Processing $GIT_BRANCH branch of remote git tree, using tag:" \
         "$GIT_UPSTREAM_TAG"
    echo "(For much fast processing, consider establishing a local git tree" \
         "at $GIT_LOCAL_TREE)"
    git clone $GIT_TREE $GIT_DIR -b $GIT_BRANCH
    (cd $GIT_DIR && git remote add upstream "$GIT_TREE")
    (cd $GIT_DIR && git remote update)
fi
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
    head -n -3 "$i" | tail -n +2 > "$CMP_DIR/$newname"
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

for package in rpmlint; do
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

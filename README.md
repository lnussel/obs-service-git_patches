# Spec file patch management made easy

## Introduction

This script was originally developed by the qemu maintainers. It
updates the patches applied on top of a tarball based on commmits in
git

## Preparing the package

In the package checkout create a file update_git.cfg. Assuming a
fictional package hello with version 4.2 this may look like this

    PACKAGES=(hello)
    GIT_TREE=https://github.com/hello/hello.git
    GIT_LOCAL_TREE=~/git/hello
    GIT_BRANCH=opensuse-4.2
    GIT_UPSTREAM_TAG=v4.2

In the spec file add

    # PATCHLIST BEGIN

before the patches, resp

    # PATCHLIST END

after it.

Use %autosetup instead of %setup and delete all %patch lines.

## Creating a git repo based on spec

    quilt setup $PACKAGE.spec
    cp hello-$VERSION/series .
    mkdir ~/git; cd ~/git
    git clone git://github.com/project/package
    git checkout -b opensuse-$VERSION v$UPSTREAMVERSION
    git quiltimport --patches /where/$PACKAGE/checkout/is

All patches are now in git. You may want to use git rebase -i and
edit all patch summaries.

## Updating spec file based on git

To update the patch list in the spec file and update the changes
file with added and removed patches simply run

    update_git.sh

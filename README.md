# Spec file patch management made easy

## Introduction

This script was originally developed by the qemu maintainers. It
updates patches applied on top of a tarball based on commits in git.

The idea is to have the pristine upstream release tarball in the package. Any
changes to it need to be supplied as patch. In order to take advantage of all
the nifty git features it's still good to keep the patch series in git though.

The script here assume that the upstream revision of the software is tagged in
it and that the patches live in a branch on top of that tag.

In addition to handling the patches, the script will also update the .changes
file to list added and removed patches.

The script can be used standalone or as OBS service.

## Initializing a git repo based on the spec file

    quilt setup hello.spec
    cp hello-4.2/series .
    mkdir ~/git; cd ~/git
    git clone git://github.com/hello/hello
    git checkout -b v4.2-opensuse v4.2
    git quiltimport --patches /where/hello/checkout/is

All patches are now in git. You may want to use git rebase -i and
edit all patch summaries to have useful patch names.

## Preparing the package

There are two ways to have patches listed. Either in the spec file
itself, or in an include file. By default inline patch list is
expected. For that case add

    # PATCHLIST BEGIN

before the patches, resp

    # PATCHLIST END

after it.

For the external patch list mode, use %include to include the
generated patch list. It's named $packagename-git_patches.inc. So in
a spec file one would use e.g.

    %include %{_sourcedir}/hello-git_patches.inc

In both cases use %autopatch or %autosetup (instead of %setup) and
delete all %patch lines.

### Standalone Mode

In the package checkout create a file update_git.cfg. Assuming a
fictional package hello with version 4.2 this may look like this

    PACKAGES=(hello)
    GIT_TREE=https://github.com/hello/hello.git
    GIT_BRANCH=v4.2-opensuse
    GIT_UPSTREAM_TAG=v4.2

To enable an external patch list use

    GIT_EXTERNAL_PATCHLIST=yes

In order to update the patches in the package run

    update_git.sh

### OBS service mode

Create a _service file:

    <services>
      <service name="git_patches" mode="disabled">
        <param name="url">https://github.com/hello/hello.git</param>
        <param name="branch">v4.2-opensuse</param>
        <param name="upstream_tag">4.2</param>
      </service>
    </services>

To enable an external patch list use

    <param name="patchfile">enable</param>

In order to update the patches in the package run

    osc service dr

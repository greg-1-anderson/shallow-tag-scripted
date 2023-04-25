#!/bin/bash

set -ex

WORK="$HOME/tmp/shallow-tag-work"

SIMULATED_EXTERNAL="$WORK/simulated-external"
SIMULATED_PANTHEON="$WORK/simulated-pantheon"

SIMULATED_HYBRID="$WORK/simulated-hybrid"

SIMULATED_FIXED="$WORK/simulated-pantheon-fixed"
SIMULATED_SIB="$WORK/simulated-sib"
SCRATCH_EXTERNAL_GIT_DIR="$WORK/scratch-external-git-dir"

rm -rf $WORK
mkdir -p $WORK


# This is our simulated external repository.
SIMULATED_EXTERNAL_URL=https://github.com/namespacebrian/drupal-10-composer-managed-upstream.git
# git clone $SIMULATED_EXTERNAL_URL --depth=1 $SIMULATED_EXTERNAL

SIMULATED_PANTHEON_URL=ssh://codeserver.dev.5671ead7-32a5-4b01-9e15-179e50bb5b43@codeserver.dev.5671ead7-32a5-4b01-9e15-179e50bb5b43.drush.in:2222/~/repository.git
# This is opur simulated Pantheon repository. It's a real Pantheon repository, but we'll use our local working copy as our remote.
git clone $SIMULATED_PANTHEON_URL $SIMULATED_PANTHEON

# Make a work dir that is like the SIB image
mkdir -p $SIMULATED_SIB

# Make a work dir JUST for the .git dir of the external repo's local working copy
SCRATCH_EXTERNAL_GIT_DIR=$WORK/

(
	# These are the steps that the SIB does to pull from the code server.
	# We need to pull the files first, even if we are not going to use them,
	# because we need to initialize the .git local working copy to point to
	# HEAD of the working branch. Note that in SIB, the code to set up the
	# initial code pull is the same for internal (codeserver) and external
	# repositories alike.
	cd $SIMULATED_SIB
	git init
	# git config user.email & user.name
	git remote add origin "$SIMULATED_PANTHEON"
	# git config to set the binding cert and ca cert
	# git pull --depth=1 "$SIMULATED_PANTHEON" master
	git fetch --depth=1 origin master
	git checkout master

	###
	### Hack to pull the files from the external repository. We are going
	### to grab just the files without modifying our local working copy at
	### all; we want that to still be set up to point at the code server,
	### so that SJS can pull and push artifact tags there.
	###

	# Clean everything in our local working repo EXCEPT FOR .git
	# (hack just delete the dot files we know happen to be there, because I am lazy)
	rm -rf *
	rm -f .gitattributes
	rm -f .gitignore

	# Make another local working copy to pull external repo to
	mkdir -p "$SCRATCH_EXTERNAL_GIT_DIR"
	(cd "$SCRATCH_EXTERNAL_GIT_DIR" && git init)

	# Note that .git dir of scratch external working copy is modified,
	# but the FILES pulled end up at the cwd
	git --git-dir="$SCRATCH_EXTERNAL_GIT_DIR/.git" pull --depth=1 "$SIMULATED_EXTERNAL_URL" main

	# We need to commit the files on top of the HEAD commit from the code
	# server so that our shenanigans below work correctly. It would be
	# cool if we also grabbed the author and comment from the top commit
	# of the external repo. Note that if we wanted these commit comments
	# to display on the dashboard too, that there are potentially multiple
	# commits in the external repo, and we'd have to pull at a greater depth
	# to get them all. How deep? :shrug:
	git add -fA .
	git commit -m "Stuff from external repo"

	# `git pull` switches our branch to the branch we pulled? Hm. Go back to `master`.
	# Most of the time these branches should be the SAME, but not for the fixtures I picked. :p
	# Probably won't need to ever do anything like this in actual SIB code.
	git checkout -B master

	###
	### End SIB PoC hacky hack.
	###

	# This way also worked, but was not very much like the SIB process
	#git init
	#git pull --depth=1 $SIMULATED_EXTERNAL_URL main
	#rm -rf .git
	#cp -R $SIMULATED_PANTHEON/.git $SIMULATED_HYBRID
	#git add -fA .
	#git commit -m "Stuff from external repo"

	# Now we start doing the steps that SJS does
	git fetch --depth=1 origin tag pantheon_build_artifacts_master

	# Here is the part that we do in "standard" SJS that we do not do in "ICR" SJS
	# I found it unnecessary to remove this; this script seems to work the same
	# with and without this step. It neither helps nor hurts.
	git fetch --depth=1 origin master

	BUILD_FROM_SHA=$(git rev-parse HEAD)

	echo "Should not be much here yet"
	ls web

	git checkout pantheon_build_artifacts_master

	echo "Now we should see a Drupal site"
	ls web

	# Here's the optimization thing
	git reset --soft $BUILD_FROM_SHA
	git reset HEAD *
	git reset --hard
	git clean -ffd

	echo "Is autoload an ignored file?"
	git check-ignore vendor/autoload.php || echo "autoload.php not ignored"
	echo "----"

	# Composer install
	composer --no-interaction --no-progress --prefer-dist --ansi install

	# tag derivative build artifacts
	echo "In theory, we want git status to be clean here"
	git status --porcelain

	###
	### At this point, we have all of the files we need for our build in place.
	### HOWEVER, since we pulled them in as shallow clones, we cannot tag and
	### then push the tag out to the origin. We need to fix things.
	###
	### Simply including `git fetch origin master` here does not help; the
	### problem is that our "external" repo does not share commits with the
	### "pantheon" repo. We can work around this by ensuring that our artifact
	### tag's parent is the HEAD of the branch on the "pantheon" repo instead
	### of HEAD of the "external" repo.
	###

	# This 'git clone' hack did fix things up in the context of SJS, but we'd rather not fix things up here
#	CODESERVER_URL=$(git config --get remote.origin.url)
#	git clone --depth=1 $CODESERVER_URL $SIMULATED_FIXED
#	rm -rf .git
#	mv -f $SIMULATED_FIXED/.git .

	# This, in theory does a checkout without changing the working files, but this was not sufficient
#	git symbolic-ref HEAD refs/heads/master
#	git reset

	#echo "In theory, we are still clean here"
	#git status --porcelain

	# SJS simulated process continues here

	git add -fA .

	git commit -m "Build artifacts added by simulated Pantheon"
	BUILT_SHA=$(git rev-parse HEAD)
	git tag -f -m "Build artifacts added by simulated Pantheon from commit $BUILD_FROM_SHA" pantheon_build_artifacts_master $BUILT_SHA

	# Looks like site job scripts does not force push the tag, but that SHOULD be necessary, since the tag already exists, right?
	git push -f origin pantheon_build_artifacts_master
)

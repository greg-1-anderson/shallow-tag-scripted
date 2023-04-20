#!/bin/bash

set -ex

WORK="$HOME/tmp/shallow-tag-work"

SIMULATED_EXTERNAL="$WORK/simulated-external"
SIMULATED_PANTHEON="$WORK/simulated-pantheon"

SIMULATED_FIXED="$WORK/simulated-pantheon-fixed"

rm -rf $WORK
mkdir -p $WORK


# This is our simulated external repository.
SIMULATED_EXTERNAL_URL=https://github.com/namespacebrian/drupal-10-composer-managed-upstream.git
git clone $SIMULATED_EXTERNAL_URL --depth=1 $SIMULATED_EXTERNAL

SIMULATED_PANTHEON_URL=ssh://codeserver.dev.5671ead7-32a5-4b01-9e15-179e50bb5b43@codeserver.dev.5671ead7-32a5-4b01-9e15-179e50bb5b43.drush.in:2222/~/repository.git
# This is opur simulated Pantheon repository. It's a real Pantheon repository, but we'll use our local working copy as our remote.
git clone $SIMULATED_PANTHEON_URL $SIMULATED_PANTHEON

(
	# Configure our simulated repo such that its "origin" points at our simulated
	# pantheon repo. We'll also keep the original "origin" as "external", although
	# this remote does not exist on Pantheon
	cd $SIMULATED_EXTERNAL
	git remote rename origin external
	git remote add origin $SIMULATED_PANTHEON
	git checkout -b master

	# Now we start doing the steps that SJS does
	git fetch --depth=1 origin tag pantheon_build_artifacts_master

	# Here is the part that we do in "standard" SJS that we do not do in "ICR" SJS
	# I found it unnecessary to remove this; this script seems to work the same
	# with and without this step. It neither helps nor hurts.
	git fetch --depth=1 origin master

	BUILD_FROM_SHA=$(git rev-parse master)

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

	CODESERVER_URL=$(git config --get remote.origin.url)
	git clone --depth=1 $CODESERVER_URL $SIMULATED_FIXED
	rm -rf .git
	mv -f $SIMULATED_FIXED/.git .

	# This, in theory does a checkout without changing the working files, but it did not work.
#	git symbolic-ref HEAD refs/heads/master
#	git reset

	echo "In theory, we are still clean here"
	git status --porcelain

	# SJS simulated process continues here

	git add -fA .

	git commit -m "Build artifacts added by simulated Pantheon"
	BUILT_SHA=$(git rev-parse HEAD)
	git tag -f -m "Build artifacts added by simulated Pantheon from commit $BUILD_FROM_SHA" pantheon_build_artifacts_master $BUILT_SHA

	# Looks like site job scripts does not force push the tag, but that is necessary, since the tag already exists, right?
	git push -f origin pantheon_build_artifacts_master
)

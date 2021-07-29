#!/bin/sh -l

set -e  # stops execution
set -u  # undefined variable

echo "Cloning git repository"
git config --global user.name "${GIT_USER}"
git config --global user.email "${GIT_EMAIL}"
mkdir /tmp/git
git clone --single-branch --branch "$TARGET_BRANCH" "https://$GIT_USER:$GIT_USER_API_TOKEN@github.com/$REPOSITORY_USERNAME/$REPOSITORY_NAME.git" /tmp/git
cd /tmp/git
echo Test > testfile
git add -A
git diff --cached
git commit -m "Test commit ${TAG}"
git push
git log -2

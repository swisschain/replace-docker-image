#!/bin/sh -l

set -e  # stops execution
set -u  # undefined variable

echo "Cloning git repository"
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"
mkdir /tmp/git
git clone --single-branch --branch "$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH" "https://x-access-token:$GIT_USER_API_TOKEN@github.com/$GIT_INFRASTRUCTURE_REPOSITORY_OWNER/$GIT_INFRASTRUCTURE_REPOSITORY_NAME.git" /tmp/git
cd /tmp/git
#
TAG=$(echo ${GITHUB_REF} | sed -e "s/refs\/tags\/${INPUT_TAG_NAME_SKIP}//")
DOCKER_IMAGE=$(printf "%s/%s" $DOCKER_REPOSITORY_NAME $DOCKER_IMAGE_NAME)
echo DOCKER_IMAGE=$DOCKER_IMAGE
DOCKER_IMAGE_SLASH=$(echo ${DOCKER_IMAGE} | sed 's#/#\\/#g')
echo DOCKER_IMAGE_SLASH=${DOCKER_IMAGE_SLASH}
#
for YAML_FILE in $(grep -rn $DOCKER_IMAGE: ./ | awk -F: '{print $1}')
do
  echo Processing $YAML_FILE
  sed -E "s/${DOCKER_IMAGE_SLASH}:.+$/${DOCKER_IMAGE_SLASH}:${TAG}/" ${YAML_FILE} > ${YAML_FILE}.tmp
  mv ${YAML_FILE}.tmp ${YAML_FILE}
done
#
git add -A
git diff --cached
git commit -m "$GIT_REPOSITORY_NAME ${TAG}"
git push
git log -2

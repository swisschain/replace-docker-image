#!/bin/sh -l

#set -e  # stops execution
set -u  # undefined variable

echo "Set git globals"
git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"
clone_commit_push() {
  (
  if [ -d /tmp/git ]; then 
    echo Temp Directory exist - remove
    rm -r /tmp/git
    echo Create New Temp Directory
    mkdir /tmp/git
  else
    echo Create Temp Directory
    mkdir /tmp/git
  fi
  echo "Cloning git repository (branch=$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH, owner=$GIT_INFRASTRUCTURE_REPOSITORY_OWNER, name=$GIT_INFRASTRUCTURE_REPOSITORY_NAME)"
  if ! git clone --single-branch --branch "$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH" "https://x-access-token:$GIT_USER_API_TOKEN@github.com/$GIT_INFRASTRUCTURE_REPOSITORY_OWNER/$GIT_INFRASTRUCTURE_REPOSITORY_NAME.git" /tmp/git;then
    echo "Git clone failed"
    exit 1
  fi
  echo "Go to git repository dir"
  cd /tmp/git
  
  if [ -z "$CREATE_PR" ];then
    CREATE_PR=false
  fi
  
  if [ $CREATE_PR = true ];then
    HEAD_GIT_BRANCH=$(printf "%s-v%s" $DOCKER_IMAGE_NAME $TAG)
    echo "Switching branch to $HEAD_GIT_BRANCH"
    git checkout -b $HEAD_GIT_BRANCH
  else
    HEAD_GIT_BRANCH=$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH
  fi
  #
  echo "Set tag"
  echo INPUT_TAG_NAME_SKIP=${INPUT_TAG_NAME_SKIP}
  TAG=$(echo ${GITHUB_REF} | sed -e "s/refs\/tags\/${INPUT_TAG_NAME_SKIP}//")
  echo "Set docker image"
  echo TAG=${TAG}
  if echo ${TAG} | grep refs;then
    echo "Get TAG failed"
    exit 1
  fi
  DOCKER_IMAGE=$(printf "%s/%s" $DOCKER_REPOSITORY_NAME $DOCKER_IMAGE_NAME)
  echo DOCKER_IMAGE=$DOCKER_IMAGE
  echo "Set docker image with slash"
  DOCKER_IMAGE_SLASH=$(echo ${DOCKER_IMAGE} | sed 's#/#\\/#g')
  echo DOCKER_IMAGE_SLASH=${DOCKER_IMAGE_SLASH}
  #
  echo "Start processing"
  for YAML_FILE in $(grep -rn $DOCKER_IMAGE: ./ | awk -F: '{print $1}')
  do
    echo Processing $YAML_FILE
    sed -i "s/${DOCKER_IMAGE_SLASH}:.*/${DOCKER_IMAGE_SLASH}:${TAG}/" ${YAML_FILE}
  done
  #
  echo "Add changed file to git"
  git add -A
  echo "Show changes"
  git diff --cached
  echo "Commit to git"
  git commit -m "$GIT_REPOSITORY_NAME ${TAG}"
  #echo Sleep 60
  #sleep 60
  echo "Push to git"
  if ! git push --set-upstream origin $HEAD_GIT_BRANCH;then
    echo "Git push failed"
    exit 1
  fi
  echo $? > /tmp/exit_status
  echo "Changes log"
  git log -2
  #
  if [ $CREATE_PR = true ];then
    echo "Creating PR..."
    PR_TITLE=$(printf "%s %s" $DOCKER_IMAGE_NAME $TAG)
    PR_BODY=$(printf "%s %s update" $DOCKER_IMAGE_NAME $TAG)
    PR_URL="https://api.github.com/repos/${GIT_INFRASTRUCTURE_REPOSITORY_OWNER}/${GIT_INFRASTRUCTURE_REPOSITORY_NAME}/pulls"
    PR_DATA='{"title":"${PR_TITLE}","body":"${PR_BODY}","head":"${HEAD_GIT_BRANCH}","base":"${GIT_INFRASTRUCTURE_REPOSITORY_BRANCH}"}'
    
    echo "PR title: $PR_TITLE"
    echo "PR body: $PR_BODY"
    echo "PR URL: $PR_URL"
    echo "PR data: $PR_DATA"
    
    if ! curl -L \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GIT_USER_API_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        $PR_URL \
        -d $PR_DATA;then
      echo "PR creation failed"
      exit 1
    fi
  fi
  ) > /tmp/clone_commit_push.log 2>&1
}
if ! clone_commit_push;then
  echo "Print Log F0"
  cat /tmp/clone_commit_push.log
  echo "Update-Not-Success"
  exit 1
fi
exit_code=$(cat /tmp/exit_status)
if [ "$exit_code" -eq 1 ]; then
  echo "Print Log F1"
  cat /tmp/clone_commit_push.log
  echo "Update-Not-Success try again"
  clone_commit_push
  exit_code_2=$(cat /tmp/exit_status)
  if [ "$exit_code_2" -eq 1 ]; then
    echo "Print Log F2"
    cat /tmp/clone_commit_push.log
    echo "Update-Not-Success"
    exit 1
  fi
else
  echo "Print Log S1"
  cat /tmp/clone_commit_push.log
  echo "Success-Update"
  exit 0
fi

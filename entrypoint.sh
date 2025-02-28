#!/bin/sh -l

#set -e  # stops execution
set -u  # fail on undefined variables

CREATE_PR=${CREATE_PR:-false}

echo "Configuring git globals..."

git config --global user.name "${GIT_USER_NAME}"
git config --global user.email "${GIT_USER_EMAIL}"

process() {
  (
  # Temp dir preparation
  if [ -d /tmp/git ]; then 
    echo "Temp dir found. Removing"
    rm -r /tmp/git
    echo "Creating new temp dir"
    mkdir /tmp/git
  else
    echo "Creating temp dir"
    mkdir /tmp/git
  fi
  
  # Cloning the repo
  echo "Cloning git repository (branch=$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH, owner=$GIT_INFRASTRUCTURE_REPOSITORY_OWNER, name=$GIT_INFRASTRUCTURE_REPOSITORY_NAME)"
  if ! git clone --single-branch --branch "$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH" "https://x-access-token:$GIT_USER_API_TOKEN@github.com/$GIT_INFRASTRUCTURE_REPOSITORY_OWNER/$GIT_INFRASTRUCTURE_REPOSITORY_NAME.git" /tmp/git; then
    echo "Git clone failed"
    exit 1
  fi

  cd /tmp/git

  # Building the tag
  echo "Building tag"
  echo INPUT_TAG_NAME_SKIP=${INPUT_TAG_NAME_SKIP}
  TAG=$(echo ${GITHUB_REF} | sed -e "s/refs\/tags\/${INPUT_TAG_NAME_SKIP}//")
  
  echo "Tag=${TAG}"
  if echo ${TAG} | grep refs; then
    echo "Tag building failed"
    exit 1
  fi

  # Switching branch if PR creation is requested
  if [ "$CREATE_PR" = "true" ]; then
    HEAD_GIT_BRANCH=$(printf "%s-v%s" $GIT_REPOSITORY_NAME $TAG)
    echo "Switching git branch to $HEAD_GIT_BRANCH"
    if ! git checkout -b $HEAD_GIT_BRANCH; then
      echo "Git checkout failed"
      exit 1
    fi
  else
    HEAD_GIT_BRANCH=$GIT_INFRASTRUCTURE_REPOSITORY_BRANCH
  fi
  
  echo "Head git branch $HEAD_GIT_BRANCH"
  
  # Processing docker image names
  
  for DOCKER_IMAGE_NAME_ITEM in $(echo $DOCKER_IMAGE_NAME | tr "," "\n")
  do
    DOCKER_IMAGE=$(printf "%s/%s" $DOCKER_REPOSITORY_NAME $DOCKER_IMAGE_NAME_ITEM)
    echo DOCKER_IMAGE=$DOCKER_IMAGE

    DOCKER_IMAGE_SLASH=$(echo ${DOCKER_IMAGE} | sed 's#/#\\/#g')
    echo "Full docker image=${DOCKER_IMAGE_SLASH}"

    for YAML_FILE in $(grep -rn $DOCKER_IMAGE: ./ | awk -F: '{print $1}')
    do
        echo "Processing $YAML_FILE"
        sed -i "s/${DOCKER_IMAGE_SLASH}:.*/${DOCKER_IMAGE_SLASH}:${TAG}/" ${YAML_FILE}
    done
  done
  
  # Adding changed files to git
  echo "Add changed files to git"
  git add -A
  
  echo "Changes:"
  git diff --cached
  
  echo "Committing to git"
  git commit -m "$GIT_REPOSITORY_NAME ${TAG}"
  
  echo "Pushing to git"
  if ! git push --set-upstream origin $HEAD_GIT_BRANCH; then
    echo "Git push failed"
    exit 1
  fi
  echo $? > /tmp/exit_status
  
  echo "Git changes log:"
  git log -2
  
  # Creating GitHub PR
  if [ "$CREATE_PR" = "true" ]; then
    echo "Creating PR"
    
    PR_TITLE=$(printf "%s %s" $GIT_REPOSITORY_NAME $TAG)
    PR_BODY=$(printf "%s %s update" $GIT_REPOSITORY_NAME $TAG)
    PR_URL="https://api.github.com/repos/${GIT_INFRASTRUCTURE_REPOSITORY_OWNER}/${GIT_INFRASTRUCTURE_REPOSITORY_NAME}/pulls"
    PR_DATA="{\"title\":\"${PR_TITLE}\",\"body\":\"${PR_BODY}\",\"head\":\"${HEAD_GIT_BRANCH}\",\"base\":\"${GIT_INFRASTRUCTURE_REPOSITORY_BRANCH}\"}"
    
    echo "PR title: $PR_TITLE"
    echo "PR body: $PR_BODY"
    echo "PR URL: $PR_URL"
    echo "PR data: $PR_DATA"
    
    if ! PR_CREATION_RESPONSE=$(curl -L \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GIT_USER_API_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        --write-out '%{http_code}' \
        --silent \
        --output "/dev/null" \
        -d "$PR_DATA" \
        $PR_URL); then
      echo "PR creation CURL execution failed"
      exit 1
    fi
    
    echo "PR creation http status code: $PR_CREATION_RESPONSE" 
       
    if [ "$PR_CREATION_RESPONSE" -ne 200 ]; then
      echo "PR creation failed"
      exit 1
    fi    
  fi
  ) > /tmp/process.log 2>&1
}

if ! process; then
  echo "Failed to process. Log:"
  cat /tmp/process.log
  exit 1
else
  echo "Processing done. Log:"
  cat /tmp/process.log
fi

exec "$@"
#!/bin/bash
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

GITHUB_REPO=https://github.com/$MY_GITHUB_USER/tssc-dev-gitops
GITLAB_REPO=https://gitlab.com/$MY_GITLAB_USER/tssc-dev-gitops
JENKINS_REPO=https://github.com/$MY_GITHUB_USER/tssc-dev-gitops-jenkins

WORK=$(mktemp -d)

GH_LOCAL=$WORK/gh-gitops
GL_LOCAL=$WORK/gl-gitops
J_LOCAL=$WORK/j-gitops
git clone $GITHUB_REPO $GH_LOCAL --quiet
git clone $GITLAB_REPO $GL_LOCAL --quiet
git clone $JENKINS_REPO $J_LOCAL --quiet
WATCH=components/tssc-dev/overlays/development/deployment-patch.yaml
function getImage() {
    (
        cd $1
        yq .spec.template.spec.containers[0].image $WATCH
    )
}

# Note, the env var name PREV_IMAGE_ENV_NAME is passed so it can be updated
function promoteIfUpdated() {
    PREV_IMAGE_ENV_NAME=$1
    CURRENT_IMAGE=$2
    REPO=$3

    echo "$REPO"
    echo "P: ${!PREV_IMAGE_ENV_NAME}"
    echo "C: $CURRENT_IMAGE"

    if [[ "${!PREV_IMAGE_ENV_NAME}" != "$CURRENT_IMAGE" ]]; then
        echo "$REPO being updated from ${!PREV_IMAGE_ENV_NAME} to $CURRENT_IMAGE"
        bash $SCRIPTDIR/rhtap-promote --repo $REPO
        eval "$PREV_IMAGE_ENV_NAME"="$CURRENT_IMAGE"
    fi
}
function pushIfUpdated() {
    PREV_IMAGE_ENV_NAME=$1
    CURRENT_IMAGE=$2
    REPO=$3

    echo "$REPO"
    echo "P: ${!PREV_IMAGE_ENV_NAME}"
    echo "C: $CURRENT_IMAGE"

    if [[ "${!PREV_IMAGE_ENV_NAME}" != "$CURRENT_IMAGE" ]]; then
        echo "$REPO  being updated from ${!PREV_IMAGE_ENV_NAME} to $CURRENT_IMAGE"
        bash $SCRIPTDIR/rhtap-push-dev --repo $REPO
        eval "$PREV_IMAGE_ENV_NAME"="$CURRENT_IMAGE"
    fi
}

GH_PREV=$(getImage $GH_LOCAL)
GL_PREV=$(getImage $GL_LOCAL)
J_PREV=$(getImage $J_LOCAL)
# count down and reprint the messages
COUNT=0
while true; do
    if [[ $COUNT == 0 ]]; then
        COUNT=10
        echo
        echo "Github Repo: $GITHUB_REPO"
        echo "Waiting for Github image $GH_PREV to be updated"
        echo
        echo "Gitlab Repo: $GITLAB_REPO"
        echo "Waiting for Gitlab image $GL_PREV to be updated"
        echo
        echo "Jenkins Repo: $JENKINS_REPO"
        echo "Waiting for Jenkins image $J_PREV to be updated"
    fi
    let COUNT--

    echo "Checking repo contents ..."
    for repo in $GH_LOCAL $GL_LOCAL $J_LOCAL; do
        (
            cd $repo
            git pull --quiet
        )
    done
    # pass the var name to hold the previus value so it can be updated
    GH_CURRENT=$(getImage $GH_LOCAL)
    promoteIfUpdated GH_PREV $GH_CURRENT $GITHUB_REPO
    GL_CURRENT=$(getImage $GL_LOCAL)
    promoteIfUpdated GL_PREV $GL_CURRENT $GITLAB_REPO
    J_CURRENT=$(getImage $J_LOCAL)
    pushIfUpdated J_PREV $J_CURRENT $JENKINS_REPO
    SLEEP=10
    echo "Sleep..."
    while [[ $SLEEP != 0 ]]; do
        sleep 1
        echo -n "$SLEEP."
        let SLEEP--
    done

done

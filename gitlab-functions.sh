#!/bin/bash



function create_or_update_gitlab_group() {

  GITLAB_GROUP_NAME=$GITLAB_GROUP_PREFIX$GITHUB_ORGANIZATION
  GITLAB_GROUP_DESC=$GITHUB_ORGA_DESC
  GITLAB_GROUP_AVATAR_URL=$GITHUB_ORGA_AVATAR_URL # gitlab API does not support it yet

  # check the $GITLAB_GROUP_NAME exists or not
  # create it if necessary and update its description
  # https://docs.gitlab.com/ee/api/groups.html#details-of-a-group
  GITLAB_GROUP_EXISTS=$(curl -s -H "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -o /dev/null -s -w "%{http_code}\n" -X GET $GITLAB_HTTP_BASEURL/api/v4/groups/$GITLAB_GROUP_NAME)
  if [ "$GITLAB_GROUP_EXISTS" == "404" ]; then
    echo "-> Gitlab $GITLAB_GROUP_NAME group does not exists, create it !"
    # https://docs.gitlab.com/ee/api/groups.html#new-group
    curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X POST \
       --form "name=$GITLAB_GROUP_NAME" \
       --form "path=$GITLAB_GROUP_NAME" \
       --form "description=$GITLAB_GROUP_DESC (backup de $GITHUB_ORGA_URL)" \
       --form "visibility=public" \
       --form "avatar_url=$GITLAB_GROUP_AVATAR_URL" \
       $GITLAB_HTTP_BASEURL/api/v4/groups
  fi
  # update the gitlab group properties (name, description, visibility...)
  # https://docs.gitlab.com/ee/api/groups.html#update-group
  curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X PUT \
     --form "name=$GITLAB_GROUP_NAME" \
     --form "description=$GITLAB_GROUP_DESC (backup de $GITHUB_ORGA_URL)" \
     --form "visibility=public" \
     --form "avatar_url=$GITLAB_GROUP_AVATAR_URL" \
     $GITLAB_HTTP_BASEURLapi/v4/groups/$GITLAB_GROUP_NAME

  # retrieve the gitlab group id
  curl -s -H "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X GET \
     $GITLAB_HTTP_BASEURL/api/v4/groups/$GITLAB_GROUP_NAME \
     >/usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/GITLAB_GROUP_INFO.json
  GITLAB_GROUP_ID=$(jq -r .id /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/GITLAB_GROUP_INFO.json)
  if [ "$GITLAB_GROUP_ID" == "" ]; then
    echo "Fatal error: GITLAB_GROUP_ID should not be empty !"
    exit 1
  fi
}

function create_or_update_gitlab_projects() {


  for GITLAB_PROJECT_NAME in $GITHUB_REPOS_NAMES
  do

    GITHUB_CU=$(cat /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$GITLAB_PROJECT_NAME.cu.txt)
    GITHUB_DESC=$(cat /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$GITLAB_PROJECT_NAME.desc.txt)
    GITHUB_DESC=$([ "$GITHUB_DESC" = "null" ] && echo "" || echo $GITHUB_DESC)
    GITHUB_HOME=$(cat /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$GITLAB_PROJECT_NAME.home.txt)
    GITHUB_HOME=$([ "$GITHUB_HOME" = "null" ] && echo "" || echo $GITHUB_HOME)
    GITHUB_URL=$(cat /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$GITLAB_PROJECT_NAME.url.txt)
    GITHUB_URL=$([ "$GITHUB_URL" = "null" ] && echo "" || echo $GITHUB_URL)

    # check the $GITLAB_PROJECT_NAME exists or not
    # create it if necessary and update its description 
    # https://docs.gitlab.com/ee/api/projects.html#create-project
    GITLAB_PROJECT_EXISTS=$(curl -s -H "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -o /dev/null -s -w "%{http_code}\n" -X GET $GITLAB_HTTP_BASEURL/api/v4/projects/${GITLAB_GROUP_NAME}%2F${GITLAB_PROJECT_NAME})
    if [ "$GITLAB_PROJECT_EXISTS" == "404" ]; then
      echo "-> Gitlab $GITLAB_GROUP_NAME/$GITLAB_PROJECT_NAME project does not exists, create it !"
      curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X POST \
           --form "namespace_id=$GITLAB_GROUP_ID" \
           --form "name=$GITLAB_PROJECT_NAME" \
           --form "path=$GITLAB_PROJECT_NAME" \
           --form "description=$GITHUB_DESC $GITHUB_HOME (backup de $GITHUB_URL)" \
           --form "visibility=public" \
           --form "archived=false" \
           --form "merge_requests_enabled=false" \
           --form "issues_enabled=false" \
           --form "wiki_enabled=true" \
           --form "snippets_enabled=false" \
           --form "jobs_enabled=false" \
           $GITLAB_HTTP_BASEURL/api/v4/projects
    fi
    # update the gitlab project properties
    LOCAL_CLONE_FOLDER=$(basename $GITHUB_CU)
    curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X PUT \
         --form "namespace_id=$GITLAB_GROUP_ID" \
         --form "name=$GITLAB_PROJECT_NAME" \
         --form "description=$GITHUB_DESC $GITHUB_HOME (backup de $GITHUB_URL)" \
         --form "visibility=public" \
         --form "archived=false" \
         --form "merge_requests_enabled=false" \
         --form "issues_enabled=false" \
         --form "wiki_enabled=true" \
         --form "snippets_enabled=false" \
         --form "jobs_enabled=false" \
         $GITLAB_HTTP_BASEURL/api/v4/projects/${GITLAB_GROUP_NAME}%2F${GITLAB_PROJECT_NAME} \
         >/usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$LOCAL_CLONE_FOLDER/GITLAB_PROJECT_INFO.json

    # force the gitlab project to be unarchived
    # because if it is archived we cannot push to the wiki git repository
    curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X POST \
      $GITLAB_HTTP_BASEURL/api/v4/projects/${GITLAB_GROUP_NAME}%2F${GITLAB_PROJECT_NAME}/unarchive >/dev/null

    echo ""
  done # $GITHUB_REPOS_NAMES loop

}

function create_ssh_key_for_gitlab_push() {

  echo "-> Creating or updating deploy keys on gitlab projects"

  for GITLAB_PROJECT_NAME in $GITHUB_REPOS_NAMES
  do

    # generate a dedicated ssh key for each projects
    # because gitlab do not allow to reuse a ssh key between projects
    # see {"message":{"deploy_key.fingerprint":["has already been taken"]}}
    # these keys will be used to push/mirror on the gitlab repositories thanks to the git command
    if [ ! -f ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME ]; then
      ssh-keygen -t rsa -f ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME -q -P ""
      echo "StrictHostKeyChecking no" > ~/.ssh/config
    fi

    # search for the existing deploy key and update or create it
    GITLAB_DEPLOY_KEY_ID=$(curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X GET \
      $GITLAB_HTTP_BASEURL/api/v4/projects/$GITLAB_GROUP_NAME%2F$GITLAB_PROJECT_NAME/deploy_keys/ \
      | jq -r ".[] | select(.title == \"$GITLAB_GROUP_NAME\") | .id | select (.!=null)")
    if [ "$GITLAB_DEPLOY_KEY_ID" != "" ]; then
      GITLAB_DEPLOY_KEY=$(curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X GET \
      $GITLAB_HTTP_BASEURL/api/v4/projects/$GITLAB_GROUP_NAME%2F$GITLAB_PROJECT_NAME/deploy_keys/$GITLAB_DEPLOY_KEY_ID \
      | jq -r ".key | select (.!=null)")
      
      # update the existing gitlab project deploy key only if necessary
      if [ "$GITLAB_DEPLOY_KEY" != "$(cat ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME.pub)" ]; then
        echo "--> Update the gitlab deply key for $GITLAB_GROUP_NAME/$GITLAB_PROJECT_NAME"
        curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X DELETE \
          $GITLAB_HTTP_BASEURL/api/v4/projects/$GITLAB_GROUP_NAME%2F$GITLAB_PROJECT_NAME/deploy_keys/$GITLAB_DEPLOY_KEY_ID
        curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X POST \
          --form "can_push=true" \
          --form "key=$(cat ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME.pub)" \
          --form "title=$GITLAB_GROUP_NAME" \
          $GITLAB_HTTP_BASEURL/api/v4/projects/$GITLAB_GROUP_NAME%2F$GITLAB_PROJECT_NAME/deploy_keys/ \
          >/tmp/ezmaster-globs_gitlab_deploy_keys_post.log
      fi

    else
      # create a totally new deploy key for this gitlab project
      curl -s --header "Private-Token: $GITLAB_PERSONAL_ACCESS_TOKEN" -X POST \
        --form "can_push=true" \
        --form "key=$(cat ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME.pub)" \
        --form "title=$GITLAB_GROUP_NAME" \
        $GITLAB_HTTP_BASEURL/api/v4/projects/$GITLAB_GROUP_NAME%2F$GITLAB_PROJECT_NAME/deploy_keys/ \
        >/tmp/ezmaster-globs_gitlab_deploy_keys_post.log
    fi

  done
}

function do_gitlab_mirrors() {

  # all the repositories are clonned locally
  # we have to add remote gitlab repository
  # and push/mirror to it
  for GITLAB_PROJECT_NAME in $GITHUB_REPOS_NAMES
  do
    GITHUB_CU=$(cat /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$GITLAB_PROJECT_NAME.cu.txt)
    LOCAL_CLONE_FOLDER=$(basename $GITHUB_CU)
    GITHUB_HAS_WIKI=$(cat /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$GITLAB_PROJECT_NAME.has_wiki.txt)
    LOCAL_WIKI_CLONE_FOLDER=$(echo $LOCAL_CLONE_FOLDER | sed 's#.git$#.wiki.git#g')

    echo "-> Mirror $GITHUB_CU to $GITLAB_SSH_BASEURL:$GITLAB_GROUP_NAME/$LOCAL_CLONE_FOLDER"       
    cd /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$LOCAL_CLONE_FOLDER
    GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME" \
    git push --mirror $GITLAB_SSH_BASEURL:$GITLAB_GROUP_NAME/$LOCAL_CLONE_FOLDER

    if [ $GITHUB_HAS_WIKI == "true" ]; then
      echo "-> Mirror $GITHUB_CU (wiki) to $GITLAB_SSH_BASEURL:$GITLAB_GROUP_NAME/$LOCAL_WIKI_CLONE_FOLDER"
      cd /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/$LOCAL_WIKI_CLONE_FOLDER
      GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa_$GITLAB_PROJECT_NAME" \
      git push --mirror $GITLAB_SSH_BASEURL:$GITLAB_GROUP_NAME/$LOCAL_WIKI_CLONE_FOLDER
    fi

  done # $GITHUB_REPOS_NAMES loop

}
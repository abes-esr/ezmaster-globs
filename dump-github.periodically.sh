#!/bin/bash
# script looping indefinitly and doing each X hours
# a github backup into /usr/local/apache2/htdocs/ folder

. /github-functions.sh
. /gitlab-functions.sh

# loop forever but wait $DUMP_EACH_NBMINUTES between each loops 
while true
do

  do_local_cleanup_for_old_github_organizations

  # loop over all the organization repo list 
  # and clone its repositories locally
  rm -f /usr/local/apache2/htdocs/GITHUB_ORGANIZATIONS.txt && touch /usr/local/apache2/htdocs/GITHUB_ORGANIZATIONS.txt
  for GITHUB_ORGANIZATION in $GITHUB_ORGANIZATIONS
  do
    # stuff for HTML view
    echo $GITHUB_ORGANIZATION >> /usr/local/apache2/htdocs/GITHUB_ORGANIZATIONS.txt
    mkdir -p /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/
    cp -f /usr/local/apache2/htdocs/index2.html /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/index.html


    echo "-> Dumping locally the $GITHUB_ORGANIZATION github organization"
    get_github_organization_info
    get_github_repositories_info
    do_local_mirrors
    # update the full organization size for the HTML view
    du -sh /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION | awk '{ print $1 }' > /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/GITHUB_ORGANIZATION_SIZE.txt
    # update the organization repositories list for the HTML view
    cd /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/ && ls -d */ 2>/dev/null > /usr/local/apache2/htdocs/$GITHUB_ORGANIZATION/GITHUB_ORGANIZATION_CONTENT.txt


    if [[ ${DUMP_TO[*]} =~ "gitlab" ]]; then
      echo "-> Dumping on gitlab the $GITHUB_ORGANIZATION github organization"
      create_or_update_gitlab_group
      if [ "$GITLAB_GROUP_ID" == "" ]; then
        echo "Error: GITLAB_GROUP_ID should not be empty ! skipping gitlab mirroring."
      else
        create_or_update_gitlab_projects
        create_ssh_key_for_gitlab_push
        do_gitlab_mirrors
      fi
    fi

  done # GITHUB_ORGANIZATIONS loop

  echo "-> Waiting $DUMP_EACH_NBMINUTES minutes before next dump."
  sleep ${DUMP_EACH_NBMINUTES}m
done

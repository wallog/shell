#!/bin/bash

set -eu

baseurl=""

if [[ $# -eq 0 ]];then
 curl -s ${baseurl}/v2/_catalog |jq
elif [[ $1 == "delete" ]];then
app="$2"
etag="v2.17|v2.18"
dockerHost=""
header="Accept: application/vnd.docker.distribution.manifest.v2+json"

tagarray=($(curl -s ${baseurl}/v2/km/$app/tags/list |jq .tags | egrep -v "$etag" | tr "[]" " " | tr "," " "))

function deleteSha() {
  curl -I -X DELETE ${dockerHost}:5000/v2/km/$app/manifests/$1
}

    for tag in ${tagarray[@]};do
        ntag=$(echo $tag | tr -d "\"")
        sha="$(curl --header "${header}" -I -X GET ${dockerHost}:5000/v2/km/${app}/manifests/${ntag} -s| grep "Etag" | cut -d "\"" -f 2)"
        if [ x"$sha" != x ];then
            deleteSha $sha
        else
            echo "$tag inexistence!" 
        fi
    done
else
   curl -s ${baseurl}/v2/$1/tags/list |jq
fi

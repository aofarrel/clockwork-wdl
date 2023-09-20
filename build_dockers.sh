#!/bin/bash

if [[ "$1" = "" ]]; 
then
    echo "ERROR: Specify a version number for tagging the images (specific to this repo, not clockwork)"
    exit 1
fi

ash_tag=".$1"
official_tag="v0.11.3"
tag=$official_tag$ash_tag
echo "Images will be tagged with $tag"

if [ -d "./references/" ]; 
then
    echo "Found references/ folder."
else
    mkdir references
fi

if [ -f "./references/Ref.H37Rv.tar" ]; 
then
    echo "Found indexed H37Rv reference."
else
    echo "Place Ref.H37Rv.tar in $pwd/reference"
    exit 1
fi

if [ -f "./references/Ref.remove_contam.tar" ]; 
then
    echo "Found default (CRyPTIC) decontamination reference."
else
    echo "Place Ref.remove_contam.tar in $pwd/reference"
    exit 1
fi

if [ -f "./references/varpipe.Ref.remove_contam.tar" ]; 
then
    echo "Found varpipe_wgs (CDC) decontamination reference."
else
    echo "Place varpipe.Ref.remove_contam.tar in $pwd/reference"
    exit 1
fi

docker build -f Dockerfile_slim .
docker tag $(docker images | awk '{print $3}' | awk 'NR==2') ashedpotatoes/clockwork-plus:$tag-slim
docker push "ashedpotatoes/clockwork-plus:$tag-slim"


# I use OSX, so https://stackoverflow.com/a/62309999 and https://stackoverflow.com/a/4247319 are at play
# (and also the slash needs to be escaped)
base_image_line="FROM ashedpotatoes\/clockwork-plus:$tag-slim"
sed -i '' -e "2s/.*/$base_image_line/" Dockerfile_CRyPTIC
sed -i '' -e "2s/.*/$base_image_line/" Dockerfile_CDC

# build CRyPTIC image
docker build -f Dockerfile_CRyPTIC .
docker tag $(docker images | awk '{print $3}' | awk 'NR==2') ashedpotatoes/clockwork-plus:$tag-CRyPTIC
docker push "ashedpotatoes/clockwork-plus:$tag-CRyPTIC"

# build CDC image
docker build -f Dockerfile_CDC .
docker tag $(docker images | awk '{print $3}' | awk 'NR==2') ashedpotatoes/clockwork-plus:$tag-CDC
docker push "ashedpotatoes/clockwork-plus:$tag-CDC"
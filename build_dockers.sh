#!/bin/bash
# Warning: This downloads ~15 GB worth of files from a requester-pays bucket

if [[ "$1" = "" ]]; 
then
    echo "ERROR: Specify a version number for tagging the images"
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
    echo "Downloading indexed H37Rv reference..."
    gsutil -u ucsc-idgc cp gs://topmed_workflow_testing/tb/ref/index_H37Rv_reference_output/Ref.H37Rv.tar ./references
fi

if [ -f "./references/Ref.remove_contam.tar" ]; 
then
    echo "Found decontamination reference."
else
    echo "Downloading decontamination reference (it's over 10 GB so this will take a while)..."
    gsutil -u ucsc-idgc cp gs://topmed_workflow_testing/tb/ref/index_decontamination_ref_output/Ref.remove_contam.tar ./references
fi

docker build -f Dockerfile_slim .
docker tag $(docker images | awk '{print $3}' | awk 'NR==2') ashedpotatoes/iqbal-clockwork-plus--slim:$tag
exit 0

docker push ashedpotatoes/iqbal-clockwork-plus-ref-genomes-slim

# replace first line of full docker file with FROM ashedpotatoes/iqbal-clockwork-plus-ref-genomes-slim:$tag

docker build -f Dockerfile_full .
docker tag $(docker images | awk '{print $3}' | awk 'NR==2') ashedpotatoes/iqbal-clockwork-plus--full:$tag
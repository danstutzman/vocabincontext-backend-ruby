#!/bin/bash -ex

INSTANCE_IP=`tugboat droplets | grep vocabincontext | egrep -oh "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" || true`
echo INSTANCE_IP=$INSTANCE_IP

if [ "$INSTANCE_IP" == "" ]; then
  echo "Creating new instance..."
  # Run tugboat keys to find the 41226 ID number
  tugboat create vocabincontext -k 41226 -s 512MB -r nyc1 -i ubuntu-14-04-x32
  tugboat wait vocabincontext
fi

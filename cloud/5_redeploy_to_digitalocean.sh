#!/bin/bash -ex
cd `dirname $0`

INSTANCE_IP=`tugboat droplets | grep vocabincontext | egrep -oh "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"`
echo INSTANCE_IP=$INSTANCE_IP
rsync -e "ssh -l web" -rv .. root@$INSTANCE_IP:/var/www/vocabincontext --exclude vendor --exclude ".*"

tugboat ssh vocabincontext <<EOF
chown -R web:web /var/www/vocabincontext
cd /var/www/vocabincontext
sudo sudo -u web bundle install --deployment
sudo service unicorn stop || true
sleep 1
sudo service unicorn start
EOF
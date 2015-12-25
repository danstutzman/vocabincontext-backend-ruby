#!/bin/bash -ex
cd `dirname $0`

tugboat ssh vocabincontext <<EOF
set -ex
# See https://www.digitalocean.com/community/tutorials/how-to-set-up-a-firewall-with-ufw-on-ubuntu-14-04
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow 60001:60010/udp
yes | sudo ufw enable
sudo apt-get install -y mosh
EOF

tugboat ssh vocabincontext <<EOF
set -ex
sudo apt-get update
sudo apt-get install -y nginx
sudo apt-get install -y ruby2.0 ruby2.0-dev
sudo apt-get install -y build-essential bison openssl libreadline6 libreadline6-dev curl git-core zlib1g zlib1g-dev libssl-dev libyaml-dev libxml2-dev autoconf libc6-dev ncurses-dev automake libtool
sudo gem2.0 install unicorn
id -u web &>/dev/null || useradd web
sudo mkdir -p /var/www/vocabincontext
EOF

INSTANCE_IP=`tugboat droplets | grep vocabincontext | egrep -oh "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" || true`
echo INSTANCE_IP=$INSTANCE_IP
rsync -e "ssh -l web -o StrictHostKeyChecking=no" -rv .. root@$INSTANCE_IP:/var/www/vocabincontext --exclude vendor --exclude ".*"

tugboat ssh vocabincontext <<EOF
set -ex
sudo chown web:web /var/www/vocabincontext
cd /var/www/vocabincontext
gem2.0 install bundler
sudo apt-get install -y libpq-dev
sudo sudo -u web bundle install --deployment
touch /var/log/unicorn.log
chown web:web /var/log/unicorn.log
# to test out: sudo -u web bundle exec unicorn

sudo rm -f /etc/nginx/sites-available/default
cp cloud/nginx.conf /etc/nginx/conf.d/default.conf
chown root:root /etc/nginx/conf.d/default.conf
cp cloud/init.d.unicorn /etc/init.d/unicorn
chown root:root /etc/init.d/unicorn
chmod +x /etc/init.d/unicorn
/usr/sbin/update-rc.d -f unicorn defaults
sudo service unicorn stop
sudo service unicorn start
sleep 1
sudo service nginx restart
EOF

tugboat ssh vocabincontext <<"EOF"
sudo apt-get install -y postgresql postgresql-client-common
USER_EXISTS=$(echo "\du" | sudo -u postgres psql | grep -c vocabincontext)
if [ "$USER_EXISTS" == "0" ]; then
  sudo sudo -u postgres createuser -s -e vocabincontext
  echo "ALTER USER vocabincontext WITH PASSWORD 'vocabincontext'" | sudo sudo -u postgres psql
fi
EOF

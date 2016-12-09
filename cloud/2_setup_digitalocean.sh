#!/bin/bash -ex
cd `dirname $0`

fwknop -s -n vocabincontext.danstutzman.com
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

rsync -e "ssh -l web" -rv .. root@vocabincontext.danstutzman.com:/var/www/vocabincontext --exclude vendor --exclude ".*"

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

tugboat ssh vocabincontext <<EOF
set -ex
sudo apt-get install -y python-pip
sudo pip install --upgrade youtube_dl
sudo apt-get install -y build-essential yasm libx264-dev sox
if [ ! -e libav ]; then
  git clone git://git.libav.org/libav.git
fi
cd /usr/local/libav
git checkout v11.4
./configure \
  --prefix=/usr/local \
  --enable-nonfree \
  --enable-gpl \
  --disable-shared \
  --enable-static \
  --enable-libx264 \
  --enable-libfdk-aac
make
make install
EOF

tugboat ssh vocabincontext <<EOF
set -ex
curl -O https://storage.googleapis.com/golang/go1.5.3.linux-386.tar.gz
tar xvzf go1.5.3.linux-386.tar.gz
rm -rf /usr/local/go
mv go /usr/local/go

sudo apt-get install -y supervisor
sudo tee /etc/vocabincontext_postgres_credentials.json <<EOF2
{
  "Username": "vocabincontext",
  "Password": "vocabincontext",
  "DatabaseName": "postgres",
  "SSLMode": "disable"
}
EOF2
sudo tee /etc/supervisor/conf.d/gobackend.conf <<EOF2
[program:backend]
command=/var/www/vocabincontext/golang/backend --postgres_credentials_path /etc/vocabincontext_postgres_credentials.json
EOF2

EOF

#!/bin/bash -ex
cd `dirname $0`

fwknop -s -n vocabincontext.danstutzman.com
rsync -e "ssh -l web" -rv .. root@vocabincontext.danstutzman.com:/var/www/vocabincontext --exclude vendor --exclude ".*" --exclude "*.wav"

tugboat ssh vocabincontext <<EOF
chown -R web:web /var/www/vocabincontext

cd /var/www/vocabincontext/golang
mkdir -p gopath
GOPATH=$PWD/gopath /usr/local/go/bin/go get github.com/lib/pq
GOPATH=$PWD/gopath /usr/local/go/bin/go build *.go

cd /var/www/vocabincontext
sudo sudo -u web bundle install --deployment
sudo service unicorn stop || true
sleep 1
sudo service unicorn start

sudo service supervisor restart
EOF

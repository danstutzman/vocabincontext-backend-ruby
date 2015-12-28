#!/bin/bash -ex

gcloud compute disks create speech-snapshot2 --size 10 --image ubuntu-15-04

gcloud compute instances create speech-snapshot \
  --disk name=speech-snapshot,boot=yes \
  --machine-type n1-highcpu-2

gcloud compute ssh speech-snapshot <<EOF
set -ex

sudo apt-get install -y mosh

sudo apt-get install -y python-software-properties debconf-utils
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections
sudo apt-get install -y oracle-java8-installer
EOF

gcloud compute ssh speech-snapshot <<EOF
sudo apt-get install -y git
if [ ! -e sphinx4 ]; then
  git clone http://github.com/cmusphinx/sphinx4
fi
cd sphinx4
sudo apt-get install -y ruby
ruby -i -pe "gsub /^\s+tuple.add\(it.next\(\)\);/, 'if (it.hasNext()) { tuple.add(it.next()); }'" sphinx4-core/src/main/java/edu/cmu/sphinx/alignment/LongTextAligner.java
ruby -i -pe 'gsub /^\s+<item>speedTracker<\/item>$/, "<!--<item>speedTracker</item>-->"' ./sphinx4-core/src/main/resources/edu/cmu/sphinx/api/default.config.xml
ruby -i -pe 'gsub /^\s+<item>memoryTracker<\/item>$/, "<!--<item>memoryTracker</item>-->"' ./sphinx4-core/src/main/resources/edu/cmu/sphinx/api/default.config.xml
sudo apt-get install -y gradle
JAVA_HOME=/usr/lib/jvm/java-8-oracle gradle jar
cd
EOF

gcloud compute ssh speech-snapshot <<"EOF"
set -ex

sudo apt-get install -y autoconf libtool bison python-dev swig make g++

if [ ! -e openfst-1.3.4 ]; then
  curl http://www.openfst.org/twiki/pub/FST/FstDownload/openfst-1.3.4.tar.gz > openfst-1.3.4.tar.gz
  tar xvzf openfst-1.3.4.tar.gz
fi
cd openfst-1.3.4
./configure --enable-compact-fsts --enable-const-fsts --enable-far --enable-lookahead-fsts --enable-pdt
make
sudo make install
cd

if [ ! -e opengrm-ngram-1.1.0 ]; then
  curl http://www.openfst.org/twiki/pub/GRM/NGramDownload/opengrm-ngram-1.1.0.tar.gz > opengrm-ngram-1.1.0.tar.gz
  tar xvzf opengrm-ngram-1.1.0.tar.gz
fi
cd opengrm-ngram-1.1.0
./configure
make
sudo make install
cd

if [ ! -e sphinxbase ]; then
  git clone https://github.com/cmusphinx/sphinxbase.git
fi
cd sphinxbase
autoreconf -i
./configure
make
sudo make install
cd

if [ ! -e sphinxtrain ]; then
  git clone https://github.com/cmusphinx/sphinxtrain.git
fi
cd sphinxtrain
cat etc/sphinx_train.cfg | sed "s/\$CFG_G2P_MODEL\s*=\s*'\(.*\)';/\$CFG_G2P_MODEL = 'yes';/" > sphinx_train.cfg.new
mv sphinx_train.cfg.new sphinx_train.cfg
./autogen.sh amd64 –enable-g2p-decoder
LDFLAGS="-L/usr/local/lib/fst" ./configure -enable-g2p-decoder
make
sudo make install
cd

if [ ! -e voxforge-es-0.2/README ]; then
  curl -L "http://sourceforge.net/projects/cmusphinx/files/Acoustic%20and%20Language%20Models/Spanish%20Voxforge/voxforge-es-0.2.tar.gz/download" > voxforge-es-0.2.tar.gz
  tar xvzf voxforge-es-0.2.tar.gz
fi
cat ~/voxforge-es-0.2/etc/voxforge_es_sphinx.dic | ruby -pe "gsub %r[ +$], ''" > es.dic
LD_LIBRARY_PATH=/usr/local/lib sphinxtrain/src/programs/g2p_train/g2p_train -ifile es.dic

sudo apt-get install -y subversion
if [ ! -e g2p ]; then
  svn co https://svn.code.sf.net/p/cmusphinx/code/branches/g2p
fi
cd g2p/fst
sudo apt-get install -y ant
ant
./openfst2java.sh ../../model model.fst.ser

sudo apt-get install -y python-pip ffmpeg sox ruby-dev
sudo pip install --upgrade youtube_dl
sudo gem install rest-client
EOF

gcloud compute instances stop speech-snapshot
gcloud compute disks snapshot speech-snapshot --snapshot-names speech-snapshot --zone us-central1-b
gcloud compute images create speech-snapshot --source-disk speech-snapshot
gcloud compute instances delete speech-snapshot

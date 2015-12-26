#!/bin/bash -ex

INSTANCE_NAME=speech2

INSTANCE_IP=`gcloud compute instances list "$INSTANCE_NAME" --format text | grep 'networkInterfaces\[0\].accessConfigs\[0\].natIP' | awk '{print $2}'`;
echo "INSTANCE_IP=$INSTANCE_IP"

if [ "$INSTANCE_IP" == "" ]; then
  gcloud compute instances create "$INSTANCE_NAME" \
    --image ubuntu-15-04 \
    --machine-type n1-standard-1 \
    --preemptible
else
  gcloud compute instances start "$INSTANCE_NAME"
fi

while true; do
  if [ "`gcloud compute ssh speech2 -C echo true`" == true ]; then
    break
  fi
  sleep 3
done

gcloud compute ssh $INSTANCE_NAME <<EOF
set -ex

sudo apt-get install -y mosh

sudo apt-get install -y python-software-properties debconf-utils
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | sudo debconf-set-selections
sudo apt-get install -y oracle-java8-installer
EOF

gcloud compute ssh $INSTANCE_NAME <<EOF
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

gcloud compute ssh $INSTANCE_NAME <<"EOF"
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

sudo apt-get install -y python-pip
sudo pip install --upgrade youtube_dl
VIDEO_ID=SqWrliMzrW8
youtube-dl "http://www.youtube.com/watch?v=$VIDEO_ID" --id
sudo apt-get install -y ffmpeg
ffmpeg -y -i "$VIDEO_ID.mp4" -vn -acodec copy "$VIDEO_ID.m4a" -nostdin
ffmpeg -i "$VIDEO_ID.m4a" "$VIDEO_ID.wav" -nostdin

sudo apt-get install -y sox
sox $VIDEO_ID.wav short.wav channels 1 rate 16k trim 17 10
tee short.txt <<EOF2
El otro día me dijiste que me quieres mira como eres
tu bato es camarada mío y quiero que te esperes
para que tu y el se separen de un final
EOF2

java -cp \
  sphinx4/sphinx4-samples/build/libs/sphinx4-samples-5prealpha-SNAPSHOT.jar \
  edu.cmu.sphinx.demo.aligner.AlignerDemo \
  short.wav \
  short.txt \
  voxforge-es-0.2/model_parameters/voxforge_es_sphinx.cd_ptm_3000 \
  voxforge-es-0.2/etc/voxforge_es_sphinx.dic \
  g2p/fst/model.fst.ser

EOF

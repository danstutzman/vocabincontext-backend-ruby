#!/bin/bash -ex

INSTANCE_IP=`tugboat droplets | grep monitoring | egrep -oh "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" || true`
echo INSTANCE_IP=$INSTANCE_IP

tugboat ssh monitoring <<"EOF"
mkdir -p /etc/letsencrypt/live/piwik.vocabincontext.com

tee /etc/apache2/sites-enabled/piwik.vocabincontext.com.conf <<"EOF2"
<VirtualHost *:443>
  ServerAdmin admin@vocabincontext.com
  ServerName piwik.vocabincontext.com
  DocumentRoot /var/www/html
  ErrorLog /var/log/apache2/error.log
  CustomLog /var/log/apache2/access.log combined

  SSLEngine on
  SSLCertificateFile    /etc/letsencrypt/live/piwik.vocabincontext.com/cert.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/piwik.vocabincontext.com/privkey.pem
  SSLCertificateChainFile /etc/letsencrypt/live/piwik.vocabincontext.com/chain.pem
  </VirtualHost>
EOF2
EOF

rsync --copy-links -e "ssh -o StrictHostKeyChecking=no" -r -v conf/live/piwik.vocabincontext.com/ root@$INSTANCE_IP:/etc/letsencrypt/live/piwik.vocabincontext.com

tugboat ssh monitoring <<EOF
sudo a2enmod ssl
ufw allow 443
sudo service apache2 restart
EOF

#!/bin/bash -ex

INSTANCE_IP=`tugboat droplets | grep "vocabincontext" | egrep -oh "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"`
echo INSTANCE_IP=$INSTANCE_IP

ssh root@$INSTANCE_IP <<"EOF"
cd /tmp # eliminate warning
for TABLE_NAME in `sudo -u postgres psql -t -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"`; do sudo -u postgres psql -c "drop table $TABLE_NAME"; done
EOF

/Applications/Postgres.app/Contents/MacOS/bin/pg_dump -U postgres -Fc -v | ssh root@$INSTANCE_IP -C "cd /tmp && sudo -u postgres pg_restore -U postgres -e -Fc -d postgres"

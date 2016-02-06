#!/bin/bash -ex

INSTANCE_IP=`tugboat droplets | grep monitoring | egrep -oh "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" || true`
echo INSTANCE_IP=$INSTANCE_IP

ZONE_ID=`aws route53 list-hosted-zones | python -c '
import json, sys
j=json.load(sys.stdin)
for zone in j["HostedZones"]:
  if zone["Name"] == "vocabincontext.com.":
    print zone["Id"]
'`

tee new_record_set.json <<EOF
{
  "Comment": "A new record set for the zone.",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "piwik.vocabincontext.com.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "$INSTANCE_IP"
          }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://$PWD/new_record_set.json
rm new_record_set.json

aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID

#!/bin/bash -ex

IP_ADDRESS="$1"
if [ "$IP_ADDRESS" == "" ]; then
  echo 1>&2 "Specify IP_ADDRESS as first parameter"
  exit 1
fi

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
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "digitalocean.vocabincontext.com.",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "$IP_ADDRESS"
          }
        ]
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file://$PWD/new_record_set.json
rm new_record_set.json

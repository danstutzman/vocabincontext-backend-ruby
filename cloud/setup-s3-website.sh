#!/bin/bash -ex

aws s3 website s3://vocabincontext-media-excerpts --index-document index.html

tee policy.json <<EOF
{
  "Version":"2012-10-17",
  "Statement":[{
    "Sid":"PublicReadForGetBucketObjects",
    "Effect":"Allow",
    "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::vocabincontext-media-excerpts/*"
      ]
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket vocabincontext-media-excerpts \
 --policy file://policy.json

rm policy.json

curl http://vocabincontext-media-excerpts.s3-website-us-east-1.amazonaws.com/es.dic

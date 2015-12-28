#!/bin/bash -ex
tee policy.json <<EOF
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::vocabincontext-media-excerpts/*"
    }
  ]
}
EOF

aws iam put-user-policy --user-name vocabincontext-media-excerpts-uploader \
 --policy-name can-upload-to-s3 \
 --policy-document file://policy.json

rm policy.json

#!/bin/bash -ex

CLOUDFRONT_DISTRIBUTION_ID=E28SJ6YOTSERS3

#brew install dialog

#pip install letsencrypt

#pip install letsencrypt-s3front

AWS_ACCESS_KEY_ID=`grep aws_access_key_id ~/.aws/config | awk '{print $3}'`
AWS_SECRET_ACCESS_KEY=`grep aws_secret_access_key ~/.aws/config | awk '{print $3}'`

s3cmd mb s3://letsencrypt-vocabincontext-com
s3cmd ws-create s3://letsencrypt-vocabincontext-com
s3cmd setpolicy bucket_policy.json s3://letsencrypt-vocabincontext-com

mkdir -p conf work logs

AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  letsencrypt --agree-tos -a letsencrypt-s3front:auth \
  --letsencrypt-s3front:auth-s3-bucket letsencrypt-vocabincontext-com \
  -i letsencrypt-s3front:installer \
  --letsencrypt-s3front:installer-cf-distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
  --config-dir conf --work-dir work --logs-dir logs \
  -d vocabincontext.com

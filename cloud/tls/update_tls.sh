#!/bin/bash -ex

CLOUDFRONT_DISTRIBUTION_ID=E28SJ6YOTSERS3

brew install dialog

pip install letsencrypt

pip install letsencrypt-s3front

AWS_ACCESS_KEY_ID=`grep aws_access_key_id ~/.aws/config | awk '{print $3}'`
AWS_SECRET_ACCESS_KEY=`grep aws_secret_access_key ~/.aws/config | awk '{print $3}'`

mkdir -p conf work logs

aws s3 mb s3://letsencrypt-vocabincontext-com
aws s3 website s3://letsencrypt-vocabincontext-com --index-document index.html
aws s3api put-bucket-policy --bucket letsencrypt-vocabincontext-com \
  --policy file://$PWD/bucket_policy.vocabincontext-com.json

AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  letsencrypt --agree-tos -a letsencrypt-s3front:auth \
  --letsencrypt-s3front:auth-s3-bucket letsencrypt-vocabincontext-com \
  -i letsencrypt-s3front:installer \
  --letsencrypt-s3front:installer-cf-distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
  --config-dir conf --work-dir work --logs-dir logs \
  -d vocabincontext.com

aws s3 mb s3://piwik.vocabincontext.com
aws s3 website s3://piwik.vocabincontext.com --index-document index.html
aws s3api put-bucket-policy --bucket piwik.vocabincontext.com \
  --policy file://$PWD/bucket_policy.piwik.vocabincontext.com.json

# Do not specify --letsencrypt-s3front:installer-cf-distribution-id
#   because that will override vocabincontext.com's TLS config!
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  letsencrypt --agree-tos -a letsencrypt-s3front:auth \
  --letsencrypt-s3front:auth-s3-bucket piwik.vocabincontext.com \
  -i letsencrypt-s3front:installer \
  --config-dir conf --work-dir work --logs-dir logs \
  -d piwik.vocabincontext.com

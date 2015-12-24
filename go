#!/bin/bash -e
ifconfig | grep 'inet 10.0'
PATH=/Applications/Postgres.app/Contents/MacOS/bin:/usr/bin /usr/local/bin/bundle exec rackup --host 0.0.0.0

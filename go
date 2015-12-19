#!/bin/bash -e
ifconfig | grep 'inet 10.0'
rackup --host 0.0.0.0

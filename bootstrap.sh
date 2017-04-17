#!/bin/sh
 
set -e

cd $(dirname $0)

scripts/libssl.sh
scripts/libevent.sh
scripts/tor.sh
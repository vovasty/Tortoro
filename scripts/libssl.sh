#!/bin/sh
 
set -e

source $(dirname $0)/settings.sh

ars=$(printf " %s" "${ARCHS[@]}")
ars=${ars:1}

cd dist/OpenSSL-for-iPhone
./build-libssl.sh --ec-nistp-64-gcc-128 --ios-sdk=${SDKVERSION} --archs="${ars}"

mkdir -p ${BUILT_PRODUCTS_DIR}
cp lib/*.a ${BUILT_PRODUCTS_DIR}
mkdir -p ${BUILT_PRODUCTS_DIR}/openssl
cp -r include/openssl ${BUILT_PRODUCTS_DIR}/openssl
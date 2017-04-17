#!/bin/bash

# set -x

source $(dirname $0)/settings.sh

# We need gettext to build libevent
# This extends the path to look in some common locations (for example, if installed via Homebrew)
PATH=$PATH:/usr/local/bin:/usr/local/opt/gettext/bin

cd $(dirname $0)/../dist/libevent

# Generate the configure script (necessary for version control distributions)
if [[ ! -f ./configure ]]; then
    ./autogen.sh
fi

REBUILD=1

# If the built binaries include a different set of architectures, then rebuild the target
if [[ ${ACTION:-build} = "build" ]]; then
    for LIBRARY in $(find "${BUILT_PRODUCTS_DIR}" -name "libevent*.a")
    do
        for ARCH in $ARCHS
        do
            if [[ $(lipo -info "${LIBRARY}" 2>&1) != *"${ARCH}"* ]]; then
                REBUILD=1;
            fi
        done
    done
fi

# If rebuilding or cleaning then delete the built products
if [[ $ACTION = "clean" ]] || [[ $REBUILD = 1 ]]; then
    make distclean 2>/dev/null
    rm -rf "${BUILT_PRODUCTS_DIR}/libevent"* 2>/dev/null
fi

if [[ $REBUILD = 0 ]]; then
    exit;
fi

if [[ "${BITCODE_GENERATION_MODE}" = "bitcode" ]]; then
    BITCODE_FLAGS="-fembed-bitcode"
elif [[ "${BITCODE_GENERATION_MODE}" = "marker" ]]; then
    BITCODE_FLAGS="-fembed-bitcode-marker"
fi

# If there is a space in SRCROOT, make a symlink without a space and use that
if [[ "${SRCROOT}" =~ \  ]]; then
    SYM_DIR="$(mktemp -d)/Tor"
    ln -s "${SRCROOT}" "${SYM_DIR}"
    SRCROOT="${SYM_DIR}"
fi

# We need XPC to build libevent, so copy it from the OSX SDK into a temporary directory
XPC_INCLUDE_DIR="${CONFIGURATION_TEMP_DIR}/libevent-xpc"
mkdir -p "${XPC_INCLUDE_DIR}/xpc"
cp -f "$(xcrun --sdk macosx --show-sdk-path)/usr/include/xpc/base.h" "${XPC_INCLUDE_DIR}/xpc"

# Build each architecture one by one using clang
for ARCH in "${ARCHS[@]}"
do
    if [[ ${ARCH} == arm* ]]; then
        CROSS_SDK=${CROSS_SDK_IOS}
        CROSS_SDK_TOP=${CROSS_TOP_IOS}
        PLATFORM_NAME=iphoneos
    else
        CROSS_SDK=${CROSS_SDK_SIM}
        CROSS_SDK_TOP=${CROSS_TOP_SIM}
        PLATFORM_NAME=iphonesimulator
    fi  
    SDKROOT=${CROSS_SDK_TOP}/SDKs/${CROSS_SDK}  
    export SDKROOT
    
    PREFIX="${CONFIGURATION_TEMP_DIR}/libevent-${ARCH}"
    ./configure --disable-shared --enable-static --disable-debug-mode --enable-gcc-hardening --prefix="${PREFIX}" CC="$(xcrun -f --sdk ${PLATFORM_NAME} clang) -arch ${ARCH} -miphoneos-version-min=${IOS_MIN_SDK_VERSION}" CPP="$(xcrun -f --sdk ${PLATFORM_NAME} clang) -E -arch ${ARCH} -miphoneos-version-min=${IOS_MIN_SDK_VERSION}" CFLAGS="-I\"${BUILT_PRODUCTS_DIR}/openssl\" ${BITCODE_FLAGS} -I${XPC_INCLUDE_DIR}" LDFLAGS="-L${BUILT_PRODUCTS_DIR} ${BITCODE_FLAGS}" cross_compiling="yes" ac_cv_func_clock_gettime="no"
    make -j$(sysctl hw.ncpu | awk '{print $2}')
    make install
    make distclean
done

mkdir -p "${BUILT_PRODUCTS_DIR}"

# Copy the build products from the temporary directory to the built products directory
for ARCH in "${ARCHS[@]}"
do
    cp -r "${CONFIGURATION_TEMP_DIR}/libevent-${ARCH}/include" "${BUILT_PRODUCTS_DIR}/libevent-${ARCH}"
    for LIBRARY in "${CONFIGURATION_TEMP_DIR}/libevent-${ARCH}/lib/"*.a;
    do
        cp $LIBRARY "${BUILT_PRODUCTS_DIR}/$(basename ${LIBRARY} .a).${ARCH}.a"
    done
done

cp -rf "${BUILT_PRODUCTS_DIR}/libevent-${ARCHS[0]}" "${BUILT_PRODUCTS_DIR}/libevent"

# Combine the built products into a fat binary
xcrun --sdk $PLATFORM_NAME lipo -create "${BUILT_PRODUCTS_DIR}/libevent."*.a -output "${BUILT_PRODUCTS_DIR}/libevent.a"
xcrun --sdk $PLATFORM_NAME lipo -create "${BUILT_PRODUCTS_DIR}/libevent_core."*.a -output "${BUILT_PRODUCTS_DIR}/libevent_core.a"
xcrun --sdk $PLATFORM_NAME lipo -create "${BUILT_PRODUCTS_DIR}/libevent_pthreads."*.a -output "${BUILT_PRODUCTS_DIR}/libevent_pthreads.a"
xcrun --sdk $PLATFORM_NAME lipo -create "${BUILT_PRODUCTS_DIR}/libevent_extra."*.a -output "${BUILT_PRODUCTS_DIR}/libevent_extra.a"
rm "${BUILT_PRODUCTS_DIR}/libevent"*.*.a

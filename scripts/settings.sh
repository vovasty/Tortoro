ARCHS=(arm64 armv7 i386 x86_64)
BUILT_PRODUCTS_DIR=$(pwd)/lib
BITCODE_GENERATION_MODE=bitcode
SRCROOT=$(pwd)
CONFIGURATION_TEMP_DIR=$(pwd)/build
SDKVERSION=$(xcrun -sdk iphoneos --show-sdk-version)
IOS_MIN_SDK_VERSION=7.0

DEVELOPER=$(xcode-select -print-path)
CROSS_SDK_SIM=iPhoneSimulator${SDKVERSION}.sdk
CROSS_SDK_IOS=iPhoneOS${SDKVERSION}.sdk
CROSS_TOP_SIM="${DEVELOPER}/Platforms/iPhoneSimulator.platform/Developer"
CROSS_TOP_IOS="${DEVELOPER}/Platforms/iPhoneOS.platform/Developer"
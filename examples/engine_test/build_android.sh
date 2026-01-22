#!/usr/bin/env sh

#https://github.com/IllusionMan1212/android-native-example-odin

cp -r res/* android/assets
mkdir -p android/lib/lib/arm64-v8a
odin build . -out:android/lib/lib/arm64-v8a/libengine_test.so -debug -build-mode:shared -target:linux_arm64 -subtarget:android

KEYSTORE="android/debug.keystore"
PASSWORD="android"
BUNDLE_DIR="android"

#?"$ANDROID_JBR/bin/keytool" -genkey -v -keystore .keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000
odin bundle android ${BUNDLE_DIR} -android-keystore:${KEYSTORE} -android-keystore-password:${PASSWORD}
mv test.apk engine_test.apk
rm test.apk-build
rm test.apk.idsig
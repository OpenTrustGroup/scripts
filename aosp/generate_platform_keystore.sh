#!/bin/bash
mkdir -p security
tar xf security.tar.gz -C security
openssl pkcs8 -inform DER -nocrypt -in security/platform.pk8 -out platform.der
openssl pkcs12 -export -in security/platform.x509.pem -inkey platform.der -out platform.p12 -password pass:android -name androidplatformkey
keytool -importkeystore -deststorepass android -destkeystore platform.keystore -srckeystore platform.p12 -srcstoretype PKCS12 -srcstorepass android
keytool -list -v -keystore platform.keystore

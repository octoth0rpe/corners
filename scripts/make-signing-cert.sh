#!/bin/sh
# Creates a self-signed code signing certificate in the login keychain.
#
# macOS remembers the Accessibility grant by the app's designated requirement.
# For an ad-hoc signature that's the exact binary hash, which changes on every
# build. For a certificate it's "this bundle ID, signed by this certificate",
# which stays the same across builds. The certificate doesn't need to be
# trusted; it only needs to stay the same.
#
# To remove it later: Keychain Access → login → My Certificates → delete it.
set -eu

name=${1:-Corners Local Signing}
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    echo "\"$name\" already exists in the login keychain."
    exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

cat > "$dir/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# /usr/bin/openssl is LibreSSL, whose PKCS#12 output the keychain can import.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$dir/cert.cnf" -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" \
    -name "$name" -passout pass:corners -out "$dir/identity.p12"

# -T lets codesign use the key without a keychain prompt.
security import "$dir/identity.p12" -k "$keychain" -P corners -T /usr/bin/codesign
echo "Created \"$name\". Run 'make install' to sign with it."

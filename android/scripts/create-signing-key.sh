#!/bin/zsh
set -euo pipefail
config_dir="$HOME/.config/luma"
mkdir -p "$config_dir"
chmod 700 "$config_dir"
if [[ -f "$config_dir/signing.properties" ]]; then
  print "Signing configuration already exists at $config_dir/signing.properties"
  exit 0
fi
export LUMA_STORE_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
keytool -genkeypair -keystore "$config_dir/release.jks" -alias luma -keyalg RSA -keysize 3072 -validity 10000 -storepass:env LUMA_STORE_PASSWORD -keypass:env LUMA_STORE_PASSWORD -dname 'CN=Luma Android TV' >/dev/null 2>&1
umask 077
print -r -- "storeFile=$config_dir/release.jks
storePassword=$LUMA_STORE_PASSWORD
keyAlias=luma
keyPassword=$LUMA_STORE_PASSWORD" > "$config_dir/signing.properties"
print "Signing key created outside the repository. Back up $config_dir securely; updates require this key."

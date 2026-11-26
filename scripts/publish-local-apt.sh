#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=${SHENG_POP_WORK:-/var/tmp/popos-sheng-26.04}
apt_repo=$repo/apt-local
export GNUPGHOME=$work/apt-signing
install -d -m 0700 "$GNUPGHOME"
cd "$apt_repo"
test -n "$(find pool -maxdepth 1 -name 'linux-image-popos-sheng_*_arm64.deb' -print -quit)"

echo 'Index the ARM64 and architecture-independent device packages'
dpkg-scanpackages pool /dev/null > Packages.partial
gzip -n -c Packages.partial > Packages.gz.partial
mv Packages.partial Packages
mv Packages.gz.partial Packages.gz
{
    printf 'Origin: Pop!_OS Sheng local\nLabel: Pop!_OS Sheng local\nArchitectures: arm64 all\n'
    printf 'Date: %s\nDescription: Local Xiaomi Pad 6S Pro kernel and device packages\n' "$(date -Ru)"
    printf 'SHA256:\n'
    for name in Packages Packages.gz; do
        digest=$(sha256sum "$name" | cut -d ' ' -f 1)
        printf ' %s %16s %s\n' "$digest" "$(stat -c %s "$name")" "$name"
    done
} > Release.partial
mv Release.partial Release

identity='Pop!_OS Sheng Local APT <apt@sheng.invalid>'
if ! gpg --batch --list-secret-keys "$identity" >/dev/null 2>&1; then
    gpg --batch --pinentry-mode loopback --passphrase '' --quick-generate-key "$identity" ed25519 sign 0
fi
gpg --batch --yes --local-user "$identity" --output InRelease.partial --clearsign Release
gpg --batch --yes --local-user "$identity" --output Release.gpg.partial --detach-sign Release
gpg --batch --export "$identity" > popos-sheng-archive.gpg.partial
mv InRelease.partial InRelease
mv Release.gpg.partial Release.gpg
mv popos-sheng-archive.gpg.partial popos-sheng-archive.gpg
gpgv --keyring "$PWD/popos-sheng-archive.gpg" InRelease
gpg --batch --with-colons --fingerprint "$identity" | awk -F: '$1 == "fpr" {print $10}' > SIGNING-KEY-FINGERPRINT.txt

check=$(mktemp -d "${TMPDIR:-/tmp}/popos-sheng-apt-check.XXXXXXXX")
trap 'rm -r -- "$check"' EXIT
chmod 0755 "$check"
mkdir "$check/lists"
printf 'deb [arch=arm64 signed-by=%s/popos-sheng-archive.gpg] file:%s ./\n' "$apt_repo" "$apt_repo" > "$check/source.list"
cat > "$check/apt.conf" <<EOF
APT::Architecture "arm64";
Dir::Etc::SourceList "$check/source.list";
Dir::Etc::SourceParts "-";
Dir::State::Lists "$check/lists";
Dir::State::Status "/dev/null";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
#clear APT::Update::Post-Invoke-Success;
EOF
apt-get -c "$check/apt.conf" update --error-on=any
apt-cache -c "$check/apt.conf" policy linux-image-popos-sheng | tee "$repo/out/local-apt-policy.txt"
grep -E 'Candidate: 7\.2\.6' "$repo/out/local-apt-policy.txt"
echo "Signed local APT repository: $apt_repo"

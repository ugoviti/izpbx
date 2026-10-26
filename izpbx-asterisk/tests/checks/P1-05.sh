#!/usr/bin/env bash
# P1-05: the base stage. Every package of build/packages-runtime.txt is
# installed, apt sources are only Debian and Zabbix, the Zabbix keyring holds
# only the pinned key (ZABBIX_GPG_FPR), and asterisk is 1000:1000.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
dir="$REPO_DIR/izpbx-asterisk"
fpr=$(sed -n 's/^ZABBIX_GPG_FPR=//p' "$dir/versions.env")
image=izpbx-asterisk:p1-05

assert_cmd "image builds" -- t_build_image "$image"

# data from the image (primary key fingerprints: subkeys also print an fpr record)
sed -e 's/#.*//' -e 's/[[:space:]]//g' "$dir/build/packages-runtime.txt" | grep -v '^$' > "$work/wanted"
docker run --rm --entrypoint "" -i "$image" sh -c 'xargs dpkg-query -W -f="\${Package} \${db:Status-Status}\n" 2>/dev/null' < "$work/wanted" > "$work/dpkg" || true
docker run --rm --entrypoint "" "$image" sh -c 'grep -hE "^URIs:" /etc/apt/sources.list.d/*.sources 2>/dev/null | cut -d" " -f2-; grep -hE "^deb " /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | cut -d" " -f2' > "$work/uris"
docker run --rm --entrypoint "" "$image" gpg --show-keys --with-colons /usr/share/keyrings/zabbix.gpg 2>/dev/null | awk -F: '$1=="pub"{p=1; next} $1=="fpr" && p{print $10} {p=0}' > "$work/fprs"

missing_pkgs() { # wanted dpkg -> packages not installed
  local p; while read -r p; do grep -qx "$p installed" "$2" || echo "$p"; done < "$1"
}
foreign_uris() { # uris -> URIs that are neither Debian nor Zabbix
  tr ' ' '\n' < "$1" | grep -v '^$' | grep -vE '^https?://(deb\.debian\.org/debian(-security)?|security\.debian\.org/debian-security|repo\.zabbix\.com/zabbix/[0-9.]+/debian)/?$' || true
}

assert_eq "" "$(missing_pkgs "$work/wanted" "$work/dpkg" | tr '\n' ' ')" "every package of packages-runtime.txt is installed ($(wc -l < "$work/wanted"))"
assert_eq "" "$(foreign_uris "$work/uris" | tr '\n' ' ')" "apt sources are only Debian and Zabbix"
assert_cmd "a Zabbix source is configured" -- grep -q 'repo.zabbix.com' "$work/uris"
assert_eq "$fpr" "$(tr '\n' ' ' < "$work/fprs" | sed 's/ $//')" "the Zabbix keyring holds only the pinned key"
assert_eq "uid=1000(asterisk) gid=1000(asterisk)" "$(docker run --rm --entrypoint "" "$image" id asterisk | cut -d' ' -f1-2)" "asterisk is 1000:1000"
assert_cmd "zabbix_agent2 runs" -- docker run --rm --entrypoint "" "$image" zabbix_agent2 -V

# negatives
{ cat "$work/wanted"; echo no-such-package-izpbx; } > "$work/wanted2"
assert_eq "no-such-package-izpbx" "$(missing_pkgs "$work/wanted2" "$work/dpkg")" "a missing package is reported"
{ cat "$work/uris"; echo "http://ppa.example.com/ubuntu"; } > "$work/uris2"
assert_eq "http://ppa.example.com/ubuntu" "$(foreign_uris "$work/uris2")" "a foreign apt source is reported"
curl -fsSL https://repo.zabbix.com/zabbix-official-repo.key | docker run --rm --entrypoint "" -i "$image" gpg --show-keys --with-colons 2>/dev/null \
  | awk -F: '$1=="pub"{p=1; next} $1=="fpr" && p{print $10} {p=0}' > "$work/allfprs"
assert_ne "$fpr" "$(tr '\n' ' ' < "$work/allfprs" | sed 's/ $//')" "the whole published key bundle would not pass the keyring check"

finish

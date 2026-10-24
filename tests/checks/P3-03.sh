#!/usr/bin/env bash
# P3-03: persistence.sh (symlinks to APP_DATA, <dir>.dist, .initialized).
# Run inside the image (bash and coreutils of the runtime), as root:
# - temporary tree (IZPBX_ROOT): two runs give the same tree (find -printf +
#   checksums), no nested .dist;
# - the real image tree with an empty /data: two runs (a restart) give the
#   same tree, /data seeded from .dist with the owners of the image, the
#   persisted paths are symlinks;
# - a 20.16.22 /data volume (fixture): no existing file or directory is
#   changed (content, mode, owner, mtime of files; mode and owner of dirs);
# - negative checks: seeding a non-empty target (bug simulated) is caught by
#   the 20.16 comparison; a real directory where the symlink should be is
#   refused instead of being nested into .dist.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-03
fx="$TESTS_DIR/fixtures/out/20.16.22"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

cat > "$work/lib.sh" <<'EOF'
set -Eeuo pipefail
export LC_ALL=C
. /usr/local/lib/izpbx/persistence.sh
# tree snapshot: type, mode, owner, path, link target, checksum of files
snap() { # dir...
  find "$@" -printf '%y %m %U:%G %p -> %l\n' | sort
  find "$@" -type f -print0 | sort -z | xargs -0r md5sum
}
# entries of the 20.16 volume: files (content, mode, owner, size, mtime) and
# dirs (mode, owner); a new file in a dir changes its mtime, which is allowed
snap_existing() { # dir
  find "$1" -type d -printf 'd %m %U:%G %p\n' | sort
  find "$1" \( -type f -o -type l \) -printf '%y %m %U:%G %s %T@ %p -> %l\n' | sort
  find "$1" -type f -print0 | sort -z | xargs -0r md5sum
}
nested() { find "$@" \( -path '*.dist/*.dist' -o -name '*.dist.dist' \) -print 2>/dev/null | head -5; }
EOF

# --- temporary tree
cat > "$work/tmptree.sh" <<'EOF'
. /t/lib.sh
r=/tmp/r
mkdir -p $r/etc/asterisk $r/var/lib/asterisk/sounds $r/root $r/var/log/apache2
echo conf > $r/etc/asterisk/asterisk.conf
echo snd > $r/var/lib/asterisk/sounds/a.gsm
echo amp > $r/etc/amportal.conf
chown -R 1000:1000 $r/var/lib/asterisk
export IZPBX_ROOT=$r APP_DATA=/data
persistence_setup 2>/dev/null; snap $r > /tmp/s1
persistence_setup 2>/dev/null; snap $r > /tmp/s2
diff /tmp/s1 /tmp/s2 >&2 && echo "same tree"
[ -z "$(nested $r)" ] && echo "no nested dist"
[ "$(readlink $r/etc/asterisk)" = $r/data/etc/asterisk ] && echo "link ok"
[ "$(cat $r/data/etc/asterisk/asterisk.conf)" = conf ] && echo "seeded"
[ "$(stat -c %u $r/data/var/lib/asterisk)" = 1000 ] && echo "owner kept"
[ "$(cat $r/data/etc/amportal.conf)" = amp ] && [ -L $r/etc/amportal.conf ] && echo "file linked"
[ -L $r/etc/freepbx.conf ] && echo "dangling file link"
[ -f $r/data/root/.initialized ] && echo "initialized stamp"
# negative: a real directory where the link should be
rm $r/etc/asterisk && mkdir $r/etc/asterisk
( persistence_setup ) 2>/dev/null || echo "refuses to nest"
EOF
out=$(docker run --rm --entrypoint "" -v "$work:/t:ro" "$image" bash /t/tmptree.sh 2>"$work/err1") || true
for m in "same tree" "no nested dist" "link ok" "seeded" "owner kept" "file linked" \
         "dangling file link" "initialized stamp" "refuses to nest"; do
  assert_contains "$out" "$m" "temporary tree: $m"
done
[ -s "$work/err1" ] && log "stderr: $(head -c 2000 "$work/err1")"

# --- real image tree, empty /data, run twice (restart)
cat > "$work/image.sh" <<'EOF'
. /t/lib.sh
export APP_DATA=/data
paths=(); for p in "${PERSIST_DIRS[@]}" "${PERSIST_FILES[@]}"; do paths+=("$p"); [ -e "$p.dist" ] && paths+=("$p.dist"); done
persistence_setup 2>/dev/null
list() { for p in "${PERSIST_DIRS[@]}" "${PERSIST_FILES[@]}"; do find "$p" "$p.dist" -maxdepth 0 -printf '%y %p -> %l\n' 2>/dev/null || true; done; snap /data; }
list > /tmp/s1
persistence_setup 2>/dev/null
list > /tmp/s2
diff /tmp/s1 /tmp/s2 >&2 && echo "same tree"
[ -z "$(nested / -xdev 2>/dev/null)" ] && echo "no nested dist"
ok=1; for p in "${PERSIST_DIRS[@]}"; do [ "$(readlink "$p")" = "/data$p" ] || { ok=; echo "not linked: $p" >&2; }; done
[ -n "$ok" ] && echo "all linked"
[ "$(stat -c %U /data/var/lib/asterisk)" = asterisk ] && echo "asterisk owner"
[ -f /data/var/lib/asterisk/.initialized ] && echo "initialized stamp"
diff <(cd /var/lib/asterisk.dist && find . | sort) <(cd /data/var/lib/asterisk && find . ! -name .initialized | sort) >&2 && echo "seeded from dist"
EOF
out=$(docker run --rm --entrypoint "" -v "$work:/t:ro" "$image" bash /t/image.sh 2>"$work/err2") || true
for m in "same tree" "no nested dist" "all linked" "asterisk owner" "initialized stamp" "seeded from dist"; do
  assert_contains "$out" "$m" "image tree: $m"
done
[ -s "$work/err2" ] && log "stderr: $(head -c 2000 "$work/err2")"

# --- 20.16.22 volume
cat > "$work/legacy.sh" <<'EOF'
. /t/lib.sh
export APP_DATA=/data
mkdir -p /data && tar -xzf /fx/data.tar.gz -C /data --same-owner --numeric-owner
snap_existing /data | sort > /tmp/before
grep -v '^d' /tmp/before | grep -c . > /tmp/n
# bug simulated: every target looks empty, so it is seeded over its data
if [ "${1:-}" = bug ]; then _dir_empty() { case "$1" in *.dist) [ -z "$(ls -A "$1")" ] ;; *) true ;; esac; }; fi
persistence_setup 2>/dev/null
# every line of before must still be there after the run (new ones are allowed)
snap_existing /data | sort > /tmp/after
missing=$(comm -23 /tmp/before /tmp/after | head -20)
if [ -z "$missing" ]; then echo "volume unchanged"; else printf '%s\n' "$missing" >&2; fi
echo "entries=$(cat /tmp/n)"
[ -d /data/var/log/httpd ] && echo "httpd logs kept"
[ "$(readlink /var/log/apache2)" = /data/var/log/apache2 ] && echo "apache2 linked"
EOF
out=$(docker run --rm --entrypoint "" -v "$work:/t:ro" -v "$fx:/fx:ro" "$image" bash /t/legacy.sh 2>"$work/err3") || true
assert_contains "$out" "volume unchanged" "20.16.22 volume: existing files and dirs unchanged"
assert_ne "entries=0" "$(grep -o 'entries=[0-9]*' <<<"$out")" "20.16.22 volume has files"
assert_contains "$out" "httpd logs kept" "20.16.22 volume: old Apache logs kept as an archive"
assert_contains "$out" "apache2 linked" "20.16.22 volume: /var/log/apache2 persisted"
[ -s "$work/err3" ] && log "stderr: $(head -c 1500 "$work/err3")"
out=$(docker run --rm --entrypoint "" -v "$work:/t:ro" -v "$fx:/fx:ro" "$image" bash /t/legacy.sh bug 2>/dev/null) || true
case "$out" in *"volume unchanged"*) rc=1 ;; *) rc=0 ;; esac
assert_eq 0 "$rc" "control: seeding a non-empty target is caught"
finish

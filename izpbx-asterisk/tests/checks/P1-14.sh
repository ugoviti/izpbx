#!/usr/bin/env bash
# P1-14: HEALTHCHECK declared in the Dockerfile (design H5).
# - docker inspect: the command is izpbx-healthcheck, start-period >= 30 min;
# - the image runs it: a container started without --health-* options gets a
#   health state from it (starting during the start period, the command runs:
#   at least one health log entry with its output);
# - negative check: an image built from the same Dockerfile without the
#   HEALTHCHECK line has no health check.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p1-14
dir="$REPO_DIR/izpbx-asterisk"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

hc=$(docker image inspect -f '{{json .Config.Healthcheck}}' "$image")
log "healthcheck: $hc"
test_cmd=$(docker image inspect -f '{{join .Config.Healthcheck.Test " "}}' "$image")
assert_contains "$test_cmd" "/usr/local/bin/izpbx-healthcheck" "the health command is izpbx-healthcheck"
# nanoseconds from the JSON (the template prints a duration such as 30m0s)
sp=$(sed -n 's/.*"StartPeriod":\([0-9]*\).*/\1/p' <<< "$hc")
assert_cmd "start-period >= 30 minutes ($((${sp:-0} / 1000000000)) s)" -- test "${sp:-0}" -ge $((30 * 60 * 1000000000))
assert_cmd "the health command is in the image" -- docker run --rm --entrypoint "" "$image" test -x /usr/local/bin/izpbx-healthcheck

c=$(t_run hc "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true)
assert_eq "starting" "$(docker inspect -f '{{.State.Health.Status}}' "$c")" "a new container is 'starting' (start period)"
assert_cmd "the image's health command runs (health log entry)" -- \
  t_wait_for 90 -- sh -c "docker inspect -f '{{len .State.Health.Log}}' $c | grep -qv '^0$'"
assert_contains "$(docker inspect -f '{{range .State.Health.Log}}{{.Output}}{{end}}' "$c")" "healthy" "the health log holds the output of izpbx-healthcheck"

grep -v '^HEALTHCHECK' "$dir/Dockerfile" > "$work/Dockerfile.nohc"
nohc=$(docker build -q -f "$work/Dockerfile.nohc" "$dir")
assert_eq "null" "$(docker image inspect -f '{{json .Config.Healthcheck}}' "$nohc")" "control: without the line the image has no health check"
docker rmi "$nohc" >/dev/null 2>&1 || true
finish

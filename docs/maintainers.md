# Maintainers: component updates and releases
Component versions and checksums live in `izpbx-asterisk/versions.env`; the FreePBX modules pre-downloaded into the image in `izpbx-asterisk/build/freepbx-modules.txt`. In `izpbx-asterisk`, `build/` holds only what the image build uses; maintainer tools are in `izpbx-asterisk/tools`, development notes (build and run from the sources) in [development.md](development.md).

Check for updates, then apply them (versions and sha256 together; when Asterisk changes, its bundled pjproject and jansson follow the release tarball):
```
izpbx-asterisk/tools/make-updates.sh            # report (exit 10 when updates are available)
izpbx-asterisk/tools/make-updates.sh --apply    # write versions.env and freepbx-modules.txt
```
Then rebuild, run `izpbx-asterisk/tests/run.sh all-done` and commit. When FreePBX, Asterisk, FOP2 or the Debian base change, go through [workarounds.md](workarounds.md): each workaround for an upstream defect says how to tell whether it is still needed.

Release the next patch version (`22.17.0` → `22.17.1` …) from `main` (or `release/X.Y` for a maintenance series):
```
izpbx-asterisk/tools/make-release.sh              # dry run: the CHANGELOG entry and the changes, nothing written
izpbx-asterisk/tools/make-release.sh --commit     # review the entry in $EDITOR, commit "X.Y.Z release" and tag X.Y.Z
izpbx-asterisk/tools/make-release.sh --push       # as --commit, then push the branch and the tag (starts the izpbx-release workflow)
izpbx-asterisk/tools/make-release.sh --rc --push  # release candidate X.Y.Z-rcN of the next version: only the tag, from any branch (pushed with the branch)
```
Write the changes under `## [Unreleased]` in `CHANGELOG.md` while you work: the release dates that block and adds one line per updated component by itself. If nothing was written there, the draft comes from the commit subjects, or from Claude Code with `--ai` (`claude -p`); review it before confirming. GitHub and Docker Hub are updated separately with the `izpbx-promote` workflow (Gitea > Actions > izpbx-promote > Run workflow): a `version` publishes that tag (git tag and branch on GitHub, image on Docker Hub, with branch `main` the Docker Hub overview from its README, made by `izpbx-asterisk/tools/readme-dockerhub.sh`); an empty `version` only pushes the branch to GitHub (and with `main` the overview). The README must stay under the 25000 bytes of Docker Hub: `izpbx-asterisk/tests/lint.sh` checks it.

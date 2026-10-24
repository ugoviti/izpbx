#!/usr/bin/env python3
"""Compare the defaults of env.sh with docs/env-contract.md (P3-02).

  env-compare.py CONTRACT VERSIONS_ENV DIFFERENCES DESIGN ACTUAL

DIFFERENCES: a 22.17 default "<REMOVED>" means a variable of the contract
that 22.17 no longer has (it must not be declared in env.sh).
ACTUAL: "VAR<tab>value" lines printed by sourcing env.sh in an empty
environment (HOSTNAME=izpbx-test); "<UNSET>" for an undeclared variable.
Prints one line per mismatch and "checked=N"; exit 1 on any mismatch.
"""
import re, sys

contract, versions_env, differences, design, actual_file = sys.argv[1:6]
HOST = "izpbx-test"
# computed at start by the module that needs them: declared empty in env.sh
COMPUTED = {"PHONEBOOK_ADDRESS", "FREEPBX_VER_INSTALLED", "FOP2_AMI_HOST", "FOP2_AMI_PORT",
            "FOP2_AMI_USERNAME", "FOP2_AMI_PASSWORD", "FOP2_LICENSE_IFACE"}

rows, section = {}, 0
for line in open(contract):
    m = re.match(r"^## (\d+)\.", line)
    if m:
        section = int(m.group(1))
    if section >= 15:
        break
    m = re.match(r"^\| `([A-Z0-9_]+)` \| ([^|]*)\|", line)
    if m:
        rows[m.group(1)] = m.group(2).strip()

versions = dict(l.strip().split("=", 1) for l in open(versions_env) if re.match(r"^[A-Z0-9_]+=", l))
section13 = re.search(r"^## 13\..*?(?=^## 14\.)", open(design).read(), re.S | re.M).group(0)
diffs, problems = {}, []
for l in open(differences):
    if l.startswith("#") or not l.strip():
        continue
    var, value, keyword = (l.rstrip("\n").split("\t") + ["", ""])[:3]
    if value.startswith("versions.env:"):
        value = versions[value.split(":", 1)[1]]
    diffs[var] = value
    if not keyword or keyword not in section13:
        problems.append(f"{var}: difference not listed in §13 of the design (keyword '{keyword}')")

actual = dict(l.rstrip("\n").split("\t", 1) for l in open(actual_file) if "\t" in l)

def expected(var, seen=()):
    # a reference back into the chain (SMTP_MAIL_TO <-> ROOT_MAILTO) is the
    # value given by the user: empty in an empty environment
    if var in seen:
        return ""
    seen = seen + (var,)
    if var in diffs:
        return diffs[var]
    if var in COMPUTED:
        return ""
    if var == "HOSTNAME":
        return HOST
    d = rows[var]
    m = re.match(r"^`\$\{?([A-Z_]+)\}?`, then `([^`]*)`", d)
    if m:
        return expected(m.group(1), seen) or m.group(2)
    m = re.match(r"^`\$\{?([A-Z_]+)\}?`", d)
    if m:
        return expected(m.group(1), seen)
    m = re.match(r"^(?:image: )?(?:build arg \()?`([^`]*)`", d)
    if m:
        return m.group(1)
    if re.match(r"^(empty|unset|file default|image: empty|image: build arg)", d):
        return ""
    raise SystemExit(f"unhandled default for {var}: {d}")

norm = lambda s: " ".join(s.split())
for var in rows:
    want, got = expected(var), actual.get(var, "<UNSET>")
    if want == "<REMOVED>":
        if got != "<UNSET>":
            problems.append(f"{var}: removed in 22.17 but still declared in env.sh")
    elif got == "<UNSET>":
        problems.append(f"{var}: not declared in env.sh")
    elif norm(got) != norm(want):
        problems.append(f"{var}: env.sh '{got}', expected '{want}'")
print("\n".join(problems))
print(f"checked={len(rows)}")
sys.exit(1 if problems else 0)

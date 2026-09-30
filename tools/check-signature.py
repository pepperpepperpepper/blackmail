#!/usr/bin/env python3
"""check-signature.py - does every bundle in a signed .ipa carry its OWN identity?

The question zsign got wrong (B-036). One `-e` signs the whole archive, so a
share extension at `wtf.uhoh.blackmail.share` came out claiming the app's
`application-identifier`, and iOS refuses a bundle whose signature names
another. Nothing about such an archive looks wrong until installd reads it
on a device, so it is read here instead, straight out of the Mach-O.

For the app and every PlugIns/*.appex it checks:

  - entitlements: application-identifier is TEAM.<its own CFBundleIdentifier>,
    com.apple.developer.team-identifier is TEAM, keychain-access-groups holds
    the group the app and the extension share, get-task-allow is false, and
    the DER copy says the same as the XML one. An app with no extension
    claims no keychain-access-groups at all: it is signed exactly as every
    build before the extension was, the one way proven on his iPad;
  - the CodeDirectory: its identifier is the bundle id and its team is TEAM;
  - the special slots: Info.plist, CodeResources and both entitlement blobs
    hash to what the CodeDirectory recorded, and so does every code page;
  - the CMS signature is over that CodeDirectory (openssl, chain not checked);
  - the seal: every file in _CodeSignature/CodeResources hashes as recorded,
    no file in the bundle is left out of it, and the extension is sealed as
    it is now signed, whether the seal holds its cdhash (codesign) or its
    files' hashes (zsign) -- which is what re-signing an extension after the
    fact breaks;
  - embedded.mobileprovision, where there is one: the team, and that the
    profile's own entitlements allow what the bundle claims.

Usage:  check-signature.py SIGNED.ipa|Payload-dir [--team T] [--group G]
Exit 0 only when every check passed.
"""
import argparse
import fnmatch
import hashlib
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

TEAM = "JGLH7HX44Y"
SHARED_GROUP = TEAM + ".wtf.uhoh.blackmail.shared"

LC_CODE_SIGNATURE = 0x1D
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CSMAGIC_CODEDIRECTORY = 0xFADE0C02
HASHES = {1: ("sha1", 20), 2: ("sha256", 32), 3: ("sha256", 20), 4: ("sha384", 48)}

failures = []


def check(cond, what):
    print(("  ok    " if cond else "  FAIL  ") + what)
    if not cond:
        failures.append(what)
    return cond


def macho_signature(path):
    """The file's bytes, and its embedded signature's blobs keyed by slot
    type (0 CodeDirectory, 5 entitlements, 7 DER entitlements, 0x10000 CMS)."""
    data = open(path, "rb").read()
    magic = struct.unpack("<I", data[:4])[0]
    if magic in (0xCAFEBABE, 0xBEBAFECA):
        raise ValueError("fat binary; expected one arm64 slice")
    if magic != 0xFEEDFACF:
        raise ValueError(f"not a 64-bit Mach-O (magic {magic:#x})")
    ncmds = struct.unpack("<I", data[16:20])[0]
    off = 32
    sig = None
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", data[off:off + 8])
        if cmd == LC_CODE_SIGNATURE:
            sig = struct.unpack("<II", data[off + 8:off + 16])
        off += size
    if sig is None:
        raise ValueError("no LC_CODE_SIGNATURE")
    start, length = sig
    blob = data[start:start + length]
    smagic, _, count = struct.unpack(">III", blob[:12])
    if smagic != CSMAGIC_EMBEDDED_SIGNATURE:
        raise ValueError(f"signature superblob magic {smagic:#x}")
    blobs = {}
    for i in range(count):
        kind, boff = struct.unpack(">II", blob[12 + 8 * i:20 + 8 * i])
        _, blen = struct.unpack(">II", blob[boff:boff + 8])
        blobs[kind] = blob[boff:boff + blen]
    return data, blobs


def code_directory(cd):
    (magic, length, version, flags, hash_off, ident_off, n_special, n_code,
     code_limit, hash_size, hash_type, _, page_log) = struct.unpack(
        ">IIIIIIIIIBBBB", cd[:40])
    assert magic == CSMAGIC_CODEDIRECTORY
    ident = cd[ident_off:cd.index(b"\0", ident_off)].decode()
    team = None
    if version >= 0x20200:
        team_off = struct.unpack(">I", cd[48:52])[0]
        if team_off:
            team = cd[team_off:cd.index(b"\0", team_off)].decode()
    return {
        "ident": ident, "team": team, "hash": HASHES[hash_type],
        "hash_type": hash_type, "hash_off": hash_off, "n_special": n_special,
        "n_code": n_code, "code_limit": code_limit, "page": 1 << page_log,
        "hash_size": hash_size, "raw": cd,
    }


def slot(cd, n):
    """Special slot n (1 = Info.plist ... 7 = DER entitlements), counted back
    from the first code hash."""
    at = cd["hash_off"] - n * cd["hash_size"]
    return cd["raw"][at:at + cd["hash_size"]]


def digest(cd, data):
    name, size = cd["hash"]
    return hashlib.new(name, data).digest()[:size]


# Weakest to strongest: SHA-1, truncated SHA-256, SHA-256, SHA-384.
STRENGTH = {1: 0, 3: 1, 2: 2, 4: 3}


def strength(cd):
    return STRENGTH[cd["hash_type"]]


def best_cd(blobs):
    """The CodeDirectory the system would take: the strongest hash present."""
    cds = [code_directory(b) for k, b in blobs.items()
           if k == 0 or 0x1000 <= k < 0x1005]
    return max(cds, key=strength)


def cdhash(blobs):
    cd = best_cd(blobs)
    return hashlib.new(cd["hash"][0], cd["raw"]).digest()[:20]


def der_entitlements(blob):
    """Enough DER to compare with the XML: the tags zsign writes (context
    [16] dictionary of SEQUENCE { UTF8String key, value }), where a value is
    a BOOLEAN, UTF8String or SEQUENCE of UTF8String."""
    def read(buf, i):
        tag = buf[i]
        n = buf[i + 1]
        i += 2
        if n & 0x80:
            k = n & 0x7F
            n = int.from_bytes(buf[i:i + k], "big")
            i += k
        return tag, buf[i:i + n], i + n

    def value(tag, body):
        if tag == 0x01:
            return body != b"\0"
        if tag == 0x0C:
            return body.decode()
        if tag == 0x30:
            out, i = [], 0
            while i < len(body):
                t, b, i = read(body, i)
                out.append(value(t, b))
            return out
        if tag == 0x31 or tag == 0xB0:
            d, i = {}, 0
            while i < len(body):
                _, pair, i = read(body, i)
                kt, kb, j = read(pair, 0)
                vt, vb, _ = read(pair, j)
                d[value(kt, kb)] = value(vt, vb)
            return d
        if tag == 0x02:
            return int.from_bytes(body, "big")
        raise ValueError(f"DER tag {tag:#x}")

    tag, body, _ = read(blob, 8)
    assert tag == 0x70, "DER entitlements must open with the [APPLICATION 16] tag"
    _, _, i = read(body, 0)               # version INTEGER 1
    t, b, _ = read(body, i)
    return value(t, b)


def cms_signs(cms_blob, cd_raw, scratch):
    """True when the CMS signature is a valid signature over the
    CodeDirectory. Trust in the chain is not the question here."""
    if shutil.which("openssl") is None:
        return None
    sig = os.path.join(scratch, "sig.der")
    content = os.path.join(scratch, "cd.bin")
    with open(sig, "wb") as f:
        f.write(cms_blob[8:])
    with open(content, "wb") as f:
        f.write(cd_raw)
    r = subprocess.run(["openssl", "cms", "-verify", "-inform", "DER", "-binary",
                        "-noverify", "-in", sig, "-content", content,
                        "-out", os.devnull], capture_output=True)
    return r.returncode == 0


def profile_entitlements(path):
    der = open(path, "rb").read()
    r = subprocess.run(["openssl", "smime", "-inform", "der", "-verify", "-noverify"],
                       input=der, capture_output=True)
    return plistlib.loads(r.stdout)


def allowed(claimed, granted):
    """Whether a profile's entitlement value (which may be a wildcard pattern
    or a list of them) permits the value a signature claims."""
    patterns = granted if isinstance(granted, list) else [granted]
    values = claimed if isinstance(claimed, list) else [claimed]
    if isinstance(claimed, bool):
        return claimed == granted or claimed is False
    return all(any(fnmatch.fnmatchcase(v, p) for p in patterns) for v in values)


def check_bundle(root, bundle, scratch, team, group, shares):
    here = os.path.join(root, bundle)
    info = plistlib.load(open(os.path.join(here, "Info.plist"), "rb"))
    bid = info["CFBundleIdentifier"]
    exe = os.path.join(here, info["CFBundleExecutable"])
    print(f"\n{bundle}  ({bid})")

    try:
        data, blobs = macho_signature(exe)
    except ValueError as e:
        check(False, f"{bundle}: signature readable ({e})")
        return None
    cd = best_cd(blobs)

    xml = plistlib.loads(blobs[5][8:]) if 5 in blobs else {}
    want = f"{team}.{bid}"
    check(xml.get("application-identifier") == want,
          f"application-identifier is {want} (signed: {xml.get('application-identifier')})")
    check(xml.get("com.apple.developer.team-identifier") == team,
          f"team-identifier is {team}")
    if shares:
        check(group in (xml.get("keychain-access-groups") or []),
              f"keychain-access-groups holds {group} (signed: {xml.get('keychain-access-groups')})")
    else:
        check("keychain-access-groups" not in xml,
              f"no keychain-access-groups without an extension "
              f"(signed: {xml.get('keychain-access-groups')})")
    check(xml.get("get-task-allow") is False, "get-task-allow is false")
    if 7 in blobs:
        check(der_entitlements(blobs[7]) == xml, "DER entitlements say what the XML says")

    check(cd["ident"] == bid, f"CodeDirectory identifier is {bid} (signed: {cd['ident']})")
    check(cd["team"] == team, f"CodeDirectory team is {team} (signed: {cd['team']})")

    code = cd["page"]
    pages_ok = all(
        cd["raw"][cd["hash_off"] + i * cd["hash_size"]:][:cd["hash_size"]]
        == digest(cd, data[i * code:min((i + 1) * code, cd["code_limit"])])
        for i in range(cd["n_code"]))
    check(pages_ok, f"all {cd['n_code']} code page hashes match")
    check(slot(cd, 1) == digest(cd, open(os.path.join(here, "Info.plist"), "rb").read()),
          "Info.plist hash matches the signature")
    seal_path = os.path.join(here, "_CodeSignature", "CodeResources")
    check(os.path.exists(seal_path) and slot(cd, 3) == digest(cd, open(seal_path, "rb").read()),
          "CodeResources hash matches the signature")
    if 5 in blobs:
        check(slot(cd, 5) == digest(cd, blobs[5]), "entitlements hash matches the signature")
    if 7 in blobs and cd["n_special"] >= 7:
        check(slot(cd, 7) == digest(cd, blobs[7]), "DER entitlements hash matches the signature")
    if 0x10000 in blobs:
        verdict = cms_signs(blobs[0x10000], blobs[0], scratch)
        if verdict is not None:
            check(verdict, "CMS signature is over the CodeDirectory")
    else:
        check(False, "has a CMS signature (not ad-hoc)")

    prov = os.path.join(here, "embedded.mobileprovision")
    if os.path.exists(prov):
        p = profile_entitlements(prov)
        granted = p.get("Entitlements", {})
        check(team in p.get("TeamIdentifier", []), "profile is the team's")
        for key, claimed in xml.items():
            check(key in granted and allowed(claimed, granted[key]),
                  f"profile allows {key}")
    elif bundle.endswith(".appex"):
        check(False, "extension carries embedded.mobileprovision")

    return cdhash(blobs)


def check_seal(root, bundle, nested):
    """The seal of `bundle`: every file hashed, nothing left out, and each
    nested bundle recorded by the cdhash it really has."""
    here = os.path.join(root, bundle)
    seal = plistlib.load(open(os.path.join(here, "_CodeSignature", "CodeResources"), "rb"))
    files2 = seal.get("files2", {})
    info = plistlib.load(open(os.path.join(here, "Info.plist"), "rb"))
    exe = info["CFBundleExecutable"]
    inner = [os.path.relpath(n, bundle) for n in nested
             if n != bundle and n.startswith(bundle.rstrip("/") + "/")]

    bad = []
    for name, entry in files2.items():
        if not isinstance(entry, dict):
            continue
        path = os.path.join(here, name)
        if "cdhash" in entry:
            full = os.path.normpath(os.path.join(bundle, name))
            actual = nested.get(full)
            if actual != entry["cdhash"]:
                bad.append(f"{name}: sealed cdhash {entry['cdhash'].hex()} "
                           f"but the bundle is signed {actual.hex() if actual else 'not at all'}")
        elif "hash2" in entry:
            if not os.path.isfile(path) or \
               hashlib.sha256(open(path, "rb").read()).digest() != entry["hash2"]:
                bad.append(f"{name}: hash differs from the seal")
    check(not bad, f"{bundle}: every sealed file and nested bundle matches"
          + ("" if not bad else " -- " + "; ".join(bad[:4])))

    unsealed = []
    for dirpath, _, names in os.walk(here):
        rel_dir = os.path.relpath(dirpath, here)
        if rel_dir.split(os.sep)[0] == "_CodeSignature":
            continue
        if any(rel_dir == n or rel_dir.startswith(n + os.sep) for n in inner):
            continue
        for n in names:
            rel = os.path.normpath(os.path.join(rel_dir, n))
            if rel in (exe, "Info.plist", "PkgInfo") or rel in files2:
                continue
            unsealed.append(rel)
    check(not unsealed, f"{bundle}: nothing in the bundle is outside the seal"
          + ("" if not unsealed else " -- " + ", ".join(unsealed[:6])))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ipa")
    ap.add_argument("--team", default=TEAM)
    ap.add_argument("--group", default=SHARED_GROUP)
    ap.add_argument("--require-extension", action="store_true",
                    help="fail when the archive has no app extension")
    args = ap.parse_args()

    scratch = tempfile.mkdtemp(prefix="check-signature-",
                               dir=os.environ.get("CHECK_SIGNATURE_SCRATCH"))
    try:
        if os.path.isdir(args.ipa):
            root = args.ipa
        else:
            with zipfile.ZipFile(args.ipa) as z:
                z.extractall(scratch)
            root = scratch
        payload = os.path.join(root, "Payload") if os.path.isdir(os.path.join(root, "Payload")) else root
        apps = [d for d in os.listdir(payload) if d.endswith(".app")]
        if len(apps) != 1:
            raise SystemExit(f"expected one .app in {payload}, found {apps}")
        app = apps[0]
        plugins = os.path.join(payload, app, "PlugIns")
        extensions = sorted(os.path.join(app, "PlugIns", d) for d in os.listdir(plugins)
                            if d.endswith(".appex")) if os.path.isdir(plugins) else []
        if args.require_extension:
            check(bool(extensions), "the archive carries an app extension")

        nested = {}
        # Innermost first, as they are signed, so the app's seal is checked
        # against the extension signatures as they now stand.
        for bundle in extensions + [app]:
            h = check_bundle(payload, bundle, scratch, args.team, args.group,
                             shares=bool(extensions))
            if h is not None:
                nested[bundle] = h
        for bundle in extensions + [app]:
            check_seal(payload, bundle, nested)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print()
    if failures:
        print(f"FAILED: {len(failures)} check(s)")
        return 1
    print("PASSED: every bundle is signed as itself, and the seal holds")
    return 0


if __name__ == "__main__":
    sys.exit(main())

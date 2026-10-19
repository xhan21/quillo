#!/usr/bin/env python3
"""Create/reuse a local development identity, without changing certificate trust.

Run explicitly once, not during builds. The non-exportable key stays in the
login keychain; only its public fingerprint is stored in Application Support.
This is for one's own Mac, not a Developer ID or notarized distribution identity.
"""
import hashlib
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile

NAME = "Quillo Local Development"
CONFIG = Path.home() / "Library/Application Support/Quillo/Signing/identity.sha1"


def run(*args, input=None):
    result = subprocess.run(args, input=input, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout


def main():
    os.umask(0o077)
    identities = run("/usr/bin/security", "find-identity", "-p", "codesigning")
    if CONFIG.exists():
        fingerprint = CONFIG.read_text().strip()
        if not re.fullmatch(r"[A-Fa-f0-9]{40}", fingerprint) or fingerprint not in identities:
            raise RuntimeError("Configured signing key is unavailable. Restore it; do not replace it silently.")
    else:
        found = set(re.findall(r'([A-Fa-f0-9]{40}) "' + re.escape(NAME) + r'"', identities))
        if len(found) > 1:
            raise RuntimeError("Multiple Quillo identities exist. Select one explicitly before continuing.")
        fingerprint = next(iter(found), None)

    with tempfile.TemporaryDirectory(prefix="quillo-signing-") as temp:
        temp = Path(temp)
        if not fingerprint:
            config = temp / "certificate.cnf"
            config.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = extensions
[subject]
CN = Quillo Local Development
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
            key, cert, bundle = temp / "key.pem", temp / "certificate.pem", temp / "identity.p12"
            run("/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:3072", "-nodes",
                "-keyout", str(key), "-out", str(cert), "-days", "3650", "-sha256", "-config", str(config))
            der = subprocess.check_output(["/usr/bin/openssl", "x509", "-in", str(cert), "-outform", "DER"])
            fingerprint = hashlib.sha1(der).hexdigest().upper()
            # Temporary files are private and removed after import, including on failure.
            temporary_passphrase = secrets.token_hex(32)
            run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
                "-out", str(bundle), "-name", NAME, "-descert", "-passout", "stdin", input=temporary_passphrase + "\n")
            login = Path.home() / "Library/Keychains/login.keychain-db"
            if not login.exists():
                raise RuntimeError("Login keychain was not found. Use Keychain Access to set up signing.")
            run("/usr/bin/security", "import", str(bundle), "-k", str(login), "-f", "pkcs12",
                "-P", temporary_passphrase, "-x", "-T", "/usr/bin/codesign")

        # Check that changing the program keeps its identity, with no microphone access.
        requirement = None
        for revision in (1, 2):
            source, binary = temp / "probe.c", temp / "probe"
            source.write_text(f"int main(void) {{ return {revision}; }}\n")
            run("/usr/bin/xcrun", "clang", str(source), "-o", str(binary))
            run("/usr/bin/codesign", "--force", "--sign", fingerprint,
                "--identifier", "jp.xuhan.QuilloSigningProbe", str(binary))
            run("/usr/bin/codesign", "--verify", "--strict", str(binary))
            result = subprocess.run(["/usr/bin/codesign", "-d", "-r-", str(binary)], capture_output=True, text=True, check=True)
            match = re.search(r"designated => (.+)", result.stdout + result.stderr)
            if not match or "cdhash" in match[1] or "certificate" not in match[1]:
                raise RuntimeError("The signing identity is not certificate-bound.")
            if requirement is not None and requirement != match[1]:
                raise RuntimeError("The identity changed across builds.")
            requirement = match[1]
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        CONFIG.write_text(fingerprint + "\n")
        print("Local Quillo signing identity ready; stable across two different programs.")
        print("Private key: login keychain, non-exportable; no certificate trust settings changed.")
        print("Configuration:", CONFIG)


if __name__ == "__main__":
    main()

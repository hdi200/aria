#!/usr/bin/env python3
"""Owner-run, interactive upload-key setup. Never run through an agent/chat log."""
import getpass
import os
from pathlib import Path
import shutil
import subprocess


def main():
    repo = Path(__file__).resolve().parents[1]
    properties = repo / 'Aria/Android/app/keystore.properties'
    if properties.exists():
        raise SystemExit('keystore.properties already exists; refusing to replace it.')
    key_path = Path(input('New upload keystore path OUTSIDE all source repositories: ')).expanduser().resolve()
    if key_path.is_relative_to(repo.parent) or key_path.exists():
        raise SystemExit('Use a new keystore path outside the source tree.')
    password = getpass.getpass('New keystore/key password (at least 6 characters): ')
    if len(password) < 6 or password != getpass.getpass('Repeat password: '):
        raise SystemExit('Passwords do not match or are too short.')
    keytool = shutil.which('keytool')
    if not keytool:
        raise SystemExit('Install a JDK and add its bin directory to PATH first.')
    key_path.parent.mkdir(parents=True, exist_ok=True)
    previous_umask = os.umask(0o077)
    try:
        env = dict(os.environ, ARIA_UPLOAD_STORE_PASSWORD=password)
        # Password is never a command-line argument. keytool asks the owner for identity.
        subprocess.run([keytool, '-genkeypair', '-v', '-keystore', str(key_path),
                        '-storetype', 'PKCS12', '-alias', 'aria-upload', '-keyalg', 'RSA',
                        '-keysize', '2048', '-validity', '10000',
                        '-storepass:env', 'ARIA_UPLOAD_STORE_PASSWORD',
                        '-keypass:env', 'ARIA_UPLOAD_STORE_PASSWORD'], env=env, check=True)
        key_path.chmod(0o600)
        def escape(value):
            return ''.join('\\u%04x' % ord(c) if ord(c) > 126 or ord(c) < 32
                           else '\\' + c if c in '\\:=#! ' else c for c in value)
        with properties.open('x', encoding='ascii') as output:
            for name, value in [('storeFile', str(key_path)), ('storePassword', password),
                                ('keyAlias', 'aria-upload'), ('keyPassword', password)]:
                output.write(name + '=' + escape(value) + '\n')
        properties.chmod(0o600)
    finally:
        os.umask(previous_umask)
    print('Upload key and ignored properties created. Back up the key and password privately.')
    print('Do not paste credentials into chat. Use Play App Signing with a Google-generated app signing key.')


if __name__ == '__main__':
    main()

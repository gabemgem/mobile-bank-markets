"""Install the official NetLogo 7 Fetch extension alongside the model."""
from pathlib import Path
import hashlib
import io
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
URL = ('https://raw.githubusercontent.com/NetLogo/NetLogo-Libraries/'
       'cfbeb0b9293cdf91e1bcecb20a2a254f0587f922/extensions/fetch-1.0.5.zip')
ZIP_SHA256 = '7660e33cfe65f32a07079bb75e94be25a602d71bc0a8efdc1c087066a02b0bfa'
JAR_SHA256 = 'b0b3ecae2de1ec3f8a9c37ec58396313e7aa882e141647f97fef6059484fba3a'


def main():
    target = ROOT / 'fetch' / 'fetch.jar'
    if target.exists():
        if hashlib.sha256(target.read_bytes()).hexdigest() != JAR_SHA256:
            raise SystemExit('Existing fetch.jar differs; preserve it and resolve the version before installing.')
        print('Verified existing official Fetch 1.0.5 (NetLogo API 7.0, Java 11 compatible).')
        return
    data = urllib.request.urlopen(URL, timeout=30).read()
    if hashlib.sha256(data).hexdigest() != ZIP_SHA256:
        raise SystemExit('Fetch archive checksum mismatch; nothing installed.')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        jar = archive.read('fetch.jar')
    if hashlib.sha256(jar).hexdigest() != JAR_SHA256:
        raise SystemExit('Fetch jar checksum mismatch; nothing installed.')
    target.parent.mkdir(exist_ok=True)
    target.write_bytes(jar)
    print(f'Installed official Fetch 1.0.5 in {target.parent}.')


if __name__ == '__main__':
    main()

#!/usr/bin/env bash
# Repair stale trust material inside the disposable official CI container.
set -Eeuo pipefail
mkdir -p /buildd/artifacts/apt-sources-before
cp -a /etc/apt/sources.list.d/. /buildd/artifacts/apt-sources-before/
echo '0f8014a75ed6ef25ee00fa8f6142290ee1679fe0c701b48b71ed6e9c57b32f60  /project/config/droidian-archive-keyring.gpg' | sha256sum --check
install -D -m 0644 /project/config/droidian-archive-keyring.gpg /usr/share/archive-keyrings/droidian.gpg
install -D -m 0644 /project/config/droidian-archive-keyring.gpg /etc/apt/trusted.gpg.d/droidian.gpg
# The old official build image explicitly references this armored key path
# for production.repo.droidian.org. Refresh it from the official keyring.
install -D -m 0644 /project/config/droidian-archive-keyring.asc /etc/apt/droidian-gpg.d/hybris-mobian.asc
# Mobian's expired repository is unrelated to this kernel build. Disable
# only that source in this container, without bypassing signature checks.
python3 - <<'PY'
from pathlib import Path
for path in Path('/etc/apt/sources.list.d').glob('*.list'):
    lines = path.read_text().splitlines()
    output = ['# CI disabled expired optional Mobian source: ' + line
              if not line.lstrip().startswith('#') and 'repo.mobian-project.org' in line else line
              for line in lines]
    path.write_text('\n'.join(output) + '\n')
PY
cp -a /etc/apt/sources.list.d /buildd/artifacts/apt-sources-effective

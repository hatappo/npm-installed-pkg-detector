import sys
from collections import defaultdict

packages = defaultdict(list)

with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or "@" not in line:
            continue
        # 最後の @ で分割
        name, version = line.rsplit("@", 1)
        packages[name].append(version)

for name, versions in packages.items():
    print(f"{name} ({', '.join(versions)})")

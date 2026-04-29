# 🐳 Docker One Click Installation

This folder contains OS-based Docker installation scripts.

## Supported OS

| OS | Script |
|---|---|
| Debian / Ubuntu | `debian.sh` |
| Amazon Linux | `awslinux.sh` |
| CentOS / RHEL | `centos.sh` |

## Run Installation

### Debian / Ubuntu

```bash
chmod +x debian.sh
./debian.sh

### Amazon Linux

chmod +x awslinux.sh
./awslinux.sh

### CentOS / RHEL

chmod +x centos.sh
./centos.sh

### Verify Installation

docker --version

docker compose version

sudo systemctl status docker

### Test Docker

docker run hello-world

### Important : After installation, logout and login again:

exit

Then reconnect to your server.

---

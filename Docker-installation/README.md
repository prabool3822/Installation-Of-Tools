# 🐳 Docker Installation Automation

This repository contains simple shell scripts to install Docker on different Linux operating systems.

## 📌 What is Docker?

Docker is a containerization platform used to package applications with all required dependencies.  
It helps developers and DevOps engineers run applications consistently across different environments.

## 📁 Files

| File | Purpose |
|---|---|
| `debian.sh` | Install Docker on Debian/Ubuntu |
| `awslinux.sh` | Install Docker on Amazon Linux |
| `centos.sh` | Install Docker on CentOS/RHEL |
| `commands.md` | Useful Docker commands |
| `Steps.md` | Step-by-step installation guide |
| `checklist.md` | Verification checklist |
| `one_click_install.md` | Quick install instructions |

## 🚀 Quick Start

Clone the repository:

```bash
git clone <your-repo-url>
cd Docker-installation

### Run script according to your OS:

chmod +x debian.sh
./debian.sh

### For Amazon Linux:

chmod +x awslinux.sh
./awslinux.sh

### For CentOS:

chmod +x centos.sh
./centos.sh

### ✅ Verify

	docker --version
	docker compose version
	docker run hello-world

### ⚠️ Note

If Docker works only with sudo, logout and login again because the user was added to the Docker group during installation.

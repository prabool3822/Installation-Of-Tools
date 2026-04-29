#!/bin/bash

set -e

echo "===================================="
echo " Docker Installation for CentOS/RHEL"
echo "===================================="

sudo dnf update -y
sudo dnf install -y yum-utils

sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker $USER

echo "===================================="
echo " Docker installed successfully!"
echo " Logout and login again to use docker without sudo."
echo "===================================="

docker --version
docker compose version


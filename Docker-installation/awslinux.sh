#!/bin/bash

set -e

echo "===================================="
echo " Docker Installation for Amazon Linux"
echo "===================================="

sudo yum update -y
sudo yum install -y docker

sudo systemctl enable docker
sudo systemctl start docker

sudo usermod -aG docker ec2-user || true
sudo usermod -aG docker $USER || true

echo "===================================="
echo " Docker installed successfully!"
echo " Logout and login again to use docker without sudo."
echo "===================================="

docker --version

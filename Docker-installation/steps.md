# Docker Installation Steps

## Step 1: Check OS

```bash
cat /etc/os-release

## Step 2: Choose Script

OS	Script
Ubuntu / Debian	debian.sh
Amazon Linux	awslinux.sh
CentOS / RHEL	centos.sh

## Step 3: Give Execute Permission

chmod +x script-name.sh

Example:

chmod +x debian.sh
Step 4: Run Script
./debian.sh

## Step 5: Verify Docker

docker --version
docker compose version

## Step 6: Start Docker

sudo systemctl start docker
Step 7: Enable Docker on Boot
sudo systemctl enable docker

## Step 8: Test Docker

docker run hello-world

## Step 9: Run Docker Without Sudo

If Docker says permission denied, logout and login again:

exit

Then reconnect to your server.


---


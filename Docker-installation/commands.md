# Useful Docker Commands

## Check Docker Version

```bash

docker --version

## Check Docker Compose Version

docker compose version

## Docker Service Status

sudo systemctl status docker

## Start Docker

sudo systemctl start docker

## Stop Docker

sudo systemctl stop docker

## Restart Docker

sudo systemctl restart docker

## Enable Docker on Boot

sudo systemctl enable docker

## Run Test Container

docker run hello-world

## List Running Containers

docker ps

## List All Containers

docker ps -a

## List Images

docker images

## Pull Image

docker pull nginx

## Run Nginx Container

docker run -d --name nginx-container -p 80:80 nginx

## Stop Container

docker stop nginx-container

## Start Container

docker start nginx-container

## Remove Container

docker rm nginx-container

## Remove Image

docker rmi nginx

## View Logs

docker logs container-name

## Enter Running Container

docker exec -it container-name bash

## For Alpine containers:

docker exec -it container-name sh

## Remove Unused Data

docker system prune

---

#!/bin/bash

host_port=11434
container_port=11434

read -r -p "Do you want rose in Docker with GPU support? (y/n): " use_gpu

docker rm -f rose || true
docker pull qompass/rose:latest

docker_args="-d -v rose:/root/.rose -p $host_port:$container_port --name rose qompass/rose"

if [ "$use_gpu" = "y" ]; then
    docker_args="--gpus=all $docker_args"
fi

docker run $docker_args

docker image prune -f

#!/bin/bash
set -x

export WEAVE_HOSTS=""
export TOTAL_NODES=2
export PWD=`pwd`

# quick reset hack
for i in `docker-machine ls | grep -v "NAME" | awk '{ print $1; }'`;
do
	docker-machine rm -f $i;
done

# setup swarm nodes
for i in $(seq 1 $TOTAL_NODES); do
	if [ $i == 1 ]; then
		export SWARM_MASTER="--swarm-master";
		export CONSUL_MASTER="127.0.0.1"
	else
		export CONSUL_MASTER=$(docker-machine ip swarm-node-1)
		export SWARM_MASTER=""
	fi

	docker-machine create -d virtualbox --swarm ${SWARM_MASTER} --swarm-discovery="consul://${CONSUL_MASTER}:8500" --engine-opt="cluster-store=consul://${CONSUL_MASTER}:8500" --engine-opt="cluster-advertise=eth1:2376" swarm-node-$i
	export WEAVE_HOSTS="${WEAVE_HOSTS} $(docker-machine ip swarm-node-$i)"

	if [ $i == 1 ]; then
		# configure consul-master
		eval $(docker-machine env swarm-node-$i)
		docker-compose -f compose/consul-master.yml up -d
	else
		# configure consul-slave
		eval $(docker-machine env swarm-node-$i)
		docker-compose -f compose/consul-slave.yml up -d
	fi
done

# configure registrator in the swarm master
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/registrator.yml up -d

# run some apps
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/apps.yml up -d

# now lets test some scaling
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/apps.yml scale web=10

export SWARM_MASTER_NODE=$(docker-machine ip swarm-node-1)

echo "Checking Docker Machine List:";
docker-machine ls

echo "Checking Swarm Status:";
eval $(docker-machine env --swarm swarm-node-1)
docker info

echo "CONSUL UI = http://${CONSUL_MASTER}:8500";
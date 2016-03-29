#!/bin/bash
# set -x

export LOADBALANCERS=""
export TOTAL_NODES=2
export PWD=`pwd`

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
	NODE_IP=$(docker-machine ip swarm-node-$i)
	export LOADBALANCERS="${LOADBALANCERS} ${NODE_IP}"

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

# configure a load balancer for each node
export CONSUL_MASTER=$(docker-machine ip swarm-node-1)
eval $(docker-machine env --swarm swarm-node-1)
for i in $(seq 1 $TOTAL_NODES); do
	docker run -d --name lb-${i} -p 80:80 -e APP_NAME=example_app -e CONSUL_URL=${CONSUL_MASTER}:8500 --net app hanzel/load-balancing-swarm
done

export SWARM_MASTER_NODE=$(docker-machine ip swarm-node-1)

echo "Checking Docker Machine List:";
docker-machine ls

echo "Checking Swarm Status:";
eval $(docker-machine env --swarm swarm-node-1)
docker info

echo "CONSUL UI = http://${CONSUL_MASTER}:8500";

for i in $LOADBALANCERS; do
	echo "WEB LB: http://${i}";
done

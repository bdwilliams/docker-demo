#!/bin/bash

export LOADBALANCER=$(docker-machine ip swarm-node-consul)
docker-machine ls

for i in $(seq 1 10)
do
	CALL=`curl -s http://${LOADBALANCER}`
	echo "Attempt #${i} - ${CALL}"
done

# scale the web service up
#eval $(docker-machine env --swarm swarm-node-1)
#docker-compose -f compose/apps.yml scale web=15

# scale the rethinkdb service up
#eval $(docker-machine env --swarm swarm-node-1)
#docker-compose -f compose/rethinkdb.yml scale dbslave=5


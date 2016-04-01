#!/bin/bash

# scale the web service up
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/apps.yml scale web=15

# scale the rethinkdb service up
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/rethinkdb.yml scale dbslave=5


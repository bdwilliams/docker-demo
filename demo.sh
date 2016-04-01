#!/bin/bash

export TOTAL_NODES=2 # how many host (swarm) nodes should be running
export WEB_SCALE=1 # how many nodes should be running after the web service scale
export DB_SCALE=1 # how many nodes should be running after the db service scale

function banner () {

  echo
  echo
  echo -e "\033[1;35m _____     _       _ _"
  echo -e "|_   _| __(_)_ __ (_) |_ _   _"
  echo -e "  | || '__| | '_ \| | __| | | |"
  echo -e "  | || |  | | | | | | |_| |_| |"
  echo -e "  |_||_|  |_|_| |_|_|\__|\__, |"
  echo -e "                         |___/\033[0m"
  echo
  echo
  echo -e "This will demo the Trinity development environment."
  echo -e "It will build, launch and demonstrate failover in"
  echo -e "the environment."
  echo
  echo -e "You may be asked to enter your password in order to"
  echo -e "setup the NFS shared volume support."
}

echoSuccess ()
{
  echo -e "\033[0;32m$1 \033[0m"
}

echoInfo ()
{
  printf "\033[1;34m[INFO] \033[0m$1\n"
}

echoError ()
{
  echo -e "\033[0;31mFAIL\n\n$1 \033[0m"
}

function get_trinity_id(){
  if [ ! -e ${TRINITY_ID} ]
  then
    uuidgen > ${TRINITY_ID}
  fi
  cat ${TRINITY_ID}
}

banner


echoInfo "Creating a consul master node";
# setup consul nodes
STATUS=$(docker-machine status swarm-node-consul 2>&1)
if [ $? -ne 0 ]; then
	docker-machine create -d virtualbox swarm-node-consul
	export NODE_IP=$(docker-machine ip swarm-node-consul)
	eval $(docker-machine env swarm-node-consul)
	docker-compose -f compose/consul-master.yml up -d
fi

# set up shared networking
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETWORK_ID=$(VBoxManage showvminfo swarm-node-consul --machinereadable | grep hostonlyadapter | cut -d'"' -f2)
NFS_HOST_IP=$(VBoxManage list hostonlyifs | grep "${NETWORK_ID}" -A 3 | grep IPAddress | cut -d ':' -f2 | xargs)
NETWORK=$(echo "${NFS_HOST_IP}" | awk -F '.' '{print $1"."$2".0.0"}')
MASK=255.255.0.0
ID=$(id -u)
GID=$(id -g)
TRINITY_STORAGE=${DIR}/.trinity
TRINITY_ID=${DIR}/.trinity/id
TRINITY_SHARE=${TRINITY_STORAGE}/nfs
BOOTLOCAL_SH=`eval "cat <<EOF
$(<bootlocal.sh)
EOF
" 2> /dev/null`

mkdir -p ${TRINITY_SHARE}

EXPORT_LINE="${TRINITY_SHARE} -network=${NETWORK} -mask=${MASK} -mapall=${ID}:${GID}"
TRINITY_ID=$(get_trinity_id)
if ! grep -q ${TRINITY_ID} /etc/exports
then
  echo "######## BEGIN ${TRINITY_ID} ########" | sudo tee -a /etc/exports > /dev/null
  echo "${EXPORT_LINE}" | sudo tee -a /etc/exports > /dev/null
  echo "########  END ${TRINITY_ID}  ########" | sudo tee -a /etc/exports > /dev/null
  sudo nfsd restart ; sleep 2 && sudo nfsd checkexports
fi
if [ $? -eq 0 ]
then
  echo
  echoSuccess "NFS configuration successfully updated"
else
  echo
  echoError "Unable to update NFS configuration"
  exit 1
fi

export CONSUL_MASTER=$(docker-machine ip swarm-node-consul)
echoInfo "Creating ${TOTAL_NODES} swarm nodes";
# setup swarm nodes
for i in $(seq 1 $TOTAL_NODES)
do
	STATUS=$(docker-machine status swarm-node-$i 2>&1)
	if [ $? -ne 0 ]; then
		if [ $i == 1 ]; then
			export SWARM_MASTER="--swarm-master";
		else
			export SWARM_MASTER=""
		fi

		docker-machine create -d virtualbox --swarm ${SWARM_MASTER} --swarm-discovery="consul://${CONSUL_MASTER}:8500" --engine-opt="cluster-store=consul://${CONSUL_MASTER}:8500" --engine-opt="cluster-advertise=eth1:2376" --swarm-opt="replication=true" --swarm-opt="advertise=eth0:3376" swarm-node-$i
		BOOTLOCAL_FILE="/var/lib/boot2docker/bootlocal.sh"
        echo "${BOOTLOCAL_SH}" | docker-machine ssh swarm-node-$i "sudo tee ${BOOTLOCAL_FILE}" > /dev/null
        docker-machine ssh swarm-node-$i "sudo chmod +x ${BOOTLOCAL_FILE} && sync && tce-status -i | grep -q bash | tce-load -wi bash && bash /var/lib/boot2docker/bootlocal.sh"
        docker run -d -p 5000:5000 --name registry registry
        read -r -d '' SSH_COMMAND <<EOF
sudo /bin/sh -c "echo 'EXTRA_ARGS=\"\\\$EXTRA_ARGS --insecure-registry docker.registry.local:5000\"' >> /var/lib/boot2docker/profile" ; sudo /bin/sh -c "echo '127.0.0.1 docker.registry.local' >> /etc/hosts"
EOF
        docker-machine ssh ${CLUSTER_PREFIX}-support "${SSH_COMMAND}"
        docker-machine restart swarm-node-$i
        docker-machine ssh swarm-node-$i ls > /dev/null 2>&1
        while [ $? -ne 0 ]
        do
            sleep 2
            echo "waiting for swarm-node-$i"
            docker-machine ssh swarm-node-$i ls > /dev/null 2>&1
        done
		eval $(docker-machine env swarm-node-$i)
		export NODE_IP=$(docker-machine ip swarm-node-$i)
		docker-compose -f compose/consul-agent.yml up -d
		docker-compose -f compose/registrator.yml up -d

		if [ $i == 1 ]; then
			# setup a load balancer
			docker-compose -f compose/node-lb.yml up -d
		fi
	fi
done


# make sure swarm is ready/healthy
eval $(docker-machine env --swarm swarm-node-1)
COUNTER=0
while [ "$(docker network create -d overlay example_app_temp > /dev/null 2>&1; echo $?)" -ne 0 ]; do
	COUNTER=$[$COUNTER +1]
	echo "${COUNTER} -- Waiting for swarm to become healthy"
	sleep 5;

	if [[ $COUNTER -gt 30 ]]; then
	  echo "Demo failed due to timeout...";
	  exit 1
	fi
done

# cleanup health check
docker network rm example_app_temp

# set some important variables
export SWARM_MASTER_NODE=$(docker-machine ip swarm-node-1)
export LOADBALANCER=$(docker-machine ip swarm-node-1)

# run a db service
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/rethinkdb.yml up -d

# run some apps
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/apps.yml up -d

# scale the web service up
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/apps.yml scale web=15

# scale the rethinkdb service up
eval $(docker-machine env --swarm swarm-node-1)
docker-compose -f compose/rethinkdb.yml scale dbslave=5


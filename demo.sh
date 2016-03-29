#!/bin/bash

export LOADBALANCERS=""
export TOTAL_NODES=2
export PWD=`pwd`

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

echoInfo "Creating ${TOTAL_NODES} swarm nodes"
# setup swarm nodes
for i in $(seq 1 $TOTAL_NODES)
do
	if [ $i == 1 ]; then
		export SWARM_MASTER="--swarm-master";
		export CONSUL_MASTER="127.0.0.1"
	else
		export CONSUL_MASTER=$(docker-machine ip swarm-node-1)
		export SWARM_MASTER=""
	fi

	docker-machine create -d virtualbox --swarm ${SWARM_MASTER} --swarm-discovery="consul://${CONSUL_MASTER}:8500" --engine-opt="cluster-store=consul://${CONSUL_MASTER}:8500" --engine-opt="cluster-advertise=eth1:2376" swarm-node-$i
  if [ $? -ne 0 ]
  then
    NODE_IP=$(docker-machine ip swarm-node-$i)
    export LOADBALANCERS="${LOADBALANCERS} ${NODE_IP}"

    if [ $i == 1 ]
    then
      # configure consul-master
      eval $(docker-machine env swarm-node-$i)
      docker-compose -f compose/consul-master.yml up -d
    else
      # configure consul-slave
      eval $(docker-machine env swarm-node-$i)
      docker-compose -f compose/consul-slave.yml up -d
    fi
  fi
done

# set up shared networking
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETWORK_ID=$(VBoxManage showvminfo swarm-node-1 --machinereadable | grep hostonlyadapter | cut -d'"' -f2)
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

for i in $(seq 1 $TOTAL_NODES); do
  BOOTLOCAL_FILE="/var/lib/boot2docker/bootlocal.sh"
  echo "${BOOTLOCAL_SH}" | docker-machine ssh swarm-node-$i "sudo tee ${BOOTLOCAL_FILE}" > /dev/null
  docker-machine ssh swarm-node-$i "sudo chmod +x ${BOOTLOCAL_FILE} && sync && tce-status -i | grep -q bash || tce-load -wi bash && bash /var/lib/boot2docker/bootlocal.sh"
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

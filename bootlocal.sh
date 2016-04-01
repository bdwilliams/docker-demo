#!/bin/sh

if ! tce-status -i | grep -q iana-etc
then
  tce-load -wi iana-etc
fi

sudo mkdir -p /nfs
sudo umount /nfs > /dev/null 2>&1
if ! pidof rpcbind > /dev/null
then
  sudo /usr/local/etc/init.d/nfs-client start
fi
sudo mount -t nfs -o noacl,async ${NFS_HOST_IP}:${TRINITY_SHARE} /nfs
if [ ! -e /usr/local/bin/convoy ]
then
  wget https://github.com/rancher/convoy/releases/download/v0.5.0.2-rancher/convoy.tar.gz
  tar xvf convoy.tar.gz
  sudo cp convoy/convoy convoy/convoy-pdata_tools /usr/local/bin/
  rm -f convoy.tar.gz
fi
sudo mkdir -p /etc/docker/plugins/
if [ ! -e /etc/docker/plugins/convoy.spec ]
then
  sudo rm -f /etc/docker/plugins/convoy.spec
  sudo sh -c 'echo "unix:///var/run/convoy/convoy.sock" > /etc/docker/plugins/convoy.spec'
fi
if ! pidof convoy > /dev/null
then
  sudo start-stop-daemon --start --background --exec /usr/local/bin/convoy -- daemon --drivers vfs --driver-opts vfs.path=/nfs --log /var/log/convoy.log 2>/dev/null
fi

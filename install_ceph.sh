#!/bin/bash
#install_ceph.sh

#prerequisites: 
#- a working Ceph DC/OS service
#- jq

CEPH_CONF_PATH="/etc/ceph"
CEPH_CONF=$CEPH_CONF_PATH"/ceph.conf"
CEPH_MON_KEYRING=$CEPH_CONF_PATH"/ceph.mon.keyring"
CEPH_CLIENT_ADMIN_KEYRING=$CEPH_CONF_PATH"/ceph.client.admin.keyring"
CEPH_INSTALLER="ceph_installer.sh"

#find out serve directory location
#assume we're installed in ~/.DCOS_install
DCOS_INSTALL_PATH="/root/DCOS_install"
SERVE_PATH=$DCOS_INSTALL_PATH"/genconf/serve"
#serve address
BOOTSTRAP_PORT=80
BOOTSTRAP_IP=$(/usr/sbin/ip route get $DNS_SERVER | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | tail -1) # this node's default route interface

#pretty colours
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

#get SECRETS from Zookeeper
SECRETS=$(curl -s leader.mesos)"FAKESECRET"

#generate ceph_installer.sh with keys
sudo cat >> $CEPH_INSTALLER  << EOF2

export SECRETS=$SECRETS
# example: export SECRETS='{"fsid":"bc74ca0d-ff9a-480d-ac18-ccad34d144d4","adminRing":"AQBAxDxYFv/CBRAALIZk22t8X3q3WS8+cHuoKQ==","monRing":"AQBAxDxY9o4BDBAA3hv1p/SJiHhwe5KwWOddug==","mdsRing":"AQBAxDxYa2YCDBAAXZjSsMWBNkdaKtjiXmNVig==","osdRing":"AQBAxDxYeiYDDBAANaBgkJi98oA1chOk4tvXUQ==","rgwRing":"AQBAxDxY4RAEDBAAV5APHwy6clkNAON8rwSP2w=="}'

EOF2

#ceph_installer.sh
######################
sudo cat >> $CEPH_INSTALLER  << 'EOF2'

#install jq
wget http://stedolan.github.io/jq/download/linux64/jq
chmod +x ./jq
yes | cp -rf jq /usr/bin

#configure ceph
mkdir -p /etc/ceph

#ceph.conf
sudo cat >> $CEPH_CONF  << 'EOF'
export HOST_NETWORK=0.0.0.0/0 
rpm --rebuilddb && yum install -y bind-utils
export MONITORS=$(for i in $(dig srv _mon._tcp.ceph.mesos|awk '/^_mon._tcp.ceph.mesos/'|awk '{print $8":"$7}'); do echo -n $i',';done)
cat <<-EOF > /etc/ceph/ceph.conf
[global]
fsid = $(echo "$SECRETS" | jq .fsid)
mon host = "${MONITORS::-1}"
auth cluster required = cephx
auth service required = cephx
auth client required = cephx
public network = $HOST_NETWORK
cluster network = $HOST_NETWORK
max_open_files = 131072
mon_osd_full_ratio = ".95"
mon_osd_nearfull_ratio = ".85"
osd_pool_default_min_size = 1
osd_pool_default_pg_num = 128
osd_pool_default_pgp_num = 128
osd_pool_default_size = 3
rbd_default_features = 1
EOF

#ceph.mon.keyring
cat <<-EOF > $CEPH_MON_KEYRING
[mon.]
 key = $(echo "$SECRETS" | jq .monRing -r)
 caps mon = "allow *"
EOF

#ceph.client.admin.keyring
cat <<-EOF > $CEPH_CLIENT_ADMIN_KEYRING
[client.admin]
  key = $(echo "$SECRETS" | jq .adminRing -r)
  auid = 0
  caps mds = "allow"
  caps mon = "allow *"
  caps osd = "allow *"
EOF

#install ceph
yum install -y centos-release-ceph-jewel
yum install -y ceph

#check correct functioning
/bin/python /bin/ceph mon getmap -o /etc/ceph/monmap-ceph
#expected output: "got monmap epoch 3"

/bin/python /bin/ceph -s

EOF2
#ceph_installer.sh
######################
#end of ceph installer

#copy ceph installer to serve directory
cp $CEPH_INSTALLER $DCOS_INSTALL_PATH"/"$SERVE_PATH
#copy ceph.conf and keyrings to serve
cp $CEPH_CONF $DCOS_INSTALL_PATH"/"$SERVE_PATH
cp $CEPH_MON_KEYRING $DCOS_INSTALL_PATH"/"$SERVE_PATH
cp $CEPH_CLIENT_ADMIN_KEYRING $DCOS_INSTALL_PATH"/"$SERVE_PATH

#print message to copy&paste in the agents

  echo -e "** ${BLUE}COPY AND PASTE THE FOLLOWING INTO EACH NODE OF THE CLUSTER TO INSTALL CEPH:"
  echo -e ""
  echo -e "${RED}sudo su"
  echo -e "cd"
  echo -e "curl -O http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename "$CEPH_CONF") $CEPH_CONF
  echo -e "curl -O http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename "$CEPH_MON_KEYRING") $CEPH_MON_KEYRING
  echo -e "curl -O http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename "$CEPH_CLIENT_ADMIN_KEYRING") $CEPH_CLIENT_ADMIN_KEYRING
  echo -e "curl -O http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename "$CEPH_INSTALLER") && sudo bash $(basename "$CEPH_INSTALLER") ${NC}"
  echo -e ""
  echo -e "** ${BLUE}Done${NC}."

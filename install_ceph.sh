#!/bin/bash
#install_ceph.sh

#prerequisites: 
#- a working Ceph DC/OS service
#- jq

#find out serve directory location
#assume we're installed in ~/.DCOS_install
DCOS_INSTALL_PATH="/root/DCOS_install"
SERVE_PATH=$DCOS_INSTALL_PATH"/genconf/serve"
#Volume(s) to be used by Ceph
#separated by space as in  "/dev/hda /dev/hdb /dev/hdc"
CEPH_DISKS="/dev/xvdb"
#configuration paths
CEPH_CONF_PATH="/etc/ceph"
CEPH_CONF=$CEPH_CONF_PATH"/ceph.conf"
CEPH_MON_KEYRING=$CEPH_CONF_PATH"/ceph.mon.keyring"
CEPH_CLIENT_ADMIN_KEYRING=$CEPH_CONF_PATH"/ceph.client.admin.keyring"
CEPH_INSTALLER="ceph_installer.sh"

#install CEPH on DC/OS
dcos auth login
echo "** INFO: Installing ceph on mesos..."
dcos package install --yes ceph

until $(curl --output /dev/null --silent --head --fail http://ceph.mesos:5000); do
    printf '**INFO: Waiting for Ceph on DC/OS to be available...'
    sleep 5
done

#pretty colours
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

#depencencies
#jq
curl -O http://stedolan.github.io/jq/download/linux64/jq
chmod +x ./jq
cp jq /usr/bin
#zkCLi
mkdir -p /opt/zookeeper
chown nobody:nobody /opt/zookeeper
cd /opt/zookeeper
git clone https://github.com/id/zookeeper-el7-rpm
cd zookeeper-el7-rpm/
sudo yum install -y make rpmdevtools
make rpm
yum install -y x86_64/zookeeper-3.4.9-1.x86_64.rpm
cp /usr/local/bin/zkcli /usr/bin

#get SECRETS from Zookeeper
SECRETS_ZK_KEY="/ceph-on-mesos/secrets.json"
SECRETS=$(zkcli -server leader.mesos get $SECRETS_ZK_KEY | grep { )
echo "** DEBUG: Secrets is: "$SECRETS

if [[ ${SECRETS} != *"fsid"* ]]; then
	echo "** ERROR: Couldn't get key from Zookeeper. Please check your Ceph DC/OS framework is running, healthy and CONFIGURED. Check https://github.com/dcos/examples/tree/master/1.8/ceph for details."
	exit 1
fi

#configure ceph
mkdir -p $CEPH_CONF_PATH
cd $CEPH_CONF_PATH

#install ceph on bootstrap for testing
rpm --rebuilddb && yum install -y --enablerepo=extras bind-utils epel-release centos-release-ceph ceph

#generate Ceph configuration files for the cluster on bootstrap
#ceph.conf
export HOST_NETWORK=0.0.0.0/0 
export MONITORS=$(for i in $(dig srv _mon._tcp.ceph.mesos|awk '/^_mon._tcp.ceph.mesos/'|awk '{print $8":"$7}'); do echo -n $i',';done)
echo "**DEBUG: SECRETS: "$SECRETS
echo "**DEBUG: MONITORS: "$MONITORS

cat <<-EOF > $CEPH_CONF
[global]
fsid = $(echo $SECRETS | jq .fsid)
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

#check correct functioning
/bin/python /bin/ceph mon getmap -o /etc/ceph/monmap-ceph
#expected output if Ceph is running: "got monmap epoch 3"

/bin/python /bin/ceph -s

#copy ceph.conf and keyrings to SERVE directory
cp $CEPH_INSTALLER $SERVE_PATH
cp $CEPH_CONF $SERVE_PATH
cp $CEPH_MON_KEYRING $SERVE_PATH
cp $CEPH_CLIENT_ADMIN_KEYRING $SERVE_PATH

#generate ceph_installer.sh to be used in agents
#######################################
sudo tee $CEPH_INSTALLER <<-EOF2
#no inherited variables to translate
EOF2
sudo tee -a $CEPH_INSTALLER <<-'EOF2' #with ticks -- rest of variables kept literal to translate on agents
#install ceph
rpm --rebuilddb && yum install -y --enablerepo=extras bind-utils epel-release centos-release-ceph ceph

#get config and keys from bootstrap node, place in the right directory
curl -s -o CEPH_CONF http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_CONF)
curl -s -o CEPH_MON_KEYRING http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_MON_KEYRING)
curl -s -o CEPH_CLIENT_ADMIN_KEYRING http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_CLIENT_ADMIN_KEYRING)

#check correct functioning
/bin/python /bin/ceph mon getmap -o /etc/ceph/monmap-ceph
#expected output if Ceph is running: "got monmap epoch 3"
/bin/python /bin/ceph -s

#display finished message
echo -e "${NC}Ceph is available at http://$PUBLIC_NODE_IP:5000. Please log in and configure Ceph Monitors and OSDs following the instructions in https://github.com/dcos/examples/tree/master/1.8/ceph#configure-ceph"

EOF2
######################
#end of ceph installer

#print message to copy&paste in the agents
#serve address
DNS_SERVER=8.8.8.8
BOOTSTRAP_PORT=80
BOOTSTRAP_IP=$(/usr/sbin/ip route get $DNS_SERVER | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | tail -1) # this node's default route interface

echo -e "** ${BLUE}COPY AND PASTE THE FOLLOWING INTO EACH NODE OF THE CLUSTER TO INSTALL CEPH:"
echo -e ""
echo -e "${RED}sudo su"
echo -e "cd"
echo -e "curl -s -O http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_INSTALLER) && sudo bash $(basename $CEPH_INSTALLER)"
echo -e ""
echo -e "${NC}Ceph is available at http://$PUBLIC_NODE_IP:5000. Please log in and configure Ceph Monitors and OSDs following the instructions in https://github.com/dcos/examples/tree/master/1.8/ceph#configure-ceph"
echo -e "${BLUE}** Done${NC}."

#remove this installer along with the secret
rm -f $CEPH_INSTALLER
rm -f 

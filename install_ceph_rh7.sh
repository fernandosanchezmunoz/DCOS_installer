#!/bin/bash
#install_ceph.sh

#prerequisites: 
#- a working Ceph DC/OS service with Marathon-LB running.

#find out serve directory location
#assume we're installed in ~/.DCOS_install
DCOS_INSTALL_PATH="/root/DCOS_install"
SERVE_PATH=$DCOS_INSTALL_PATH"/genconf/serve"
#configuration paths
CEPH_CONF_PATH="/etc/ceph"
CEPH_CONF=$CEPH_CONF_PATH"/ceph.conf"
CEPH_MON_KEYRING=$CEPH_CONF_PATH"/ceph.mon.keyring"
CEPH_CLIENT_ADMIN_KEYRING=$CEPH_CONF_PATH"/ceph.client.admin.keyring"
CEPH_INSTALLER="ceph_installer.sh"
#TODO: delete section.
#Volume(s) to be used by Ceph
#separated by space as in  "/dev/hda /dev/hdb /dev/hdc"
#CEPH_DISKS_FILE=DCOS_INSTALL_PATH"/.ceph_disks"
#CEPH_DISKS=$(echo $CEPH_DISKS_FILE)

#pretty colours
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

#install CEPH on DC/OS cluster
dcos auth login
echo "** INFO: Installing ceph on mesos..."
dcos package install --yes ceph

#wait until Ceph is available and healthy
#until $(curl --output /dev/null --silent --head --fail http://ceph.mesos:5000); do
while true; do
 ping -c 1 ceph.mesos > /dev/null 2>&1
 if [ $? == 0 ]; then
    echo "** INFO: Ceph on DC/OS is available. Continuing install..."
    break
 else
    echo "** INFO: Waiting for Ceph on DC/OS to be available..."
    sleep 2
 fi
done

echo -e "${NC}Ceph is available through Marathon-LB at http://PUBLIC-NODE:5000"
echo -e "Please log in and configure Ceph Monitors and OSDs following the instructions in:"
echo -e "${BLUE}https://github.com/dcos/examples/tree/master/1.8/ceph#configure-ceph${NC}"

#do not continue until Ceph is configured and monitors are reachable
while true; do
read -p "Press ENTER ONLY WHEN YOU HAVE CONFIGURED MONITORS AND OSDs ACCORDING TO THE LINK ABOVE AND THEY'RE ALL WORKING."
#check that monitors are up
if ping -c 1 mon.ceph.mesos &> /dev/null
then
  break
else 
  echo -e "Ceph monitors are still unreachable. Please check your configuration and the documentation link above and try again."
fi
done

#depencencies

#jq
echo "** INFO: Installing JQ..."
curl -s -O http://stedolan.github.io/jq/download/linux64/jq
chmod +x ./jq
yes | cp -f jq /usr/bin > /dev/null 2>&1

#zkCLi
echo "** INFO: Installing zkCli with Java and Zookeeper (this may take a while)..."
mkdir -p /opt/zookeeper
chown nobody:nobody /opt/zookeeper
cd /opt/zookeeper
rm -Rf zookeeper-el7-rpm
git clone https://github.com/id/zookeeper-el7-rpm
cd zookeeper-el7-rpm/
sudo yum install -y make > /dev/null 2>&1
sudo yum install -y rpmdevtools java > /dev/null 2>&1
make rpm > /dev/null 2>&1
yum install -y x86_64/zookeeper-3.4.9-1.x86_64.rpm > /dev/null 2>&1
rm -f /usr/bin/zkcli > /dev/null 2>&1
cp -f /usr/local/bin/zkcli /usr/bin 

#get SECRETS from Zookeeper
echo "** INFO: Getting Ceph keys from Zookeeper..."
SECRETS_ZK_KEY="/ceph-on-mesos/secrets.json"
SECRETS=$(zkcli -server leader.mesos get $SECRETS_ZK_KEY | grep { )

if [[ ${SECRETS} != *"fsid"* ]]; then
	echo "** ERROR: Couldn't get key from Zookeeper. Please check your Ceph DC/OS framework is running, healthy and CONFIGURED. Check https://github.com/dcos/examples/tree/master/1.8/ceph for details."
	exit 1
fi

#install ceph on bootstrap for testing
echo "** INFO: Installing Ceph..."
rpm --rebuilddb 
# yum install -y --enablerepo=extras bind-utils epel-release centos-release-ceph && yum install -y ceph

#install depencencies
sudo cat > ./install.sh << 'EOF'
yum install -y \
https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
rpm -Fvh --nodeps ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/redhat-lsb-core-4.1-27.el7.centos.1.x86_64.rpm \
ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/b/bash-completion-extras-2.1-11.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/atrpms.net/el7-i386/atrpms/stable/bash-completion-20060301-11.noarch.rpm 
yum install -y \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/cryptsetup-1.7.2-1.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/l/lttng-ust-2.4.1-4.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/virt/x86_64/ovirt-4.0/common/userspace-rcu-0.7.7-1.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/storage/x86_64/ceph-jewel/libbabeltrace-1.2.4-3.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/storage/x86_64/ceph-hammer/fcgi-2.4.0-21.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/extras/x86_64/Packages/python-flask-0.10.1-4.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/storage/x86_64/ceph-hammer/leveldb-1.12.0-5.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/libaio-0.3.109-13.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/boost-program-options-1.53.0-26.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/gperftools-libs-2.4-8.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/extras/x86_64/Packages/python-flask-0.10.1-4.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/fuse-libs-2.9.2-7.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/mailcap-2.1.41-2.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/libunwind-1.1-5.el7_2.2.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/extras/x86_64/Packages/python-itsdangerous-0.23-2.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-jinja2-2.7.2-2.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-babel-0.9.6-8.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-markupsafe-0.11-10.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/boost-thread-1.53.0-26.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/boost-system-1.53.0-26.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/w/waf-1.8.22-1.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-javapackages-3.4.1-11.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/spax-1.5.2-13.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/hdparm-9.43-5.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librados2-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librados2-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-common-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-fuse-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-libs-compat-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-radosgw-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-test-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libcephfs1-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libcephfs1-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libradosstriper1-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libradosstriper1-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librbd1-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librbd1-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-ceph-compat-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-cephfs-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-rados-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-rbd-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/rbd-fuse-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/rest-bench-0.94.10-0.el7.x86_64.rpm 

EOF
chmod +x ./install.sh
bash ./install.sh

#configure ceph
echo "** INFO: Configuring Ceph..."
mkdir -p $CEPH_CONF_PATH
cd $CEPH_CONF_PATH

#generate Ceph configuration files for the cluster on bootstrap
#ceph.conf
export HOST_NETWORK=0.0.0.0/0 
#export MONITORS=$(for i in $(dig srv _mon._tcp.ceph.mesos|awk '/^_mon._tcp.ceph.mesos/'|awk '{print $8":"$7}'); do echo -n $i',';done)
export PORT_MON=$(dig srv _mon._tcp.ceph.mesos|awk '/^_mon._tcp.ceph.mesos/'|head -n 1|awk '{print $7}') #assume all mons are in the same port, pick first

sudo cat > $CEPH_CONF << EOF
[global]
fsid = $(echo $SECRETS | jq .fsid)
#mon host = "${MONITORS::-1}"
mon host = "mon.ceph.mesos:$PORT_MON"
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
echo "** INFO: Testing Ceph..."
/bin/python /bin/ceph mon getmap -o /etc/ceph/monmap-ceph
#expected output if Ceph is running: "got monmap epoch 3"

/bin/python /bin/ceph -s

#find out my serve address for printing message to copy&paste in the agents
BOOTSTRAP_PORT=80
BOOTSTRAP_IP=$(/usr/sbin/ip route get 8.8.8.8| grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | tail -1) # this node's default route interface

sleep 1

#generate ceph_installer.sh to be used in agents
#######################################
echo "** INFO: Generating Ceph installer for agents..."
cat <<-EOF > $CEPH_INSTALLER 

#install depencencies
sudo cat > ./install.sh << 'EOF'
yum install -y \
https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
rpm -Fvh --nodeps ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/redhat-lsb-core-4.1-27.el7.centos.1.x86_64.rpm \
ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/b/bash-completion-extras-2.1-11.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/atrpms.net/el7-i386/atrpms/stable/bash-completion-20060301-11.noarch.rpm 
yum install -y \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/cryptsetup-1.7.2-1.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/l/lttng-ust-2.4.1-4.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/virt/x86_64/ovirt-4.0/common/userspace-rcu-0.7.7-1.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/storage/x86_64/ceph-jewel/libbabeltrace-1.2.4-3.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/storage/x86_64/ceph-hammer/fcgi-2.4.0-21.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/extras/x86_64/Packages/python-flask-0.10.1-4.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/storage/x86_64/ceph-hammer/leveldb-1.12.0-5.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/libaio-0.3.109-13.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/boost-program-options-1.53.0-26.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/gperftools-libs-2.4-8.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/extras/x86_64/Packages/python-flask-0.10.1-4.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/fuse-libs-2.9.2-7.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/mailcap-2.1.41-2.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/libunwind-1.1-5.el7_2.2.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/extras/x86_64/Packages/python-itsdangerous-0.23-2.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-jinja2-2.7.2-2.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-babel-0.9.6-8.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-markupsafe-0.11-10.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/boost-thread-1.53.0-26.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/boost-system-1.53.0-26.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/download.fedora.redhat.com/pub/fedora/epel/7/x86_64/w/waf-1.8.22-1.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/python-javapackages-3.4.1-11.el7.noarch.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/spax-1.5.2-13.el7.x86_64.rpm \
ftp://ftp.pbone.net/mirror/ftp.centos.org/7.3.1611/os/x86_64/Packages/hdparm-9.43-5.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librados2-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librados2-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-common-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-fuse-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-libs-compat-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-radosgw-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/ceph-test-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libcephfs1-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libcephfs1-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libradosstriper1-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/libradosstriper1-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librbd1-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/librbd1-devel-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-ceph-compat-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-cephfs-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-rados-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/python-rbd-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/rbd-fuse-0.94.10-0.el7.x86_64.rpm \
https://download.ceph.com/rpm/el7/x86_64/rest-bench-0.94.10-0.el7.x86_64.rpm 

EOF
chmod +x ./install.sh
bash ./install.sh

#install ceph
#sudo tee /etc/yum.repos.d/ceph.repo <<-EOF2
#[ceph]
#name=Ceph packages for $basearch
#baseurl=https://download.ceph.com/rpm-jewel/el7/x86_64/  
#enabled=1
#priority=2
#gpgcheck=1
#gpgkey=https://download.ceph.com/keys/release.asc
#EOF2

#rpm --rebuilddb && yum install -y bind-utils centos-release-ceph && yum install -y ceph

#get config and keys from bootstrap node, place in the right directory
curl -s -o $CEPH_CONF http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_CONF)
curl -s -o $CEPH_MON_KEYRING http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_MON_KEYRING)
curl -s -o $CEPH_CLIENT_ADMIN_KEYRING http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_CLIENT_ADMIN_KEYRING)

#check correct functioning
/bin/python /bin/ceph mon getmap -o /etc/ceph/monmap-ceph
#expected output if Ceph is running: "got monmap epoch 3"
/bin/python /bin/ceph -s

#restart rexray
systemctl restart dcos-rexray

#display finished message
echo -e "${NC}Done. ${RED}Ceph${NC} is configured on this node."

EOF
######################
#end of ceph installer

#copy installer, ceph.conf and keyrings to SERVE directory
cp $CEPH_INSTALLER $SERVE_PATH
cp $CEPH_CONF $SERVE_PATH
cp $CEPH_MON_KEYRING $SERVE_PATH
cp $CEPH_CLIENT_ADMIN_KEYRING $SERVE_PATH

echo "** INFO: Complete..."
echo -e "** ${BLUE}COPY AND PASTE THE FOLLOWING INTO EACH *PRIVATE AGENT* OF THE CLUSTER TO CONFIGURE IT FOR CEPH:"
echo -e ""
echo -e "${RED}sudo su"
echo -e "cd"
echo -e "curl -s -O http://$BOOTSTRAP_IP:$BOOTSTRAP_PORT/$(basename $CEPH_INSTALLER) && sudo bash $(basename $CEPH_INSTALLER)"
echo -e ""
echo -e "${BLUE}Done${NC}."

#remove this installer along with the secret
rm -f $CEPH_INSTALLER
rm -f 

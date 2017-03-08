#do not continue until Ceph is configured and monitors are reachable
while true; do
read -p "Press Enter when you have COMPLETED the cluster INSTALL and MASTER nodes are up."
#check that monitors are up
if ping -c 1 leader.mesos &> /dev/null
then
  echo -e "** INFO: DC/OS leader ready."
  break
else 
  echo -e "** ERROR: DC/OS leader is still unreachable. Please check your configuration."
fi
done
dcos auth login

dcos package install --yes --cli dcos-enterprise-cli
dcos security org service-accounts keypair -l 4096 marathon-lb-private-key.pem marathon-lb-public-key.pem
dcos security org service-accounts create -p marathon-lb-public-key.pem -d "dcos_marathon_lb service account" dcos_marathon_lb
dcos security org service-accounts show dcos_marathon_lb

sleep 5

curl -skSL -X PUT -H 'Content-Type: application/json' -d '{"description": "Marathon Services"}' -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:service:marathon:marathon:services:%252F
curl -skSL -X PUT -H 'Content-Type: application/json' -d '{"description": "Marathon Events"}' -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:service:marathon:marathon:admin:events
curl -skSL -X PUT -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:service:marathon:marathon:services:%252F/users/dcos_marathon_lb/read
curl -skSL -X PUT -H "Authorization: token=$(dcos config show core.dcos_acs_token)" $(dcos config show core.dcos_url)/acs/api/v1/acls/dcos:service:marathon:marathon:admin:events/users/dcos_marathon_lb/read

sleep 5

dcos security secrets create-sa-secret marathon-lb-private-key.pem dcos_marathon_lb marathon-lb
dcos security secrets list /
dcos security secrets get /marathon-lb --json | jq -r .value | jq

sleep 5

# Launch Marathon-LB using the secret and the cert created above
tee marathon-lb-secret-options.json <<'EOF'
{
     "marathon-lb": {
         "secret_name": "marathon-lb",
         "cpus": 1
     }
}
EOF

dcos package install --options=marathon-lb-secret-options.json --yes marathon-lb

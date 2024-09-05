set -e # fail immediately

# Test static dns resolution

echo "Ping vm1 from vm0:"
echo "------------------"
ssh -o 'ConnectTimeout=10' -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' root@192.168.100.10 \
"ping vm1 -c 1"
echo
echo

echo "Ping vm2 from vm1:"
echo "------------------"
ssh -o 'ConnectTimeout=10' -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' 'root@192.168.100.11' \
"ping vm2 -c 1"
echo 
echo

echo "Ping vm0 from vm2:"
echo "------------------"
ssh -o 'ConnectTimeout=10' -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' 'root@192.168.100.12' \
"ping vm0 -c 1"

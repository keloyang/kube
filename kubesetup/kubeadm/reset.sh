#!/bin/sh

INSTALLDIR=/home/workspace/lambda/kube/kubesetup/kubeadm
NODES=(
	192.168.137.6
	192.168.137.7
)

MASTER=192.168.137.2

for n in ${NODES[@]};
do
	ssh root@$n kubectl drain $n --delete-local-data --force --ignore-daemonsets
	ssh root@$n kubectl delete node $n
	ssh root@$n kubeadm reset
	ssh root@$n rm -rf /etc/kubernetes
done

kubeadm reset
rm -rf /var/lib/etcd
rm -rf /etc/kubernetes
rm -rf ~/.kube/config


var=`kubeadm init --config $INSTALLDIR/kubeadm.conf`
CMD="${var:0-160}"
for n in ${NODES[@]};
do
	echo "registr node ============================================================================="
	echo $CMD
	ssh root@$n $CMD
	ssh root@$n mkdir -p ~/.kube
	scp /etc/kubernetes/admin.conf root@$n:~/.kube/config
done

cp  /etc/kubernetes/admin.conf ~/.kube/config

kubectl create -f $INSTALLDIR/kube-flannel.yml

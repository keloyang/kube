#!/bin/bash
curdir=`pwd`

master=(192.168.137.2)
node=(
	192.168.137.6
	192.168.137.7
)

user=root
dockerversion=17.04.0-ce
binarybin=$curdir/bin
softdir=$curdir/soft
installpath=/usr
SYSTEMD_DIR=/lib/systemd/system
install=install.sh
kubeimage=yangkuihappy/kube

function tmpstr(){
	head -c 16 /dev/urandom | od -An -t x | tr -d ' '
}

function download(){
	echo "download" $1 $2
	f=$1
	dst=$2
	rm -rf  $dst/${f##*/}
	wget --no-check-certificate -P $dst $f
}

function download_docker(){
	rm -rf $softdir/docker*
	mkdir -p $binarybin

	download https://get.docker.com/builds/Linux/x86_64/docker-$dockerversion.tgz $softdir
	tar -xvf $softdir/docker-$dockerversion.tgz -C $softdir
	cp $softdir/docker/docker* $binarybin
}
 
function run_remote(){
	echo $@
	remote=$1
	shift 1
	ssh $user@$remote $@
}

function copy_to_node(){
	file=$1
	dst=$2
	n=$3
	mode=$4

	echo "copy_to_node" $n $file $dst
	ssh $user@$n mkdir -p $dst
	name=${file##*/}
	if [[ $EASYK8S_ARCHIVE == 1 ]]
	then
		archivefile=$easykube$(tmpstr)
		scp -r $file $user@$n:$dst/$archivefile
		ssh $user@$n tar -xvf $dst/$archivefile -C $dst
		ssh $user@$n rm -rf $dst/$archivefile
	else
		scp -r $file $user@$n:$dst/
		ssh $user@$n chmod -R $mode $dst/$name
	fi
}

function exec_to_nodes(){
	n=$1
	file=$2
	dst=$3
	copy_to_node $file $dst $n 0755

	name=${file##*/}

	ssh $user@$n $dst/$name
	ssh $user@$n rm -rf $dst/$name
}

function copy_to_cluster(){
	file=$1
	dst=$2
	mode=$3
	worker=(${master[@]} ${node[@]})
	for n in ${worker[@]};
	do
		echo "copy_to_cluster" $n
		ssh $user@$n mkdir -p $dst
		name=${file##*/}
		if [[ $EASYK8S_ARCHIVE == 1 ]]
		then
			archivefile=$easykube$(tmpstr)
			scp -r $file $user@$n:$dst/$archivefile
			ssh $user@$n tar xvf $dst/$archivefile -C $dst
			ssh $user@$n rm -rf $dst/$archivefile
		else
			scp -r $file $user@$n:$dst
			ssh $user@$n chmod -R $mode $dst/$name
		fi
	done
}

function copy_binary_to_cluster(){
	chmod -R 0755 $binarybin
	cd $binarybin/
	tarfile=$(tmpstr)
	tar -czvf ../$tarfile.tar.gz *
	EASYK8S_ARCHIVE=1 copy_to_cluster ../$tarfile.tar.gz $installpath/bin 0755 
	rm -rf ../$tarfile.tar.gz
}

function setup_no-passwd(){
	echo "setup_no-passwd ..."
	keygen=$2
	if [[ $keygen == "keygen" ]]
	then
		ssh-keygen -t rsa
	fi

	worker=(${master[@]} ${node[@]})
	for n in ${worker[@]};
	do 
		echo $n
		ssh-copy-id -i ~/.ssh/id_rsa.pub  $user@$n
	done
}

function build_docker_scripts(){
	remoteaddr=$1
	echo $install
	cat > $install <<EOF
#!/bin/bash

sed -i '/swap/s/^[#]*//g' /etc/fstab
sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab

mkdir -p /etc/docker/
cat << EOF > /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "insecure-registries": ["gcr.io", "k8s.gcr.io", "dockerhub.jd.com", "idockerhub.jd.com"]
}
#EOF

cat > $SYSTEMD_DIR/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker.socket flannel.service

[Service]
Type=notify
EnvironmentFile=-/run/flannel/docker
ExecStart=$INSTALL_DIR/bin/dockerd \\
                \$DOCKER_OPT_BIP \\
                \$DOCKER_OPT_MTU \\
                -H tcp://0.0.0.0:4243 \\
                -H unix:///var/run/docker.sock \\
                --log-opt max-size=1g
ExecReload=/bin/kill -s HUP $MAINPID
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
# Uncomment TasksMax if your systemd version supports it.
# Only systemd 226 and above support this version.
#TasksMax=infinity
TimeoutStartSec=0
# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes
# kill only the docker process, not all processes in the cgroup
KillMode=process
Restart=on-failure
[Install]
WantedBy=multi-user.target
#EOF

systemctl enable docker
systemctl daemon-reload
systemctl restart docker

mkdir -p /opt/cni/bin
tar -C /opt/cni/bin -xvzf $installpath/bin/cni-plugins-amd64-v0.6.0.tgz
rm -rf $installpath/bin/cni-plugins-amd64-v0.6.0.tgz 

mkdir -p /etc/systemd/system/kubelet.service.d
mv $installpath/bin/kubelet.service /etc/systemd/system/kubelet.service
mv $installpath/bin/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl enable kubelet 
#systemctl start kubelet

mv $installpath/bin/images.tgz /tmp
cd /tmp/ && tar zxvf images.tgz
for image in \$(ls /tmp/images); do docker load < /tmp/images/\${image}; done
rm -rf /tmp/images /tmp/images.tgz

EOF
	sed -i '/#EOF/s/^[#]*//g' $install
}

function install(){
	build_docker_scripts
	worker=(${master[@]} ${node[@]})
	for e in ${worker[@]};
	do 
		exec_to_nodes $e $install $installpath/bin
	done
	rm -rf $dockerinstall
}

function copy(){
	/usr/bin/cp -rf $@
}

function kubectl(){
	#docker pull $kubeimage
	#docker run --name kubeadm -itd $kubeimage /bin/sh
	#docker cp kubeadm:/opt /tmp
	#docker kill kubeadm;
	#docker rm kubeadm
	
	mkdir -p $binarybin
	copy 10-kubeadm.conf $binarybin
	copy /tmp/opt/cni-plugins-amd64-v0.6.0.tgz $binarybin
	copy /tmp/opt/kubelet.service $binarybin
	copy /tmp/opt/kubectl $binarybin
	copy /tmp/opt/kubelet $binarybin
	copy /tmp/opt/kubeadm $binarybin
	copy /tmp/opt/crictl $binarybin
	#cp /tmp/opt/images.tgz $binarybin
}

operation=$1

if [[ ${operation} = "evn" ]];
then
	setup_no-passwd
fi

if [[ ${operation} = "download" ]];
then
	download_docker
fi

if [[ ${operation} = "copy" ]];
then
	copy_binary_to_cluster
fi

if [[ ${operation} = "install" ]];
then
	install
fi

if [[ ${operation} = "kubectl" ]];
then
	kubectl
fi


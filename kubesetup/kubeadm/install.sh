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
EOF

cat > /lib/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker.socket flannel.service

[Service]
Type=notify
EnvironmentFile=-/run/flannel/docker
ExecStart=/bin/dockerd \
                $DOCKER_OPT_BIP \
                $DOCKER_OPT_MTU \
                -H tcp://0.0.0.0:4243 \
                -H unix:///var/run/docker.sock \
                --log-opt max-size=1g
ExecReload=/bin/kill -s HUP 
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
EOF

systemctl enable docker
systemctl daemon-reload
systemctl restart docker


tar -C /usr/bin -xvzf /usr/bin/cni-plugins-amd64-v0.6.0.tgz
rm -rf /usr/bin/cni-plugins-amd64-v0.6.0.tgz 

mkdir -p /etc/systemd/system/kubelet.service.d
mv /usr/bin/kubelet.service /etc/systemd/system/kubelet.service
mv /usr/bin/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl enable kubelet 
systemctl start kubelet

mv /usr/bin/images.tgz /tmp
cd /tmp/ && tar zxvf images.tgz
for image in $(ls /tmp/images); do docker load < /tmp/images/${image}; done
rm -rf /tmp/images


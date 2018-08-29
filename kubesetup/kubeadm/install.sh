#!/bin/sh

mkdir -p /opt/cni/bin
tar -C /opt/cni/bin -xvzf cni-plugins-amd64-v0.6.0.tgz

cp kubeadm kubelet kubectl crictl /usr/bin

mkdir -p /etc/systemd/system/kubelet.service.d
cp kubelet.service /etc/systemd/system/
cp 10-kubeadm.conf /etc/systemd/system/kubelet.service.d/

tar -zxvf images.tgz
for image in $(ls images/); do docker load < images/${image}; done

systemctl enable kubelet && systemctl start kubelet

kubeadm init --config kubeadm.conf

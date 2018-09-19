RELEASE=v1.11.1
CNI_VERSION=v0.6.0
IMAGES := \
	k8s.gcr.io/hyperkube-amd64:v1.11.1\
	k8s.gcr.io/kube-proxy-amd64:v1.11.1\
	k8s.gcr.io/coredns:1.1.3 \
	k8s.gcr.io/etcd-amd64:3.2.18\
	k8s.gcr.io/kube-apiserver-amd64:v1.11.1\
	k8s.gcr.io/kube-controller-manager-amd64:v1.11.1\
	k8s.gcr.io/kube-scheduler-amd64:v1.11.1\
	k8s.gcr.io/pause:3.1\
	quay.io/coreos/flannel:v0.10.0-amd64
TARGET_TAG = v0.2
TARGET_REPO = yangkuihappy/kubeadm

test:
	 for image in ${IMAGES}; do filename=$$(echo $${image} | cut -f 2 -d '/'); echo $${filename}; done

release:
	mkdir -p cni/bin images services bin
	wget "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-amd64-${CNI_VERSION}.tgz"
	cd bin && curl -L "https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.11.1/crictl-${RELEASE}-linux-amd64.tar.gz" | tar -xz && chmod +x *
	cd bin && curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/{kubeadm,kubelet,kubectl} && chmod +x *
	curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/kubelet.service" > services/kubelet.service
	curl -sSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${RELEASE}/build/debs/10-kubeadm.conf" > services/10-kubeadm.conf
	for image in ${IMAGES}; do docker pull $${image}; done
	for image in ${IMAGES}; do filename=$$(echo $${image} | cut -f 2 -d '/'); docker save $${image} > images/$${filename}.tar; done
	tar -czvf images.tgz images && rm -rf images
	for i in $$(docker images | awk '{print $$3}' | grep ${TARGET_REPO}| sort | uniq); do docker rmi $${i}; done
	docker build -t ${TARGET_REPO}:${TARGET_TAG} .
	rm -rf docker cni bin services images images.tgz kubeadm.tar cni-plugins-amd64-${CNI_VERSION}.tgz

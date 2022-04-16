#!/bin/bash

# stop the scrpit execution if any error happens
set -e

# set kube version
kube_version=1.23.5

# default network interface
default_interface=eth0
pod_network_cidr="10.0.0.0/24"

# control plane endpoint
control_plane_endpoint=api-server-k85

# install extra packages
sudo yum install -y bash-completion vim wget

# disable linux swap and remove any existing swap partitions
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Install containerd container runtime
## configure containerd prerequisites
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

### Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

### Apply sysctl params without reboot
sudo sysctl --system

## install containerd from docker repo
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y containerd.io

## configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

## Using the systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

## restart containerd
sudo systemctl enable containerd
sudo systemctl start containerd

# install kubelet kubeadm kubectl
## add kubernetes repo
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

## Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

sudo yum -y install kubelet-${kube_version} kubeadm-${kube_version} kubectl-${kube_version} --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

# init your cluster
## set --control-plane-endpoint, set the shared endpoint for all control-plane nodes if you have plans to upgrade this single control-plane kubeadm cluster to high availabile cluster (DNS name or an IP address of a load-balancer)
### get default interface ip and add record in hosts file, later can be added to DNS
default_interface_ip=`ip -4 addr show ${default_interface} | awk '/inet /{print $2}' | cut -d'/' -f1`

sudo cp /etc/hosts /etc/hosts.bk-`date +%F-%H-%M-%S`

cat <<EOF | sudo tee -a /etc/hosts
${default_interface_ip} ${control_plane_endpoint}
EOF

kubeadm init --control-plane-endpoint=${control_plane_endpoint} --pod-network-cidr=${pod_network_cidr}


# kubectl configs
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

## kubectl completion
echo 'source <(kubectl completion bash)' >>~/.bashrc

## kubectl alias + auto-complete for alias
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# pod network plugin installation
#due to a bug in the image versions
#kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

curl -L https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n') -o weave.yaml
sed -i 's/ghcr.io\/weaveworks\/launcher/docker.io\/weaveworks/g' weave.yaml
kubectl -f weave.yaml apply

# install crictl which provides a CLI for CRI-compatible container runtimes to interact with containerd
CRICTL_VERSION="v1.23.0"
curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz --output crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
sudo tar zxvf crictl-$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VERSION-linux-amd64.tar.gz

## crictl configs as runtime endpoint config,..
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF


# create and display join token command token will expire after 24H if not you can add --ttl 0 (never expire)
kubeadm token create --print-join-command

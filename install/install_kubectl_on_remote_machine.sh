#!/bin/bash

# set kube version
kube_version=1.23.5

# add kubernetes repo and install kubectl
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

sudo yum -y install kubectl-${kube_version} --disableexcludes=kubernetes

# kubectl auto-complete + alias k for kubectl
sudo yum install -y bash-completion
echo 'source <(kubectl completion bash)' >>~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

mkdir -p $HOME/.kube
touch $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "copy the content of kube/config file from master to your user home dir '.kube/config' "

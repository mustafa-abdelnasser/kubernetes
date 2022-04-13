#!/bin/bash

# stop the scrpit execution if any error happens
set -e

# set kube version
kube_version=1.23.5


# control plane endpoint
control_plane_endpoint=api-server-k85
control_plane_endpoint_ip=

# install extra packages
sudo yum install -y bash-completion vim

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

# install kubelet kubeadm
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

sudo yum -y install kubelet-${kube_version} kubeadm-${kube_version} --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

# join this worker node to the cluster
## add control plane ip to the hosts file if DNS is not used
sudo cp /etc/hosts /etc/hosts.bk-`date +%F-%H-%M-%S`

cat <<EOF | sudo tee -a /etc/hosts
${control_plane_endpoint_ip} ${control_plane_endpoint}
EOF


echo "On master node run this command: kubeadm token create --print-join-command"
echo "copy the output command from master and run it on the worker node with sudo permissions to join it to the cluster"

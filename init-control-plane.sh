#!/bin/bash
# 初始化第一台master机器
# 要安装的kubernetes版本
kubernetes_version="v1.27.4"
echo "$(curl -fsSL http://100.100.100.200/latest/meta-data/private-ipv4) apiserver.liguanghui.pro" >> /etc/hosts
kubeadm init --kubernetes-version ${kubernetes_version} --control-plane-endpoint apiserver.liguanghui.pro --pod-network-cidr 10.244.0.0/16 --upload-certs
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u):$(id -g)" $HOME/.kube/config
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl apply -f https://gitlab.com/liguanghui/deploy-kubernetes-on-aliyun-with-terraform/-/raw/main/metrics-server.yaml

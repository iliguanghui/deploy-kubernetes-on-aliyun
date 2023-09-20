#!/bin/bash
# Print commands and their arguments as they are executed
set -x
# 要安装的kubernetes版本
kubernetes_version="v1.27.4"
# 要使用的containerd版本
containerd_version="1.7.3"
runc_version="v1.1.8"
cni_plugins_version="v1.3.0"
cri_tools_version="v1.27.0"
nerdctl_version="v1.5.0"
metrics_server_version="v0.6.4"
# 要安装的aliyun cli的文件名
aliyun_cli_file="aliyun-cli-linux-3.0.2-amd64.tgz"
# ecs、oss实例所在的阿里云地域
aliyun_region="cn-zhangjiakou"
# 关联到ecs实例上的角色，aliyun cli使用这个角色从oss下载安装包
ecs_ram_role_name="admin-role"
# 用来存放kubernetes安装包的oss存储桶的名称
oss_bucket_name="kubernetes-packages"
# kubernetes服务端安装包名
kubernetes_server_package_name="kubernetes-server-linux-amd64.tar.gz"
containerd_package_name="containerd-${containerd_version}-linux-amd64.tar.gz"

function setup_hostname {
    METADATA_BASEURL="http://100.100.100.200"
    METADATA_TOKEN_PATH="latest/api/token"
    IMDS_TOKEN=$(curl -s -f --max-time 3 -X PUT -H "X-aliyun-ecs-metadata-token-ttl-seconds: 900" ${METADATA_BASEURL}/${METADATA_TOKEN_PATH})
    region=$(curl -s -q --max-time 3 -H "X-aliyun-ecs-metadata-token: ${IMDS_TOKEN}" -f ${METADATA_BASEURL}/latest/meta-data/region-id)
    while [ -z "$region" ]; do
        region=$(curl -s -q --max-time 3 -H "X-aliyun-ecs-metadata-token: ${IMDS_TOKEN}" -f ${METADATA_BASEURL}/latest/meta-data/region-id)
        sleep 1
    done
    ip=$(curl -s -q --max-time 3 -H "X-aliyun-ecs-metadata-token: ${IMDS_TOKEN}" -f ${METADATA_BASEURL}/latest/meta-data/private-ipv4)
    while [ -z "$ip" ]; do
        ip=$(curl -s -q --max-time 3 -H "X-aliyun-ecs-metadata-token: ${IMDS_TOKEN}" -f ${METADATA_BASEURL}/latest/meta-data/private-ipv4)
        sleep 1
    done
    echo "Generating hostname ${region}-${ip//./-}"
    hostnamectl set-hostname "${region}-${ip//./-}"
}
setup_hostname
function update_os_and_install_necessary_tools {
    # yum -y update // too slow
    yum makecache
    yum -y install jq wget yum-utils conntrack-tools ipvsadm socat git lrzsz ipvsadm
}
update_os_and_install_necessary_tools

function install_ecs_metadata {
    wget https://gitlab.com/liguanghui/ecs-metadata/-/raw/main/ecs-metadata -O /usr/local/bin/ecs-metadata
    chmod a+x /usr/local/bin/ecs-metadata
}
install_ecs_metadata

function install_aliyun_cli {
    wget https://aliyuncli.alicdn.com/${aliyun_cli_file} -O ${aliyun_cli_file}
    tar -zxvf ${aliyun_cli_file} -C /usr/local/bin/
    chmod a+x /usr/local/bin/aliyun
    rm -f ${aliyun_cli_file}
    aliyun configure set --profile default --mode EcsRamRole --ram-role-name ${ecs_ram_role_name} --region ${aliyun_region}
}
install_aliyun_cli

function install_containerd {
    # 加载了这两个模块，下面的sysctl命令才不会报错
    echo "br_netfilter" >> /etc/modules-load.d/netfilter.conf
    echo "overlay" >> /etc/modules-load.d/netfilter.conf
    modprobe br_netfilter overaly
    cat > /etc/sysctl.d/containerd.conf << 'EOF'
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
    sysctl -p /etc/sysctl.d/containerd.conf
    local object_name="oss://${oss_bucket_name}/${kubernetes_version}/${containerd_package_name}"
    aliyun oss cp "${object_name}" .
    tar -zxvf ${kubernetes_version}/${containerd_package_name} -C /usr/local/
    # 使用systemd管理containerd服务
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/containerd.service" /etc/systemd/system/containerd.service
    # 安装低级运行时runc
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/runc-${runc_version}.amd64" /usr/local/sbin/runc
    chmod a+x /usr/local/sbin/runc
    # 安装cni插件
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/cni-plugins-linux-amd64-${cni_plugins_version}.tgz" .
    mkdir -p /opt/cni/bin && tar -zxvf ${kubernetes_version}/cni-plugins-linux-amd64-${cni_plugins_version}.tgz -C /opt/cni/bin
    # 安装调试工具crictl
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/crictl-${cri_tools_version}-linux-amd64.tar.gz" .
    tar -zxvf ${kubernetes_version}/crictl-${cri_tools_version}-linux-amd64.tar.gz -C /usr/local/bin/
    chmod a+x /usr/local/bin/crictl
    cat << 'EOF' >> /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: true
EOF
    # 安装containerd的命令行工具nerdctl
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/nerdctl-${nerdctl_version/v/}-linux-amd64.tar.gz" .
    tar -zxvf ${kubernetes_version}/nerdctl-${nerdctl_version/v/}-linux-amd64.tar.gz -C /usr/local/bin/
    # 生成containerd默认配置文件
    mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml
    sed -i 's@registry.k8s.io/pause:3.8@registry.k8s.io/pause:3.9@' /etc/containerd/config.toml
    # https://stackoverflow.com/questions/55571566/unable-to-bring-up-kubernetes-api-server
    # 使用systemd管理cgroup https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd
    sed -i 's/ *SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
    # 启动服务
    systemctl daemon-reload
    systemctl enable --now containerd.service
}
install_containerd

function download_kubernetes_packages {
    local server_object_name="oss://${oss_bucket_name}/${kubernetes_version}/${kubernetes_server_package_name}"
    aliyun oss cp "${server_object_name}" .
    tar -zxvf ${kubernetes_version}/${kubernetes_server_package_name}
    for tarfile in kubernetes/server/bin/*.tar; do nerdctl -n k8s.io image load -i $tarfile; done
    for img in kube-apiserver-amd64 kube-controller-manager-amd64 kube-proxy-amd64 kube-scheduler-amd64; do nerdctl -n k8s.io image tag registry.k8s.io/$img:${kubernetes_version} registry.k8s.io/${img/-amd64/}:${kubernetes_version}; done
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/pause_etcd_coredns.tar" .
    nerdctl -n k8s.io image load -i ${kubernetes_version}/pause_etcd_coredns.tar
    install -o root -g root -m 0755 kubernetes/server/bin/kubectl-convert /usr/local/bin/kubectl-convert
    # 使用systemd管理kubelet
    cat >> /etc/systemd/system/kubelet.service << 'EOF'
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /etc/systemd/system/kubelet.service.d
    cat >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << 'EOF'
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
    mv kubernetes/server/bin/{kubeadm,kubelet,kubectl} /usr/local/bin
    chmod a+x /usr/local/bin/{kubeadm,kubelet,kubectl}
    kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null
    chmod a+r /etc/bash_completion.d/kubectl
    echo 'alias k=kubectl' >> ~/.bashrc
    echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc
    systemctl enable kubelet
}
download_kubernetes_packages

function download_metrics_server_image {
    aliyun oss cp "oss://${oss_bucket_name}/${kubernetes_version}/metrics-server-${metrics_server_version}.tar" .
    nerdctl -n k8s.io image load -i "${kubernetes_version}/metrics-server-${metrics_server_version}.tar"
}
download_metrics_server_image

echo 'GRUB_CMDLINE_LINUX="cgroup_enable=cpu"' >> /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot

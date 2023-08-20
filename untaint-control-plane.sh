#!/bin/bash
# 移除control-plane上的污点，使普通Pod也能运行在上面
for node in $(kubectl get nodes | grep control-plane | awk '{print $1}'); do kubectl taint nodes $node node-role.kubernetes.io/control-plane-; done

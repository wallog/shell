#!/bin/bash

#km-wl
set -ux

source env

if [ $# -eq 0 ];then
    echo -e "${YELLOW}deploy kubernetes 1.8.3 pre-check:
    1,k8s nodes logon without password
    2,k8s nodes docker install
    input:${GREEN}$0 install${NC} ${YELLOW}starting deploy elemental
    $NC"
    exit
fi

function judge() {
    if [ $1 == 0 ];then
        echo -e "${GREEN}[INFO]step $2 ok!${NC} "
    else
        echo -e "${RED}[ERROR] step $2 something wrong${NC}"
#    uninstall
#    echo -e "${RED}[ERROR] uninstall kubernetes!${NC}"
        exit 3
    fi
}

#ca
echo -e "${GREEN}[INFO]step 1: basic deploy(docker,etcd,kubelet), import images.${NC}"
for NODE in ${knodes[@]};do
    ssh ${NODE} "cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF"
    ssh ${NODE} "sysctl -p /etc/sysctl.d/k8s.conf"
    scp docker-images/base_images/{pause.tar,calico-node.tar,proxy.tar} ${NODE}:/root/ &>/dev/null
    ssh ${NODE} "docker load < pause.tar"
    ssh ${NODE} "docker load < calico-node.tar"
    ssh ${NODE} "docker load < proxy.tar"
    ssh ${NODE} "mkdir -p ${k8sDir}/pki ${etcdDir}/ssl ${etcDir}/kubelet.service.d ${cniDir}/bin ${kubeletVarDir} ${kubeLogDir}"
    for FILE in etcd-ca.pem etcd.pem etcd-key.pem; do
        scp ${etcdDir}/ssl/${FILE} ${NODE}:${etcdDir}/ssl/${FILE} &>/dev/null
    done
    for FILE in pki/ca.pem pki/ca-key.pem bootstrap.conf; do
        scp ${k8sDir}/${FILE} ${NODE}:${k8sDir}/${FILE} &>/dev/null
    done
    for FILE in pki/kube-proxy.pem pki/kube-proxy-key.pem kube-proxy.conf; do
        scp ${k8sDir}/${FILE} ${NODE}:${k8sDir}/${FILE} &>/dev/null
    done
    scp nodes/bin/kubelet ${NODE}:/usr/local/bin/ &>/dev/null
    scp nodes/conf/10-kubelet.conf ${NODE}:${etcDir}/kubelet.service.d/ &>/dev/null
    scp nodes/conf/kubelet.service ${NODE}:${systemLibDir}/kubelet.service &>/dev/null
    scp nodes/bin/cni/* ${NODE}:${cniDir}/bin/ &>/dev/null
    ssh ${NODE} "systemctl enable kubelet.service && systemctl start kubelet"
done
sleep 15
#ClusterRoleBinding
echo -e "${GREEN}[INFO]step 2: clusterRoleBinding and approve cert${NC}"
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap &>/dev/null
sleep 15
kubectl get csr | awk '/Pending/ {print $1}' | xargs kubectl certificate approve &>/dev/null
#get nodes
#kubectl get no
#calico.
echo -e "${GREEN}[INFO]step 3: cni and calico-node${NC}"
for NODE in ${knodes[@]};do
    hostIP=$(grep ${NODE} /etc/hosts | awk '{print $1}' | uniq)
    ssh ${NODE} "mkdir -p /etc/cni/net.d"
    scp nodes/conf/10-calico.conf ${NODE}:/etc/cni/net.d/10-calico.conf &>/dev/null
    scp nodes/conf/calico-node.service ${NODE}:${systemLibDir}/calico-node.service &>/dev/null
    if [ x"${hostIP}" != x ];then
        ssh ${NODE} "sed -i 's/\$ETCDIP/$etcdip/g' /etc/cni/net.d/10-calico.conf"
        ssh ${NODE} "sed -i -e 's/\$ETCDIP/$etcdip/g' -e 's/\$HOSTIP/$hostIP/g' -e 's/\$HOSTNAME/$NODE/g' -e 's/\$INTERFACE/$interFace/g' $systemLibDir/calico-node.service" 
    else
        echo "hostip is null"
        exit 
    fi
    ssh ${NODE} "systemctl enable calico-node.service && systemctl start calico-node.service"
done
echo -e "${GREEN}[INFO]kubernetes nodes deploy successful! input check: kubectl get no & kubectl -n kube-system get po ${NC}"
sleep 5
kubectl get no
kubectl -n kube-system get po

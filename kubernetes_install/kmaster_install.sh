#!/bin/bash

#km-wl
set -u

source env

#deploy pre-check
if [ $# -eq 0 ];then
  echo -e "${YELLOW}deploy kubernetes 1.8.3 pre-check:
  1,docker version v17+ and complite deployment
  2,disable selinux
  3,disable firewalld
  4,kernel 4.0+
  5,node ssh deploy

input:${GREEN}$0 install${NC} ${YELLOW}starting deploy kubernetes
  $NC"
  exit
fi

function fileCheck() {
  if [[ ! -f $1 ]];then
   echo -e "${RED}[ERROR] ${NC}:FILE $RED$1$NC inexistence!" 
   exit 1
  fi
}

function dirCheck() {
  if [[ ! -d $1 ]];then
   echo -e "${RED}[ERROR] ${NC}:DIR $RED$1$NC inexistence!" 
   exit 2
  fi
}

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

function genca() {
  cfssl -loglevel 5 gencert -initca $1 | cfssljson -bare $2 2>&1>/dev/null
}

function cfsslgen() {
  cfssl -loglevel 5 gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=10.96.0.1,$hostIP,127.0.0.1,kubernetes.default,kubernetes.default.svc -profile=kubernetes apiserver-csr.json | cfssljson -bare apiserver 2>&1>/dev/null
}

function cfsslgen_common() {
  cfssl -loglevel 5 gencert -ca=$1 -ca-key=$2 -config=$3 -profile=kubernetes $4 | cfssljson -bare $5 2>&1>/dev/null
}

function setCluster() {
  kubectl config set-cluster kubernetes --certificate-authority=ca.pem --embed-certs=true --server=${KUBE_APISERVER} --kubeconfig=${k8sDir}/$1 2>&1>/dev/null
}

function setCredentials() {
  kubectl config set-credentials $1 --client-certificate=$2 --client-key=$3 --embed-certs=true --kubeconfig=${k8sDir}/$4 2>&1>/dev/null
}

function setContext() {
  kubectl config set-context $1 --cluster=kubernetes --user=$2 --kubeconfig=${k8sDir}/$3 2>&1>/dev/null
}

function useContext() {
  kubectl config use-context $1 --kubeconfig=${k8sDir}/$2 2>&1>/dev/null
}

function uninstall() {
  systemctl stop etcd &>/dev/null
  systemctl stop kubelet &>/dev/null
  systemctl stop calico-node &>/dev/null
  rm -rf $etcdDir $k8sDir $kubeletVarDir $kubeLogDir
  docker rm -f $(docker ps -a | grep "k8s" |awk '{print $1}') &>/dev/null
}

if [ $1 == "install" ];then
#import basic images
  echo -e $GREEN Deployment takes 2 minutes$NC
  for image in $(ls $basicDir/docker-images/base_images)
    do
      docker load < $basicDir/docker-images/base_images/$image 2>&1>/dev/null
    done

#basic bin
cp -r $basicDir/bin/* /usr/local/bin/

cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl -p /etc/sysctl.d/k8s.conf &>/dev/null
#ETCD deploy
[ ! -d $etcdDir/ssl ] && mkdir -p $etcdDir/ssl
cp $basicDir/certificates/etcd/* $etcdDir/ssl/
fileCheck $etcdDir/ssl/etcd-csr.json
sed -i "s/172.16.35.12/$hostIP/g" $etcdDir/ssl/etcd-csr.json 
cd $etcdDir/ssl
  cfssl -loglevel 5 gencert -initca etcd-ca-csr.json | cfssljson -bare etcd-ca &>/dev/null
  cfssl -loglevel 5 gencert -ca=etcd-ca.pem -ca-key=etcd-ca-key.pem -config=ca-config.json -profile=kubernetes etcd-csr.json | cfssljson -bare etcd &>/dev/null
##check generate pem
  fileCheck etcd-ca-key.pem
  fileCheck etcd-ca.pem
  fileCheck etcd-key.pem
  fileCheck etcd.pem
##add etcd
if ! grep -w "etcd" /etc/group &>/dev/null;then
    groupadd etcd && useradd -c "Etcd user" -g etcd -s /sbin/nologin -r etcd
fi
  cp $basicDir/conf/etcd/etcd.conf $etcdDir/
  cp $basicDir/conf/etcd/etcd.service $systemLibDir/
  sed -i "s/\$HOSTIP/$hostIP/g" $etcdDir/etcd.conf
  mkdir -p /var/lib/etcd && chown etcd:etcd -R /var/lib/etcd /etc/etcd
  systemctl enable etcd.service &>/dev/null && systemctl start etcd.service
  judge $? "1: etcd-deploy"
#CNI
mkdir -p /opt/cni/bin && cp $basicDir/bin/cni/* /opt/cni/bin/
#Certificates
[ ! -d $k8sDir ] && mkdir $k8sDir/pki -p
cd $k8sDir/pki
cp $basicDir/certificates/pki/* .
##ca apiserver
genca ca-csr.json ca
cfsslgen
fileCheck ca-key.pem
fileCheck ca.pem
fileCheck apiserver-key.pem
fileCheck apiserver.pem
##front-proxy
genca front-proxy-ca-csr.json front-proxy-ca
cfsslgen_common front-proxy-ca.pem front-proxy-ca-key.pem ca-config.json front-proxy-client-csr.json front-proxy-client
fileCheck front-proxy-client-key.pem
fileCheck front-proxy-client.pem
#Bootstrap Token
cat <<EOF > $k8sDir/token.csv
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
setCluster bootstrap.conf
kubectl config set-credentials kubelet-bootstrap --token=${BOOTSTRAP_TOKEN} --kubeconfig=${k8sDir}/bootstrap.conf &>/dev/null
setContext default kubelet-bootstrap bootstrap.conf
useContext default bootstrap.conf
##admin certificate
cfsslgen_common ca.pem ca-key.pem ca-config.json admin-csr.json admin
fileCheck admin-key.pem
fileCheck admin.pem
setCluster admin.conf
setCredentials kubernetes-admin admin.pem admin-key.pem admin.conf
setContext kubernetes-admin@kubernetes kubernetes-admin admin.conf 
useContext kubernetes-admin@kubernetes admin.conf
##controller manager certificate
cfsslgen_common ca.pem ca-key.pem ca-config.json manager-csr.json controller-manager
fileCheck controller-manager-key.pem
fileCheck controller-manager.pem
setCluster controller-manager.conf
setCredentials system:kube-controller-manager controller-manager.pem controller-manager-key.pem controller-manager.conf
setContext system:kube-controller-manager@kubernetes system:kube-controller-manager controller-manager.conf
useContext system:kube-controller-manager@kubernetes controller-manager.conf
##scheduler certificate
cfsslgen_common ca.pem ca-key.pem ca-config.json scheduler-csr.json scheduler
fileCheck scheduler-key.pem
fileCheck scheduler.pem
setCluster scheduler.conf
setCredentials system:kube-scheduler scheduler.pem scheduler-key.pem scheduler.conf
setContext system:kube-scheduler@kubernetes system:kube-scheduler scheduler.conf
useContext system:kube-scheduler@kubernetes scheduler.conf
##kubelet certificate
sed -i "s/\$NODE/$hostName/g" kubelet-csr.json
cfssl -loglevel 5 gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=$hostName,$hostIP -profile=kubernetes kubelet-csr.json | cfssljson -bare kubelet &>/dev/null
fileCheck kubelet-key.pem
fileCheck kubelet.pem
setCluster kubelet.conf
setCredentials system:node:$hostName kubelet.pem kubelet-key.pem kubelet.conf
setContext system:node:$hostName@kubernetes system:node:$hostName kubelet.conf
useContext system:node:$hostName@kubernetes kubelet.conf
##service account Key
openssl genrsa -out sa.key 2048 &>/dev/null
openssl rsa -in sa.key -pubout -out sa.pub
fileCheck sa.key
fileCheck sa.pub
##fileCheck
fileList=("admin.conf" "bootstrap.conf" "controller-manager.conf" "kubelet.conf" "scheduler.conf" "token.csv")
for n in ${fileList[@]};do
  fileCheck $k8sDir/$n
done
judge $? "2: certificates"
#manifests
[ ! -d $k8sDir/manifests ] && mkdir -p $k8sDir/manifests
cd $k8sDir/manifests
cp $basicDir/conf/manifests/* . 
sed -i "s/\$HOSTIP/$hostIP/g" apiserver.yml
##encryption
cat <<EOF > $k8sDir/encryption.yml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${passWD}
      - identity: {}
EOF
##audit
cat <<EOF > $k8sDir/audit-policy.yml
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF
#deploy kubelet
[ ! -d $etcDir/kubelet.service.d ] && mkdir -p $etcDir/kubelet.service.d
cp $basicDir/conf/10-kubelet.conf $etcDir/kubelet.service.d/
cp $basicDir/conf/kubelet.service $systemLibDir/
mkdir -p $kubeletVarDir $kubeLogDir
systemctl enable kubelet.service &>/dev/null && systemctl start kubelet.service
judge $? "3: kubelet-startup"
sleep 60
portList="10248 10251 10252 6443"
for port in $portList;do
  netstat -tnpl | grep -w $port &>/dev/null
  judge $? "4: manifest-docker-$port"
done
##kube status
[ ! -d ~/.kube ] && mkdir ~/.kube 
cp -f $k8sDir/admin.conf ~/.kube/config
kubectl get cs &>/dev/null
nodeStatus=$(kubectl get no | grep $hostName |awk '{print $2}')
kubectl -n kube-system get po &>/dev/null
judge $? "5: kubectl-status"
cp $basicDir/conf/apiserver-to-kubelet-rbac.yml $k8sDir/
kubectl apply -f $k8sDir/apiserver-to-kubelet-rbac.yml &>/dev/null
#CNI
mkdir -p /opt/cni/bin && cd /opt/cni/bin
cp $basicDir/bin/cni/* .
#kube-proxy dns deploy
cd $k8sDir/pki
cfsslgen_common ca.pem ca-key.pem ca-config.json kube-proxy-csr.json kube-proxy
fileCheck kube-proxy-key.pem
fileCheck kube-proxy.pem
setCluster kube-proxy.conf
setCredentials system:kube-proxy kube-proxy.pem kube-proxy-key.pem kube-proxy.conf
setContext system:kube-proxy@kubernetes system:kube-proxy kube-proxy.conf
useContext system:kube-proxy@kubernetes kube-proxy.conf
mkdir $k8sDir/addons && cd $k8sDir/addons
cp $basicDir/conf/addons/* .
kubectl apply -f kube-proxy.yml &>/dev/null
kubectl apply -f kube-dns.yml &>/dev/null
sleep 30
proxyStatus=$(kubectl get po -n kube-system | grep proxy |awk '{print $3}')
echo $proxyStatus | grep -w "Running" &>/dev/null
judge $? "6: kube-proxy"
#calico deploy
sed -i "s/\$HOSTIP/$hostIP/g" calico-controller.yml
kubectl create -f calico-controller.yml &>/dev/null
[ ! -d /opt/cni/bin ] && mkdir /opt/cni/bin
cp $basicDir/bin/cni/* /opt/cni/bin/
[ ! -d /etc/cni/net.d ] && mkdir -p /etc/cni/net.d
cp $basicDir/conf/calico/10-calico.conf /etc/cni/net.d/10-calico.conf
sed -i "s/\$HOSTIP/$hostIP/g" /etc/cni/net.d/10-calico.conf
cp $basicDir/conf/calico/calico-node.service $systemLibDir/calico-node.service
sed -i -e "s/\$HOSTIP/$hostIP/g" -e "s/\$HOSTNAME/$hostName/g" -e "s/\$INTERFACE/$interFace/g" $systemLibDir/calico-node.service
systemctl enable calico-node.service &>/dev/null && systemctl start calico-node.service
judge $? "7: calico"
#set node label
kubectl label no $(hostname) node=$(hostname)
#input kubernetes po
sleep 15
kubectl get po -n kube-system
echo -e ${GREEN}kubernetes install completed!${NC}
else
  echo "input wrong!"
fi

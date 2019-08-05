#!/bin/bash
#wl
set -e

#global val
apiurl="6443"
contenttype="application/json-patch+json"
driverurl="driver.kmtongji.com"


#get contexts list
contextList=$(curl $apiurl/api/v1/namespaces/default/pods -k -s | grep -E -o "standard.*kmde" |uniq)

if [[ $# -eq 0 ]];then
#when jobserver lived,add driver-ui-port to driver-service:4040.
while true ;do
  if [[ "x$contextList" != "x" ]];then
    sleep 4
#get driver-service name list
    service_name=$(curl $apiurl/api/v1/namespaces/default/services -k -s | grep -E -o "spark.*driver-svc" |uniq)
#modify service-yaml file
    add_service_port_json_format='[                                                                                                               
    {                                                                                                                                   
        "op": "add",                                                                                                                    
        "path": "/spec/ports/-",                                                                                                        
        "value": {                                                                                                                      
            "name": "uiport",                                                                                                           
            "protocol": "TCP",                                                                                                          
            "port": 4040,                                                                                                               
            "targetPort": 4040                                                                                                          
        }                                                                                                                               
    }                                                                                                                                   
    ]                                                                                                                                   
    '
    snum=0

    for name in $service_name;do
      curl -X PATCH -d "$add_service_port_json_format" -H "Content-Type: $contenttype" "$apiurl/api/v1/namespaces/default/services/$name" -k -s
#modify driver-ingress-yaml file
      ingress_json_format="[                                                                                                                                               
      {                                                                                                                                                                    
          \"op\": \"replace\",                                                                                                                                             
          \"path\": \"/spec/rules/$snum/http/paths/0/backend/serviceName\",                                                                                                
          \"value\": \"$name\"                                                                                                                                             
      }                                                                                                                                                                    
      ]                                                                                                                                                                    
    "

      curl -X PATCH -d "$ingress_json_format" -H "Content-Type: $contenttype" "$apirul/apis/extensions/v1beta1/namespaces/default/ingresses/ingress-elemental-driver" -k -s

      snum=$(($snum+1))

      done
      echo "CONTEXTS UPDATE OK"                                                                                                                                                                                    
      exit 0
  fi

  contextList=$(curl $apiurl/api/v1/namespaces/default/pods -k -s | grep -E -o "standard.*kmde" |uniq)

done

elif [[ "$1" == "-h" || "$1" == "h" ]];then

echo "Usage:

$0 context_name service_name;
  visit: context_name.driver.kmtongji.com
"
elif [[ "$1" == "delete" ]];then
  DeleteServiceFromIngress(){
  pass

}
 DeleteServiceFromIngress
else
#ADD new context service in ingress

AddServiceToIngress(){
  AddserviceJson="[
{
    \"op\": \"add\",
    \"path\": \"/spec/rules/-\",
    \"value\": {
        \"host\": \"$1.$driverurl\",
        \"http\": {
          \"paths\": [
            {
              \"backend\": {
                \"serviceName\": \"$2\",
                \"servicePort\": 4040
              }
            }
          ]
        }
}
}
]
"
curl -X PATCH -d "$AddserviceJson" -H "Content-Type: $contenttype" "$apiurl/apis/extensions/v1beta1/namespaces/default/ingresses/ingress-elemental-driver" -k
}

AddServiceToIngress $ContextName $ServiceName

# add dirver ui port 4040 to DB
AddServicePortToDB(){
    add_service_port_json_format='[                                                                                                               
    {                                                                                                                                   
        "op": "add",                                                                                                                    
        "path": "/spec/ports/-",                                                                                                        
        "value": {                                                                                                                      
            "name": "uiport",                                                                                                           
            "protocol": "TCP",                                                                                                          
            "port": 4040,                                                                                                               
            "targetPort": 4040                                                                                                          
        }                                                                                                                               
    }                                                                                                                                   
    ]                                                                                                                                   
    '
    curl -X PATCH -d "$add_service_port_json_format" -H "Content-Type: $contenttype" "$apiurl/api/v1/namespaces/default/services/$1" -k -s
}

ddServicePortToDB $ServiceName

fi

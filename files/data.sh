#!/bin/bash -ex
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh
kubectl create ns	wordpress-cwi   
helm -n wordpress-cwi install understood-zebu bitnami/wordpress  
sleep 30
export SERVICE_IP=$(kubectl get svc --namespace wordpress-cwi understood-zebu-wordpress --template "{{ range (index .status.loadBalancer.ingress 0) }}{{.}}{{ end }}") 
touch creds
echo "WordPress URL: http://$SERVICE_IP/"  >> creds
echo "WordPress Admin URL: http://$SERVICE_IP/admin" >> creds
echo "Username: user" >> creds 
echo Password: $(kubectl get secret --namespace wordpress-cwi understood-zebu-wordpress -o jsonpath="{.data.wordpress-password}" | base64 --decode) >> creds
 aws s3 cp creds s3://$S3_BUCKET_NAME}/
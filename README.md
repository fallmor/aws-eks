# aws-eks

This project will deploy an EKS cluster on aws using spot instances for worker group.

Important: to use ELB you have to tag the private and public subnet since AWS doesn't allow to provision ELB on private subnet.

to retrieve the access credential and configure automatically your kubeconfig you have to run the following command. (By default only the user who provision the cluster have the right to run kubectl commands)

#test
> aws eks --region eu-west-3 update-kubeconfig --name {cluster-name}

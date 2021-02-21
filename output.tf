output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.my-cluster.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value       = module.my-cluster.cluster_security_group_id
}

output "kubectl_config" {
  description = "kubectl config as generated by the module."
  value       = module.my-cluster.kubeconfig
}

output "config_map_aws_auth" {
  description = "A kubernetes configuration to authenticate to this EKS cluster."
  value       = module.my-cluster.config_map_aws_auth
}

output "region" {
  description = "AWS region."
  value       = var.region
}

# Printed after terraform apply.
output "cluster_name" {
  value = module.eks.cluster_name
}

# Copy-paste this to point kubectl at the new cluster.
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

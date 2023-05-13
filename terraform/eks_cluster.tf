resource "aws_eks_cluster" "aws_eks_cluster" {
	name     = data.external.env.result["SHORT_APP_NAME"]
	role_arn = aws_iam_role.eks_cluster_role.arn

	vpc_config {
		subnet_ids = concat(
			aws_subnet.aws_subnet_public.*.id,
			aws_subnet.aws_subnet_private.*.id,
		)
		security_group_ids = [aws_security_group.aws_security_group.id]
	}
}

resource "aws_eks_node_group" "aws_eks_node_group" {
	cluster_name = aws_eks_cluster.aws_eks_cluster.name
	node_group_name =data.external.env.result["SHORT_APP_NAME"]
	node_role_arn = aws_iam_role.eks_node_group_role.arn
	ami_type = "AL2_ARM_64"

	subnet_ids = aws_subnet.aws_subnet_private.*.id

	scaling_config {
		desired_size = 1
		max_size = 1
		min_size = 0
	}

	instance_types = ["t4g.small"]

	depends_on = [
		aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
		aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
		aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy
	]
}

resource "aws_eks_identity_provider_config" "aws_eks_identity_provider_config" {
	cluster_name = aws_eks_cluster.aws_eks_cluster.name

	oidc {
		client_id                     = substr(aws_eks_cluster.aws_eks_cluster.identity.0.oidc.0.issuer, -32, -1)
		identity_provider_config_name = "something"
		issuer_url                    = aws_eks_cluster.aws_eks_cluster.identity.0.oidc.0.issuer
	}
}

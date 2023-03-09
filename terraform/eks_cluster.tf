resource "aws_eks_cluster" "exch-gr" {
	name     = "exch-gr"
	role_arn = aws_iam_role.exch-gr-eks-cluster-role.arn

	vpc_config {
		subnet_ids = [
			aws_subnet.exch-gr-public-us-east-1a.id,
			aws_subnet.exch-gr-public-us-east-1b.id,
			aws_subnet.exch-gr-private-us-east-1a.id,
			aws_subnet.exch-gr-private-us-east-1b.id,
		]
		security_group_ids = [aws_security_group.exch-gr.id]
	}
}

resource "aws_eks_node_group" "exch-gr" {
	cluster_name = aws_eks_cluster.exch-gr.name
	node_group_name = "exch-gr"
	node_role_arn = aws_iam_role.exch-gr-eks-node-group-role.arn
	ami_type = "AL2_ARM_64"

	subnet_ids = [
		aws_subnet.exch-gr-private-us-east-1a.id,
		aws_subnet.exch-gr-private-us-east-1b.id,
	]

	scaling_config {
		desired_size = 1
		max_size = 1
		min_size = 0
	}

	instance_types = ["a1.large"]

	depends_on = [
		aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
		aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
		aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy
	]
}

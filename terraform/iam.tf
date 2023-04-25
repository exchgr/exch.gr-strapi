resource "aws_iam_role" "exch-gr-eks-cluster-role" {
	name = "exch-gr-eks-cluster-role"
	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [{
			Action = "sts:AssumeRole"
			Effect = "Allow"
			Principal = {
				Service = "eks.amazonaws.com"
			}
		}]
	})
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
	role       = aws_iam_role.exch-gr-eks-cluster-role.name
}

resource "aws_iam_role" "exch-gr-eks-node-group-role" {
	name = "exch-gr-eks-node-group-role"
	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [{
			Action = "sts:AssumeRole"
			Effect = "Allow"
			Principal = {
				Service = "ec2.amazonaws.com"
			}
		}]
	})
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
	role       = aws_iam_role.exch-gr-eks-node-group-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
	role       = aws_iam_role.exch-gr-eks-node-group-role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
	role       = aws_iam_role.exch-gr-eks-node-group-role.name
}

# AWS Load Balancer Controller

data "aws_caller_identity" "current" {}

locals {
	account_id = data.aws_caller_identity.current.account_id
	oidc_provider = trimprefix (aws_eks_cluster.exch-gr.identity.0.oidc.0.issuer, "https://")
}

resource "aws_iam_policy" "aws-load-balancer-controller" {
	name = "aws-load-balancer-controller"
	policy = file("./aws-load-balancer-controller-iam-policy.json")
}

resource "aws_iam_role" "aws-load-balancer-controller" {
	name = "aws-load-balancer-controller"
	assume_role_policy = jsonencode({
		Version = "2012-10-17"
		Statement = [{
			Action = "sts:AssumeRoleWithWebIdentity"
			Effect = "Allow"
			Principal = {
				Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${local.oidc_provider}"
			}
		}]
	})
}

resource "aws_iam_role_policy_attachment" "aws-load-balancer-controller" {
	policy_arn = aws_iam_policy.aws-load-balancer-controller.arn
	role = aws_iam_role.aws-load-balancer-controller.name
}

resource "kubernetes_service_account" "aws-load-balancer-controller" {
	metadata {
		name = "aws-load-balancer-controller"
		annotations = {
			"eks.amazonaws.com/role-arn" = aws_iam_role.aws-load-balancer-controller.arn
		}
		namespace = "kube-system"
	}
}

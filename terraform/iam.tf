resource "aws_iam_role" "eks_cluster_role" {
	name = "${data.external.env.result["SHORT_APP_NAME"]}-eks-cluster-role"
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
	role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_node_group_role" {
	name = "${data.external.env.result["SHORT_APP_NAME"]}-eks-node-group-role"
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
	role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
	role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
	policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
	role       = aws_iam_role.eks_node_group_role.name
}

# AWS Load Balancer Controller

data "aws_caller_identity" "current" {}

locals {
	account_id = data.aws_caller_identity.current.account_id
	oidc_provider = trimprefix (aws_eks_cluster.aws_eks_cluster.identity.0.oidc.0.issuer, "https://")
	oidc_provider_arn = "arn:aws:iam::${local.account_id}:oidc-provider/${local.oidc_provider}"
	aws_load_balancer_controller_service_account = "aws-load-balancer-controller"
	aws_load_balancer_controller_namespace = "kube-system"
}

resource "aws_iam_policy" "aws-load-balancer-controller" {
	name = "aws-load-balancer-controller"
	policy = file("./aws-load-balancer-controller-iam-policy.json")
}

resource "aws_iam_role" "aws-load-balancer-controller" {
	name = "aws-load-balancer-controller"
	assume_role_policy = templatefile(
		"aws-load-balancer-controller-assume-role-policy.json.tftpl",
		{
			oidc_provider_arn = local.oidc_provider_arn
			oidc_provider = local.oidc_provider
			aws_load_balancer_controller_service_account = local.aws_load_balancer_controller_service_account
			aws_load_balancer_controller_namespace = local.aws_load_balancer_controller_namespace
		}
	)
}

resource "aws_iam_role_policy_attachment" "aws-load-balancer-controller" {
	policy_arn = aws_iam_policy.aws-load-balancer-controller.arn
	role = aws_iam_role.aws-load-balancer-controller.name
}

resource "kubernetes_service_account" "aws-load-balancer-controller" {
	metadata {
		name = local.aws_load_balancer_controller_service_account
		annotations = {
			"eks.amazonaws.com/role-arn" = aws_iam_role.aws-load-balancer-controller.arn
		}
		namespace = local.aws_load_balancer_controller_namespace
	}
}

resource "kubernetes_config_map" "aws_auth" {
	metadata {
		name      = "aws-auth"
		namespace = "kube-system"
	}

	data = yamldecode(
		templatefile(
			"aws-auth-config-map.yml",
			{
				eks_node_group_role_name = aws_iam_role.eks_node_group_role.name
				aws_account_id = data.external.env.result["AWS_ACCOUNT_ID"]
			}
		)
	)

	depends_on = [aws_eks_cluster.aws_eks_cluster]
}

data "tls_certificate" "aws_eks_oidc_provider" {
	url = aws_eks_cluster.aws_eks_cluster.identity.0.oidc.0.issuer
}

resource "aws_iam_openid_connect_provider" "aws_iam_openid_connect_provider" {
	client_id_list  = ["sts.amazonaws.com"]
	thumbprint_list = [data.tls_certificate.aws_eks_oidc_provider.certificates.0.sha1_fingerprint]
	url             = aws_eks_cluster.aws_eks_cluster.identity.0.oidc.0.issuer
}

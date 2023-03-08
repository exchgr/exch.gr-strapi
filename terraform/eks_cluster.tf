resource "aws_eks_cluster" "exch-gr" {
	name     = "exch-gr"
	role_arn = aws_iam_role.exch-gr-eks-cluster-role.arn

	vpc_config {
		subnet_ids = [aws_subnet.exch-gr-public.id, aws_subnet.exch-gr-private.id]
		security_group_ids = [aws_security_group.exch-gr.id]
	}
}

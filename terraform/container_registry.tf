resource "aws_ecr_repository" "aws_ecr_repository" {
	name = data.external.env.result["APP_NAME"]
}

resource "aws_ecr_repository" "aws_ecr_repository" {
	name = data.external.env.result["APP_NAME"]
}

resource "aws_ecr_lifecycle_policy" "aws_ecr_lifecycle_policy" {
	repository = aws_ecr_repository.aws_ecr_repository.name

	policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 3 images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v"],
                "countType": "imageCountMoreThan",
                "countNumber": 3
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

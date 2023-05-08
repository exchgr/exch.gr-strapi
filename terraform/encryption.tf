resource "aws_acm_certificate" "aws_acm_certificate" {
	domain_name = data.external.env.result["DOMAIN_NAME"]

	subject_alternative_names = split(",", data.external.env.result["SUBJECT_ALTERNATIVE_NAMES"])

	validation_method = "DNS"

	# ECDSA 384 bit, the maximum allowed for public ACM certificate
	#
	# for details:
	# https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html
	# https://docs.aws.amazon.com/acm/latest/userguide/acm-certificate.html#algorithms
	key_algorithm = "RSA_2048"
}

output "aws-acm-certificate" {
	value = aws_acm_certificate.aws_acm_certificate.arn
}

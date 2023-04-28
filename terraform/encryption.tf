resource "aws_acm_certificate" "exch-gr" {
	domain_name = "exch.gr"

	subject_alternative_names = [
		"*.exch.gr"
	]

	validation_method = "DNS"

	# ECDSA 384 bit, the maximum allowed for public ACM certificate
	#
	# for details:
	# https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html
	# https://docs.aws.amazon.com/acm/latest/userguide/acm-certificate.html#algorithms
	key_algorithm = "RSA_2048"
}

output "aws-acm-exch-gr" {
	value = aws_acm_certificate.exch-gr.arn
}

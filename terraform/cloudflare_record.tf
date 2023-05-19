resource "cloudflare_record" "aws_tls_validation" {
	name    = replace(
		element(
			aws_acm_certificate.aws_acm_certificate.domain_validation_options.*.resource_record_name,
			0
		),
		".${data.external.env.result["DOMAIN_NAME"]}.",
		""
	)
	proxied = false
	ttl     = 3600
	type    = element(aws_acm_certificate.aws_acm_certificate.domain_validation_options.*.resource_record_type, 0)
	value   = element(aws_acm_certificate.aws_acm_certificate.domain_validation_options.*.resource_record_value, 0)
	zone_id = data.external.env.result["CLOUDFLARE_ZONE_ID"]
}

resource "cloudflare_record" "admin" {
	name    = "admin"
	proxied = false
	ttl     = 1
	type    = "CNAME"
	value   = kubernetes_service.kubernetes_service.status.0.load_balancer.0.ingress.0.hostname
	zone_id = data.external.env.result["CLOUDFLARE_ZONE_ID"]
}


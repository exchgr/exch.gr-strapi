# This is here instead of in kubernetes because it depends on terraform resources
resource "kubernetes_service" "kubernetes_service" {
	metadata {
		name = data.external.env.result["APP_NAME"]

		labels = {
			run = data.external.env.result["APP_NAME"]
		}

		annotations = {
			"service.beta.kubernetes.io/aws-load-balancer-type" = "external"
			"service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
			"service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
			"service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", aws_eip.aws_eip_nlb.*.allocation_id)
			"service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "http"
			"service.beta.kubernetes.io/aws-load-balancer-ssl-cert" = aws_acm_certificate.aws_acm_certificate.arn
			"service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "https"
			"service.beta.kubernetes.io/aws-load-balancer-attributes" = "load_balancing.cross_zone.enabled=true"
		}
	}

	spec {
		type = "LoadBalancer"
		port {
			name = "https"
			port = "443"
			target_port = data.external.env.result["CONTAINER_PORT"]
			protocol = "TCP"
		}
		selector = {
			run = data.external.env.result["APP_NAME"]
		}
	}
}

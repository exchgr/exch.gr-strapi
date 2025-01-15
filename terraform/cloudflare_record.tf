resource "cloudflare_record" "admin" {
	name    = "admin"
	proxied = false
	ttl     = 1
	type    = "CNAME"
	value   = data.external.env.result["ADMIN_CNAME"]
	zone_id = data.external.env.result["CLOUDFLARE_ZONE_ID"]
}


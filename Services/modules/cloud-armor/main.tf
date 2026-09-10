# Replaces WebACL + WebACLAssociation. Structural note: AWS's WebACL
# attaches once to the ALB and covers every target group behind it; Cloud
# Armor security policies attach per-backend-service, so the load-balancer
# module attaches THIS policy's id to both the backend and frontend
# backend-services to get the same whole-LB coverage.
#
# Rule priority in Cloud Armor is evaluated LOWEST number first (opposite
# convention from the AWS WAF Priority field, which is also lowest-first -
# so priority ordering below preserves the same evaluation order as the CF
# template's Priority 0-5).
resource "google_compute_security_policy" "waf" {
  project     = var.project_id
  name        = "${var.name_prefix}-waf"
  description = "ConnectHealth WAF - replaces AWS WebACL."
  type        = "CLOUD_ARMOR"

  # Priority 0: AWSManagedRulesAmazonIpReputationList equivalent.
  #
  # OFF BY DEFAULT. evaluateThreatIntelligence() is only available with Cloud
  # Armor Managed Protection PLUS, a paid subscription tier. On the standard
  # (pay-as-you-go) tier the API rejects the whole policy with "Threat
  # Intelligence is not supported as part of the current Cloud Armor service
  # tier", so a customer without Plus cannot deploy at all if this is
  # unconditional. Every other rule below works on the standard tier.
  # Set enable_threat_intelligence = true only if the project has Plus.
  dynamic "rule" {
    for_each = var.enable_threat_intelligence ? [1] : []
    content {
      action   = "deny(403)"
      priority = 0
      match {
        expr {
          expression = "evaluateThreatIntelligence('iplist-known-malicious-ips')"
        }
      }
      description = "Block known-malicious source IPs (replaces AWSManagedRulesAmazonIpReputationList). Requires Cloud Armor Managed Protection Plus."
    }
  }

  # Priority 1: CustomBodySizeLimit equivalent (deny bodies over 5 MiB).
  # NOTE: AWS returned 413 Payload Too Large here, but Cloud Armor only
  # permits deny(403), deny(404) and deny(502) as rule actions - 413 is
  # rejected by the API outright. 403 is the closest available response; the
  # semantic difference (403 vs 413) is a documented, unavoidable delta from
  # the AWS original, not an oversight.
  rule {
    action   = "deny(403)"
    priority = 1
    match {
      expr {
        expression = "int(request.headers['content-length']) > ${var.body_size_limit_bytes}"
      }
    }
    description = "Reject oversized request bodies (replaces CustomBodySizeLimit)."
  }

  # Priority 2: RequireUserAgentExceptJWKS equivalent.
  rule {
    action   = "deny(403)"
    priority = 2
    match {
      expr {
        expression = "!has(request.headers['user-agent']) && !request.path.matches('.*/.well-known/jwks.json.*')"
      }
    }
    description = "Block requests with no User-Agent, except the JWKS well-known path (replaces RequireUserAgentExceptJWKS)."
  }

  # Priority 3: AWSManagedRulesCommonRuleSet equivalent (OWASP CRS sensors).
  rule {
    action   = "deny(403)"
    priority = 3
    match {
      expr {
        # sqli runs at sensitivity 1 while the others stay at 2, because CRS
        # 942200 ("MySQL comment-/space-obfuscated injections") inspects request
        # bodies and fires on ordinary punctuation in JSON - it blocked every
        # POST to /api/login with body_denied_by_security_policy, making login
        # impossible.
        #
        # The surgical fix would be opt_out_rule_ids, but that does NOT work
        # here: the API accepts and stores it on the CRS 3.0 '-stable' sets and
        # then ignores it - verified live, 942200 kept firing with the opt-out
        # present in the expression. Rule tuning only takes effect on the CRS
        # 3.3 sets ('sqli-v33-stable'). Switching ruleset version would swap
        # every signature at once, so sensitivity is the smaller change: 942200
        # is a sensitivity-2 rule, so level 1 excludes it by construction.
        #
        # This is not a loosening relative to the system being migrated from -
        # AWS ran AWSManagedRulesCommonRuleSet, which is roughly sensitivity-1
        # equivalent, so 2 was already stricter than the AWS baseline.
        expression = "evaluatePreconfiguredWaf('sqli-stable', {'sensitivity': 1}) || evaluatePreconfiguredWaf('xss-stable', {'sensitivity': 2}) || evaluatePreconfiguredWaf('lfi-stable', {'sensitivity': 2}) || evaluatePreconfiguredWaf('rce-stable', {'sensitivity': 2})"
      }
    }
    description = "OWASP CRS-equivalent managed protection (replaces AWSManagedRulesCommonRuleSet)."
  }

  # Priority 4: AWSManagedRulesKnownBadInputsRuleSet equivalent.
  rule {
    action   = "deny(403)"
    priority = 4
    match {
      expr {
        # protocolattack is scoped OFF the workflow API; scannerdetection stays
        # at sensitivity 2 everywhere.
        #
        # CRS 921150 ("HTTP header injection via payload") inspects request
        # bodies and fires on ordinary JSON containing newlines or colons inside
        # string values. It rejected every POST to /api/workflow/<id>/check with
        # body_denied_by_security_policy on both dev and prod. The application
        # never saw those requests, which is why the same calls worked locally
        # where no WAF sits in front - and why the symptom surfaced inside
        # Node-RED as "BadRequestError: request aborted" (ECONNABORTED): the
        # load balancer cut the connection mid-body, so body-parser saw a
        # truncated stream rather than a 403.
        #
        # Lowering sensitivity does NOT exclude 921150 - it is already a
        # sensitivity-1 signature, verified by it still firing at sensitivity 1.
        # And opt_out_rule_ids, the surgical option, is accepted but silently
        # ignored on the CRS 3.0 '-stable' rulesets (proven separately when it
        # failed to suppress 942200 on login). A path exclusion is what is left.
        #
        # The exclusion is narrow on purpose. Workflow endpoints accept
        # arbitrary user-authored JSON by design and are authenticated by
        # x-api-key, and they still get: scannerdetection here, the full
        # sqli/xss/lfi/rce set at priority 3, the body-size cap at priority 1,
        # and per-IP rate limiting at priority 5. Only protocol-attack body
        # inspection is skipped, and only for /api/workflow/.
        #
        # NOTE: Terraform does not apply changes to this expression. Three
        # separate edits to this rule have passed plan and apply with no diff
        # and no error while the live policy kept its old value. This block
        # therefore records what was applied with `gcloud compute
        # security-policies rules update 4`; it is not the mechanism that
        # applies it. Fixing that means replacing these inline rule blocks with
        # standalone google_compute_security_policy_rule resources.
        expression = "(evaluatePreconfiguredWaf('protocolattack-stable', {'sensitivity': 1}) && !request.path.matches('^/api/workflow/')) || evaluatePreconfiguredWaf('scannerdetection-stable', {'sensitivity': 2})"
      }
    }
    description = "Known-bad-input protocol/scanner protection (replaces AWSManagedRulesKnownBadInputsRuleSet)."
  }

  # Priority 5: RateLimitRule equivalent.
  rule {
    action   = "rate_based_ban"
    priority = 5
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_threshold_count
        interval_sec = 300
      }
      ban_duration_sec = 300
    }
    description = "Per-IP rate limiting (replaces RateLimitRule, Limit 2000 / 5 min / IP)."
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow (matches WebACL DefaultAction: Allow)."
  }
}

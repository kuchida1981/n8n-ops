# Security alerting (see openspec's add-security-alerting): notify by email only
# about events that call for action, not about the constant stream of probes.
# Lives in bootstrap for the same reason as the log bucket: applied by hand by
# the project owner, so CI needs no write access to monitoring.
#
# This repository is public and so are its CI logs and plan comments: nothing
# that identifies the operator may be written here as a literal. Those values
# come from sensitive variables, which also makes Terraform redact every filter
# that embeds them.

locals {
  # OS Login derives the POSIX user name from the account's email address.
  operator_os_login_user = replace(replace(var.operator_email, "/[^A-Za-z0-9]/", "_"), "/^_+/", "")

  # A service account's OS Login user name is sa_<unique id>.
  ci_os_login_user = "sa_${google_service_account.terraform_ci.unique_id}"

  # Principals that read secrets in normal operation. The project is shared
  # with vaultwarden-ops, so its VM and CI accounts are listed too.
  expected_secret_readers = [
    "n8n-vm@${var.project_id}.iam.gserviceaccount.com",
    "vaultwarden-vm@${var.project_id}.iam.gserviceaccount.com",
    google_service_account.terraform_ci.email,
    "terraform-ci@${var.project_id}.iam.gserviceaccount.com",
    var.operator_email,
  ]

  # Log-match alerts: one email per matching event, at most hourly.
  log_match_alerts = {
    unexpected_ssh_login = {
      title = "n8n: unexpected SSH login"
      # Anything sshd accepted that is not "CI or operator, arriving through
      # IAP (35.235.240.0/20)". [.] avoids escaping dots twice.
      filter = join(" AND ", [
        "log_id(\"host_journal\")",
        "labels.\"compute.googleapis.com/resource_name\"=\"n8n\"",
        "jsonPayload.SYSLOG_IDENTIFIER=~\"^sshd\"",
        "jsonPayload.MESSAGE=~\"^Accepted \"",
        "NOT jsonPayload.MESSAGE=~\"^Accepted publickey for (${local.ci_os_login_user}|${local.operator_os_login_user}) from 35[.]235[.](24[0-9]|25[0-5])[.]\"",
      ])
      action = "Check who logged in (the log entry has user and source IP). If it was not you or a deploy, treat the VM as compromised."
    }
    unexpected_secret_access = {
      title = "Secret Manager: read by an unexpected principal"
      filter = join(" AND ", [
        "log_id(\"cloudaudit.googleapis.com/data_access\")",
        "protoPayload.serviceName=\"secretmanager.googleapis.com\"",
        "protoPayload.methodName=~\"AccessSecretVersion\"",
        "NOT protoPayload.authenticationInfo.principalEmail=(${join(" OR ", [for p in local.expected_secret_readers : "\"${p}\""])})",
      ])
      action = "Check the principal and the secret in the log entry. If unknown, revoke that principal's access and rotate the secret."
    }
    # Deliberately not filtered by principal: a stolen CI credential should
    # show up too.
    firewall_or_iam_change = {
      title = "GCP: firewall rule or IAM policy changed"
      filter = join(" AND ", [
        "log_id(\"cloudaudit.googleapis.com/activity\")",
        "(protoPayload.methodName=~\"compute[.]firewalls[.](insert|patch|update|delete)\" OR protoPayload.methodName=~\"[Ss]etIamPolicy\")",
      ])
      action = "Check that the change matches something you or a Terraform apply did."
    }
  }
}

resource "google_monitoring_notification_channel" "security_email" {
  project      = var.project_id
  display_name = "Security alerts (email)"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.required]
}

resource "google_monitoring_alert_policy" "log_match" {
  for_each = toset(["unexpected_ssh_login", "unexpected_secret_access", "firewall_or_iam_change"])

  project      = var.project_id
  display_name = local.log_match_alerts[each.key].title
  combiner     = "OR"

  conditions {
    display_name = local.log_match_alerts[each.key].title

    condition_matched_log {
      filter = local.log_match_alerts[each.key].filter
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "3600s"
    }
    auto_close = "86400s"
  }

  documentation {
    content   = local.log_match_alerts[each.key].action
    mime_type = "text/markdown"
  }

  notification_channels = [google_monitoring_notification_channel.security_email.id]

  depends_on = [google_project_service.required]
}

# Login failures need counting, so a log-based metric plus a threshold.
# 429 is n8n's own rate limiting, which a fast guesser hits instead of 401.
# (?i) because n8n's routing is case-insensitive.
resource "google_logging_metric" "n8n_login_failures" {
  project = var.project_id
  name    = "n8n_login_failures"
  filter = join(" AND ", [
    "log_id(\"docker_containers\")",
    "jsonPayload.RequestMethod=\"POST\"",
    "jsonPayload.RequestPath=~\"(?i)^/rest/login/?([?]|$)\"",
    "(jsonPayload.DownstreamStatus=401 OR jsonPayload.DownstreamStatus=429)",
  ])

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }

  depends_on = [google_project_service.required]
}

resource "google_monitoring_alert_policy" "n8n_login_failures" {
  project      = var.project_id
  display_name = "n8n: repeated login failures"
  combiner     = "OR"

  conditions {
    display_name = "${var.n8n_login_failure_threshold} or more failed logins in 10 minutes"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.n8n_login_failures.name}\" AND resource.type=\"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.n8n_login_failure_threshold - 1
      duration        = "0s"

      aggregations {
        alignment_period     = "600s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = "Find the client IP: log_id(\"docker_containers\") AND jsonPayload.RequestPath=\"/rest/login\". If it is not you, block it and change the n8n password."
    mime_type = "text/markdown"
  }

  notification_channels = [google_monitoring_notification_channel.security_email.id]
}

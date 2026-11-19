## 1. 事前確認

- [x] 1.1 GCP実機の現状を確認する（`gcloud logging buckets list`、`gcloud projects get-iam-policy`の`auditConfigs`）。Terraformの読み取り結果と差がないことを確かめる
- [x] 1.2 VM上で`/var/log/syslog`の有無、`journalctl`の内容、Ops Agentの現在の設定（`/etc/google-cloud-ops-agent/config.yaml`）を確認し、design.mdのOpen Questions（rsyslogの有無）を解消する（結果: rsyslog導入済みで`/var/log/syslog`あり。Ops Agentの`config.yaml`は既定のコメントのみで上書きしても失われる設定はない。`daemon.json`は旧文字列と一致。Tailscale ACLでこの端末からはSSHできないため、利用者が実施）
- [x] 1.3 `terraform/bootstrap`のCI用SAに、監査設定・log bucket・sinkの管理に必要な最小のIAMロールを洗い出し、design.mdに追記する

## 2. Terraform: ログ基盤（プロジェクト共通）

- [x] 2.1 `logging.googleapis.com`を`google_project_service`の一覧に明示的に追加する
- [x] 2.2 `google_project_iam_audit_config`で、Secret ManagerのDATA_READを有効にする
- [x] 2.3 `security_log_retention_days`変数（既定90）を追加し、`google_logging_project_bucket_config`で`security-logs`bucketを作成する
- [x] 2.4 `google_logging_project_sink`で、Traefikのアクセスログ・journald・監査ログを`security-logs`bucketへルーティングする（`_Default`は排他しない）
- [x] 2.5 必要なIAMロールをCI用SAに追加する（1.3で確定したもの）
- [ ] 2.6 `terraform plan`で、意図した差分のみであることを確認し、PRを作成する

## 3. VM側: アクセスログとコンテナログ

- [x] 3.1 `n8n/docker-compose.yml`のTraefikに、`--accesslog=true`・`--accesslog.format=json`・ヘッダのdrop/redact設定を追加する
- [x] 3.2 `startup-script.sh.tftpl`の`daemon.json`に`log-driver`/`log-opts`（`max-size=10m`、`max-file=5`）を追加し、既存の文字列比較ロジックも更新する
- [x] 3.3 `startup-script.sh.tftpl`で、`/etc/google-cloud-ops-agent/config.yaml`を生成する（コンテナログの`files`receiver、`systemd_journald`receiver、パイプライン）。変更があったときだけOps Agentを再起動する
- [x] 3.4 コンテナ名のラベル付けの方法を決め（Open Questions）、実装する
- [ ] 3.5 アクセスログのクエリ文字列の扱い（n8nのWebhookのトークン）を決め、必要ならTraefik側で落とす（保留: Traefikの`RequestPath`にクエリが含まれるかは実ログで確認する。4.4で確認し、含まれる場合に対処する）
- [ ] 3.6 `shellcheck`と`docker compose config`で、構文を検証する

## 4. 反映と動作確認

- [ ] 4.1 Terraform（グループ2）をマージし、`terraform-apply`で適用する
- [ ] 4.2 docker-compose.ymlとstartup-scriptの変更をマージし、VMへ反映する（再起動またはscriptの再実行。`docker compose up -d --force-recreate`でコンテナを再作成する）
- [ ] 4.3 Cloud Loggingで、Traefikのアクセスログ・journald・n8nのログが検索できることを確認する
- [ ] 4.4 存在しないパスへ数回アクセスし、アクセスログに404が記録されること、`Authorization`/`Cookie`がredactされていることを確認する
- [ ] 4.5 Secret Managerのシークレットを読み取り、Data Access監査ログに主体・対象・時刻が記録されることを確認する
- [ ] 4.6 `docker inspect`で、ログのローテーション設定が新しいコンテナに適用されていることを確認する
- [ ] 4.7 1週間運用し、ログ量（無料枠の消費）を確認して、保持期間・ヘッダのdrop設定を調整する。この結果を、vaultwarden-opsへ適用するかどうかの判断材料にする

## 5. ドキュメントと連携

- [ ] 5.1 README.md/README.ja.mdに、ログの見方（Cloud Loggingのクエリ例）と保持期間を追記する
- [ ] 5.2 `openspec/specs`への反映は、archive時に行う（本タスクの対象外）
- [ ] 5.3 4.7の結果を踏まえて、vaultwarden-opsへの適用（Caddyの`log`、sinkの扱い）を別changeとして起こすか判断する（このchangeでは作成しない）

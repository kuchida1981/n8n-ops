## Why

n8nは公開環境（80/443をインターネットに開放）で動いているが、攻撃の痕跡を確認・保存・検知する仕組みが事実上ない。TraefikにはアクセスログがなくGCP側の監査ログもAdmin Activity（既定）のみで、コンテナログはDockerのjson-fileに溜まるだけ（ローテーション・保持期間・外部退避なし）。Ops Agentは入っているがメトリクス用途のみ。侵害や総当たりが起きても記録が残らず、VMが侵害されればローカルのログは改ざん・削除できる。まず「痕跡を残して後から確認できる」状態を作る。検知・通知はどう受け取るかを別途検討するため、このchangeの範囲外とする。

## What Changes

- **Traefikのアクセスログを有効化**する（`--accesslog`、JSON形式、`Authorization`/`Cookie`ヘッダはredact）。
- **Ops Agentの設定を追加**し、n8n/Traefikのコンテナログ（Docker json-file）とjournald（sshd/Tailscale SSH/sudo/unattended-upgrades等）をCloud Loggingへ転送する。VM外にログが保存されるため、VMの再作成や侵害後の削除に耐える。
- **Dockerのログローテーション**（`log-driver=json-file`、`max-size`/`max-file`）を`/etc/docker/daemon.json`に追加する。
- **Data Access監査ログを有効化**する（Secret Manager `DATA_READ`、IAP/Compute関連）。プロジェクト共通リソースのため、**このリポジトリ（n8n-ops）のみが所有**する。
- **ログの保持期間を明示**する（専用のlog bucketを作り、既定30日より長く保持）。
- Vaultwarden側（Caddyの`log`ディレクティブ等）は、**n8nでの成果を確認してから`vaultwarden-ops`に別changeとして適用する**（構成が似るため、先にn8nで実証する）。この変更では作成しない。プロジェクト共通リソースは重複定義しない。
- 範囲外: アラートポリシー・ログベースメトリクス・通知チャンネル（通知の受け取り方を別途検討するため後続の変更とする）、Cloud Armor/WAF導入、VPC Flow Logs（コストと効果の兼ね合いで今回は見送り）、外部SIEM連携、fail2ban等の自動遮断、n8n自身のワークフロー実行ログの保持期間変更。

## Capabilities

### New Capabilities
- `security-logging`: 攻撃痕跡の記録に関する要件（Traefikアクセスログ、コンテナログ/journaldのCloud Logging転送、Dockerログローテーション、Data Access監査ログ、保持期間）。

### Modified Capabilities
- `n8n-service`: Traefikがアクセスログを出力すること、およびDockerログのローテーション設定を要件として追加する。
- `gcp-infrastructure`: Data Access監査ログの有効化と、ログ保持用バケットを要件として追加する。

## Impact

- `n8n/docker-compose.yml`: Traefikのコマンドにaccesslog関連フラグを追加。
- `terraform/main/templates/startup-script.sh.tftpl`: `daemon.json`にログローテーションを追加、Ops Agentの`config.yaml`（receiver/pipeline）を配置して再起動。
- `terraform/bootstrap/main.tf`（または`terraform/main`）: `google_project_iam_audit_config`、`google_logging_project_bucket_config`、`google_logging_project_sink`を追加。`logging.googleapis.com`のAPI有効化を明示。
- CIのサービスアカウントに、監査設定・ログ設定用のIAMロール追加が必要になる可能性がある（design.mdで確定）。
- コスト: Cloud Loggingの無料枠（月50GiB）内に収まる想定。保持期間の延長分とData Access監査ログの量は実装時に確認する。
- 既存のVMは`startup-script`の変更により再作成/再起動が必要になる可能性がある（design.mdで手順を確定）。
- 別リポジトリ: `vaultwarden-ops`への適用は、n8nでの成果確認後に別changeで行う（本proposalのスコープ外）。

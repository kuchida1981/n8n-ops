## Context

n8nは公開VM（80/443をインターネットへ開放、SSHはTailscaleとIAP経由のみ）で動く。現状の記録・検知は次のとおり。

- Traefik: アクセスログなし。n8n・Traefikのコンテナログは、Dockerのjson-fileにローテーション設定なしで溜まるだけ。
- Ops Agent: 導入済みだが、メトリクス用途のみ。コンテナログは既定では収集対象外。
- GCP: Admin Activity監査ログ（既定）だけが残る。Data Access監査ログ、ファイアウォールのログ、アラートポリシーはいずれもTerraformにない。
- ログの保持: `_Default` bucketの30日のみ。
- 同じGCPプロジェクト内に`vaultwarden-ops`のVMがあり、Terraformのstateはリポジトリごとに別。

## Goals / Non-Goals

**Goals:**
- 外部からの攻撃試行（スキャン、総当たり、不正パス）をアクセスログとして残す。
- ログをVM外（Cloud Logging）に退避し、VMの再作成や侵害後の削除に耐えるようにする。
- 保持期間を明示的に定める。
- Cloud Loggingの無料枠（月50GiB）に収める。

**Non-Goals:**
- Cloud Armor/WAF、fail2banなどの自動遮断。
- VPC Flow Logs、ファイアウォールのログ。
- 外部SIEMへの連携。
- n8n自身のワークフロー実行ログ（`EXECUTION_DATA_MAX_AGE`）の変更。
- アラートポリシー・ログベースメトリクス・通知チャンネル（通知の受け取り方を別途検討するため、後続の変更で扱う）。
- vaultwarden-ops側の実装（n8nでの成果確認後に別changeで扱う）。

## Decisions

### D1: アクセスログはTraefikの`--accesslog`をJSONで標準出力に出す
- 設定: `--accesslog=true`、`--accesslog.format=json`、`--accesslog.fields.headers.defaultmode=drop`（必要なヘッダだけ`keep`し、`Authorization`/`Cookie`は`redact`）。
- 理由: 標準出力に出せば、Docker→Ops Agentの既存経路に乗る。ファイルに出すと、ローテーションやマウントの管理が増える。
- 代替案: `--accesslog.filepath`でファイルに出力する。→ 管理が増え、メリットがないので不採用。

### D2: Ops Agentのreceiverでコンテナログとjournaldを収集する
- `/etc/google-cloud-ops-agent/config.yaml`をstartup-scriptで生成する。
  - `fluent_forward`ではなく、`files`receiverで`/opt/n8n/docker-data/containers/*/*-json.log`を読む。
  - `systemd_journald`receiverでjournaldを読む（Debian 13にはrsyslogが入っていない可能性があり、`/var/log/syslog`は当てにしない）。
- 理由: Ops Agentだけで完結し、追加のエージェントやコンテナが不要。
- 代替案: Dockerの`gcplogs`ログドライバ。→ `docker compose`のログ形式が変わり、既存のコンテナの再作成が必要。`docker logs`でローカルでも読めるようにしたいので不採用。
- コンテナ名とログの対応づけは、ファイルパスのコンテナIDから、後段のprocessorで付与する。実装時に確認する（Open Questions）。

### D3: Dockerのログローテーションは`daemon.json`に統一する
- `{"data-root": "...", "log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}`。
- startup-scriptには、`daemon.json`の内容が一致するかを文字列比較する既存の仕組みがある。比較対象の文字列を更新する。
- 変更後に`systemctl restart docker`が走るため、既存コンテナは再作成が必要（`log-opts`は新規作成のコンテナにだけ適用される）。

### D4: ログは専用のlog bucketにルーティングし、保持期間を変数にする
- `google_logging_project_bucket_config`で`security-logs`を作成する。保持は`var.security_log_retention_days`（既定90日）。
- `google_logging_project_sink`で、Traefikのアクセスログ・journald・監査ログだけをこのbucketへ送る。`_Default`にも残る（排他しない）。
- 理由: 保持期間を延ばす対象を絞り、コストを抑える。
- 代替案: `_Default`の保持期間をプロジェクト全体で延長する。→ vaultwardenやその他のログも対象になり、影響が大きいので不採用。

### D5: プロジェクト共通リソースはn8n-opsが所有する
- Data Access監査ログ（`google_project_iam_audit_config`）と、log bucketは、同じプロジェクトを共有しているため、n8n-opsだけが定義する。
- vaultwarden-opsのVMのログも、同じプロジェクトのCloud Loggingに入るため、sinkのフィルタで`resource.labels.instance_id`または`labels.app`で絞る方式にして、重複定義を避ける。vaultwarden-opsへの適用はn8nでの成果確認後に別changeで行い、その際にsinkの追加が必要か、n8n-opsのsinkで足りるかを決める。

### D6: アラート・通知はこのchangeに含めない
- 通知の受け取り方（メール以外も含む）を別途検討するため、アラートポリシー・ログベースメトリクス・通知チャンネルは後続の変更に切り出す。
- このchangeは、後続のアラートがそのまま利用できる形（構造化されたアクセスログ、journald、監査ログがCloud Loggingに揃っている状態）を作るところまでを担う。


## Risks / Trade-offs

- [ログ量が無料枠を超える] → アクセスログのヘッダを`drop`にして量を抑える。実装後に1週間ほど、実際の流入量を確認する。
- [アクセスログに個人情報・秘密が残る] → `Authorization`/`Cookie`/`Set-Cookie`をredactする。クエリ文字列にトークンが入る場合がある（n8nのWebhook等）。パスのみ残すか、実装時に確認する。
- [daemon.jsonの変更でDockerが再起動し、短時間ダウンする] → 既存のデプロイ手順に合わせて、メンテナンス時間に適用する。個人用途のため許容する。
- [Ops Agentの設定ミスでログが届かない] → 適用後に、Cloud Loggingで実際にログが出ることを確認する手順をtasksに含める。
- [Data Access監査ログがログ量を増やす] → Secret ManagerのDATA_READだけに絞る。シークレット数が少ないため、増加は小さい見込み。
- [CIのSAに必要な権限が増える] → `roles/logging.configWriter`等が必要になる可能性がある。最小権限で、必要な権限だけを追加する。

## Migration Plan

1. Terraform（audit config、log bucket、sink）を適用する。VMには影響しない。
2. `docker-compose.yml`と`startup-script`を更新して、mainにマージする。
3. VMへ反映する。startup-scriptは再起動時に実行されるため、VMを再起動（またはscriptを再実行）して`daemon.json`とOps Agent設定を適用し、`docker compose up -d --force-recreate`でコンテナを再作成する。
4. Cloud Loggingでログの到達を確認する。テスト用に、存在しないパスへ数回アクセスして、アクセスログが記録されることを確認する。
5. ロールバック: `docker-compose.yml`の変更をrevertして再デプロイすれば、アクセスログは止まる。Terraformリソースは`terraform destroy -target`で個別に外せる。ログ収集の停止は、Ops Agent設定を元に戻して再起動する。

## Open Questions

- コンテナログに、コンテナ名（`traefik`/`n8n`）のラベルを付ける方法は、`files`receiverのprocessorで足りるか、`fluent_forward`が必要か。
- アクセスログのクエリ文字列を、n8nのWebhookでトークンが入る場合に備えて落とすべきか。
- 保持期間の既定値（90日）は妥当か、コストを見て調整するか。
- sinkは、n8n-opsだけで両VMのログを拾うか、vaultwarden-ops側にも定義するか（vaultwarden-opsへの適用時に決める）。

## Why

GCP上のn8n(e2-microインスタンス`n8n-debian`, us-west1-b)は手動構築されたまま1年以上運用されており、IaC管理が一切ない。VM再作成やディスク障害時に復旧手順が存在せず、設定変更の履歴も追えない。姉妹プロジェクトのvaultwarden-opsで確立したTerraform+GitHub Actionsのパターンが既に実証済みであり、これをn8nにも適用してインフラをコード化する。

## What Changes

- 新規GCP Compute Engine VM(e2-micro, us-west1, Traefik + n8n のdocker compose)をTerraformで構築する。既存の`n8n-debian`インスタンスは直接importせず、並行して新規に立ち上げる(blue/green的アプローチ)
- Dockerの`data-root`を専用Persistent Disk上に配置し、named volume(`n8n_data`/`traefik_data`)の構造を変えずにVMのライフサイクルからデータを独立させる
- 1GB swapfileの構成をstartup-scriptでidempotentに再現する(e2-microのメモリ制約下でのn8n安定稼働に必須)
- n8nイメージをリテラルタグに固定し、Dependabotによる自動バージョン更新PRの対象にする(現状の`latest`運用から変更)
- Tailscaleに専用タグ(`tag:n8n-server`)で参加させ、ACLで`tailscale ssh`アクセスを絞る
- GitHub Actions(plan on PR / apply on main、承認ゲート付き)でTerraformを継続的に適用するCI/CDパイプラインを構築する。リポジトリは公開のため、シークレットはコミットせずGitHub Actions SecretsとGCP Secret Manager経由で扱う
- `n8n-test.u-rei.com`で空のn8nを先行検証した後、旧VMを停止して本番データ(`database.sqlite`, `config`のencryptionKey, `ssh/`, `nodes/`等)をtailscale経由でコピーし、DNSを`n8n.u-rei.com`へ切り替えて旧VMを削除する、一度きりの移行手順を含む(ダウンタイムは許容)

## Capabilities

### New Capabilities
- `gcp-infrastructure`: n8n用GCE VM・ファイアウォール・専用データディスク・Secret Manager・サービスアカウントのTerraform管理
- `deployment-pipeline`: GitHub Actionsによるterraform plan/apply CI/CD(承認ゲート付き)とTerraform bootstrap(GCS state bucket・WIF）
- `tailscale-connectivity`: n8n VMのtailnet参加・タグ付け・ACLによるSSHアクセス制御
- `n8n-service`: VM上で稼働するn8n+Traefikのdocker compose構成(データ永続化・swap・バージョン管理を含む)、および旧VMからの一度きりのデータ移行手順

### Modified Capabilities
(なし。vaultwarden-opsとは別リポジトリのため既存specへの変更はない)

## Impact

- 新規GCP課金対象リソース: 静的外部IP、専用Persistent Disk(既存の20GBブートディスクに加えて)。e2-micro自体はus-west1の無料枠を維持
- 旧VM(`n8n-debian`)は移行完了後に削除される。削除までは新旧VMが並行稼働する期間がある
- 移行作業中、vaultwarden-opsが依存する`/alive`死活監視ワークフロー(このn8n上で稼働)の一時停止・再開が発生する。移行完了後、同ワークフローがencryptionKey維持により正常に復号・動作することの確認が必須
- DNS(`n8n.u-rei.com`, `n8n-test.u-rei.com`)はvaultwarden-opsの前例に倣いTerraform管理外とし、レジストラ側で手動設定する
- スコープ外: NASへの自動バックアップ(別change)、`default-allow-ssh`等ネットワーク全体のポート公開是正(別change/ロードマップ)、リバースプロキシのCaddy統一(将来検討)

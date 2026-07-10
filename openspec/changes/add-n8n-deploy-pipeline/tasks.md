## 1. Dependabotのn8nバージョン追跡を修正

- [x] 1.1 `.github/dependabot.yml`のdocker-composeエコシステムエントリに`registries:`設定を追加し、`docker.n8n.io`(type: docker-registry, url: https://docker.n8n.io)を登録する
- [x] 1.2 変更をPRとして作成・マージする(PR #15)

## 2. CI用サービスアカウントへのIAM追加(bootstrap、手動apply)

- [x] 2.1 `terraform/bootstrap/main.tf`の`terraform_ci_roles`に`roles/iap.tunnelResourceAccessor`と`roles/compute.osAdminLogin`を追加する(`/opt/n8n`配下がroot所有のためsudoが必要、`osLogin`ではなく`osAdminLogin`を採用)
- [x] 2.2 `/usr/bin/terraform`を使い、ユーザーが手動でbootstrapのplan/applyを実行する(このリポジトリの既存運用同様、bootstrapはCIではなく手動一回限りのapply)。plan通り3 to add・0 to change・0 to destroyでapply成功

## 3. VM側のIAP tunnel受け入れ設定(terraform/main、CI apply)

- [x] 3.1 `terraform/main/compute.tf`のVM metadataに`enable-oslogin = "TRUE"`を追加する
- [x] 3.2 `terraform/main/network.tf`に、IAPの専用ソースレンジ`35.235.240.0/20`からのtcp:22を`target_tags = ["n8n-server"]`へ許可する専用ファイアウォールルールを新設する(既存の広域`default-allow-ssh`レガシールールには依存しない設計であることをコメントで明記する)
- [x] 3.3 PRを作成し、`terraform-plan.yml`のplan結果を確認する(PR #15、1 to add・1 to change・0 to destroy、VM再作成なし、`tailscale_acl`に差分なしを確認)
- [x] 3.4 mainへマージし、`terraform-apply.yml`の`production` Environment承認を経てapplyする(apply成功)

## 4. n8nデプロイワークフローの新設

- [x] 4.1 `.github/workflows/n8n-deploy.yml`を新設する。トリガーは`on: push: branches: [main], paths: ["n8n/**"]`
- [x] 4.2 `environment: production`を指定し、既存のterraform-apply.ymlと同じ承認ゲートを流用する
- [x] 4.3 WIF経由でGCP認証するステップを追加する(terraform-apply.ymlと同じ`google-github-actions/auth@v2`パターン)
- [x] 4.4 `gcloud compute ssh --tunnel-through-iap`経由でVMに接続し、`cd /opt/n8n/app && git pull --ff-only && cd n8n && docker compose --env-file /opt/n8n/.env pull && docker compose --env-file /opt/n8n/.env up -d`を実行するステップを追加する。`git pull`失敗時にフォールバックせず、ジョブ全体を失敗させる(startup-scriptの`|| echo WARNING`パターンとは意図的に異なる挙動であることをコメントで明記する)
- [x] 4.5 PRを作成し、mainへマージする(PR #15)

## 5. ドキュメント更新

- [x] 5.1 README.mdに、n8nのバージョン更新フロー(Dependabot PR確認・マージ→n8n-deploy.ymlの承認→反映確認)を追記する
- [x] 5.2 README.mdのbootstrap手順に、IAP用IAM追加の手動apply手順を追記する

## 6. 動作確認

- [ ] 6.1 dependabot.yml変更後、Dependabotがn8nのバージョンPRを実際に作成することを確認する(次回の定期実行、または`gh api`でのmanual trigger相当の確認手段を検討する)
- [ ] 6.2 テスト用に軽微な変更(例: 既存タグのまま`n8n/`配下の無害な差分)をmainにマージし、n8n-deploy.ymlが起動し`production` Environmentの承認待ちで一時停止することを確認する
- [ ] 6.3 承認し、IAP tunnel経由のSSH接続・`docker compose pull/up`が成功することを確認する
- [ ] 6.4 デプロイ後もn8nの既存ワークフロー(vaultwarden死活監視含む)が正常稼働していることを確認する
- [x] 6.5 `tailscale_acl`リソースに意図しない変更(diff)が生じていないことを`terraform plan`で確認する(PR #15のterraform-plan.ymlログで確認済み、`tailscale_acl.this`はrefreshのみでdiffなし)

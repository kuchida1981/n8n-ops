## Context

`migrate-n8n-to-iac`でn8nをTerraform+GitHub Actions+Tailscaleによる管理へ移行済み。docker-compose.yml上のn8n/traefikイメージはDependabotの自動検知を前提にリテラルタグで固定しているが、探索の結果2つのギャップが判明した。

1. n8nのイメージ参照が`docker.n8n.io/n8nio/n8n:2.26.4`という独自レジストリホスト名を使っており、Dependabotのdocker-composeエコシステムがDocker Hub以外のホスト名を`dependabot.yml`の`registries:`ブロックなしには検知できないため、n8nのバージョンPRが一度も作成されていない(traefikは標準Docker Hub参照のため正常に検知・PR作成されている)。
2. 仮にPRが作成・マージされても、`terraform-apply.yml`は`terraform/main/**`のpathフィルタで発火するため`n8n/**`の変更では起動せず、VM上のstartup-scriptは起動時にしか実行されないため、本番反映の経路が存在しない。

## Goals / Non-Goals

**Goals:**
- Dependabotがn8nのバージョン更新を正しく検知し、PRを作成できるようにする
- PRマージ後、明示的な承認操作を経て本番VMへ安全に反映できるパイプラインを用意する
- 反映作業がGitHub Actions上に実行履歴として残り、可視化される
- 既存のTailscale ACL・vaultwarden-opsには一切変更を加えない

**Non-Goals:**
- リアルタイム/自動即時反映(月1回程度の更新頻度を想定しており、承認を挟まない自動反映は目指さない)
- Tailscale ACLの2リポジトリ間所有権問題の解決(Issue #12で別途追跡)
- `default-allow-ssh`レガシーファイアウォールルールの是正(既知のロードマップ項目、本changeのスコープ外)

## Decisions

### 1. dependabot.ymlにdocker.n8n.io用のregistries設定を追加する

`docker.n8n.io`は実体としてDocker Hubの`n8nio/n8n`をそのまま配信するパブリックミラーで、認証チャレンジも`auth.docker.io`(Docker Hub本体)を指す(`curl`で確認済み: `WWW-Authenticate: Bearer realm="https://auth.docker.io/token",service="registry.docker.io"`)。よって認証情報は不要で、`type: docker-registry`と`url: https://docker.n8n.io`のみを登録すれば匿名トークンフローでタグ一覧を取得できる想定。

代替案として「イメージ参照を`n8nio/n8n`(Docker Hub暗黙参照)に書き換える」ことも検討したが、`docker.n8n.io`はn8n公式ドキュメントが推奨する参照方法であり、実体が同じでも参照方法を変える理由がないため採用しない。

### 2. 新しいGitHub Environmentは作らず`production`を流用する

ユーザーの意向により、既存の`production` environment(terraform-apply.ymlが使用、required reviewers設定済み)をn8n-deploy.ymlでも共有する。インフラ変更承認とアプリバージョン反映承認を同一の環境・同一の通知経路で扱うことになるが、個人プロジェクトの運用規模では分離のメリットが薄いと判断。

### 3. VMへの接続はGCP IAP tunnel経由の`gcloud compute ssh`を使い、Tailscaleには一切触れない

Tailscale ACLは既に`tailscale_acl`という単一リソースがn8n-ops/vaultwarden-ops両方のstateから触られており(Issue #12で追跡中の既知の課題)、新しい用途のためにこのACLへさらにタグ・ルールを足すとこの問題を悪化させる。GCP側で完結するIAP tunnelであれば、n8n-opsのTerraform stateだけで完結し、Tailscale側に一切変更が要らない。IAP tunnel経由のSSHは実際の本番移行作業(migrate-n8n-to-iac Phase B)で人間が使い実績のある経路でもある。

代替案として「CIランナーをephemeral Tailscaleノードとしてtailnetに参加させ`tailscale ssh`を使う」ことも検討したが、ACLの`ssh`ルールに新しいsrc(CIノード用のtag)を追加する必要があり、Issue #12の課題を拡大させるため不採用。

### 4. IAP tunnel用に、CI用SAへのIAM追加とVM側の設定変更が必要

- **IAM**: `terraform/bootstrap/main.tf`の`terraform_ci_roles`に`roles/iap.tunnelResourceAccessor`と`roles/compute.osLogin`を追加する。bootstrapはユーザーが手動で一度だけapplyする運用のため、この変更もユーザー自身による手動apply(READMEに手順追記)とする。
- **OS Login有効化**: 現在VMのmetadataに`enable-oslogin`が設定されておらず(プロジェクトデフォルトはOS Login無効)、`roles/compute.osLogin`を付与してもVM側がOS Loginを受け付けなければSSHは成立しない。`terraform/main/compute.tf`のVM metadataに`enable-oslogin = "TRUE"`を追加する。
- **ファイアウォール**: 現在tcp:22への専用ingressルールは存在せず、`tailscale ssh`はTailscaleのWireGuardトンネル経由でGCPのVPCファイアウォールを経由しないため成立している。一方IAP tunnelはGoogleのIAPインフラを経由して実際にVPC内へtcp:22のパケットを転送するため、IAP専用のソースレンジ`35.235.240.0/20`からのtcp:22を許可する専用ファイアウォールルールを`target_tags = ["n8n-server"]`で新設する。プロジェクトに残る広域な`default-allow-ssh`レガシールールに依存しない設計とする(そのルールは将来是正される可能性がある既知の課題のため)。

### 5. デプロイ内容はVM再起動を伴わない`compose pull/up`のみ

`gcloud compute ssh`経由で`cd /opt/n8n/app && git pull --ff-only && cd n8n && docker compose --env-file /opt/n8n/.env pull && docker compose --env-file /opt/n8n/.env up -d`を実行する。VM自体のreboot/resetは行わない。`docker compose up -d`は変更のあったサービス(通常はn8nコンテナのみ)だけを再作成するため、Traefikの`acme.json`(named volume)は触れられず、実際の本番移行時に発生したACME再取得の問題を再現しない。

## Risks / Trade-offs

- [IAP tunnel確立の失敗(ネットワーク一時障害等)] → ワークフローはジョブ失敗として明示的にActions上に残り、再実行(re-run)で対応可能。無人リトライは行わない(承認を経た明示的操作という設計方針と整合)
- [`git pull --ff-only`がfast-forwardできない状態(VM上のローカルチェックアウトが何らかの理由で乱れた場合)] → 失敗時はコマンド全体が非ゼロ終了し、ジョブが失敗として可視化される。startup-scriptと異なり`|| echo WARNING`でのフォールバックは行わない(デプロイ処理は「反映されたかどうか」が明確であるべきで、黙って失敗を握りつぶすべきではないため)
- [OS Login有効化によるVMへのSSH経路の意図しない拡大] → `roles/compute.osLogin`はCI用SAにのみ付与し、他のIAM primitiveには付与しない。ファイアウォールもIAPの専用レンジのみに限定するため、実質的にIAP経由・CI用SAの認証情報を持つ主体のみがSSH可能

## Migration Plan

1. `terraform/bootstrap/main.tf`にIAM変更を加え、ユーザーが手動で`terraform apply`(bootstrap)を実行
2. `terraform/main/compute.tf`(OS Login metadata)・`terraform/main/network.tf`(IAPファイアウォール)をPR経由でmain反映、`terraform-apply.yml`経由でVMへ反映
3. `.github/dependabot.yml`・`.github/workflows/n8n-deploy.yml`をPR経由でmain反映
4. 次にDependabotがn8nのバージョンPRを作成した際に、マージ→Environment承認→実際のデプロイ、という一連の流れを実地で確認する

ロールバックは、`n8n-deploy.yml`・IAM追加・ファイアウォールルールをそれぞれ独立にrevert可能。VM上のアプリケーション状態には触れない変更のため、ロールバックによるデータ影響はない。

## Open Questions

(なし。ユーザーとの探索で主要な論点は決着済み)

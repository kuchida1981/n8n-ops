## Why

n8nイメージはDependabotによる自動検知・更新PRの仕組みを前提にリテラルタグ固定で運用しているが、実際には2つの理由でこの前提が成立していない。(1) `docker.n8n.io`という独自レジストリホスト名がDependabotのdocker-composeエコシステムに認識されておらず、n8nのバージョンPRが一度も作成されていない。(2) 仮にPRが作成・マージされても、それを本番VMへ反映する経路がリポジトリ内に存在しない。IaC移行の目的の一つであった「更新作業の可視化・再現性」を実現するため、この2つを埋める。

## What Changes

- `n8n/docker-compose.yml`のn8nイメージ参照を`docker.n8n.io/n8nio/n8n:2.26.4`から`n8nio/n8n:2.26.4`(暗黙のDocker Hub参照、実体は同一イメージ)に書き換え、Dependabotのdocker-composeエコシステムが標準のDocker Hub検知経路でバージョン更新を検知できるようにする(`docker-registry`タイプの`registries:`設定は`username`/`password`必須のためこのケースには適さないと判明したため不採用)
- `.github/workflows/n8n-deploy.yml`を新設。`main`ブランチの`n8n/**`変更をトリガーに、既存の`production` GitHub Environment(terraform-apply.ymlと共有)の承認を経て、CIランナーがGCP IAP tunnel経由でVMに接続し`git pull && docker compose pull && docker compose up -d`を実行する
- Terraform CI用サービスアカウント(bootstrap管理)に`roles/iap.tunnelResourceAccessor`と`roles/compute.osAdminLogin`を追加付与する
- VM実行時サービスアカウント側の変更は無し。Tailscale ACL(tailscale.tf)には一切変更を加えない

## Capabilities

### New Capabilities

(なし)

### Modified Capabilities

- `deployment-pipeline`: 「n8nイメージバージョンのDependabot管理」要件にレジストリ登録の前提を追加し、新たに「n8nデプロイパイプライン」要件(承認ゲート付きCI起点デプロイ)を追加する

## Impact

- 変更対象ファイル: `n8n/docker-compose.yml`(イメージ参照), `.github/dependabot.yml`, `.github/workflows/n8n-deploy.yml`(新規), `terraform/bootstrap/main.tf`(CI用SAのIAM追加)
- 影響範囲: n8n-opsリポジトリ内で完結。vaultwarden-ops・Tailscale ACL・VM実行時サービスアカウントへの変更なし
- 運用への影響: Dependabotが作成するn8nバージョンPRをマージした後、`n8n-deploy.yml`のGitHub Environment承認を行うことで初めて本番へ反映される(マージだけでは反映されない)

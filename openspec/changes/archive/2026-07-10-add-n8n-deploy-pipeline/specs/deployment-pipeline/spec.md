## MODIFIED Requirements

### Requirement: n8nイメージバージョンのDependabot管理
システムは、docker-compose.yml内のn8nイメージ参照をリテラルタグ(変数展開を用いない形)で記述しなければならない(SHALL)。これにより、Dependabotのdocker-composeエコシステムが新バージョンを検知し、自動的に更新プルリクエストを作成できる状態を維持しなければならない(SHALL)。n8nイメージ参照は、Dependabotが認証情報なしで検知できる暗黙のDocker Hub参照(レジストリホスト名を含まない形)でなければならない(SHALL)。Dependabotの`docker-registry`タイプの`registries:`設定は`username`/`password`が必須パラメータであり、認証不要な公開レジストリであってもこの要件を満たさない設定はスキーマエラーとなるため、独自レジストリホスト名(例: `docker.n8n.io`)を参照する構成は採用してはならない(SHALL NOT)。

#### Scenario: Dependabotが新バージョンのPRを作成する
- **WHEN** n8nの新しいイメージバージョンがリリースされる
- **THEN** Dependabotがdocker-compose.yml内のタグ更新を提案するプルリクエストを自動作成する

#### Scenario: イメージ参照が暗黙のDocker Hub参照である
- **WHEN** `n8n/docker-compose.yml`のn8nサービスのimage定義を確認する
- **THEN** レジストリホスト名を含まない`n8nio/n8n:<タグ>`形式であり、`.github/dependabot.yml`に`registries:`設定は存在しない

## ADDED Requirements

### Requirement: 承認ゲート付きn8nデプロイパイプライン
システムは、`n8n/**`配下のファイルが`main`ブランチにマージされた際、GitHub Actionsのワークフローを起動しなければならない(SHALL)。このワークフローは、既存の`production` GitHub Environmentによる人間の承認を経てからのみ、本番VMへの反映処理を実行しなければならない(SHALL)。承認なしに反映処理が自動実行されてはならない(SHALL NOT)。反映処理は、VM自体の再起動(reboot/reset)を伴わず、変更のあったdocker composeサービスのみを再作成する形で行われなければならない(SHALL)。

#### Scenario: n8n/配下の変更でワークフローが起動する
- **WHEN** `n8n/docker-compose.yml`を含むコミットが`main`にマージされる
- **THEN** n8nデプロイワークフローが起動し、`production` Environmentの承認待ち状態で一時停止する

#### Scenario: 承認後にVMへ反映される
- **WHEN** 承認者が待機中のデプロイジョブを承認する
- **THEN** CIランナーがVMに接続し、`git pull`・`docker compose pull`・`docker compose up -d`が実行され、変更のあったコンテナのみが再作成される

#### Scenario: VMは再起動されない
- **WHEN** デプロイジョブが実行される
- **THEN** VMインスタンス自体のreboot/resetは発生せず、Traefikの証明書データ(`acme.json`)を保持したコンテナ再作成のみが行われる

### Requirement: CI用サービスアカウントによるIAP tunnel経由のVMアクセス
システムは、Terraform CI用サービスアカウントに対し、GCP Identity-Aware Proxy(IAP) tunnel経由でVMへSSH接続するために必要な最小限のIAM権限(`roles/iap.tunnelResourceAccessor`・`roles/compute.osAdminLogin`)のみを付与しなければならない(SHALL)。この権限はTailscale ACLやVM実行時サービスアカウントには一切影響してはならない(SHALL NOT)。

#### Scenario: CI用SAがIAP tunnel経由でSSHできる
- **WHEN** GitHub ActionsのワークフローがWIF経由でCI用SAとして認証し、IAP tunnel経由でVMへSSHを試みる
- **THEN** OS Loginにより一時的なSSH鍵が自動発行され、接続に成功する

#### Scenario: Tailscale ACLが変更されない
- **WHEN** このIAM権限追加をTerraform applyする
- **THEN** `tailscale_acl`リソースの内容に変更が生じない

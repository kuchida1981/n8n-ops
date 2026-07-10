## ADDED Requirements

### Requirement: Workload Identity FederationによるキーレスGCP認証
システムは、GitHub ActionsからGCPリソースを操作する際、長期のサービスアカウントJSONキーを保管せず、Workload Identity Federationによる認証を使用しなければならない(SHALL)。

#### Scenario: SAキーなしでワークフローがGCPに認証する
- **WHEN** GitHub Actionsのワークフローが実行される
- **THEN** WIFを通じて一時的な認証情報が発行され、GCPリソースへのアクセスに成功する。リポジトリのSecretsに長期SAキーは保存されていない

### Requirement: PRでplan、mainマージ後は承認を経てapply
システムは、プルリクエスト作成時には`terraform plan`のみを実行し、`main`ブランチへのマージ後は人間による承認を経てから`terraform apply`を実行しなければならない(SHALL)。承認なしに`apply`が自動実行されてはならない(SHALL NOT)。

#### Scenario: PRではplanのみ実行される
- **WHEN** Terraformコードを変更するプルリクエストが作成される
- **THEN** `terraform plan`の結果がPR上で確認できる状態になり、`apply`は実行されない

#### Scenario: マージ後は承認待ちで停止する
- **WHEN** プルリクエストが`main`にマージされる
- **THEN** `apply`ジョブはGitHub Environmentの承認待ち状態で一時停止し、人間が承認するまで実行されない

#### Scenario: 承認後にapplyが実行される
- **WHEN** 承認者が待機中の`apply`ジョブを承認する
- **THEN** `terraform apply`が実行され、インフラの変更が反映される

### Requirement: リモートstateはGCSに保管しリポジトリにコミットしない
システムは、Terraformのstateファイルを公開リポジトリにコミットせず、GCSバケットのリモートバックエンドに保管しなければならない(SHALL NOT / SHALL)。

#### Scenario: stateファイルがgit履歴に含まれない
- **WHEN** リポジトリのgit履歴を検査する
- **THEN** `.tfstate`ファイルおよびその内容がコミットされていない

### Requirement: bootstrapリソースの手動手順化
システムは、GCS stateバケットおよびWorkload Identity Pool/Providerなど、Terraform自身が依存する前提リソースの作成手順を、READMEに手動実行可能な形で文書化しなければならない(SHALL)。

#### Scenario: 初回セットアップがREADMEの手順のみで完了する
- **WHEN** 新しい環境でこのリポジトリを使い始める
- **THEN** README記載のgcloudコマンドを順に実行することで、GitHub ActionsからTerraformを実行できる状態になる

### Requirement: n8nイメージバージョンのDependabot管理
システムは、docker-compose.yml内のn8nイメージ参照をリテラルタグ(変数展開を用いない形)で記述しなければならない(SHALL)。これにより、Dependabotのdocker-composeエコシステムが新バージョンを検知し、自動的に更新プルリクエストを作成できる状態を維持しなければならない(SHALL)。

#### Scenario: Dependabotが新バージョンのPRを作成する
- **WHEN** n8nの新しいイメージバージョンがリリースされる
- **THEN** Dependabotがdocker-compose.yml内のタグ更新を提案するプルリクエストを自動作成する

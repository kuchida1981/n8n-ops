## MODIFIED Requirements

### Requirement: リモートstateはGCSに保管しリポジトリにコミットしない
システムは、`terraform/main`と`terraform/bootstrap`の両方について、Terraformのstateファイルを公開リポジトリにコミットせず、GCSバケットのリモートバックエンドに保管しなければならない(SHALL NOT / SHALL)。`terraform/bootstrap`のstateは、`terraform/bootstrap`自身が作成するstateバケット内で、`terraform/main`のstate(prefix `n8n/main`)とは別のprefix(`bootstrap`)に分離して保管しなければならない(SHALL)。

#### Scenario: stateファイルがgit履歴に含まれない
- **WHEN** リポジトリのgit履歴を検査する
- **THEN** `.tfstate`ファイルおよびその内容がコミットされていない

#### Scenario: 別マシンからbootstrapのstateを参照しても差分が誤検知されない
- **WHEN** `terraform/bootstrap`をリモートバックエンドへ移行済みの環境に対して、これまで一度もbootstrapを実行したことのない別マシンから`terraform init`(bucket指定込み)と`terraform plan`を実行する
- **THEN** ローカルstateの不在に起因する誤った差分(既存リソースが「新規作成」として表示される等)は発生せず、実際の差分のみが表示される

### Requirement: bootstrapリソースの手動手順化
システムは、GCS stateバケットおよびWorkload Identity Pool/Providerなど、Terraform自身が依存する前提リソースの作成手順を、READMEに手動実行可能な形で文書化しなければならない(SHALL)。この手順には、既存環境(stateバケットが既に存在する環境)に対してリモートバックエンド経由で`terraform init`する手順と、真にゼロから新規GCPプロジェクトで`terraform/bootstrap`を初めて実行する場合に限り、一時的にローカルバックエンドで`apply`した後`-migrate-state`でリモートバックエンドへ移行する一度きりの手順の、両方を含まなければならない(SHALL)。

#### Scenario: 初回セットアップがREADMEの手順のみで完了する
- **WHEN** 新しい環境でこのリポジトリを使い始める
- **THEN** README記載のgcloudコマンドを順に実行することで、GitHub ActionsからTerraformを実行できる状態になる

#### Scenario: 新規プロジェクトでの初回bootstrap実行がREADMEの手順のみで完了する
- **WHEN** stateバケットがまだ存在しない、真にゼロからのGCPプロジェクトで`terraform/bootstrap`を初めて実行する
- **THEN** README記載の手順(一時的なローカルバックエンドでの`apply`→`-migrate-state`)に従うことで、`terraform init`がバケット不在エラーで失敗することなくリモートバックエンドへの移行まで完了する

#### Scenario: 既存環境での運用者交代・別マシンからの操作がREADMEの手順のみで完了する
- **WHEN** 既にリモートバックエンドへ移行済みの環境に対して、別の運用者または別マシンから`terraform/bootstrap`を操作する
- **THEN** README記載の`-backend-config`を指定した`terraform init`のみで、既存stateを正しく参照できる

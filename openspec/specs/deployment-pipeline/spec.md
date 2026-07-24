# deployment-pipeline

## Purpose

GitHub Actionsによるterraform plan/apply CI/CD(承認ゲート付き)とTerraform bootstrap(GCS state bucket・WIF)を提供する。

## Requirements

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
システムは、`terraform/main`と`terraform/bootstrap`の両方について、Terraformのstateファイルを公開リポジトリにコミットせず、GCSバケットのリモートバックエンドに保管しなければならない(SHALL NOT / SHALL)。`terraform/bootstrap`のstateは、`terraform/bootstrap`自身が作成するstateバケット内で、`terraform/main`のstate(prefix `n8n/main`)とは別のprefix(`bootstrap`)に分離して保管しなければならない(SHALL)。

#### Scenario: stateファイルがgit履歴に含まれない
- **WHEN** リポジトリのgit履歴を検査する
- **THEN** `.tfstate`ファイルおよびその内容がコミットされていない

#### Scenario: 別マシンからbootstrapのstateを参照しても差分が誤検知されない
- **WHEN** `terraform/bootstrap`をリモートバックエンドへ移行済みの環境に対して、これまで一度もbootstrapを実行したことのない別マシンから`terraform init`(bucket指定込み)と`terraform plan`を実行する
- **THEN** ローカルstateの不在に起因する誤った差分(既存リソースが「新規作成」として表示される等)は発生せず、実際の差分のみが表示される

### Requirement: bootstrapのdependabot PRに対するCI plan(applyは対象外)
システムは、`terraform/bootstrap`配下のファイルを変更するプルリクエスト(dependabotによるものを含む)に対して、CI上で`terraform plan`を実行し、その結果をPR上にコメントしなければならない(SHALL)。この実行は`terraform/main`用のCIジョブとは独立した、`terraform/bootstrap`専用のジョブ・ステップとして実装しなければならない(SHALL)。`terraform/bootstrap`向けの`terraform apply`をCIから自動実行してはならない(SHALL NOT)。`terraform/bootstrap`の変更の反映は、引き続きREADMEに記載された手動apply手順によってのみ行われなければならない(SHALL)。

#### Scenario: bootstrap向けdependabot PRでplanがコメントされる
- **WHEN** dependabotが`terraform/bootstrap`配下のprovider定義を更新するプルリクエストを作成する
- **THEN** CI上で`terraform/bootstrap`ディレクトリに対する`terraform plan`が実行され、その結果がPRにコメントされる

#### Scenario: bootstrap向けPRがmainにマージされてもapplyは実行されない
- **WHEN** `terraform/bootstrap`配下の変更を含むプルリクエストが`main`にマージされる
- **THEN** `terraform-apply.yml`は起動せず、`terraform/bootstrap`への変更はCIによって自動適用されない

#### Scenario: terraform/main向けのCIジョブに影響しない
- **WHEN** `terraform/bootstrap`専用のjob/stepを追加した後、`terraform/main`配下のみを変更するプルリクエストを作成する
- **THEN** 既存の`terraform/main`用plan結果・挙動に変化はない

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

### Requirement: n8nイメージバージョンのDependabot管理
システムは、docker-compose.yml内のn8nイメージ参照をリテラルタグ(変数展開を用いない形)で記述しなければならない(SHALL)。これにより、Dependabotのdocker-composeエコシステムが新バージョンを検知し、自動的に更新プルリクエストを作成できる状態を維持しなければならない(SHALL)。n8nイメージ参照は、Dependabotが認証情報なしで検知できる暗黙のDocker Hub参照(レジストリホスト名を含まない形)でなければならない(SHALL)。Dependabotの`docker-registry`タイプの`registries:`設定は`username`/`password`が必須パラメータであり、認証不要な公開レジストリであってもこの要件を満たさない設定はスキーマエラーとなるため、独自レジストリホスト名(例: `docker.n8n.io`)を参照する構成は採用してはならない(SHALL NOT)。

#### Scenario: Dependabotが新バージョンのPRを作成する
- **WHEN** n8nの新しいイメージバージョンがリリースされる
- **THEN** Dependabotがdocker-compose.yml内のタグ更新を提案するプルリクエストを自動作成する

#### Scenario: イメージ参照が暗黙のDocker Hub参照である
- **WHEN** `n8n/docker-compose.yml`のn8nサービスのimage定義を確認する
- **THEN** レジストリホスト名を含まない`n8nio/n8n:<タグ>`形式であり、`.github/dependabot.yml`に`registries:`設定は存在しない

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

### Requirement: 承認前のバージョン差分可視化
システムは、`n8n-deploy.yml`のワークフロー実行タイトルに、トリガーとなったコミットのメッセージをそのまま表示しなければならない(SHALL)。また、`n8n/docker-compose.yml`内で変更された`image:`行の差分を、ワークフロー実行のジョブサマリーに出力しなければならない(SHALL)。この差分表示は、変更対象がn8n・traefikいずれのイメージであるかを区別せず、同一の仕組みで機能しなければならない(SHALL)。

#### Scenario: ワークフロー実行タイトルにコミットメッセージが表示される
- **WHEN** `n8n/**`配下の変更を含むコミットが`main`にマージされ、`n8n-deploy.yml`が起動する
- **THEN** ワークフロー実行一覧および「Review pending deployments」画面のリンク先タイトルに、マージされたコミットのメッセージがそのまま表示される

#### Scenario: ジョブサマリーにimageの差分が表示される
- **WHEN** `n8n/docker-compose.yml`内の`image:`行(nがn8nイメージ・traefikイメージいずれか、または両方)が変更されたコミットで`n8n-deploy.yml`が起動する
- **THEN** ワークフロー実行のジョブサマリーに、変更前後の`image:`行の差分が表示される

#### Scenario: traefikイメージ更新でも同じ仕組みで機能する
- **WHEN** traefikイメージのみが変更されたDependabot PRが`main`にマージされ、`n8n-deploy.yml`が起動する
- **THEN** n8nイメージ更新時と同様に、実行タイトルにコミットメッセージが表示され、ジョブサマリーにtraefikの`image:`行の差分が表示される

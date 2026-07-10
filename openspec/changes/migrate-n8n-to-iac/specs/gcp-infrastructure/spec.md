## ADDED Requirements

### Requirement: us-west1リージョンの最安スペックVM
システムは、GCP Compute Engine上にus-west1リージョン、マシンタイプ`e2-micro`、Debian(安定版)のVMインスタンスをTerraformでプロビジョニングしなければならない(SHALL)。当該リージョンはGCP Compute Engine常時無料枠の対象リージョン(us-west1/us-central1/us-east1)に含まれるものでなければならない(SHALL)。Preemptible/SpotなどVMが強制停止されうる構成は使用しない。

#### Scenario: Terraformでインスタンスが作成される
- **WHEN** `terraform apply`を実行する
- **THEN** us-west1リージョンに`e2-micro`のVMインスタンスが1台作成される

### Requirement: 静的External IPの永続化
システムは、VMに静的External IPを割り当て、VMインスタンスが再作成された場合でも同一のIPアドレスを維持しなければならない(SHALL)。

#### Scenario: VM再作成後もIPが変わらない
- **WHEN** VMインスタンスがdestroy&createされる
- **THEN** 静的External IPリソースは削除されず、新しいVMに再アタッチされ、外部から見えるIPアドレスは変化しない

### Requirement: 公開ファイアウォールは80/443のみ
システムは、このVMに紐づく公開ファイアウォールルールとして、インターネットからのインバウンド接続を80番・443番ポートのみに制限しなければならない(SHALL)。このVM専用のファイアウォールルールとしてSSH(22番)を許可してはならない(SHALL NOT)。

#### Scenario: このVM向けルールが80/443のみを許可する
- **WHEN** このVMのタグに紐づくファイアウォールルール一覧を確認する
- **THEN** 許可されているポートは80と443のみであり、22番を許可するルールは含まれない

### Requirement: n8nデータ用の専用永続ディスク
システムは、n8nおよびTraefikのデータ(DockerのdataルートごとVMに配置)を保存するための、VM本体のライフサイクルから独立した永続ディスクを作成しなければならない(SHALL)。当該ディスクはTerraformの`prevent_destroy`ライフサイクル設定により誤destroyから保護されなければならない(SHALL)。

#### Scenario: VM再作成後もデータディスクが残る
- **WHEN** VMインスタンスのみがTerraformによりdestroy&createされる
- **THEN** データ用永続ディスクは削除されず、新しいVMインスタンスに再アタッチされてn8nのワークフロー・credentials・実行履歴が引き継がれる

### Requirement: 機密情報はSecret Managerで最小権限管理
システムは、Tailscale認証キーなどの機密情報をGoogle Secret Managerに保管しなければならない(SHALL)。VMに付与する実行時サービスアカウントは、自身が必要とするシークレットに対する`roles/secretmanager.secretAccessor`のみを持ち、それ以外のシークレットや書き込み権限を持ってはならない(SHALL NOT)。Terraform/CI用の管理サービスアカウントとVM実行時サービスアカウントは別々に定義しなければならない(SHALL)。

#### Scenario: VM実行時SAは割り当てられたシークレットのみ読み取れる
- **WHEN** VMの実行時サービスアカウントが自身に割り当てられたシークレットのバージョンにアクセスする
- **THEN** アクセスに成功し、平文の値が取得できる

#### Scenario: VM実行時SAは他のシークレットにアクセスできない
- **WHEN** VMの実行時サービスアカウントが自身に割り当てられていない別のシークレット(例: vaultwarden-ops側が管理するシークレット)へのアクセスを試みる
- **THEN** IAM権限不足によりアクセスが拒否される

### Requirement: OSの自動セキュリティ更新
システムは、VM上でセキュリティパッチの自動適用(unattended-upgrades相当の仕組み)を有効化しなければならない(SHALL)。

#### Scenario: セキュリティパッチが無人で適用される
- **WHEN** OSのセキュリティリポジトリに新しいパッチが公開される
- **THEN** 手動操作なしに、VM上の定期実行タイミングでそのパッチが自動的に適用される

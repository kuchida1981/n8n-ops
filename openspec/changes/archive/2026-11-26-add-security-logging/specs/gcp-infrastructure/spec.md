## ADDED Requirements

### Requirement: Data Access監査ログの有効化
システムは、Secret ManagerのDATA_READについて、プロジェクトレベルのData Access監査ログをTerraform(`google_project_iam_audit_config`)で有効にしなければならない(SHALL)。

#### Scenario: 監査設定がTerraformで管理される
- **WHEN** `terraform plan`を実行する
- **THEN** 監査設定がコード上に存在し、手動変更があれば差分として検出される

### Requirement: ログ保持用のlog bucket
システムは、セキュリティログ専用のlog bucketをTerraformで作成し、保持期間(`retention_days`)を変数で指定しなければならない(SHALL)。

#### Scenario: 専用bucketへログがルーティングされる
- **WHEN** Traefikのアクセスログまたは監査ログが出力される
- **THEN** ログは専用log bucketに保存され、設定された保持期間の間検索できる

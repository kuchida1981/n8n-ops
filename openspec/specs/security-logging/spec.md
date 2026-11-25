# security-logging Specification

## Purpose

公開環境への攻撃の痕跡を、VMの外(Cloud Logging)に保存し、後から確認できるようにする(アクセスログ・コンテナログ・journald・監査ログと、その保持期間)。検知・通知は対象外。

## Requirements

### Requirement: Traefikはアクセスログを出力する
システムは、Traefikが受けたすべてのHTTP(S)リクエストについて、クライアントIP・メソッド・パス・ステータスコード・レスポンス時間を含むアクセスログをJSON形式で標準出力へ出力しなければならない(SHALL)。`Authorization`・`Cookie`・`Set-Cookie`ヘッダの値はログに含めてはならない(SHALL NOT)。

#### Scenario: 不正なパスへのアクセスが記録される
- **WHEN** 外部クライアントが存在しないパス(例: `/.env`)へリクエストし、404が返る
- **THEN** そのクライアントIP・パス・ステータス404がTraefikのアクセスログに1行のJSONとして記録される

#### Scenario: 認証情報はログに残らない
- **WHEN** `Authorization`または`Cookie`ヘッダ付きのリクエストが処理される
- **THEN** アクセスログ上のこれらヘッダの値は`REDACTED`等に置換され、実際の値は記録されない

### Requirement: コンテナログとjournaldはCloud Loggingへ転送される
システムは、Traefik・n8nのコンテナログおよびホストのjournald(sshd・Tailscale SSH・sudo・unattended-upgrades等)を、Ops AgentによってCloud Loggingへ転送しなければならない(SHALL)。これにより、VMが再作成または侵害されてもログがVM外に残らなければならない(SHALL)。

#### Scenario: コンテナログがCloud Loggingで検索できる
- **WHEN** Traefikがアクセスログを1行出力する
- **THEN** 数分以内にCloud Loggingで当該VMのログとして検索できる

#### Scenario: VM再作成後も過去ログが参照できる
- **WHEN** VMインスタンスが再作成される
- **THEN** 再作成前に出力されたログはCloud Loggingに引き続き保持されている

### Requirement: Dockerのログはローテーションされる
システムは、Dockerのjson-fileログドライバに`max-size`と`max-file`を設定し、ログがディスクを無制限に消費しないようにしなければならない(SHALL)。

#### Scenario: ログサイズが上限で頭打ちになる
- **WHEN** コンテナが上限を超える量のログを出力する
- **THEN** 古いログファイルが破棄され、1コンテナあたりのログ総量は`max-size`×`max-file`を超えない

### Requirement: Data Access監査ログを有効化する
システムは、Secret ManagerのDATA_READについて、Data Access監査ログを有効にしなければならない(SHALL)。この設定はプロジェクト共通リソースであり、n8n-opsのTerraformのみが管理する(SHALL)。

#### Scenario: シークレット読み取りが記録される
- **WHEN** あるプリンシパルがSecret Managerのシークレットバージョンにアクセスする
- **THEN** 主体・対象シークレット・時刻を含む監査ログがCloud Loggingに記録される

### Requirement: セキュリティログの保持期間は明示的に定める
システムは、セキュリティ関連ログ(アクセスログ・journald・監査ログ)を、専用のlog bucketにルーティングし、既定の30日より長い、明示された保持期間で保存しなければならない(SHALL)。保持期間はTerraformの変数で定義されなければならない(SHALL)。

#### Scenario: 保持期間がコードで確認できる
- **WHEN** Terraformのコードとlog bucketの設定を確認する
- **THEN** 保持日数が変数として定義され、実際のbucketの`retention_days`と一致している

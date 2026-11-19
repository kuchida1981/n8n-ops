## ADDED Requirements

### Requirement: Traefikのアクセスログを有効にする
システムは、docker-compose.ymlのTraefik設定でアクセスログをJSON形式・標準出力で有効にし、認証関連ヘッダをredactしなければならない(SHALL)。ログの収集と保持はsecurity-loggingスペックに従う。

#### Scenario: composeでアクセスログが有効になる
- **WHEN** VM上で`docker compose up -d`が実行される
- **THEN** Traefikコンテナの標準出力にJSON形式のアクセスログが出力される

### Requirement: Dockerログのローテーションを設定する
システムは、startup-scriptが生成する`/etc/docker/daemon.json`に、データルート設定を保ったまま`log-driver`と`log-opts`(`max-size`/`max-file`)を含めなければならない(SHALL)。

#### Scenario: daemon.jsonにログ設定が含まれる
- **WHEN** startup-scriptが実行される
- **THEN** `daemon.json`には既存の`data-root`と`log-opts`の両方が含まれ、Dockerが正常に再起動する

# n8n-service

## Purpose

VM上で稼働するn8n+Traefikのdocker compose構成(データ永続化・swap・バージョン管理を含む)を提供する。

## Requirements

### Requirement: Docker ComposeによるTraefik+n8nのデプロイ
システムは、n8nとTraefik(リバースプロキシ/TLS終端)をDocker Composeで構成し、VM上で稼働させなければならない(SHALL)。

#### Scenario: docker composeでサービスが起動する
- **WHEN** VM上で`docker compose up -d`が実行される
- **THEN** n8nコンテナとtraefikコンテナがともに起動し、正常稼働状態になる

### Requirement: カスタムドメインでの自動TLS終端
システムは、設定されたカスタムドメイン宛のHTTPSリクエストに対し、TraefikのTLS-ALPN-01チャレンジによりLet's Encryptから自動取得した証明書でTLSを終端しなければならない(SHALL)。

#### Scenario: 有効なTLS証明書で応答する
- **WHEN** ブラウザが設定済みドメインへ`https://`でアクセスする
- **THEN** Let's Encrypt発行の有効な証明書が提示され、警告なく接続できる

### Requirement: データはVMのライフサイクルから独立して永続化
システムは、n8n・Traefikのデータ(named volume `n8n_data`/`traefik_data`)が実際に書き込まれるDockerのdataルートを、gcp-infrastructureで定義された専用永続ディスクのマウントパス上に配置しなければならない(SHALL)。docker-compose.yml/base.ymlのvolume定義自体(named volumeとしての宣言)は変更してはならない(SHALL NOT)。

#### Scenario: VM再作成後もワークフロー・credentialsが保持される
- **WHEN** VMインスタンスが再作成され、専用永続ディスクが新VMに再アタッチされる
- **THEN** Dockerのdataルートが同じマウントパスを参照し、既存のnamed volume(ワークフロー定義・credentials・encryptionKeyを含む`config`ファイル等)がそのまま読み込まれる

### Requirement: e2-microの制約に対応するswap
システムは、e2-microインスタンスの限られたメモリでn8n+Traefikが安定稼働するよう、起動時にswapfileを構成しなければならない(SHALL)。この構成はVM再起動時に再実行されても二重にswapfileを作成せず、冪等でなければならない(SHALL)。

#### Scenario: 初回起動時にswapが有効化される
- **WHEN** VMが初めて起動する
- **THEN** swapfileが作成され、`swapon`により有効化され、`/etc/fstab`に永続化のエントリが1つ追加される

#### Scenario: 再起動してもswap設定が重複しない
- **WHEN** startup-scriptが既にswapfileが存在する状態で再実行される
- **THEN** 新たなswapfileの作成や`/etc/fstab`への重複エントリ追加は行われない

### Requirement: n8nイメージはリテラルタグで固定
システムは、docker-compose.yml内のn8nイメージを`latest`ではなく、リテラルなバージョンタグで指定しなければならない(SHALL)。

#### Scenario: イメージタグがlatestではない
- **WHEN** docker-compose.yml内のn8nサービスのimage定義を確認する
- **THEN** 具体的なバージョン番号を含むタグが指定されており、`latest`ではない

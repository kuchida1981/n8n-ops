## Context

n8nは現在、GCP e2-microインスタンス`n8n-debian`(us-west1-b, Debian 12)上で手動構築されたdocker compose(Traefik + n8n、n8n公式のself-hosted quickstartに準拠)として稼働している。IaC管理は一切ない。

現状の構成(SSH調査で確認済み):
- `docker-compose.yml`/`base.yml`: Traefik(TLS-ALPN-01, `tlschallenge=true`)がn8nコンテナ(`127.0.0.1:5678`)へリバースプロキシ。データはnamed volume`n8n_data`/`traefik_data`(`external: true`)
- n8nイメージは`docker.n8n.io/n8nio/n8n`のタグ無指定(`latest`)
- `n8n_data`ボリューム内`config`ファイルに`encryptionKey`が存在(値未確認、存在のみ確認)。これを失うと保存済みcredentials(vaultwarden-opsの`/alive`死活監視ワークフローが使うDiscord Webhook等を含む)が復号不能になる
- DB(`database.sqlite`, 約245MB)はWALモードで常時更新中の本番データ
- 1GB swapfile(`dd`+`mkswap`+`/etc/fstab`)がe2-micro(メモリ1GB)でのn8n安定稼働に必須
- Tailscaleに個人アカウントとして未タグ参加済み(tailnet: 既存デバイス多数と共存)
- 静的外部IPなし(エフェメラルIP)。ファイアウォールは`http-server`/`https-server`タグで80/443が公開、22番は(タグ指定なしの)legacy `default-allow-ssh`ルールでネットワーク全体に公開されている

参照実装として、姉妹プロジェクトvaultwarden-ops(同じGCPプロジェクト`kuchida-devel`、同じユーザーが運用)がTerraform + GitHub Actions + Tailscale ACLでVaultwardenを構築済みで、本changeはそのパターンを踏襲する。

## Goals / Non-Goals

**Goals:**
- n8nインフラ(VM・ネットワーク・データディスク・Secret Manager・Tailscale ACL)をTerraformで宣言的に管理する
- GitHub Actionsによる継続的なplan/apply CI/CDパイプラインを構築する(vaultwarden-opsと同じ承認ゲート付き)
- 既存の`docker-compose.yml`/`base.yml`の構造(Traefik、named volume)を保ったまま、VMのライフサイクルからデータを独立させる
- 本番データ(ワークフロー、credentials、encryptionKey)を欠損なく新環境へ移行する
- vaultwarden-opsの死活監視ワークフローが移行後も正常動作することを保証する

**Non-Goals:**
- リバースプロキシのCaddyへの統一(Traefikを維持する。将来のロードマップ候補)
- NASへの自動バックアップ機構の構築(vaultwarden-opsの`add-nas-backup`に相当する別changeとして後日実施)
- `default-allow-ssh`等、プロジェクト全体のネットワークファイアウォール是正(既知の問題だが別スコープ)
- 既存VM(`n8n-debian`)のTerraform import(新規構築で代替する)
- ゾーン統合(vaultwardenのasia-northeast1には寄せない。e2-micro無料枠がus-west1/us-central1/us-east1限定のため)

## Decisions

### 1. 既存VMをimportせず、新規VMを並行構築する(blue/green)
**選択**: `terraform import`で既存の手動構築VMを取り込むのではなく、Terraformで全く新しいVMを立ち上げ、データ移行後に旧VMを削除する。
**理由**: 手動構築されたVMには、Terraformでは表現しきれない"歪み"(パッケージのインストール順序、設定ファイルの手動編集履歴など)が残っている可能性が高い。importで取り込むとその歪みがstateに固定化される。新規構築なら、起動スクリプトが冪等かつ完全に記述する状態だけが存在することを保証できる。
**代替案**: `terraform import` + 手動での state 補正 → 却下(調査・修正コストが高く、再現性の低い"隠れた設定"を見逃すリスクがある)。

### 2. データ移行を2フェーズに分離する
**選択**:
- Phase A: `n8n-test.u-rei.com`で「空の」n8n(データ移行なし)をIaCで立ち上げ、Terraform/startup-script/CI-CDパイプライン自体が正しく機能するか検証する。本番データには一切触れない。
- Phase B以降: 検証OK後にのみ、旧VMを停止して本番データをコピーし、DNSを`n8n.u-rei.com`へ切り替える。
**理由**: 「IaCが正しく動くか」と「本番データを安全に移せるか」という独立した2つの懸念を分離できる。Phase Aが空のn8nである間は、稼働中ワークフロー(Cron/Intervalトリガー含む)が存在しないため、旧VMとの並行稼働による二重発火(例: vaultwardenの`/alive`監視が両VMで同時に動き、Discordへ二重通知される)が原理的に発生しない。
**代替案**: 最初から本番データを持ち込んでblue/green並行稼働 → 却下(トリガー系ワークフローの二重発火を避けるための無効化・再有効化手順が別途必要になり、複雑さが増す)。

### 3. ダウンタイムを許容し、停止してからコピーする
**選択**: データ移行時は旧VMのn8nを`docker compose down`で停止してからコピーする。vaultwardenの`sqlite3 .backup`のような無停止スナップショット技法は使わない。
**理由**: ユーザーがダウンタイムを許容しており、サービス停止後のコピーはWAL破損の懸念がなく単純。将来NASバックアップchangeで無停止バックアップ機構を作る際に、この知見を再利用できる。
**代替案**: vaultwarden同様`sqlite3 .backup`でオンラインスナップショット → 今回は見送り(過剰な作り込み。停止できる前提があるなら不要)。

### 4. named volumeの構造を変えず、Dockerの`data-root`をディスクに向ける
**選択**: `docker-compose.yml`/`base.yml`はnamed volume(`n8n_data`/`traefik_data`, `external: true`)のまま変更しない。代わりに`/etc/docker/daemon.json`の`data-root`を専用Persistent Disk上のディレクトリ(例: `/opt/n8n/docker-data`)に向け、Docker自体のデータ全体をそのディスクに配置する。
**理由**: n8n公式サンプルの構成を尊重したい("大きく変えたくない")という要望と、vaultwardenの「データディスクはVMのライフサイクルと独立」という設計原則を、compose file無変更のまま両立できる。vaultwardenはbind mount(`${DATA_DIR}:/data`)方式だが、これはcompose fileの書き換えを伴うため今回は採用しない。
**代替案**:
  a. vaultwarden同様bind mountに書き換える → 却下(ユーザーの「変えたくない」希望に反する)
  b. データディスクを使わず、ブートディスクのみで運用 → 却下(VM再作成のたびにdocker volume export/importが必要になり、vaultwardenが確立した「ディスクはVMと独立」という利点を失う)

### 5. n8nイメージをリテラルタグに固定し、Dependabotの管理下に置く
**選択**: `image: docker.n8n.io/n8nio/n8n`を`image: docker.n8n.io/n8nio/n8n:<version>`のようにリテラルタグへ変更し、Dependabotのdocker-composeエコシステムで自動検知・更新PRの対象にする。
**理由**: vaultwardenの`vaultwarden/server:1.36.0`と同じ理由(「変数展開だとDependabotが解決できない」)。バージョンアップ手順自体はn8n公式ドキュメント通り`docker compose pull && down && up -d`のままで変わらないが、いつどのバージョンに上げたかがgit履歴で追跡可能になる。
**代替案**: `latest`のまま維持 → 却下(VM再作成のたびに予期しないバージョンを踏む可能性があり、IaCでバージョンを追跡できないトレードオフが大きい)。

### 6. swapfileをstartup-scriptで冪等に再現する
**選択**: vaultwardenのデータディスクmountブロック(`blkid`チェック→未フォーマットなら`mkfs`、`mountpoint`チェック→未マウントならmount、`/etc/fstab`に重複なく追記)と同様のガード付きで、swapfileの存在確認→`dd`+`mkswap`→`swapon`→`/etc/fstab`追記を行う。
**理由**: e2-micro(メモリ1GB)ではswapなしでn8n+Traefikが不安定になることが実運用で確認済み。起動スクリプトの再実行(VM再起動時など)で二重に`dd`しないよう冪等性が必須。

### 7. Tailscaleに専用タグで参加させる
**選択**: `tailscale up --advertise-tags=tag:n8n-server`で新VMを参加させ、`tailscale_acl`リソースに`tag:n8n-server`のtagOwnersとssh accessルールを追加する(vaultwardenの`tag:vaultwarden-server`と同じパターン)。
**理由**: vaultwarden-opsの`tailscale_acl`リソースは**tailnet全体のACLポリシーを単一リソースとして上書き管理**している。n8n-opsは別リポジトリ・別Terraform stateだが同じtailnetを操作するため、n8n-ops側で`tailscale_acl`を適用すると、vaultwarden-ops側が最後に適用した内容を上書きしてしまう競合が起きる。
**重要な設計上の制約**: 2つの独立したTerraformリポジトリが同じtailnetの`tailscale_acl`(ACLポリシー全体)を管理しようとすると、どちらかが後勝ちで相手の設定を消してしまう。本changeでは、n8n-ops側の`tailscale.tf`は**vaultwarden-opsが適用済みのACL内容(`tag:vaultwarden-server`のtagOwners/sshルールを含む)を読み取り、その上に`tag:n8n-server`のエントリを追加した完全なポリシーとして`jsonencode`する**(vaultwarden-ops側のACL定義をコピー・合成する)。tasks.mdに、実装時にvaultwarden-opsの`tailscale.tf`を参照してこの合成を行う手順を明記する。将来的に3つ目のサービスを追加する場合も同様の合成が必要になる点は、既知のトレードオフとしてOpen Questionsに記載する。

### 8. GitHubリポジトリは公開、シークレットはSecret Manager経由
**選択**: vaultwarden-opsと同じ構成(bootstrap用の一時的なTerraform CI SA、VM runtime用の別サービスアカウント、GitHub Actions SecretsからSecret Managerへ書き込み、VMはSecret Managerから起動時に読み取り)。
**理由**: 公開リポジトリのため、平文シークレットのコミットは論外。vaultwardenで確立済みのWorkload Identity Federationパターンをそのまま踏襲できる。

## Risks / Trade-offs

- [encryptionKey欠損によるcredentials全滅] → コピー対象に`n8n_data`ボリューム全体(`config`ファイル含む)を必ず含め、移行後にvaultwardenの`/alive`監視ワークフローが実際にDiscord通知を送れることをタスクの完了条件とする
- [Tailscale ACLの2リポジトリ間競合] → 上記Decision 7の通り、n8n-ops側の`tailscale_acl`はvaultwarden-opsの既存内容を合成したものとして書く。tasks.mdに「apply前にvaultwarden-opsの現行ACLをtailscale管理画面で確認し、差分がないか照合する」手順を含める
- [カットオーバー時のTLS証明書再発行ラグ] → `SUBDOMAIN`を`n8n-test`から`n8n`へ切り替えた直後、Let's Encryptからの新規証明書発行(TLS-ALPN-01)に数秒〜数分かかる。ダウンタイム許容前提のため許容するが、tasks.mdの動作確認手順に「証明書が有効になるまで待つ」ステップを明記する
- [旧VMのDNS切替タイミングのずれ] → DNSはTerraform管理外(手動)のため、TTLに応じて新旧VMへのアクセスが数分〜数十分混在しうる。旧VMは新VM側の動作確認が完了するまで停止のみに留め、削除は最後に行う(ロールバック余地を残す)
- [`n8n_data`のコピー漏れ] → `nodes/`(コミュニティノード)、`ssh/`(SSH認証情報)など、`database.sqlite`以外のディレクトリも含めてボリューム全体をコピーする。tasks.mdでボリューム配下の全ディレクトリを明示的にリストする

## Migration Plan

1. Terraform bootstrap(GCS state bucket, WIF Pool, CI用SA)を手動で1回apply
2. GitHub Actions Secretsを登録(vaultwarden-opsのSecrets一覧を参考に、n8n用に読み替え)
3. Tailscale ACLを、vaultwarden-opsの現行ポリシーに`tag:n8n-server`を合成した内容で用意(apply前に手動でtailscale管理画面の現行ACLと照合)
4. `terraform/main`を`domain=n8n-test.u-rei.com`でapply → 新VM起動、空のn8nで動作確認(Traefik証明書取得、tailscale ssh到達性、swap有効化、GitHub ActionsのCI/CDサイクル自体の確認)
5. DNSに`n8n-test.u-rei.com`のAレコードを手動作成し、外部からの疎通を確認
6. (検証OK後)旧VM(`n8n-debian`)で`docker compose down`
7. `n8n_data`ボリューム配下全体(`database.sqlite`, `config`, `binaryData/`, `nodes/`, `ssh/`, `storage/`等)をtailscale経由でrsync/scpし、新VMのデータディスク上へ配置
8. `terraform/main`を`domain=n8n.u-rei.com`で再apply(またはVM上で`.env`の`SUBDOMAIN`を直接書き換えてcompose再起動) → 証明書再発行を待つ
9. DNSの`n8n.u-rei.com`Aレコードを新VMの静的IPへ切り替え
10. 動作確認: n8nエディタへのアクセス、既存ワークフロー一覧の表示、vaultwardenの`/alive`監視ワークフローが正常に実行されDiscord通知が届くことを確認
11. 問題なければ旧VM(`n8n-debian`)を削除

## Open Questions

- Tailscale ACLの2リポジトリ間管理(n8n-ops/vaultwarden-ops)は今回は手動合成で対応するが、3つ目のサービスが増えた場合にスケールしない。将来的にACL管理を1つの共通リポジトリに切り出すか、`tailscale_acl`を諦めて手動ACL管理に戻すかは別途検討が必要
- 新VMの静的外部IP・VM名など、DNS切替に使う具体的な出力値の命名は実装時にvaultwarden-opsの`outputs.tf`パターンに倣って決める

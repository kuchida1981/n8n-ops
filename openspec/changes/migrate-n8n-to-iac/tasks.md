## 1. リポジトリ構成の初期化

- [x] 1.1 `terraform/bootstrap`, `terraform/main`, `n8n`, `.github/workflows` のディレクトリ構成を作成
- [x] 1.2 `.gitignore`に`*.tfstate*`, `.terraform/`等を追加し、機密情報が誤ってコミットされない状態にする

## 2. Bootstrap(手動・1回のみ)

- [x] 2.1 GCSバケット(Terraform remote state用)を`gcloud`で手動作成する手順をREADMEに記載
- [x] 2.2 GitHub Actions用のWorkload Identity Pool/Providerおよび管理用サービスアカウントを手動作成する手順をREADMEに記載
- [x] 2.3 vaultwarden-opsが既に発行済みのTailscale OAuthクライアントを再利用できるか確認し、再利用できない場合のみ新規発行手順をREADMEに記載(README「2. Tailscale OAuthクライアントの発行」に両パターンを記載。実際にどちらが使えるかの確認自体はPhase A実行時に行う)
- [x] 2.4 上記で得られた値をGitHub Actions Secretsに登録する手順をREADMEに記載

## 3. Terraform: GCPコアインフラ (`gcp-infrastructure`)

- [x] 3.1 `terraform/main`にGCSバックエンド設定を追加
- [x] 3.2 `e2-micro`のVMインスタンスをus-west1(既存VMと同じゾーン`us-west1-b`)に定義
- [x] 3.3 静的External IPリソースを定義しVMにアタッチ
- [x] 3.4 ファイアウォールルールを定義(このVM向けには公開80/443のみ、SSHは許可しない)
- [x] 3.5 n8nデータ用の専用Persistent Diskを定義し、`lifecycle { prevent_destroy = true }`を設定してVMにアタッチ
- [x] 3.6 Google Secret ManagerにTailscale authkey用のシークレットリソースを定義
- [x] 3.7 CI/Terraform用管理サービスアカウントとVM実行時サービスアカウントを分離して定義し、実行時SAには対象シークレットへの`secretAccessor`のみを付与
- [x] 3.8 起動時にunattended-upgradesを有効化するstartup-script断片を追加

## 4. Terraform: Tailscale接続 (`tailscale-connectivity`)

- [x] 4.1 `tailscale`プロバイダを設定(vaultwarden-opsと同じtailnetを操作するため、Terraform stateは別リポジトリ・別stateのまま)
- [x] 4.2 apply前に、Tailscale管理画面(https://login.tailscale.com/admin/acl/file )で現行ACLポリシーの内容(vaultwarden-opsが管理する`tag:vaultwarden-server`関連の設定)を取得する(実施メモ: 管理画面のブラウズではなく、vaultwarden-opsリポジトリの`terraform/main/tailscale.tf`を直接読み、`terraform plan`の出力で意図通りの合成結果になっていることを確認する形で代替した。実apply後、両タグとも正しくtailnetに反映されていることも確認済み。このパターンの持続的な課題(2リポジトリでのACL二重管理)はissue #12として記録し、今回は見送り)
- [x] 4.3 `tailscale_acl`リソースを、4.2で取得した既存内容に`tag:n8n-server`のtagOwners・sshルールを追加合成した完全なポリシーとして定義する(vaultwarden-opsの`terraform/main/tailscale.tf`を参照し、既存のtagOwners/acls/sshブロックを漏れなく含める)
- [x] 4.4 `tailscale_tailnet_key`でタグ付き認証キーを発行し、Secret Managerのシークレットバージョンとして書き込む
- [x] 4.5 VMのstartup-scriptにSecret Managerから認証キーを取得し`tailscale up --ssh --hostname=n8n --advertise-tags=tag:n8n-server`を無人実行する処理を追加(冪等: 既にtailnetに参加済みならスキップ)

## 5. n8nアプリケーション基盤 (`n8n-service`)

- [x] 5.1 現行の`docker-compose.yml`をリポジトリの`n8n/`ディレクトリへ移し、n8nイメージをリテラルタグ(`2.26.4`、稼働中バージョンをSSHで確認済み)に変更する。それ以外の構造(named volume `n8n_data`/`traefik_data`, Traefikのtlschallenge設定等)は変更しない。`base.yml`は現行docker-compose.ymlの元になった未使用の参考ファイル(実際には`docker compose`から参照されていない)と判断し、移設対象から除外した。PR #1でのGemini Code Assistレビュー指摘を受け、Traefikイメージも同様の理由でリテラルタグ(`v3.7.5`、稼働中バージョンをSSHで確認済み。レビューコメントが提案した`v2.11`は誤りで、実際にはv3系が稼働中だった)に固定した
- [x] 5.2 startup-scriptにDocker/Docker Composeのインストール処理を追加
- [x] 5.3 startup-scriptに、専用Persistent Diskをフォーマット・マウントし(未フォーマット/未マウント時のみ、`/etc/fstab`への重複エントリなし)、`/etc/docker/daemon.json`の`data-root`をそのマウントパス配下に向けてDockerを(必要な場合のみ)再起動する処理を追加
- [x] 5.4 startup-scriptに、swapfileの作成(`dd`+`mkswap`)・有効化(`swapon`)・`/etc/fstab`への永続化を、冪等なガード付きで追加する
- [x] 5.5 startup-scriptに、GitHubからn8nのdocker-compose.yml一式をcloneし(git pull失敗時は既存チェックアウトにフォールバック)、`SUBDOMAIN`/`DOMAIN_NAME`/`SSL_EMAIL`/`GENERIC_TIMEZONE`等を含む`.env`を生成し、`docker compose up -d`を実行する処理を追加(external volumeのため`docker volume create`の事前実行も追加)
- [x] 5.6 Terraform変数`domain`(vaultwarden-opsの`domain`変数と同様のパターン)を定義し、startup-scriptのSUBDOMAIN/DOMAIN_NAMEに渡す(デフォルト値は`n8n-test.u-rei.com`。カットオーバー時にデフォルト値を`n8n.u-rei.com`に変更するPRを出す運用)

## 6. GitHub Actions CI/CD (`deployment-pipeline`)

- [x] 6.1 WIFを使ったGCP認証ステップを含む`terraform plan`ワークフロー(PRトリガー)を作成
- [x] 6.2 PRにplan結果をコメントする処理を追加
- [x] 6.3 GitHub Environmentのprotection ruleで承認ゲート付きの`terraform apply`ワークフロー(mainマージトリガー)を作成
- [x] 6.4 Dependabotの設定を追加し、`n8n/docker-compose.yml`のn8nイメージタグを自動更新PR化する

## 7. Phase A: 空のn8nでインフラ検証(テストサブドメイン)

- [x] 7.1 `domain=n8n-test.u-rei.com`で初回`terraform apply`(承認込み)を実行し、インフラ一式を作成する(実施メモ: 初回applyは`tailscale_tailnet_key`が2回失敗した。1回目は`TAILSCALE_TAILNET` Secretの値が誤っており404、2回目は`tailscale_acl`と`tailscale_tailnet_key`の間に依存関係がなく並行実行されたことによる競合(PR #8で`depends_on`を追加して修正)、3回目はvaultwarden-opsと共用していたTailscale OAuthクライアントのAuth Keysスコープが`tag:vaultwarden-server`専用に制限されていたため`tag:n8n-server`のキー発行が拒否された(n8n専用の新規OAuthクライアントを発行して解消)。4回目のapplyで成功)
- [x] 7.2 出力された静的External IPを使い、`u-rei.com`のDNS管理画面で`n8n-test.u-rei.com`のAレコードを手動作成する
- [x] 7.3 Let's Encrypt証明書が正常に発行され、`https://n8n-test.u-rei.com`でn8nの初期セットアップ画面にアクセスできることを確認する(`curl -sv`でLet's Encrypt発行の有効な証明書とHTTP/2 200を確認)
- [x] 7.4 `tailscale ssh`でVMに接続できることを確認する(ACLの`action: check`による追加認証を含めて確認)
- [x] 7.5 `free -h`/`swapon --show`でswapが有効になっていることを確認する
- [x] 7.6 VM再起動を行い、startup-scriptの再実行で二重処理(swapfile重複作成、fstab重複エントリ等)が起きないことを確認する(`gcloud compute instances reset`で実施、いずれも重複なしを確認)
- [x] 7.7 PRを作成し、`terraform plan`がCIで実行されることを確認する(PR #1・PR #8の両方でCI上の`terraform plan`が正常動作することを確認済み)

## 8. Phase B〜E: 本番データの移行とカットオーバー

- [x] 8.1 旧VM(`n8n-debian`)で`docker compose down`を実行し、n8nを停止する
- [x] 8.2 旧VMの`n8n_data`ボリューム配下全体(`config`, `database.sqlite`, `binaryData/`, `nodes/`, `ssh/`, `storage/`等)をtailscale経由のrsync/scpで新VMへコピーする(実施メモ: VM間の直接rsyncではなく、両VMともgcloud IAPトンネル経由でこのセッションから到達可能だったため、`tar czf | ssh ... | tar xzf`のパイプでこのセッション自身を中継点として転送した)
- [x] 8.3 新VM側でコピーしたデータを正しいDocker data-root配下のnamed volumeパスに配置し、パーミッション(コンテナ実行ユーザーとの一致)を確認する(`stat -c '%u:%g'`で数値UID/GIDが旧VM側と一致(1000:1000)することを確認。`ls -la`上の表示ユーザー名が旧VMと異なって見えたのは、新VM側のOS Loginユーザーが偶然同じuid 1000を持っていたための表示上の見た目の違いで、実害はなかった)
- [x] 8.4 新VM上で`docker compose down && docker compose up -d`を実行し、コピーしたデータでn8nが起動することを確認する(この時点ではまだ`n8n-test.u-rei.com`のまま)
- [x] 8.5 n8nエディタにアクセスし、既存ワークフロー一覧・credentials一覧が正しく表示されることを確認する(encryptionKeyが正しく引き継がれている証拠)(全ワークフローが正常にActivateされ、vaultwardenの死活監視ワークフローを手動実行してDiscord通知が届くことも確認した)
- [x] 8.6 Cron/Interval/Pollトリガーを持つワークフロー(vaultwardenの`/alive`監視を含む)が意図せず二重実行されないよう、必要であれば旧VMを完全に停止済みであることを再確認する(旧VM停止→新VM起動の順で実行したため、重複稼働期間は発生しなかった)
- [x] 8.7 Terraform変数`domain`を`n8n.u-rei.com`に変更してapplyする(またはVM上で`.env`の`SUBDOMAIN`を直接書き換えて`docker compose up -d`を再実行する)(両方実施: Terraform変数を変更・apply後、VM上の`.env`も直接書き換えてcompose再起動した)
- [x] 8.8 `n8n.u-rei.com`向けの新しいTLS証明書が発行されるまで待ち、`https://n8n.u-rei.com`にアクセスできることを確認する(実施メモ: Traefikが直近の失敗(DNS未伝播時のACME検証失敗)をキャッシュしており自動再試行しなかったため、Traefikコンテナを再起動して再取得させる必要があった)
- [x] 8.9 DNSの`n8n.u-rei.com`Aレコードを新VMの静的IPへ切り替える(TTLに応じた浸透待ちを考慮する)
- [x] 8.10 vaultwardenの`/alive`監視ワークフローが正常にDiscord通知を送れることを実際に確認する(カットオーバー後の本番ドメインでも再確認済み)
- [x] 8.11 問題がないことを確認した上で、旧VM(`n8n-debian`)とそのディスクを削除する(`gcloud compute instances delete n8n-debian --zone us-west1-b`で削除。ブートディスクは`autoDelete`設定によりVM削除と同時に自動削除された)

## 9. ドキュメント

- [x] 9.1 README.mdに全体アーキテクチャ図、bootstrap手順、DNS手動設定手順、blue/greenカットオーバー手順、ロードマップ(NASバックアップ・Caddy統一・SSH公開是正)を記載

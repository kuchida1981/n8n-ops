## Why

`add-security-logging`で攻撃の痕跡は残るようになったが、誰かがログを見に行かない限り気づけない。探索や総当たりは週に数千件あり、全部を通知しても読まれないため、「行動が必要な事象」だけを通知する。

## What Changes

- Cloud MonitoringのアラートポリシーをTerraformで追加し、**メール**で通知する。対象は次の4つ。
  1. CIと運用者以外（またはIAP以外の経路）のSSHログイン成功（n8n VMの`sshd`）
  2. 想定外の主体によるSecret Managerのシークレット読み取り
  3. ファイアウォールルールとIAMポリシーの変更
  4. n8nのログイン失敗（`POST /rest/login`の401）の連続
- 通知先のメールアドレスと許可する主体は、公開リポジトリとCIの公開ログに出ないように、sensitiveな変数で渡す。
- READMEに、アラートの一覧と受け取ったときの確認手順を追記し、**Discordへの通知をロードマップに載せる**。
- 範囲外: Discordへの通知（メールは気づきにくいので、後続の変更で扱う）、Vaultwarden固有のアラート（n8nで実績を作ってから）、Webの探索・総当たりの通知、ログ欠落（エージェント停止）の検知、ワークフロー失敗やディスク残量などの運用監視、自動遮断、**Tailscale SSH経由のログインの検知**（`tailscale ssh`は一度も成功した実績がなく、成功時の記録の形式が分からないため、今後検討する）。

## Capabilities

### New Capabilities
- `security-alerting`: 検知する事象、通知先、通知の抑制、機密の扱い。

### Modified Capabilities
（なし）

## Impact

- `terraform/bootstrap`: 通知チャンネル、ログベースメトリクス、アラートポリシー、`monitoring.googleapis.com`の有効化、CIの読み取り用ロール。
- `.github/workflows/terraform-plan.yml`: bootstrapのplanに変数を渡す（GitHub Secretsの追加が必要）。
- 2と3はプロジェクト全体の監査ログを見るため、同じプロジェクトのvaultwardenに関する事象も通知される。
- 料金: アラートポリシーの課金（参照するメトリクス1件につき月0.35ドル）は、2027-09-01より前には始まらない予定という情報がある（2026-11-26に検索、公式ページは未確認）。4ポリシーなら課金開始後も月2ドル未満の見込み。

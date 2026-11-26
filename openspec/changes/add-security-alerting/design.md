## Context

2026-11-26に確認した基準値。

| 事象 | 実績 |
|---|---|
| シークレット読み取り（14日） | `vaultwarden-vm` 8、`terraform-ci-n8n` 6、`terraform-ci` 5、運用者 1 |
| `SetIamPolicy`（30日、各サービス合計） | 約18 |
| ファイアウォール変更（30日） | 2 |
| n8nの`POST /rest/login`（7日） | 0 |
| n8nの`sshd`の`Accepted`・`tailscaled`のSSH記録（7日） | 7・2 |

- 通知の日常の経路はDiscordとみられるが、今回はメールにする。
- CI用のサービスアカウントは、監視リソースの書き込み権限を持たない。
- リポジトリと、Actionsのログは公開されている。

## Goals / Non-Goals

**Goals:** 侵入や設定変更の兆しを、VMの外で検知して通知する。通知が読まれ続ける量に抑える。
**Non-Goals:** proposalの「範囲外」のとおり。

## Decisions

### D1: 検知はCloud Monitoringで行う
n8nのワークフローでログを読む案は、監視対象が自分を監視することになり、n8nにログの読み取り権限を持たせるため不採用。

### D2: Terraformは`terraform/bootstrap`に置く
CI用のSAに監視の書き込み権限を足さず、手元のapplyで管理する（`add-security-logging`と同じ判断）。planのrefresh用に`roles/monitoring.viewer`だけをreadonlyロールに足す。

### D3: ポリシーの方式
- 1〜3はログ一致条件（`condition_matched_log`）。1件でも起きたら知らせる。`notification_rate_limit`は必須で、初期値は1時間。
- 4は回数で判定するため、ログベースメトリクスと閾値条件にする。初期値は10分間に5回以上。n8n自身のrate limitによる429も数える。閾値条件には`notification_rate_limit`を指定できないが、通知はインシデントの発生ごとになる。

### D4: 許可する主体は変数で持つ
- シークレット読み取り: `n8n-vm`、`vaultwarden-vm`、`terraform-ci-n8n`、`terraform-ci`、運用者。
- SSH: CIのOS Loginユーザーと運用者のOS Loginユーザーで、送信元がIAP（`35.235.240.0/20`）のものだけを除外する。
- 通知先と運用者のメールアドレスは`sensitive = true`の変数にし、値はコードに書かない。planの出力が公開ログとPRコメントに出るためである。運用者のOS Loginのユーザー名はメールアドレスから、CIのユーザー名はサービスアカウントの`unique_id`から導出する。

### D5: ファイアウォールとIAMの変更は、主体で除外しない
CIの認証情報が悪用される場合も知りたいため、自分やCIの操作も通知する。1か月の観察で多すぎれば絞る。

### D6: 通知はメールのみ
Cloud Monitoringのwebhookは、Discordの形式と合わないので中継が必要になる。中継は後続の変更で、n8nに依存しない方式を含めて検討する。

## Risks / Trade-offs

- [Tailscale SSHのログインは検知できない] → 今回は受け入れる。VMは`tailscale up --ssh`で受け付けており、ログインは`sshd`の記録に出ない。tailnetのACLが許可する相手に限られる。`tailscale ssh`を使えるようにするか、無効にするかとあわせて今後検討する。
- [メールに気づかない] → 受け入れる。Discordをロードマップに残す。
- [自分の操作で通知が来る] → 期待する通知として扱い、rate limitで抑える。
- [公開ログに通知先や主体が出る] → sensitive変数とGitHub Secrets。PRのplanのログを、値を表示せずに検索して確認する。
- [条件の書き間違いで、鳴らないことに気づけない] → 各ポリシーを実際に発火させて確認する。
- [ログが止まると検知できない] → 今回は範囲外と明記する。

- [ポリシーの更新はすぐには効かない] → 更新の約5分後のSSHログインでは通知されず、後の再試行で通知された（同時に更新したシークレットのポリシーは約6分後の事象で通知）。フィルタを変えて試すときは、10分以上待つ。

## Migration Plan

bootstrapを手元でapplyする。VMへの影響はない。戻す場合は、追加したリソースを削除してapplyする。

## Open Questions

- Cloud Run等、別の用途のリソースの操作で、`SetIamPolicy`の通知が増えないか。

## Context

2026-11-26に読み取り専用で確認した状態。

| ルール | 送信元 | ポート | ターゲットタグ |
|---|---|---|---|
| `default-allow-ssh` | 0.0.0.0/0 | 22 | **なし（全VM）** |
| `n8n-allow-iap-ssh` | 35.235.240.0/20 | 22 | n8n-server |
| `vaultwarden-allow-iap-ssh` | 35.235.240.0/20 | 22 | vaultwarden-server |
| `default-allow-internal` | 10.128.0.0/9 | 全 | なし |

- n8nの直近30日の成功ログイン: CI（IAP）、運用者（IAP: 11-17、公開IP直接: 11-19）。
- vaultwarden: sshdの認証ログがCloud Loggingに見当たらず、**誰がどの経路で接続しているかは不明**。Debianのrsyslogが`auth,authpriv`を`/var/log/syslog`に出さないためと推測（未確認）。
- 開発端末からの`tailscale ssh`は`tailnet policy does not permit you to SSH to this node`で拒否された。tailnetのACLは`u-rei-infra`が所有する。

## Goals / Non-Goals

**Goals:**
- インターネットから両VMの22番に到達できないようにする。
- 運用者が締め出されないこと。CIのデプロイが壊れないこと。

**Non-Goals:**
- 他の`default-*`ルールの整理、Tailscale ACLの変更、vaultwardenのログ収集（別change）。

## Decisions

### D1: 削除の前に無効化する
`gcloud compute firewall-rules update default-allow-ssh --disabled`は、`--no-disabled`ですぐ戻せる。削除すると、同じ設定で作り直す必要がある。1週間問題がなければ削除する。

### D2: 代替経路の確認を、無効化の前提条件にする
IAP tunnel（`gcloud compute ssh <vm> --zone us-west1-b --tunnel-through-iap`）を、両VMで運用者本人が実行して確認する。IAP経由もVMの22番を使うが、許可しているのはタグ指定のIAPルールなので、`default-allow-ssh`に依存しない。ただし現在は`default-allow-ssh`も同じ通信を許可しているため、事前確認はOS Login・IAM権限の確認にはなるが、**ファイアウォールの確認にはならない**。無効化の直後に、もう一度確認する。

### D3: `tailscale ssh`は必須にしない
正規経路はtailnetだが、開発端末からは拒否される。ACLの修正は別リポジトリの作業になるため、IAPが使えれば無効化に進む。tailnet経由の状況は確認して記録する。

### D4: Terraformに取り込まない
削除が目的のルールを、import してから消すのは手間に見合わない。このルールはGCPがプロジェクト作成時に作る既定ルールで、削除後に自動で復活しない。

## Risks / Trade-offs

- [運用者が両VMに入れなくなる] → 無効化の前後でIAP接続を確認する。戻し手順は`--no-disabled`の1コマンドで、VMへのアクセスを必要としない。
- [未知の利用者がこの経路を使っている（特にvaultwardenはログがない）] → 無効化後に1週間観察してから削除する。失敗する自動処理があれば、その時点で戻せる。
- [IAPそのものの障害や権限の問題] → GCPコンソールから`--no-disabled`で一時的に戻せる。
- [確立済みのSSHセッションは切れない] → ファイアウォールはステートフルなので、確認は必ず**新しい接続**で行う。
- [IAPのSSHログはsshd上の送信元が35.235.x になり、接続元の実IPがVM側に残らない] → 許容する。必要ならIAPの監査ログ有効化を別changeで検討する。

## Migration Plan

1. 事前確認（IAP接続、CIの経路、利用者の洗い出し）。
2. 無効化。
3. 直後の確認（公開IPの22番がタイムアウトする、IAPで新規接続できる、80/443が応答する）。
4. CIのデプロイ経路の確認（次のデプロイ、または承認ゲート付きワークフローの実行）。
5. 1週間の観察後、削除する。

ロールバック: `gcloud compute firewall-rules update default-allow-ssh --no-disabled`（削除後は`gcloud compute firewall-rules create default-allow-ssh --network=default --allow=tcp:22 --source-ranges=0.0.0.0/0 --priority=65534`）。

## Open Questions

- 運用者がvaultwardenに普段どの経路で接続しているか。
- 開発端末の`tailscale ssh`拒否を、ACL側で直すか（`u-rei-infra`の別作業）。
- `default-allow-rdp`も同じ機会に無効化するか。

## 1. 事前確認（すべて完了するまで無効化しない）

- [x] 1.1 運用者が `gcloud compute ssh n8n --zone us-west1-b --tunnel-through-iap` で新規接続でき、`sudo -n true`が通ることを確認する（2026-11-26 OK）
- [x] 1.2 運用者が `gcloud compute ssh vaultwarden --zone us-west1-b --tunnel-through-iap` で新規接続でき、`sudo -n true`が通ることを確認する（2026-11-26 OK）
- [ ] 1.3 `tailscale ssh`が使える端末があるかを確認し、結果を記録する（使えなくても先へ進む。design.md D3）
- [x] 1.4 公開IPの22番に直接つないでいる人・自動処理（手元のssh config、n8nのSSHノード、他のリポジトリのスクリプト）がないかを運用者に確認する（2026-11-26、運用者の回答: 22番/SSHを使う自動処理はないはず。両リポジトリの全ワークフローのSSHは`--tunnel-through-iap`を使うことを確認）
- [ ] 1.5 インスタンス一覧とファイアウォールルールを再取得し、design.mdの表から変わっていないことを確認する

## 2. 無効化

- [ ] 2.1 運用者の明示的な承認を得て `gcloud compute firewall-rules update default-allow-ssh --disabled` を実行する
- [ ] 2.2 両VMの公開IPの22番がタイムアウトすることを確認する
- [ ] 2.3 両VMにIAP経由で**新規**接続できることを確認する。できなければ `--no-disabled` で戻す
- [ ] 2.4 n8nとvaultwardenの443が応答することを確認する
- [ ] 2.5 CIのデプロイ経路（IAP）が動くことを、次のワークフロー実行で確認する

## 3. ドキュメント

- [ ] 3.1 README.md/README.ja.mdのSSH経路の記述と、アーキテクチャ図の注記、ロードマップを更新する（IAPの接続コマンドを含める）
- [ ] 3.2 `terraform/main/network.tf`のlegacyルールに関するコメントを更新する
- [ ] 3.3 `openspec/specs/tailscale-connectivity/spec.md`の「別途存在しており」の注記を更新する
- [ ] 3.4 `vaultwarden-ops`のREADMEが実態と合うことを確認し、必要ならIAPの接続方法を追記する

## 4. 観察と削除

- [ ] 4.1 無効化から1週間、締め出しや失敗する処理がないことを確認する
- [ ] 4.2 運用者の承認を得て `gcloud compute firewall-rules delete default-allow-ssh` を実行する
- [ ] 4.3 SSHの`Invalid user`がn8nのログに出なくなったことを確認する

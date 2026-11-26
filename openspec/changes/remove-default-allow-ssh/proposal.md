## Why

GCPプロジェクトに残る`default-allow-ssh`（tcp:22を`0.0.0.0/0`に開放、ターゲットタグなし）により、n8nとvaultwardenの両VMのSSHがインターネットに公開されている。n8nでは7日間で`Invalid user`が3,268件（送信元199 IP）あった（2026-11-26観察）。成功した不審ログインはないが、公開しておく理由がない。両リポジトリのドキュメントは「SSHはtailnet経由（CIはIAP経由）」としており、実態と食い違っている。

## What Changes

- `default-allow-ssh`を、**まず無効化**（`--disabled`、即時に戻せる）し、1週間の観察後に**削除**する。
- 無効化の前に、両VMについて代替経路（IAP tunnel、可能なら`tailscale ssh`）で実際に接続できることを確認する。**確認できるまで無効化しない。**
- このルールはどのリポジトリのTerraformでも管理していないため、`gcloud`で手動操作し、手順と結果をこのchangeに記録する。
- README/specの「legacyルールは未是正」という記述を更新する。
- **BREAKING**: 公開IPの22番への直接SSH（`--tunnel-through-iap`なしの`gcloud compute ssh`を含む）は使えなくなる。2026-11-19に、運用者がこの経路でn8nへログインした実績がある。
- 範囲外: `default-allow-rdp`（3389、Linux VMのみで待受なしの想定）、`default-allow-http`/`https`/`icmp`/`internal`の整理、Tailscale ACLの変更（`u-rei-infra`が所有）。

## Capabilities

### New Capabilities
（なし）

### Modified Capabilities
- `gcp-infrastructure`: このVMに届くルール全体（タグなしのルールを含む）で、インターネットからの22番を許可しないことを要件として追加する。

## Impact

- 影響するVM: n8n、vaultwarden（同一プロジェクトの`default`ネットワーク）。2026-11-26時点のインスタンスはこの2台のみ。
- CIのデプロイ: `n8n-deploy.yml`/`terraform-apply.yml`/vaultwarden側の同ワークフローは`--tunnel-through-iap`を使い、タグ指定の`*-allow-iap-ssh`ルールで許可されているため、影響しない想定。
- 運用者のSSH: IAP tunnelまたは`tailscale ssh`に切り替える。
- VM間のSSHは`default-allow-internal`が引き続き許可する。
- 変更するファイル: `README.md`、`README.ja.md`、`terraform/main/network.tf`のコメント、`openspec/specs/tailscale-connectivity`の注記。Terraformリソースの変更はない。

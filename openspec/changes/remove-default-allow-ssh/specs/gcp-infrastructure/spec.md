## ADDED Requirements

### Requirement: インターネットからのSSHはどのルールでも許可しない
システムは、ターゲットタグの有無にかかわらず、このVMに適用されるすべてのファイアウォールルールにおいて、`0.0.0.0/0`からの22番を許可してはならない(SHALL NOT)。管理アクセスは、tailnet経由またはIAPの送信元範囲(`35.235.240.0/20`)からに限らなければならない(SHALL)。

#### Scenario: 公開IPの22番に到達できない
- **WHEN** インターネット上の端末からVMの静的External IPの22番へ接続する
- **THEN** 接続は確立せず、タイムアウトする

#### Scenario: IAP経由のSSHは成功する
- **WHEN** 権限を持つ主体が`gcloud compute ssh --tunnel-through-iap`で接続する
- **THEN** 新規の接続が確立できる

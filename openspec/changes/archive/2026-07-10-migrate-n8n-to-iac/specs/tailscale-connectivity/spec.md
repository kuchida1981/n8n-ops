## ADDED Requirements

### Requirement: VMの無人tailnet参加
システムは、VM起動時にstartup-scriptが自動的にTailscaleクライアントをインストールし、Secret Managerから取得した認証キーを用いて手動承認なしにtailnetへ参加しなければならない(SHALL)。

#### Scenario: 起動したVMが自動的にtailnetへ現れる
- **WHEN** VMインスタンスが起動する
- **THEN** 人手を介さずに`tailscale up`が実行され、当該VMがTailscale管理画面上でtailnetの一員として`tag:n8n-server`付きで認識される

### Requirement: ACL・認証キーのTerraform管理、既存タグの保持
システムは、Tailscaleの公式Terraformプロバイダを用いて、tailnetの認証キー発行とACLポリシー(タグ`tag:n8n-server`に対する権限設定を含む)をコードとして管理しなければならない(SHALL)。このtailnetは他リポジトリ(vaultwarden-ops)によっても`tailscale_acl`リソースで管理されているため、n8n-ops側がACLポリシー全体を適用する際は、vaultwarden-ops側が管理する既存のタグ・ACLエントリ(`tag:vaultwarden-server`関連)を消失させてはならない(SHALL NOT)。

#### Scenario: Terraform applyでタグ付き認証キーが発行される
- **WHEN** `terraform apply`を実行する
- **THEN** `tag:n8n-server`が付与された認証キーが発行され、Secret Managerに書き込まれる

#### Scenario: 他リポジトリが管理するACLエントリが保持される
- **WHEN** n8n-opsリポジトリで`terraform apply`を実行し、tailnetのACLポリシーが更新される
- **THEN** 更新後のACLポリシーにも`tag:vaultwarden-server`のtagOwners・SSHルールが引き続き含まれている

### Requirement: SSHアクセスはtailnet経由を正規経路とする
システムは、VMへの正規のSSHアクセス手段として`tailscale ssh`を提供しなければならない(SHALL)。このVM自身に紐づく公開ファイアウォールルールとして、SSH(22番)を許可するルールを追加してはならない(SHALL NOT)。

#### Scenario: tailnet経由のSSHは成功する
- **WHEN** tailnetに参加済みの承認された端末から`tailscale ssh`でVMに接続する
- **THEN** 接続が確立できる

#### Scenario: このVM向けファイアウォールルールにはSSHが含まれない
- **WHEN** このVMのタグに紐づくファイアウォールルール一覧を確認する
- **THEN** 22番ポートを許可するルールは含まれない

**Note**: GCPプロジェクトにはタグ非依存でネットワーク全体に22番を公開しているレガシーなファイアウォールルール(`default-allow-ssh`)が別途存在しており、これは本capabilityの管理対象外(別changeでの是正を検討)。そのため実際のインターネット到達性は、このcapabilityの要件だけでは保証されない。

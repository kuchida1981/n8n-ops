# tailscale-connectivity

## Purpose

n8n VMのtailnet参加・タグ付け・ACLによるSSHアクセス制御を提供する。

## Requirements

### Requirement: VMの無人tailnet参加
システムは、VM起動時にstartup-scriptが自動的にTailscaleクライアントをインストールし、Secret Managerから取得した認証キーを用いて手動承認なしにtailnetへ参加しなければならない(SHALL)。

#### Scenario: 起動したVMが自動的にtailnetへ現れる
- **WHEN** VMインスタンスが起動する
- **THEN** 人手を介さずに`tailscale up`が実行され、当該VMがTailscale管理画面上でtailnetの一員として`tag:n8n-server`付きで認識される

### Requirement: 認証キーのTerraform管理、ACLポリシーは他リポジトリが唯一のオーナー
システムは、Tailscaleの公式Terraformプロバイダを用いて、`tag:n8n-server`が付与されたtailnet認証キーの発行をコードとして管理しなければならない(SHALL)。ACLポリシー(`tailscale_acl`リソース)はTailscale APIの仕様上ファイル全体を単一リソースとして上書き管理するしかなく、複数リポジトリが同時に所有すると後から適用した側が他方の設定を消失させる競合が生じるため、n8n-opsリポジトリはACLポリシーそのものを管理してはならない(SHALL NOT)。ACLポリシー(`tag:n8n-server`のtagOwners・SSHルールを含む)は姉妹リポジトリvaultwarden-opsの`terraform/main/tailscale.tf`が唯一のオーナーとして管理する。

#### Scenario: Terraform applyでタグ付き認証キーが発行される
- **WHEN** `terraform apply`を実行する
- **THEN** `tag:n8n-server`が付与された認証キーが発行され、Secret Managerに書き込まれる

#### Scenario: このリポジトリはACLポリシーを変更しない
- **WHEN** n8n-opsリポジトリで`terraform apply`を実行する
- **THEN** tailnetのACLポリシー(`tailscale_acl`)には一切変更が生じない(このリポジトリはそのリソースを持たない)

#### Scenario: vaultwarden-ops側でtag:n8n-serverが未定義だと認証キー発行が失敗する
- **WHEN** vaultwarden-ops側のACLポリシーから`tag:n8n-server`のtagOwnersエントリが欠落した状態で`terraform apply`を実行する
- **THEN** 認証キー発行がTailscale APIの400エラー(タグ未許可)で失敗し、ACLの不整合が可視化される

### Requirement: SSHアクセスはtailnet経由を正規経路とする
システムは、VMへの正規のSSHアクセス手段として`tailscale ssh`を提供しなければならない(SHALL)。このVM自身に紐づく公開ファイアウォールルールとして、SSH(22番)を許可するルールを追加してはならない(SHALL NOT)。

#### Scenario: tailnet経由のSSHは成功する
- **WHEN** tailnetに参加済みの承認された端末から`tailscale ssh`でVMに接続する
- **THEN** 接続が確立できる

#### Scenario: このVM向けファイアウォールルールにはSSHが含まれない
- **WHEN** このVMのタグに紐づくファイアウォールルール一覧を確認する
- **THEN** 22番ポートを許可するルールは含まれない

**Note**: GCPプロジェクトにはタグ非依存でネットワーク全体に22番を公開しているレガシーなファイアウォールルール(`default-allow-ssh`)が別途存在しており、これは本capabilityの管理対象外(別changeでの是正を検討)。そのため実際のインターネット到達性は、このcapabilityの要件だけでは保証されない。

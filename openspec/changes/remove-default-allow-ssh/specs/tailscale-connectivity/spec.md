## MODIFIED Requirements

### Requirement: SSHアクセスはtailnet経由を正規経路とする
システムは、VMへの正規のSSHアクセス手段として`tailscale ssh`を提供しなければならない(SHALL)。代替経路およびCIの経路として、IAP tunnel経由のSSHを許可してもよい(MAY)。インターネット全体(`0.0.0.0/0`)からのSSH(22番)を許可するファイアウォールルールを追加してはならない(SHALL NOT)。

#### Scenario: tailnet経由のSSHは成功する
- **WHEN** tailnetに参加済みの承認された端末から`tailscale ssh`でVMに接続する
- **THEN** 接続が確立できる

#### Scenario: このVM向けファイアウォールルールにはSSHが含まれない
- **WHEN** このVMに適用されるファイアウォールルール一覧を確認する
- **THEN** 22番を許可するルールの送信元に`0.0.0.0/0`は含まれず、このVMのタグ向けのルールはIAPの送信元範囲のみを許可する

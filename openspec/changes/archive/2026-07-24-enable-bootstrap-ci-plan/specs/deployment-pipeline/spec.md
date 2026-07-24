## ADDED Requirements

### Requirement: bootstrapのdependabot PRに対するCI plan(applyは対象外)
システムは、`terraform/bootstrap`配下のファイルを変更するプルリクエスト(dependabotによるものを含む)に対して、CI上で`terraform plan`を実行し、その結果をPR上にコメントしなければならない(SHALL)。この実行は`terraform/main`用のCIジョブとは独立した、`terraform/bootstrap`専用のジョブ・ステップとして実装しなければならない(SHALL)。`terraform/bootstrap`向けの`terraform apply`をCIから自動実行してはならない(SHALL NOT)。`terraform/bootstrap`の変更の反映は、引き続きREADMEに記載された手動apply手順によってのみ行われなければならない(SHALL)。

#### Scenario: bootstrap向けdependabot PRでplanがコメントされる
- **WHEN** dependabotが`terraform/bootstrap`配下のprovider定義を更新するプルリクエストを作成する
- **THEN** CI上で`terraform/bootstrap`ディレクトリに対する`terraform plan`が実行され、その結果がPRにコメントされる

#### Scenario: bootstrap向けPRがmainにマージされてもapplyは実行されない
- **WHEN** `terraform/bootstrap`配下の変更を含むプルリクエストが`main`にマージされる
- **THEN** `terraform-apply.yml`は起動せず、`terraform/bootstrap`への変更はCIによって自動適用されない

#### Scenario: terraform/main向けのCIジョブに影響しない
- **WHEN** `terraform/bootstrap`専用のjob/stepを追加した後、`terraform/main`配下のみを変更するプルリクエストを作成する
- **THEN** 既存の`terraform/main`用plan結果・挙動に変化はない

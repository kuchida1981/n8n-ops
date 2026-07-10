## ADDED Requirements

### Requirement: 承認前のバージョン差分可視化
システムは、`n8n-deploy.yml`のワークフロー実行タイトルに、トリガーとなったコミットのメッセージをそのまま表示しなければならない(SHALL)。また、`n8n/docker-compose.yml`内で変更された`image:`行の差分を、ワークフロー実行のジョブサマリーに出力しなければならない(SHALL)。この差分表示は、変更対象がn8n・traefikいずれのイメージであるかを区別せず、同一の仕組みで機能しなければならない(SHALL)。

#### Scenario: ワークフロー実行タイトルにコミットメッセージが表示される
- **WHEN** `n8n/**`配下の変更を含むコミットが`main`にマージされ、`n8n-deploy.yml`が起動する
- **THEN** ワークフロー実行一覧および「Review pending deployments」画面のリンク先タイトルに、マージされたコミットのメッセージがそのまま表示される

#### Scenario: ジョブサマリーにimageの差分が表示される
- **WHEN** `n8n/docker-compose.yml`内の`image:`行(nがn8nイメージ・traefikイメージいずれか、または両方)が変更されたコミットで`n8n-deploy.yml`が起動する
- **THEN** ワークフロー実行のジョブサマリーに、変更前後の`image:`行の差分が表示される

#### Scenario: traefikイメージ更新でも同じ仕組みで機能する
- **WHEN** traefikイメージのみが変更されたDependabot PRが`main`にマージされ、`n8n-deploy.yml`が起動する
- **THEN** n8nイメージ更新時と同様に、実行タイトルにコミットメッセージが表示され、ジョブサマリーにtraefikの`image:`行の差分が表示される

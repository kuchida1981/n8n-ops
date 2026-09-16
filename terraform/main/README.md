# こんな感じで実行する

```
terraform init -backend-config="bucket=$TFSTATE_BUCKET"
terraform plan
terraform apply
```

Sensitive な変数（`TF_VAR_tailscale_oauth_client_id` など）は `.envrc` にコメントとして列挙してある。
コミットせずにシェルのプロファイルなどで設定すること。

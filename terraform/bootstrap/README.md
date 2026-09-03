# こんな感じで実行する

```
/usr/bin/terraform init -backend-config="bucket=$TFSTATE_BUCKET" -reconfigure
/usr/bin/terraform plan
/usr/bin/terraform apply
```

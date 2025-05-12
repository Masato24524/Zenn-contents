---
title: "データレイク/Kinesis Firehoseを使ったデータ分析(AWS SAAハンズオントレーニング)"
emoji: "📌"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS"]
published: true
date: "2025-05-10"
---

### はじめに

今回はSAA試験に向けたハンズオントレーニングの二回目について記載します。

前回の記事はこちら：

https://zenn.dev/masato24524/articles/49aef95c1253c2

現在Udemyの問題集で学習を続けているのですが、Kinesis（Streams、Firehose、Apache Flink）の問題が結構出てくるにもかかわらず、理解が浅いせいか解答/解説を見てもなかなかしっくりきません。

【SAA-C03版】AWS 認定ソリューションアーキテクト アソシエイト模擬試験問題集（6回分390問）
https://www.udemy.com/course/aws-knan/

ググってみたところ、2020年と少し古いですがKinesis Firehoseを使ったハンズオントレーニングの記事があったので、それを実践してみようと思います。

https://dev.classmethod.jp/articles/ws-summit-online-2020-hol-1/

メインはデータレイク周りの構成を構築することなので、データレイク周りの知識を習得するのにも役立ちそうです。

ちなみにこれだけのサービスを使います。

- **Amazon S3(Simple Storage Service)**　※AWSでデータレイクとは、S3内で構築するという理解でいいようです
- Amazon VPC
- Amazon EC2
- AWS CloudFormation
- AWS IAM
- **Amazon Kinesis Data Firehose**
- Amazon Athena
- Amazon QuickSight

盛り沢山ですね(^^;

前回同様、記事にならってハンズオンを行い、詰まった点に関して備忘録として記載していこうと思います。


### 目次

1. CloudFormationでVPC, EC2を作成する
2. IAMロールの作成
3. SSMコンソールでの確認
4. Kinesis Firehoseの設定
5. Glueでのデータ抽出とテーブル作成
6. Athenaによるクエリの実行
7. QuickSightでの可視化
8. 後片付け

---

### 1. CloudFormationでVPC, EC2を作成する

まずは記事に従ってキーペアを作成します。

最新環境ではEC2のキーペアの中にタイプの選択があります。
こちらはRSAを選択しました。

> キーペア（Key Pair）とは、AWS EC2インスタンスに安全にログイン（SSH接続）するために使用される暗号鍵のペア

> EC2のキーペアの「タイプ」は、使用される暗号アルゴリズムの種類
RSAの方が互換性が高く、無難な選択（ED25519の方が最新式でセキュリティは高いとされる）

CloudFormationは記事で与えられたyamlファイルを使用しますが、
スタックの作成時にパラメータの設定が必要なので、

KeyPair：handson

RoleName : hansdon-minlake

としました。

KeyPairは先ほど作成したもので、RoleNameについては記事の中では前後していますが、後ほどhandson-minlakeという名前でIAMロールを作成するのでそれに合わせます。

#### EC2インスタンスの作成エラー

CREATE_FAILEDのエラーが発生しました。

これはEC2のAMI IDが記事当時のもので古いためなので、最新のものにyamlファイルを書き換えます。

![alt text](/images/65bfd4816baffb/image-1.png)

無料枠のLinux2023/t2.microを選択して、AMI IDをコピーして、yamlファイルを更新します。

**※最初Linux2で実施したのですが、Firehoseプラグインのインストールのあたりでうまくいかなくなりました**

再度CloudFormatinoのスタックを作成し直したところ、状態がCOMPLETEとなり正常に完了しました。

---

### 2. IAMロールの作成

記事内ではIAMロールを新規作成するように書かれていますが、CloudFormationによって「handson-minlake」というIAMロールが既に作成されています。

なので上記のIAMロールを選択した後、許可を追加→ポリシーをアタッチと選択し、「AmazonEC2RoleforSSM」のポリシーを追加します。

![alt text](/images/65bfd4816baffb/image-2.png)

> 記事内で急にSSMという言葉が出てきますが、SSM（AWS Systems Manager）とは、AWSが提供するEC2などのインスタンスやシステムの運用・管理を簡単にするためのマネージドサービスになります。

次にIAMロールの割り当てですが、下記から行えます。

EC2→アクション→セキュリティ→IAMロールを変更

**※こちらもCloudFormationで既に設定済みのようでした。**

### 3. SSMコンソールでの確認

元記事ではログが2分おきに出力されるとのことでしたが、その設定が見当たりません（AMIにカスタムされていた？）

仕方がないので、代わりに下記をセッションマネージャーのコンソール画面で実行します。

**(注意！)下記のコマンドで問題が発生した場合は各自で調べてみてください**

~~~
// rootユーザーに切り替え
sudo su - 

// ディレクトリを作成
mkdir -p /root/es-demo 

// スクリプトファイルを作成
cat <<EOF > /root/es-demo/testlog.sh
#!/bin/bash

while true; do
  timestamp=\$(date "+[%Y-%m-%d %H:%M:%S+0900]")
  log_message="\$timestamp INFO prd-web001 uehara 1001 [This is Information.]"
  echo "\$log_message" >> /root/es-demo/testapp.log
  sleep 120
done
EOF

// 実行権限を付与
chmod +x /root/es-demo/testlog.sh　

// バックグラウンドでスクリプトを実行
nohup /root/es-demo/testlog.sh &　

// ログファイルの中身を確認
cat /root/es-demo/testapp.log

~~~

成功すると、記事と同じようなログが2分ごとに出力されます。

~~~
[2025-05-10 05:38:46+0900] INFO prd-web001 uehara 1001 [This is Information.]
[2025-05-10 05:40:46+0900] INFO prd-web001 uehara 1001 [This is Information.]
[2025-05-10 05:42:46+0900] INFO prd-web001 uehara 1001 [This is Information.]
[2025-05-10 05:44:46+0900] INFO prd-web001 uehara 1001 [This is Information.]
~~~

あとの設定は記事通りで問題なさそうでした。

### 4. Kinesis Firehoseの設定

引き続きSSMのコンソール画面（root）で進めていきます。

記事には記載がないですが、先にgem/rubyなどの必要なパッケージをインストールする必要があります。

また、Fluentdを起動するまで、その他の設定についても記事以外の手順を踏むことになります。

（Amazon Linux2023ではtd-agentのサポート対象外のため）

中身がすべて理解できるのがベストではあるのですが、

時間の兼ね合いもあり、今回は設定ファイルなどはClaudeに聞いたものを使用しました。

~~~

# rootユーザーに切り替え
sudo su -

# 必要なパッケージのインストール
sudo dnf install -y ruby ruby-devel gcc gcc-c++ make

# Fluentd と Kinesis プラグインをインストール
sudo gem install fluentd
sudo gem install fluent-plugin-kinesis

# 設定ディレクトリを作成
sudo mkdir -p /etc/fluentd
sudo mkdir -p /var/log/fluentd/buffer

sudo mkdir -p /var/log/fluentd/buffer/firehose
sudo chmod -R 755 /var/log/fluentd

# Firehose 用の設定ファイルを作成
cat << EOF | sudo tee /etc/fluentd/fluentd.conf
# ログ設定
<system>
  log_level info
  <log>
    format json
    time_format %Y-%m-%d %H:%M:%S
  </log>
</system>

# EC2のログファイルを監視
<source>
  @type tail
  path /root/es-demo/testapp.log
  pos_file /var/log/fluentd/testapp.log.pos
  
  # ログフォーマット定義
  format /^\[(?<timestamp>[^ ]* [^ ]*)\] (?<alarmlevel>[^ ]*) *? (?<host>[^ ]*) * (?<user>[^ ]*) * (?<number>.*) \[(?<text>.*)\]$/
  time_format %d/%b/%Y:%H:%M:%S %z
  
  # データ型変換
  types size:integer, status:integer, reqtime:float, runtime:float, time:time
  
  # タグ設定
  tag testappec2.log
</source>

# Firehose経由でS3へ送信
<match testappec2.log>
  @type kinesis_firehose
  
  # AWS設定
  region ap-northeast-1  # 使用するリージョンに変更
  delivery_stream_name minilake1  # 既存のFirehoseストリーム名
  
  # EC2のIAMロールを使用（推奨）
  # aws_key_id とaws_sec_keyは明示的に設定せず、IAMロールに依存
  
  # 出力フォーマット
  <format>
    @type json
  </format>
  
  # バッファ設定
  <buffer>
    @type file
    path /var/log/fluentd/buffer/firehose
    flush_interval 1s  # 例に合わせて1秒に設定
    chunk_limit_size 1m
    retry_forever true
    retry_max_interval 30
    flush_thread_count 4
  </buffer>
</match>

# システムのヘルスチェック用ログ（オプション）
<source>
  @type monitor_agent
  bind 0.0.0.0
  port 24220
</source>
EOF

# サービス定義を作成
cat << EOF | sudo tee /etc/systemd/system/fluentd.service
[Unit]
Description=Fluentd
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/fluentd -c /etc/fluentd/fluentd.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# サービスを有効化・起動
sudo systemctl daemon-reload
sudo systemctl enable fluentd
sudo systemctl start fluentd

 状態確認
sudo systemctl status fluentd

~~~

statusを確認して、fluentd.serviceがactive(runnning)になっていればOKです。

S3にminilake-in1のフォルダが作成されており、下の階層にファイルができていれば成功ですが、フォルダやファイルが見当たらなければ設定を見直す必要があります。

### 5. Glueでのデータ抽出とテーブル作成

Glueの画面ですが、なぜか英語で表示される・・・

以下に実行した手順をメモしておきます。

Data CatalogからCrawlersを選択→Create crawlerを選択

Choose data sources and classifiersではAdd a data sourceからS3 pathを選択し、データが保存されているS3バケットを選択してパスを追加します。

IAM　roleで作成しているIAMロールを選択します。

Add databaseでデータベースを新規作成します。名前を付けるだけでOKですが、元のSet output and schedulingのページでTarget databaseの再読み込みボタンを押さないと作成したデータベースが表示されません。

実行が成功すると、S3データからGlueによってデータベーステーブルが作成されます。

![alt text](/images/65bfd4816baffb/image-3.png)

### 6. Athenaによるクエリの実行

使用を開始のTrinoSQLを使用してデータをクエリする（S3分析の場合はこちらのようです）を選択し、クエリエディタを起動します。

最初にクエリ結果の保存場所を指定する必要があります。

![alt text](/images/65bfd4816baffb/image-4.png)

作成したテーブルが表示されていることを確認し、右側の三点からテーブルをプレビューを選択

クエリ文を少しカスタマイズしてやると、必要な行だけを抽出できます。

~~~SQL
SELECT * FROM "minilake"."20250510_handson_minilake_tiger" where user= 'uehara' AND partition_1 = '2025' AND partition_2 = '05' AND partition_3 = '10';
~~~

### 7. QuickSightでの可視化

いよいよ最後の項目です。

QuickSightで取得したデータの可視化を行います。

最初にアカウントの登録が必要となるようです。

（無料枠は30日間のみ？）

S3とAthenaが選択していることを確認しておきます。

下の方に**ピクセルパーフェクトレポート（月額料金が発生します）**とあるのでチェックを外しておきます。

![alt text](/images/65bfd4816baffb/image-5.png)

取得したデータについて、グラフを表示させることができます。

ログ数が少ないのと、似たようなデータばかりなので味気ないグラフですが・・・

![alt text](/images/65bfd4816baffb/image-6.png)

### 8. 後片付け

記事にも記載がありますが、EC2などを起動したままにしておくと課金が継続されるため、不要なAWSリソースは停止しておきましょう。（できれば削除しておくのがベストです）

特にEC2（停止より削除推奨）、Elastic IP（VPCから確認可能、割り当てがないと課金される。関連付けを解除してから、解放を選択）、S3（バケットを空にするのが大事）は注意してください。

**※CloudFormationのスタックを削除すると、作成したときと同じリソースを削除してくれるんですね。便利！**

### さいごに

今回得られた知見を下記します。

- IAMロールはSSM側（操作する側）ではなく、EC2側（アクセスされる側）に設定する

- CloudFormationの便利さを体感。テンプレートファイルを使えばどのユーザーでも一発で複数の必要リソースが作成可能（IAMロールだって作れる）

- FirehoseはS3へと直接データを吐き出せる（間に別のリソースは不要）

- AWS触るならLinuxの知識（コマンド）が必須

特にFirehose（データ取得）　→　S3（データレイク）　→　Glue（テーブル作成）→ Athena（SQLクエリ分析）　と試験に頻出のリソースの連携が頭の中にイメージしやすくなり、実践してみて良かったと思います。

来週はいよいよSAA試験を受講予定なので、ラストスパートを頑張っていきます。
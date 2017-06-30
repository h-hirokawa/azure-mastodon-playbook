# Azure上へのMastodonインスタンス構築Playbook - 実行手順解説

## I. Ansible環境準備

Linux環境上にAnsibleをインストールし、Playbookを実行できる状態にする。

### 事前準備
Linuxの稼働環境を用意し、シェルに接続する。
[Vagrant](https://www.vagrantup.com) を使うと、以下の手順で簡単にUbuntu 16.04環境を作ってログインすることが可能です。

```bash
mkdir ansible-handson; cd $_
vagrant init bento/ubuntu-16.04
vagrant up
vagrant ssh
```

ログイン後は、ホストOSとファイルを共有できるように `/vagrant` ディレクトリに移動し、日本語が文字化けしないように対応を実行します。

```
cd /vagrant
unset LANGUAGE
```

### 1．当PlaybookをGithubからクローン
まずは、以下の手順でGitをインストールしましょう。

#### Debian系(Ubuntu含む)の場合
```bash
sudo apt-get update && sudo apt-get install -y git
```

#### RedHat系の場合
```bash
sudo yum install -y git
```

次に、インストールした `git` コマンドを使ってリポジトリをクローンし、ディレクトリを移動します。

```bash
git clone https://github.com/h-hirokawa/azure-mastodon-playbook.git
cd azure-mastodon-playbook
```

### 2. Ansibleをインストールする
リポジトリに含まれている `install_ansible.sh` スクリプトを使ってAnsibleをインストールしましょう。これを用いると必要な依存関係も含めてAnsibleをインストールすることができます。
中で `sudo` を実行しているので、パスワードを聞かれた場合は手で入力してください。

```bash
ansible --version
```

を実行してAnsibleのバージョンが表示されればインストールは成功です。

### 3. Ansible GalaxyからRoleをダウンロード
今回のPlaybookでは各種ミドルウェア(Nginx, Postgresql, Redis)と言語環境(Ruby, Node.js)のセットアップに公式Role共有ポータル [Ansible Galaxy](https://galaxy.ansible.com/) で公開されていRoleを使っています。
必要なRoleの依存情報は [requirements.yml](./requirements.yml) に記述されており、このファイルを使って以下のようにコマンド一発でダウンロードすることができます。

```bash
ansible-galaxy install -r ./requirements.yml
```

これでPlaybook実行のためのAnsible側の準備は整いました。

## II. Azure CLIの設定
次にPlaybookからAzureを操作する際に必要となる、Python製コマンドラインツール Azure CLI 2.0 をセットアップしていきます。

### 1. PlaybookからAzure CLIをインストール

Ansibleではローカル環境の操作も行えるため、このAzure CLIのインストール手順もPlaybook化しています。
以下のようにPlaybookを走らせてみましょう。

```bash
ansible-playbook ./site.yml
```

`sudo` 実行にパスワードが必要な環境の場合は、 `-K` オプションをつけると、

```bash
ansible-playbook -K ./site.yml
```

以下のようなプロンプトが表示されますので、パスワードを入力してください。

```
SUDO password:
```

ちなみに、今回のPlaybookはAzure CLIのインストールが完了した時点で実行失敗となってしまいますが、これは想定通りの動きです。
そのまま先に進んでいきましょう。

### 2. Azure AD上にService Principalを作成
上段のPlaybook実行時の出力を見ると、下の方に以下のような部分が見つけられます

```
TASK [azure_vm : debug] *****************************************************************************************************************************
ok: [localhost] => {
    "msg": [
        "Service Principle情報が存在しません、以下の3コマンドを順に実行してからPlaybookを再実行してください。",
        "source ~/venv/azure-cli/bin/activate",
        "az login",
        "az ad sp create-for-rbac -n http://ansible-demo --role contributor > /vagrant/azure-mastodon-playbook/resources/azure-sp.json"
    ]
}
```

出力されているメッセージ通り、Service Principal（アプリケーションからAzureを操作するための認証ID的なもの、[参考資料](https://www.slideshare.net/ToruMakabe/3azure-service-principal)）がAzure AD上に未登録であるためのエラーです。
Service Principle作成のためには、Azure CLIから各ユーザー・アカウントでログインする必要があるのですが、このログインの際にブラウザ経由の処理が必要となってしまうため、ここでは一旦Playbook実行を中断し、手動対応が必要な手順を案内するようにしています。

まず、一つ目のコマンドを実行しましょう。

```bash
source ~/venv/azure-cli/bin/activate
```

Azure CLIはVirtualenvという仕組みを使って、ホスト上のグローバルなPython環境とは隔離したスペースにインストールされていますが、上記のコマンドでそのVirtualenv環境の中に入ることができます。

次にログイン処理です。

```bash
az login
```

コマンドを実行すると、

```
To sign in, use a web browser to open the page https://aka.ms/devicelogin and enter the code XXXXXXXXX to authenticate.
```

というような表示が出てきますので、ブラウザから https://aka.ms/devicelogin にアクセスし、認証コード（`GRMJ4GLQ6` の部分）を入力し、「続行」ボタンをクリックしてください。
そこから先は、通常のAzureログイン時と同じ流れでシステムにログインすることでCLIからあなたのアカウント権限でAzureを操作することができるようになります。

最後に、

```bash
az ad sp create-for-rbac -n http://ansible-demo --role contributor > /vagrant/azure-mastodon-playbook/resources/azure-sp.json
```

（`http://ansible-demo` の部分はADごとにURL形式にさえなっていれば、実在しないURLでも問題ありません）

を実行して、Service Principleを作成すればここでの対応は完了です。
Service Principleの利用に必要なIDやパスワードは `/vagrant/azure-mastodon-playbook/resources/azure-sp.json` に保存され、Playbookから読み取り可能になっています。

### III. Playbook再実行 VM作成 ~ Mastodonインスタンス・セットアップ
Service Principleの設定が済んでしまえば、あとはVM作成からVM内のセットアップまで、全てPlaybookが実行してくれます。
先ほどと同じように

```bash
ansible-playbook ./site.yml
```

を実行して、デプロイ完了までしばらく待ちましょう。
無事、デプロイが正常に完了すると、実行ログの終わりに以下のようなメッセージが表示されます。

```
TASK [サイト情報を表示] *****************************************************************************************************************************
ok: [localhost] => {
    "msg": [
        "デプロイが完了しました。",
        "ブラウザから http://xx.xx.xx.xx にアクセスしてみましょう"
    ]
}
```

`http://xx.xx.xx.xx` の部分は各自のVMに自動で紐づけられた公開IPアドレスになります。

最後に、Mastodonインスタンスが表示されユーザー登録とログインができることを確認して、ハンズオン完了です！

注意: ユーザー登録時の確認メールはデモ用のSendGrid(https://sendgrid.kke.co.jp)経由で送られており、ハンズオン終了後には利用できなくなります。引き続きデプロイしたMastodonインスタンスを使う場合は、[site.yml](./site.yml) 中の66~68行目

```yaml
        mastodon_smtp_server: smtp.sendgrid.net
        mastodon_smtp_login: apikey
        mastodon_smtp_password: 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
```

の部分を自分のアカウント情報に書き換えて、Playbookを再実行してください。
無料でSMTPメールを送れるサービスとしては、SendGridの他に [MailGun](https://www.mailgun.com) などがあります。

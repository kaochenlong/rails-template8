# Rails Application Template

`rails new` 一行指令，把新專案的慣用配置全部就位。

## 內含什麼

| 類別       | 配置                                                                                                                                                                                                                                                                               |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 資料庫     | PostgreSQL（development/test 走 TCP，預設 `localhost` + `postgres/postgres`，可用 ENV 覆寫）                                                                                                                                                                                       |
| 前端       | **Vite**（純 Vite backend integration，不靠 vite_rails gem；自寫 manifest helper）+ Tailwind CSS v4（官方 `@tailwindcss/vite` plugin）+ **Turbo + Alpine.js**（不裝 Stimulus，搭配 [alpine-turbo-drive-adapter](https://github.com/SimoTod/alpine-turbo-drive-adapter)）；CSS/JS 熱更新、改 view/component 自動重整（vite-plugin-full-reload） |
| 測試       | RSpec + FactoryBot + Faker + Capybara（minitest 移除；system spec 預設 rack_test，`js: true` 走 headless Chrome）                                                                                                                                                                  |
| 首頁       | `pages#home` 設為 root，可愛火車風 Rails 啟動畫面（Tailwind v4 + 純 CSS 動畫、版本號動態，附 request spec）；**不含內建認證**，要的話自行 `rails g authentication`                                                                                                                                                     |
| View       | ViewComponent，**sidecar 模式為 generator 預設**，preview 路徑在 `spec/components/previews`                                                                                                                                                                                        |
| 分頁       | pagy 43.x（`ApplicationController` 已 `include Pagy::Method`，view 用 `<%== @pagy.series_nav %>`）                                                                                                                                                                                 |
| Model 註解 | annotaterb（`db:migrate` 後自動更新）                                                                                                                                                                                                                                              |
| Lint       | rubocop-rails-omakase（Rails 預設）＋ rubocop-rspec                                                                                                                                                                                                                                |
| i18n       | `default_locale = :tw`、timezone `Taipei`；fallback 鏈 `tw → zh-TW → en`，rails-i18n 的標準翻譯（AR validation 訊息等）經 fallback 直接可用，自訂翻譯寫在 `config/locales/tw.yml`                                                                                                  |
| Generator  | 關閉 helper / assets 自動生成；fixture 改用 factory（`spec/factories`）                                                                                                                                                                                                            |

template 全程**不會**做任何 git commit（`rails new` 自帶的 `git init` 保留），也**不生成 CI**（`--skip-ci`；連 Rails 原生的 ci.yml 都不會留下——它跑 minitest，跟本配置不合）。

## 前置需求

- Ruby + Rails 用現行最新版（mise 管理）：`mise use -g ruby@latest`，然後 `gem install rails`
- Node + Yarn（Vite 用；前端走 `package.json` 的 scripts，`yarn dev` / `yarn build`）
- PostgreSQL 在 `localhost:5432`（Docker 即可），預設帳密 `postgres / postgres`

## 用法

### 方法一：一行試用（什麼都不用裝）

Rails 的 `-m` 可以直接吃 URL：

```bash
rails new myapp -d postgresql --skip-javascript --skip-hotwire --skip-ci \
  -m https://raw.githubusercontent.com/kaochenlong/rails-template8/main/template.rb
```

### 方法二：設成預設（建議，一勞永逸）

把 railsrc 放到 Rails 的設定位置，之後 `rails new` 自動帶入所有參數與 template：

```bash
mkdir -p ~/.config/rails
curl -o ~/.config/rails/railsrc https://raw.githubusercontent.com/kaochenlong/rails-template8/main/railsrc

rails new myapp   # 一行搞定
```

偶爾要生一個「乾淨」的 app 時用 `rails new myapp --no-rc` 跳過 railsrc。

### 方法三：clone 下來客製

```bash
git clone https://github.com/kaochenlong/rails-template8.git ~/rails-template8
```

改完 `template.rb` 後，把 `~/.config/rails/railsrc` 裡的 `-m` 換成本機路徑（`~` 跟 `$HOME` 都會被展開）：

```
-m ~/rails-template8/template.rb
```

### 參數說明

`--skip-javascript`（JS/CSS 全交給 Vite，不裝 importmap/jsbundling）跟 `--skip-hotwire`（不裝 Stimulus，Turbo 由 template 補回）都是必要的，漏掉 template 會警告；`--skip-ci` 漏掉也沒關係，template 會把原生 ci.yml 清掉。

## 前端結構（Vite 慣例）

```
app/frontend/
├── entrypoints/application.js   # 入口：Turbo + Alpine + CSS
└── stylesheets/application.css  # Tailwind v4 入口（@source 指到 views/components）
app/helpers/vite_helper.rb       # 讀 .vite/manifest.json：dev 注入 dev server、prod 出指紋化 tag
vite.config.ts                   # Tailwind + FullReload；manifest / base:"/vite/" / publicDir:false
package.json                     # scripts：dev / build（前端走 yarn）
public/vite/                     # build 輸出：manifest + 指紋化 assets（已 gitignore）
```

開發時 `bin/dev` 起兩個 process：`bin/rails server` + `yarn dev`（走專案 local vite）。改 CSS/JS 即時生效（HMR），改 `app/views/` 或 `app/components/` 瀏覽器自動重整。

## 資料庫連線覆寫

development / test 的連線參數可用環境變數覆寫，不用改 `database.yml`：

```bash
DB_HOST=...      # 預設 localhost
DB_USERNAME=...  # 預設 postgres
DB_PASSWORD=...  # 預設 postgres
```

## 生成後的日常指令

```bash
bin/dev                                              # 開發環境（rails + vite dev server）
bin/rails db:test:prepare spec                       # 跑測試（含 vite build）
bin/rails g view_component:component Button label    # 生 ViewComponent（sidecar 結構 + component spec）
yarn build                                           # 手動 build（部署時 assets:precompile 會自動觸發）
```

## 已知注意事項

- **Dockerfile / Kamal 部署**：`rails new --skip-javascript` 生成的 Dockerfile 沒有 Node 安裝段，但 `assets:precompile` 會觸發 `yarn build`（需要 Node + `yarn install`）。要用 Dockerfile 部署時需自行補上 Node 安裝與 `yarn install` 步驟。

## 客製建議

這是一份 opinionated 的 template（我自己每天在用的配置），fork 之後最常想改的幾個點都在 `template.rb`：

| 想改什麼          | 在哪裡                                                                                                           |
| ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| locale / timezone | `environment` 區塊的 `config.i18n.*`（`:tw`）跟 `config.time_zone`（`Taipei`）                                   |
| 資料庫預設帳密    | `db_overrides` 的 `postgres / postgres`（不 fork 也能用 `DB_HOST` / `DB_USERNAME` / `DB_PASSWORD` 環境變數覆寫） |
| 首頁畫面          | `app/views/pages/home.html.erb`（可愛火車啟動畫面）；主題色/動畫 token 在 `app/frontend/stylesheets/application.css` 的 `@theme` |
| 分頁每頁筆數      | `config/initializers/pagy.rb` 的 `Pagy::OPTIONS[:limit]`                                                         |

## License

[MIT](LICENSE)


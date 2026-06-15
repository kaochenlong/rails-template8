# Rails Application Template
# https://github.com/kaochenlong/rails-template8
#
# 一次性使用（不用 clone）：
#   rails new myapp -d postgresql --skip-javascript --skip-hotwire --skip-ci \
#     -m https://raw.githubusercontent.com/kaochenlong/rails-template8/main/template.rb
#
# 設成預設（之後 rails new myapp 一行搞定）：
#   mkdir -p ~/.config/rails
#   curl -o ~/.config/rails/railsrc https://raw.githubusercontent.com/kaochenlong/rails-template8/main/railsrc
#
# 內容：PostgreSQL / Vite + Tailwind v4 / Turbo + Alpine.js（無 Stimulus）/
#       RSpec + FactoryBot + Faker / pages#home 首頁 / ViewComponent（sidecar）/
#       pagy / annotaterb / rubocop-rspec / tw locale + Taipei timezone

# ----------------------------------------------------------------------------
# 前置檢查
# ----------------------------------------------------------------------------
if Gem::Version.new(Rails::VERSION::STRING) < Gem::Version.new("8.1")
  say "這份 template 以 Rails 8.1 為基準，目前是 #{Rails::VERSION::STRING}，部分步驟可能不適用", :yellow
end

unless options[:skip_javascript]
  say "提醒：建議加上 --skip-javascript（本 template 用 Vite 處理 JS/CSS，不用 importmap/jsbundling）", :yellow
end

unless options[:skip_hotwire]
  say "提醒：建議加上 --skip-hotwire（本 template 用 Alpine.js 取代 Stimulus，Turbo 會自行補回）", :yellow
end

unless options[:database] == "postgresql"
  say "提醒：database 不是 postgresql（目前是 #{options[:database]}），跳過 database.yml 連線設定", :yellow
end

# ----------------------------------------------------------------------------
# Gemfile
# ----------------------------------------------------------------------------
gem "turbo-rails" if options[:skip_hotwire]
gem "view_component"
gem "pagy", "~> 43.5"
gem "rails-i18n"

gem_group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "rubocop-rspec", require: false
end

gem_group :development do
  gem "annotaterb"
end

# ----------------------------------------------------------------------------
# config/application.rb：timezone / i18n / generators / ViewComponent
# ----------------------------------------------------------------------------
environment <<~RUBY
  config.time_zone = "Taipei"

  config.i18n.available_locales = [:tw, :"zh-TW", :en]
  config.i18n.default_locale = :tw
  config.i18n.fallbacks = [:"zh-TW", :en]

  config.generators do |g|
    g.helper false
    g.assets false
    g.test_framework :rspec, fixture: false
    g.fixture_replacement :factory_bot, dir: "spec/factories"
  end

  config.view_component.generate.sidecar = true
  config.view_component.previews.paths << Rails.root.join("spec/components/previews").to_s
RUBY

# production.rb 預設的 fallbacks = true 會蓋掉上面的設定，改成一致的 fallback 鏈
gsub_file "config/environments/production.rb",
  "config.i18n.fallbacks = true",
  %(config.i18n.fallbacks = [:"zh-TW", :en])

# ----------------------------------------------------------------------------
# database.yml：本機 PG 走 TCP（Docker），ENV 可覆寫
# ----------------------------------------------------------------------------
if options[:database] == "postgresql"
  db_overrides = <<-YAML
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  username: <%= ENV.fetch("DB_USERNAME", "postgres") %>
  password: <%= ENV.fetch("DB_PASSWORD", "postgres") %>
  YAML

  # force: true — Thor 會因 development 段已插入相同內容而跳過 test 段的插入
  insert_into_file "config/database.yml", db_overrides,
    after: /^development:\n  <<: \*default\n  database: #{app_name}_development\n/, force: true

  insert_into_file "config/database.yml", db_overrides,
    after: /^test:\n  <<: \*default\n  database: #{app_name}_test\n/, force: true
end

# ----------------------------------------------------------------------------
# pagy（43.x：Pagy::OPTIONS + Pagy::Method）
# ----------------------------------------------------------------------------
create_file "config/initializers/pagy.rb", <<~RUBY
  Pagy::OPTIONS[:limit] = 20
  Pagy::OPTIONS[:max_limit] = 100
  Pagy::OPTIONS.freeze
RUBY

inject_into_class "app/controllers/application_controller.rb", "ApplicationController",
  "  include Pagy::Method\n\n"

# ----------------------------------------------------------------------------
# locale：自訂翻譯放 tw:，標準翻譯由 rails-i18n 的 zh-TW 經 fallback 提供
# ----------------------------------------------------------------------------
create_file "config/locales/tw.yml", <<~YAML
  tw:
    hello: "你好，世界"
YAML

# ----------------------------------------------------------------------------
# RuboCop：omakase + rubocop-rspec
# ----------------------------------------------------------------------------
append_to_file ".rubocop.yml", <<~YAML

  plugins:
    - rubocop-rspec

  AllCops:
    NewCops: enable
YAML

# ----------------------------------------------------------------------------
# CI：不用（railsrc 已帶 --skip-ci；這裡防護手動執行沒帶 flag 的情況——
# 原生 ci.yml 跑 minitest，test/ 已移除必紅，留著只會誤導）
# ----------------------------------------------------------------------------
remove_file ".github/workflows/ci.yml"

# ----------------------------------------------------------------------------
# after_bundle：esbuild / tailwind / solid 內建安裝跑完後才執行
# 所有 generate / rails_command 都得在這裡（gem 已裝、railtie 已生效）
# ----------------------------------------------------------------------------
after_bundle do
  # -- Vite（純 Vite backend integration，不靠 vite_rails gem）-----------------
  # 自己建 package.json + 裝 local vite；前端一律走 yarn，不碰 bundle exec vite
  create_file "package.json", <<~JSON, force: true
    {
      "name": "#{app_name}",
      "private": true,
      "type": "module",
      "scripts": {
        "dev": "vite",
        "build": "vite build"
      }
    }
  JSON

  run "yarn add @hotwired/turbo-rails alpinejs alpine-turbo-drive-adapter"
  run "yarn add -D vite @tailwindcss/vite tailwindcss vite-plugin-full-reload"

  # web 固定 3000；vite 用 yarn dev（走專案 node_modules 的 local vite，避開全域 vite）
  create_file "Procfile.dev", <<~PROCFILE, force: true
    web: bin/rails server -p 3000
    vite: yarn dev
  PROCFILE

  # Vite 官方 backend integration：產 manifest、指定 entry、設 dev server 的 origin/CORS
  create_file "vite.config.ts", <<~TS, force: true
    import { defineConfig } from "vite"
    import tailwindcss from "@tailwindcss/vite"
    import FullReload from "vite-plugin-full-reload"

    export default defineConfig({
      plugins: [
        tailwindcss(),
        FullReload(["config/routes.rb", "app/views/**/*", "app/components/**/*"]),
      ],
      base: "/vite/",
      // Rails 自己管 public/；關掉 vite publicDir，否則 outDir 在 public/ 內會把 Rails 靜態檔複製進去
      publicDir: false,
      build: {
        manifest: true,
        outDir: "public/vite",
        emptyOutDir: true,
        rollupOptions: { input: "app/frontend/entrypoints/application.js" },
      },
      server: {
        cors: { origin: "http://localhost:3000" },
        origin: "http://localhost:5173",
      },
    })
  TS

  create_file "app/frontend/entrypoints/application.js", <<~JS, force: true
    import "@hotwired/turbo-rails"

    import "alpine-turbo-drive-adapter"
    import Alpine from "alpinejs"

    import "../stylesheets/application.css"

    window.Alpine = Alpine
    Alpine.start()
  JS

  # Tailwind v4：vite root 在 app/frontend，掃不到 Rails 的 views/components，要顯式 @source
  create_file "app/frontend/stylesheets/application.css", <<~CSS
    @import "tailwindcss";

    @source "../../views";
    @source "../../components";
    @source "../../frontend";

    /* pages#home 可愛火車主題：字體 / 色 / 動畫（給 home 的 Tailwind utilities）*/
    @theme {
      --font-fredoka: "Fredoka", sans-serif;
      --font-baloo: "Baloo 2", sans-serif;

      --color-railsred: #E02B2B;
      --color-railsdeep: #C81E1E;

      --animate-bob: bob 3.2s ease-in-out infinite;
      --animate-chug: chug 0.5s ease-in-out infinite;
      --animate-spin360: spin360 1.6s linear infinite;
      --animate-smoke: smoke 2.4s ease-out infinite;
      --animate-drift: drift 9s ease-in-out infinite alternate;
      --animate-drift-r: driftR 11s ease-in-out infinite alternate;
      --animate-blink: blink 4.5s ease-in-out infinite;
      --animate-tracks: tracks 0.6s linear infinite;
      --animate-twinkle: twinkle 2.6s ease-in-out infinite;

      @keyframes bob { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-8px); } }
      @keyframes chug { 0%, 100% { transform: translateY(0) rotate(-0.6deg); } 50% { transform: translateY(-4px) rotate(0.6deg); } }
      @keyframes spin360 { to { transform: rotate(360deg); } }
      @keyframes smoke { 0% { transform: translateY(0) scale(0.6); opacity: 0; } 15% { opacity: 0.85; } 100% { transform: translateY(-70px) scale(1.6); opacity: 0; } }
      @keyframes drift { 0% { transform: translateX(0); } 100% { transform: translateX(40px); } }
      @keyframes driftR { 0% { transform: translateX(0); } 100% { transform: translateX(-32px); } }
      @keyframes blink { 0%, 92%, 100% { transform: scaleY(1); } 96% { transform: scaleY(0.1); } }
      @keyframes tracks { 0% { background-position: 0 0; } 100% { background-position: -44px 0; } }
      @keyframes twinkle { 0%, 100% { transform: scale(1); opacity: 0.9; } 50% { transform: scale(1.35); opacity: 0.35; } }
    }

    /* home 入場（.pop）與動畫錯開（.ad-* = animation-delay；刻意不叫 delay-* 以免撞 Tailwind 的 transition delay-*）*/
    .pop { animation: popin 0.6s cubic-bezier(0.34, 1.56, 0.64, 1) both; }
    .ad-1 { animation-delay: 0.4s; }
    .ad-2 { animation-delay: 0.8s; }
    .ad-3 { animation-delay: 1.2s; }
    @keyframes popin { 0% { transform: translateY(14px); opacity: 0; } 100% { transform: translateY(0); opacity: 1; } }
  CSS

  # Rails 端讀 Vite manifest 的 helper（純 Vite 沒有 vite_ruby 的 vite_*_tag）
  create_file "app/helpers/vite_helper.rb", <<~RUBY
    module ViteHelper
      DEV_SERVER = "http://localhost:5173".freeze
      BASE       = "/vite".freeze # 要跟 vite.config.ts 的 base 一致
      ENTRYPOINT = "app/frontend/entrypoints/application.js".freeze
      MANIFEST   = "public/vite/.vite/manifest.json".freeze

      # layout <head> 呼叫：<%= vite_assets %>
      def vite_assets(entry = ENTRYPOINT)
        if Rails.env.development?
          safe_join([
            module_script("\#{DEV_SERVER}\#{BASE}/@vite/client"),
            module_script("\#{DEV_SERVER}\#{BASE}/\#{entry}"),
          ])
        else
          chunk = vite_manifest.fetch(entry)
          safe_join(vite_css_tags(entry) + [module_script("\#{BASE}/\#{chunk["file"]}")])
        end
      end

      private

      # shared chunk 的 CSS 不在 entry 自己的 css 欄位，要沿 imports 遞迴收集
      def vite_css_tags(entry, seen = Set.new)
        return [] unless seen.add?(entry)
        chunk = vite_manifest[entry] or return []
        tags = Array(chunk["css"]).map { |f| tag.link(rel: "stylesheet", href: "\#{BASE}/\#{f}") }
        Array(chunk["imports"]).each { |imp| tags.concat(vite_css_tags(imp, seen)) }
        tags
      end

      def vite_manifest
        @vite_manifest ||= JSON.parse(Rails.root.join(MANIFEST).read)
      end

      def module_script(src)
        tag.script(type: "module", src: src)
      end
    end
  RUBY

  # layout：把預設的 stylesheet_link_tag 換成自寫的 vite_assets
  gsub_file "app/views/layouts/application.html.erb",
    /<%=\s*stylesheet_link_tag :app[^%]*%>/,
    "<%= vite_assets %>"

  # rails new 生的 bin/dev 是給 importmap/jsbundling 的；換成 foreman + Procfile.dev（force 免互動詢問）
  create_file "bin/dev", <<~SH, force: true
    #!/usr/bin/env sh

    if ! gem list foreman -i --silent; then
      echo "Installing foreman..."
      gem install foreman
    fi

    exec foreman start -f Procfile.dev "$@"
  SH
  chmod "bin/dev", 0o755

  # 部署時 assets:precompile 自動跑 vite build（vite_ruby 原本幫你做的事）
  create_file "lib/tasks/vite.rake", <<~RUBY
    namespace :vite do
      desc "Build frontend assets with Vite"
      task :build do
        sh "yarn build"
      end
    end

    if Rake::Task.task_defined?("assets:precompile")
      Rake::Task["assets:precompile"].enhance(["vite:build"])
    end
  RUBY

  # build 產物與 node_modules 不進版控
  append_to_file ".gitignore", <<~TXT

    /node_modules
    /public/vite
  TXT

  # -- RSpec ------------------------------------------------------------------
  generate "rspec:install"

  uncomment_lines "spec/rails_helper.rb", /Rails\.root\.glob/

  create_file "spec/support/factory_bot.rb", <<~RUBY
    RSpec.configure do |config|
      config.include FactoryBot::Syntax::Methods
    end
  RUBY

  # 任何 render layout 的測試都會碰到 vite_assets 讀 manifest：
  # system test 一律重 build 取最新；其他測試只在 manifest 不存在時 build 一次
  create_file "spec/support/vite.rb", <<~RUBY
    RSpec.configure do |config|
      config.before(:suite) do
        manifest = Rails.root.join("public/vite/.vite/manifest.json")
        running_system = RSpec.configuration.files_to_run.any? { |f| f.include?("/system/") }
        system("yarn build", exception: true) if running_system || !manifest.exist?
      end
    end
  RUBY

  create_file "spec/support/system.rb", <<~RUBY
    RSpec.configure do |config|
      config.before(:each, type: :system) do
        driven_by :rack_test
      end

      config.before(:each, type: :system, js: true) do
        driven_by :selenium_chrome_headless
      end
    end
  RUBY

  create_file "spec/support/view_component.rb", <<~RUBY
    require "view_component/test_helpers"
    require "view_component/system_test_helpers"
    require "capybara/rspec"

    RSpec.configure do |config|
      config.include ViewComponent::TestHelpers, type: :component
      config.include ViewComponent::SystemTestHelpers, type: :component
      config.include Capybara::RSpecMatchers, type: :component
    end
  RUBY

  create_file "spec/components/previews/.keep", ""

  # -- pages#home：root 首頁（取代 rails new 預設的 welcome 畫面）--------------
  create_file "app/controllers/pages_controller.rb", <<~RUBY
    class PagesController < ApplicationController
      def home
      end
    end
  RUBY

  create_file "app/views/pages/home.html.erb", <<~ERB
    <% content_for :head do %>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@400;500;600;700&family=Baloo+2:wght@500;600;700&display=swap" rel="stylesheet">
    <% end %>

    <div class="relative min-h-screen overflow-hidden bg-[#FFF6EE] font-fredoka text-[#5B4A45] antialiased selection:bg-railsred/20">
      <!-- soft sky gradient -->
      <div class="pointer-events-none absolute inset-0 bg-gradient-to-b from-[#FFF0E4] via-[#FFF6EE] to-[#FFE9DC]"></div>

      <!-- floating clouds -->
      <div class="pointer-events-none absolute inset-0">
        <div class="animate-drift absolute left-[8%] top-[14%] h-16 w-40 rounded-full bg-white/80 blur-[1px]"></div>
        <div class="animate-drift ad-2 absolute left-[6%] top-[20%] h-10 w-24 rounded-full bg-white/70 blur-[1px]"></div>
        <div class="animate-drift-r absolute right-[10%] top-[10%] h-20 w-52 rounded-full bg-white/75 blur-[1px]"></div>
        <div class="animate-drift-r ad-1 absolute right-[14%] top-[18%] h-12 w-28 rounded-full bg-white/60 blur-[1px]"></div>
        <div class="animate-drift ad-3 absolute left-[40%] top-[8%] h-12 w-32 rounded-full bg-white/55 blur-[1px]"></div>
      </div>

      <!-- twinkles -->
      <div class="pointer-events-none absolute inset-0">
        <div class="animate-twinkle absolute left-[22%] top-[30%] h-2.5 w-2.5 rotate-45 rounded-[2px] bg-[#FFC98A]"></div>
        <div class="animate-twinkle ad-1 absolute right-[24%] top-[26%] h-2 w-2 rotate-45 rounded-[2px] bg-[#FF9EB0]"></div>
        <div class="animate-twinkle ad-2 absolute right-[34%] top-[40%] h-3 w-3 rotate-45 rounded-[3px] bg-[#FFD27A]"></div>
        <div class="animate-twinkle ad-3 absolute left-[33%] top-[44%] h-2 w-2 rotate-45 rounded-[2px] bg-[#A0D8C8]"></div>
      </div>

      <main class="relative z-10 mx-auto flex min-h-screen max-w-3xl flex-col items-center justify-center px-6 py-10">

        <!-- train scene -->
        <div class="pop relative mb-2 h-[280px] w-full max-w-[460px]">

          <!-- sun -->
          <div class="absolute right-2 top-2 h-16 w-16 rounded-full bg-gradient-to-br from-[#FFE08A] to-[#FFC25C] shadow-[0_0_0_10px_rgba(255,209,122,0.25)]"></div>

          <!-- smoke puffs -->
          <div class="absolute left-[112px] top-[40px] h-6 w-6 rounded-full bg-white/90 animate-smoke"></div>
          <div class="absolute left-[112px] top-[40px] h-6 w-6 rounded-full bg-white/80 animate-smoke ad-1"></div>
          <div class="absolute left-[112px] top-[40px] h-6 w-6 rounded-full bg-white/70 animate-smoke ad-2"></div>

          <!-- the little engine (bobbing) -->
          <div class="animate-bob absolute bottom-[44px] left-1/2 -translate-x-1/2">
            <div class="animate-chug relative">

              <!-- smokestack -->
              <div class="absolute -top-7 left-[24px] h-8 w-9 rounded-t-xl rounded-b-md bg-railsdeep"></div>
              <div class="absolute -top-9 left-[20px] h-3 w-[68px] rounded-full bg-railsred"></div>

              <!-- cabin -->
              <div class="absolute -top-[34px] right-1 h-12 w-[78px] rounded-t-2xl rounded-b-md bg-railsred shadow-inner">
                <div class="absolute left-1/2 top-3 h-6 w-9 -translate-x-1/2 rounded-lg bg-[#BFE7FF] ring-2 ring-white/70"></div>
              </div>

              <!-- boiler body + face -->
              <div class="relative flex h-[92px] w-[210px] items-center rounded-[26px] bg-gradient-to-b from-railsred to-railsdeep shadow-[0_14px_0_rgba(200,30,30,0.25),0_22px_30px_rgba(224,43,43,0.35)]">
                <!-- front face panel -->
                <div class="ml-3 flex h-[68px] w-[68px] flex-col items-center justify-center rounded-full bg-white shadow-inner">
                  <div class="mb-1 flex gap-2.5">
                    <div class="animate-blink h-3 w-3 rounded-full bg-[#3B2B27] origin-center"></div>
                    <div class="animate-blink h-3 w-3 rounded-full bg-[#3B2B27] origin-center"></div>
                  </div>
                  <div class="h-2.5 w-5 rounded-b-full border-b-[3px] border-[#3B2B27]"></div>
                </div>
                <!-- cheeks -->
                <div class="absolute left-1 top-[44px] h-3 w-3 rounded-full bg-[#FF9EB0]/80"></div>
                <div class="absolute left-[64px] top-[44px] h-3 w-3 rounded-full bg-[#FF9EB0]/80"></div>

                <!-- side bands -->
                <div class="ml-auto mr-4 flex flex-col gap-2">
                  <div class="h-2.5 w-20 rounded-full bg-white/80"></div>
                  <div class="text-right font-baloo text-xl font-bold leading-none tracking-wide text-white">RAILS</div>
                  <div class="h-2.5 w-20 self-end rounded-full bg-white/40"></div>
                </div>

                <!-- headlamp -->
                <div class="absolute -left-2 top-1/2 h-7 w-4 -translate-y-1/2 rounded-l-lg bg-[#FFD27A]"></div>
              </div>

              <!-- wheels -->
              <div class="absolute -bottom-5 left-7 flex gap-9">
                <div class="animate-spin360 relative flex h-12 w-12 items-center justify-center rounded-full bg-[#3B2B27] ring-4 ring-white">
                  <div class="h-3.5 w-3.5 rounded-full bg-[#FFD27A]"></div>
                  <div class="absolute h-9 w-1 rounded bg-white/30"></div>
                  <div class="absolute h-1 w-9 rounded bg-white/30"></div>
                </div>
                <div class="animate-spin360 relative flex h-12 w-12 items-center justify-center rounded-full bg-[#3B2B27] ring-4 ring-white">
                  <div class="h-3.5 w-3.5 rounded-full bg-[#FFD27A]"></div>
                  <div class="absolute h-9 w-1 rounded bg-white/30"></div>
                  <div class="absolute h-1 w-9 rounded bg-white/30"></div>
                </div>
              </div>

            </div>
          </div>

          <!-- the rails / track -->
          <div class="absolute bottom-[26px] left-1/2 h-3 w-[420px] -translate-x-1/2 rounded-full bg-[#E9D9CE]"></div>
          <div class="animate-tracks absolute bottom-[14px] left-1/2 h-3 w-[420px] -translate-x-1/2 rounded" style="background-image: repeating-linear-gradient(90deg,#D8C3B6 0 8px,transparent 8px 44px);"></div>
        </div>

        <!-- copy -->
        <h1 class="pop text-center font-baloo text-4xl font-bold tracking-tight text-[#3B2B27] sm:text-5xl" style="animation-delay:.1s">
          Yay! You're on <span class="text-railsred">Rails</span>!
          <span class="inline-block animate-bob">🎉</span>
        </h1>
        <p class="pop mt-3 max-w-md text-center text-lg text-[#8A746C]" style="animation-delay:.2s">
          All aboard — your shiny new app is chugging along happily.
          Edit <code class="rounded-md bg-white px-2 py-0.5 font-baloo text-[15px] text-railsred shadow-sm">app/views/pages/home.html.erb</code> to begin the journey.
        </p>

        <!-- version chips -->
        <div class="pop mt-7 flex flex-wrap items-center justify-center gap-3" style="animation-delay:.3s">
          <div class="group flex items-center gap-2 rounded-full bg-white px-4 py-2 shadow-[0_6px_0_rgba(224,43,43,0.12)] ring-1 ring-railsred/10 transition hover:-translate-y-0.5">
            <span class="grid h-7 w-7 place-items-center rounded-full bg-railsred/10 text-base">🚂</span>
            <span class="text-sm text-[#A38F87]">Rails</span>
            <span class="font-baloo text-sm font-bold text-[#3B2B27]"><%= Rails.version %></span>
          </div>
          <div class="group flex items-center gap-2 rounded-full bg-white px-4 py-2 shadow-[0_6px_0_rgba(160,216,200,0.25)] ring-1 ring-[#A0D8C8]/30 transition hover:-translate-y-0.5">
            <span class="grid h-7 w-7 place-items-center rounded-full bg-[#A0D8C8]/20 text-base">📦</span>
            <span class="text-sm text-[#A38F87]">Rack</span>
            <span class="font-baloo text-sm font-bold text-[#3B2B27]"><%= Rack.release %></span>
          </div>
          <div class="group flex items-center gap-2 rounded-full bg-white px-4 py-2 shadow-[0_6px_0_rgba(255,194,92,0.22)] ring-1 ring-[#FFC25C]/30 transition hover:-translate-y-0.5">
            <span class="grid h-7 w-7 place-items-center rounded-full bg-[#FFC25C]/20 text-base">💎</span>
            <span class="text-sm text-[#A38F87]">Ruby</span>
            <span class="font-baloo text-sm font-bold text-[#3B2B27]"><%= RUBY_VERSION %></span>
          </div>
        </div>

        <p class="pop mt-5 text-center font-mono text-[11px] leading-relaxed text-[#C3B0A8]" style="animation-delay:.4s">
          <%= RUBY_DESCRIPTION %>
        </p>

      </main>
    </div>
  ERB

  route 'root "pages#home"'

  create_file "spec/requests/pages_spec.rb", <<~RUBY
    require "rails_helper"

    RSpec.describe "Pages", type: :request do
      it "GET / 回應 200" do
        get root_path
        expect(response).to have_http_status(:ok)
      end
    end
  RUBY

  # -- annotaterb --------------------------------------------------------------
  generate "annotate_rb:install"

  # -- 清掉 minitest 殘留 -------------------------------------------------------
  remove_dir "test"

  # -- 資料庫與收尾 -------------------------------------------------------------
  rails_command "db:prepare"

  run "bin/rubocop -a", abort_on_failure: false

  say ""
  say "完成！接下來：", :green
  say "  cd #{app_name}"
  say "  bin/dev                            # 啟動開發環境（rails server + vite dev server，含 HMR）"
  say "  bin/rails db:test:prepare spec     # 跑測試（含 vite build）"
  say "  git add . && git commit            # git 自己來"
end


# frozen_string_literal: true

source "https://rubygems.org"

ruby File.read(".ruby-version").strip

gem "hexapdf", "~> 0.47" # PDF分割処理用
gem "pdf-reader", "~> 2.12" # PDFアウトライン読み取り用

group :development, :test do
  gem "prawn", "~> 2.5" # テストPDF生成用
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.69"
  gem "rubocop-performance", "~> 1.24"
  gem "rubocop-rspec", "~> 3.3"
end

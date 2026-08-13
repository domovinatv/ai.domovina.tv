#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Jednokratni helper: otkrij chat_id grupe u koju si dodao bota.
#   1) @BotFather → /newbot → token u .env kao TELEGRAM_BOT_TOKEN
#   2) dodaj bota u grupu i pošalji poruku u njoj (npr. /start@tvoj_bot)
#   3) ./scripts/telegram-chatid.rb   → ispiše chat_id (negativan za grupe)
#
# Telegram čuva updateove ~24 h — ako je poruka starija, pošalji novu i ponovi.
require 'json'
require 'net/http'
require 'uri'

ROOT     = File.expand_path('..', __dir__)
ENV_FILE = File.join(ROOT, '.env')

token = ENV['TELEGRAM_BOT_TOKEN']
if token.to_s.empty? && File.exist?(ENV_FILE)
  File.readlines(ENV_FILE).each do |line|
    token = line.chomp.split('=', 2)[1].to_s.strip if line.start_with?('TELEGRAM_BOT_TOKEN=')
  end
end
abort('✖ TELEGRAM_BOT_TOKEN nije postavljen (stavi ga u .env).') if token.to_s.empty?

uri  = URI("https://api.telegram.org/bot#{token}/getUpdates")
res  = Net::HTTP.get_response(uri)
body = (JSON.parse(res.body.to_s) rescue {})
abort("✖ Telegram greška: #{body['description'] || res.code}") unless body['ok']

chats = {}
(body['result'] || []).each do |u|
  chat = u.dig('message', 'chat') || u.dig('my_chat_member', 'chat') || u.dig('channel_post', 'chat')
  chats[chat['id']] = chat if chat
end

if chats.empty?
  puts 'Nema updateova. Dodaj bota u grupu, pošalji poruku (npr. /start@tvoj_bot) pa ponovi.'
  puts 'Napomena: Telegram drži samo nedavne updateove (~24 h).'
  exit 0
end

puts 'Pronađeni chatovi (pravi id upiši u .env kao TELEGRAM_CHAT_ID):'
puts
chats.each_value do |c|
  name = c['title'] || [c['first_name'], c['last_name']].compact.join(' ') || c['username'] || ''
  puts format('  %-16s [%s]  %s', c['id'], c['type'], name)
end
